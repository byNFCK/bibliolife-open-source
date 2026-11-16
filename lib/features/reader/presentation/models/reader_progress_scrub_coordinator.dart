import 'dart:async';

import 'reader_ui_controller.dart';

/// A modal owns its origin/UI, a gesture owns only finger interaction, and each
/// dispatched target owns an independent native lease. No gesture opens a lease.
class ReaderProgressScrubCoordinator {
  ReaderProgressScrubCoordinator({
    required this.host,
    this.uiSessionId,
    this.cadence = const Duration(milliseconds: 100),
  }) : origin = host is ReaderProgressOriginHost
           ? (host as ReaderProgressOriginHost).captureProgressOrigin()
           : null {
    _log('progress_ui_session', {
      'result': 'opened',
      ..._originFields,
      'originPositionAvailable': origin != null,
    });
  }

  final ReaderProgressScrubHost host;
  final int? uiSessionId;
  final Duration cadence;
  final ReaderProgressOrigin? origin;
  static int _nextGesture = 0, _nextCommand = 0;
  int? _gestureId, _pendingGestureId;
  bool _gestureActive = false, _uiOpen = true, _invalidated = false;
  final Stopwatch _clock = Stopwatch()..start();
  Timer? _timer;
  DateTime? _lastStart;
  Future<void>? _flight;
  _ProgressCommand? _executing, _pendingCommand, _authority;
  double? _pendingTarget, _pendingUiValue, _lastPreview;
  int _previewCount = 0, _coalescedCount = 0, _navigationCount = 0;
  int _lastDiagnosticMs = -250;

  int? get sessionId => _authority?.nativeSessionId;
  int? get activeCommandId => _authority?.identity.commandId;
  bool get isOpen => _uiOpen && !_invalidated;
  bool get hasActiveNavigation => _flight != null;
  Future<void> get navigationDrain => _flight ?? Future<void>.value();
  bool _hostCurrent(_ProgressCommand command) =>
      host is! ReaderProgressCommandAuthorityHost ||
      (host as ReaderProgressCommandAuthorityHost).isProgressCommandCurrent(
        command.identity,
      );

  bool _claim(_ProgressCommand command) {
    if (host is ReaderProgressCommandAuthorityHost &&
        !(host as ReaderProgressCommandAuthorityHost).acceptProgressCommand(
          command.identity,
        )) {
      _terminal(command, 'superseded');
      return false;
    }
    return true;
  }

  bool isCommandCurrent(int? id) =>
      id != null &&
      _authority?.identity.commandId == id &&
      _hostCurrent(_authority!) &&
      !const {
        'superseded',
        'cancelled',
        'failed',
        'recovered_timeout',
      }.contains(_authority?.terminal);
  bool isCommandCommitted(int? id) =>
      isCommandCurrent(id) && _authority?.terminal == 'committed';

  Map<String, Object?> get _originFields => {
    'originReadingOrderIndex': origin?.readingOrderIndex,
    'originResourceProgression': origin?.resourceProgression,
    'originTotalProgression': origin?.totalProgression,
    'originLogicalPosition': origin?.logicalPosition,
  };
  Map<String, Object?> _identity(_ProgressCommand command) => {
    'commandId': command.identity.commandId,
    'commandType': command.identity.commandType,
    'gestureId': command.identity.gestureId,
    'authorityGeneration': command.identity.commandId,
    'nativeSessionId': command.nativeSessionId,
    'previewId': command.identity.commandId,
    'navigationGeneration': null,
  };
  void _log(String kind, [Map<String, Object?> fields = const {}]) {
    try {
      final sink = host;
      if (sink is ReaderProgressDiagnosticHost) {
        (sink as ReaderProgressDiagnosticHost).progressDiagnostic({
          'kind': kind,
          'uiSessionId': uiSessionId,
          'uiSessionOpen': _uiOpen,
          'gestureId': _gestureId,
          'gestureElapsedMs': _clock.elapsedMilliseconds,
          ...fields,
        });
      }
    } on Object {
      /* Observer only. */
    }
  }

  void sliderStart(double value) {
    if (!isOpen) return;
    final previousGesture = _gestureId;
    _endGesture('ended');
    _gestureId = ++_nextGesture;
    _gestureActive = true;
    _clock.reset();
    _previewCount = 0;
    _coalescedCount = 0;
    _navigationCount = 0;
    _lastDiagnosticMs = -250;
    _log('progress_slider_start', {
      'uiValue': value,
      'normalizedProgress': value.clamp(0.0, 1.0),
      'previousGestureId': previousGesture,
      'newGestureId': _gestureId,
      'previousGestureEnded': true,
      'previousNavigationStillActive': hasActiveNavigation,
      'activeCommandId': activeCommandId,
      'commandStillAuthoritative': isCommandCurrent(activeCommandId),
    });
  }

  void _endGesture(String result) {
    if (!_gestureActive) return;
    _gestureActive = false;
    _log('progress_gesture_terminal', {
      'result': result,
      'activeCommandId': activeCommandId,
      'activeCommandType': _authority?.identity.commandType,
      'commandStillAuthoritative': isCommandCurrent(activeCommandId),
      'previewCount': _previewCount,
      'coalescedPreviewCount': _coalescedCount,
      'actualNavigationCount': _navigationCount,
    });
  }

  void preview(double target, {double? uiValue}) {
    if (!isOpen || !target.isFinite) return;
    final previous = _pendingTarget;
    _previewCount++;
    if (previous != null || _flight != null || _timer?.isActive == true) {
      _coalescedCount++;
      if (previous == null ||
          _clock.elapsedMilliseconds - _lastDiagnosticMs >= 250) {
        _lastDiagnosticMs = _clock.elapsedMilliseconds;
        _log('progress_preview_coalesced', {
          'reason': _flight != null ? 'active_navigation' : 'newer_pending',
          'oldValue': previous,
          'newValue': target,
          'uiValue': uiValue ?? target,
          'coalescedPreviewCount': _coalescedCount,
        });
      }
    }
    // An actual new target may supersede a final; merely starting a gesture cannot.
    if (_authority?.identity.commandType != 'preview') {
      _supersede(_authority, 'new_preview_target');
    }
    _pendingCommand = null;
    _pendingTarget = target.clamp(0.0, 1.0);
    _pendingUiValue = uiValue ?? target;
    _pendingGestureId = _gestureId;
    _dispatchNext();
  }

  Future<void> finish(double target, {double? uiValue}) {
    if (!isOpen) return Future<void>.value();
    _log('progress_slider_end', {
      'uiValue': uiValue ?? target,
      'exactFinalNormalizedProgress': target,
      'pendingValue': _pendingTarget,
      'finalValueMatchesLastPreview': target == _lastPreview,
    });
    final operation = _accept('slider_final', target);
    _endGesture('ended');
    return operation;
  }

  Future<void> goToPosition(double target) {
    if (!isOpen) return Future<void>.value();
    final operation = _accept('go_to_position', target);
    _log('progress_ui_action', {
      'action': 'go_to_position',
      'result': 'accepted',
      'commandId': activeCommandId,
      'requestedProgress': target,
      'nativeNavigationInFlight': hasActiveNavigation,
      'dispatchState': _pendingCommand == null
          ? 'immediate'
          : 'pending_active_navigation',
    });
    _endGesture('ended');
    return operation;
  }

  Future<void> cancel() {
    if (!isOpen) return Future<void>.value();
    _log('progress_ui_action', {
      'action': 'cancel',
      'result': 'accepted',
      'activePreviewId': _executing?.identity.commandId,
      'pendingPreviewId': _pendingCommand?.identity.commandId,
      'pendingIsFinal': _pendingCommand != null,
      'nativeNavigationInFlight': hasActiveNavigation,
      'modalDismissedImmediately': true,
    });
    final operation = _accept('cancel_rollback', origin?.totalProgression ?? 0);
    _endGesture('cancelled');
    detachUi();
    return operation;
  }

  Future<void> _accept(String type, double target) {
    if (_invalidated) return Future<void>.value();
    final oldPendingPreview = _pendingTarget;
    _supersede(
      _authority,
      type == 'cancel_rollback' ? 'cancel_rollback' : 'new_explicit_target',
    );
    _timer?.cancel();
    _pendingTarget = null;
    final command = _ProgressCommand(
      ReaderProgressCommandIdentity(
        commandId: ++_nextCommand,
        uiSessionId: uiSessionId,
        gestureId: _gestureId,
        commandType: type,
      ),
      target.clamp(0.0, 1.0),
    );
    _authority = command;
    _pendingCommand = command;
    _log('progress_navigation_command', {
      ..._identity(command),
      'result': 'created',
      'normalizedProgress': target,
      'originRollback': type == 'cancel_rollback',
      if (type == 'cancel_rollback') ...{
        ..._originFields,
        'modalDismissedImmediately': true,
      },
    });
    if (!_claim(command)) {
      _pendingCommand = null;
      return command.completion.future;
    }
    _log('progress_command_authority', {
      ..._identity(command),
      'result': 'acquired',
      'reason': 'actual_target_accepted',
    });
    if (type != 'cancel_rollback') {
      _log('progress_final_target', {
        ..._identity(command),
        'isFinal': true,
        'normalizedProgress': target,
        'reason': type == 'slider_final' ? 'slider_end_exact_value' : type,
        'result': _flight == null
            ? 'dispatching'
            : 'waiting_for_active_navigation',
      });
    }
    if (oldPendingPreview != null && type == 'go_to_position') {
      _log('progress_pending_priority', {
        'result': 'explicit_final_replaced_preview',
        'oldPendingPreviewId': null,
        'newCommandId': command.identity.commandId,
        'newPreviewId': command.identity.commandId,
        'requestedProgress': target,
      });
    }
    _dispatchNext();
    return command.completion.future;
  }

  void _supersede(_ProgressCommand? command, String reason) {
    if (command == null || command.terminal != null) return;
    _log('progress_command_authority', {
      ..._identity(command),
      'result': 'superseded',
      'reason': reason,
    });
    _terminal(command, 'superseded');
    final nativeId = command.nativeSessionId;
    if (nativeId != null) unawaited(host.invalidateProgressScrub(nativeId));
  }

  void _terminal(_ProgressCommand command, String result, [Object? error]) {
    if (command.terminal != null) return;
    command.terminal = result;
    _log('progress_navigation_command', {
      ..._identity(command),
      'result': result,
    });
    _log('progress_command_authority', {
      ..._identity(command),
      'result': 'released',
      'reason': result,
    });
    if (error == null) {
      command.completion.complete();
    } else {
      command.completion.completeError(error);
    }
  }

  /// UI closure fences callbacks, but accepted finals/Go/rollback keep their lease.
  void detachUi() {
    if (!_uiOpen) return;
    _endGesture('ended');
    _uiOpen = false;
    _timer?.cancel();
    _pendingTarget = null;
    if (_authority?.identity.commandType == 'preview') {
      _supersede(_authority, 'ui_closed_preview');
    }
    _log('progress_ui_session', {
      'result': 'closed',
      'activeCommandId': activeCommandId,
      'commandStillAuthoritative': isCommandCurrent(activeCommandId),
    });
  }

  /// Explicit reader/session invalidation, never used merely for finger or modal end.
  void invalidate() {
    if (_invalidated) return;
    detachUi();
    _invalidated = true;
    _supersede(_authority, 'reader_invalidated');
    _pendingCommand = null;
  }

  void _dispatchNext({bool cadenceElapsed = false}) {
    if (_invalidated || _flight != null) return;
    var command = _pendingCommand;
    if (command == null) {
      final target = _pendingTarget;
      if (!_uiOpen || target == null) return;
      final remaining = _lastStart == null
          ? Duration.zero
          : cadence - DateTime.now().difference(_lastStart!);
      if (!cadenceElapsed && remaining > Duration.zero) {
        _timer?.cancel();
        _timer = Timer(remaining, () => _dispatchNext(cadenceElapsed: true));
        return;
      }
      _supersede(_authority, 'new_preview_target');
      command = _ProgressCommand(
        ReaderProgressCommandIdentity(
          commandId: ++_nextCommand,
          uiSessionId: uiSessionId,
          gestureId: _pendingGestureId,
          commandType: 'preview',
        ),
        target,
      );
      _authority = command;
      _pendingTarget = null;
      _lastPreview = target;
      _lastStart = DateTime.now();
      _log('progress_navigation_command', {
        ..._identity(command),
        'result': 'created',
        'normalizedProgress': target,
        'originRollback': false,
      });
      if (!_claim(command)) return;
      _log('progress_command_authority', {
        ..._identity(command),
        'result': 'acquired',
        'reason': 'preview_dispatch',
      });
      _log('progress_preview_requested', {
        ..._identity(command),
        'previewId': command.identity.commandId,
        'uiValue': _pendingUiValue,
        'normalizedProgress': target,
        'isFinal': false,
        'boundary': 'dispatch',
      });
    }
    _pendingCommand = null;
    _executing = command;
    _navigationCount++;
    final operation = _execute(command);
    _flight = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_flight, operation)) {
          _flight = null;
          _executing = null;
        }
        _dispatchNext();
      }),
    );
  }

  Future<void> _execute(_ProgressCommand command) async {
    try {
      if (!_hostCurrent(command)) {
        _terminal(command, 'superseded');
        return;
      }
      final nativeId = await host.openProgressScrub(
        checkpointCurrentPosition: false,
        command: command.identity,
      );
      command.nativeSessionId = nativeId;
      if (!identical(_authority, command) ||
          command.terminal != null ||
          _invalidated ||
          !_hostCurrent(command)) {
        unawaited(host.invalidateProgressScrub(nativeId));
        return;
      }
      final type = command.identity.commandType;
      if (type == 'preview') {
        await host.previewProgressScrub(
          sessionId: nativeId,
          requestId: command.identity.commandId,
          target: command.target,
          command: command.identity,
        );
      } else if (type == 'cancel_rollback') {
        final sink = host;
        final captured = origin;
        if (sink is! ReaderProgressOriginHost || captured == null) {
          throw StateError(
            'Canonical progress origin is unavailable for rollback.',
          );
        }
        await (sink as ReaderProgressOriginHost).restoreProgressOrigin(
          origin: captured,
          sessionId: nativeId,
          requestId: command.identity.commandId,
          command: command.identity,
        );
      } else {
        await host.finishProgressScrub(
          sessionId: nativeId,
          requestId: command.identity.commandId,
          target: command.target,
          command: command.identity,
        );
      }
      _terminal(command, 'committed');
    } on Object catch (error) {
      _terminal(
        command,
        error is ReaderProgressCommandFailure ? error.terminalResult : 'failed',
        error,
      );
    } finally {
      if (!_uiOpen && !command.callbackFenced) {
        command.callbackFenced = true;
        _log('progress_ui_callback_fence', {
          ..._identity(command),
          'previewId': command.identity.commandId,
          'result': 'rejected_closed_session',
          'commandStillAuthoritative': isCommandCurrent(
            command.identity.commandId,
          ),
        });
      }
    }
  }
}

final class _ProgressCommand {
  _ProgressCommand(this.identity, this.target) {
    // Observing errors here also covers closed UI/preview commands; callers may still await.
    unawaited(completion.future.then<void>((_) {}, onError: (Object _) {}));
  }
  final ReaderProgressCommandIdentity identity;
  final double target;
  final completion = Completer<void>();
  int? nativeSessionId;
  String? terminal;
  bool callbackFenced = false;
}

import 'dart:async';

import 'package:bibliolife/features/reader/presentation/models/reader_progress_scrub_coordinator.dart';
import 'package:bibliolife/features/reader/presentation/models/reader_ui_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'new gesture coalesces behind old drain and dispatches only its newest preview',
    () async {
      final host = _Host();
      final old = ReaderProgressScrubCoordinator(
        host: host,
        cadence: Duration.zero,
      );
      old.preview(.2);
      await Future<void>.delayed(Duration.zero);
      final oldFinal = old.finish(.5);
      final current = old;
      current.sliderStart(.5);
      current.preview(.6);
      current.preview(.7);
      current.preview(.9);
      await Future<void>.delayed(Duration.zero);
      expect(host.openedSessions, 1);
      expect(current.isCommandCurrent(current.activeCommandId), false);
      expect(host.previews, hasLength(1));
      host.previews.first.completion.complete();
      await Future<void>.delayed(Duration.zero);
      expect(host.previews.map((p) => p.target), [.2, .9]);
      expect(host.previews.last.sessionId, 2);
      final start = host.diagnostics.lastWhere(
        (e) => e['kind'] == 'progress_slider_start',
      );
      expect(start['newGestureId'], isA<int>());
      expect(start['previousGestureEnded'], true);
      expect(start['previousNavigationStillActive'], true);
      current.preview(.95);
      final finalizing = current.finish(.8123456789);
      host.previews.last.completion.complete();
      await finalizing;
      await oldFinal;
      await Future<void>.delayed(Duration.zero);
      expect(host.previews.map((p) => p.target), [.2, .9]);
      expect(host.finals.last.target, .8123456789);
      current.invalidate();
    },
  );

  test(
    'diagnostics correlate latest wins, exact release, and bounded volume',
    () async {
      final host = _Host();
      final coordinator = ReaderProgressScrubCoordinator(host: host);
      coordinator.sliderStart(.1);
      coordinator.preview(.1);
      await Future<void>.delayed(Duration.zero);
      coordinator.preview(.2);
      for (var i = 0; i < 300; i++) {
        coordinator.preview(.3 + i / 1000);
      }
      final finalizing = coordinator.finish(.8123456789, uiValue: .81234567891);
      host.previews.single.completion.complete();
      await finalizing;
      final events = host.diagnostics;
      expect(events.first['kind'], 'progress_ui_session');
      expect(
        events.where((e) => e['kind'] == 'progress_slider_start'),
        hasLength(1),
      );
      expect(
        events.where((e) => e['kind'] == 'progress_preview_requested'),
        isNotEmpty,
      );
      final coalesced = events.firstWhere(
        (e) => e['kind'] == 'progress_preview_coalesced',
      );
      expect(coalesced['reason'], 'active_navigation');
      expect(events.length, lessThan(25));
      final end = events.firstWhere((e) => e['kind'] == 'progress_slider_end');
      expect(end['uiValue'], .81234567891);
      expect(end['exactFinalNormalizedProgress'], .8123456789);
      expect(end['finalValueMatchesLastPreview'], isFalse);
      expect(end['pendingValue'], closeTo(.599, .000001));
      final finalTarget = events.firstWhere(
        (e) => e['kind'] == 'progress_final_target',
      );
      expect(finalTarget['isFinal'], isTrue);
      expect(finalTarget['result'], 'waiting_for_active_navigation');
      expect(host.finals.single.target, .8123456789);
      final ended = events.firstWhere(
        (e) => e['kind'] == 'progress_gesture_terminal',
      );
      expect(ended['previewCount'], 302);
      expect(ended['commandStillAuthoritative'], true);
      expect(events.last['result'], 'released');
      expect(events.toString(), isNot(contains('locatorJson')));
      await Future<void>.delayed(const Duration(milliseconds: 110));
      expect(host.previews, hasLength(1));
      coordinator.invalidate();
    },
  );

  test(
    'Cancel immediately revokes active preview and drops pending work',
    () async {
      final host = _Host();
      final coordinator = ReaderProgressScrubCoordinator(
        host: host,
        uiSessionId: 7,
      );
      coordinator.preview(.2);
      await Future<void>.delayed(Duration.zero);
      coordinator.preview(.7);
      coordinator.cancel();
      expect(host.invalidated, [1]);
      expect(coordinator.isOpen, isFalse);
      expect(host.finals, isEmpty);
      expect(host.restores, isEmpty);
      final action = host.diagnostics.lastWhere(
        (e) => e['kind'] == 'progress_ui_action',
      );
      expect(action['result'], 'accepted');
      expect(action['uiSessionId'], 7);
      expect(action['nativeNavigationInFlight'], true);
      host.previews.single.completion.complete();
      await Future<void>.delayed(const Duration(milliseconds: 110));
      expect(host.previews, hasLength(1));
      expect(host.diagnostics.last['result'], 'rejected_closed_session');
    },
  );

  test(
    'explicit command is accepted behind old drain and replaces pending preview',
    () async {
      final host = _Host();
      final old = ReaderProgressScrubCoordinator(host: host);
      old.preview(.2);
      await Future<void>.delayed(Duration.zero);
      old.preview(.4);
      final current = old;
      final finalizing = current.goToPosition(.8123456789);
      // Acceptance is synchronous, even before opening the new native session.
      final accepted = host.diagnostics.lastWhere(
        (e) => e['kind'] == 'progress_ui_action',
      );
      expect(accepted['action'], 'go_to_position');
      expect(accepted['dispatchState'], 'pending_active_navigation');
      expect(
        host.diagnostics.where(
          (e) => e['result'] == 'explicit_final_replaced_preview',
        ),
        hasLength(1),
      );
      host.previews.single.completion.complete();
      await finalizing;
      expect(host.finals.single.target, .8123456789);
      expect(host.previews.map((p) => p.target), [.2]);
      current.invalidate();
    },
  );

  test(
    'Cancel before explicit session opens discards final entirely',
    () async {
      final host = _Host();
      final coordinator = ReaderProgressScrubCoordinator(host: host);
      final finalizing = coordinator.goToPosition(.9);
      coordinator.cancel();
      await finalizing;
      await Future<void>.delayed(Duration.zero);
      expect(host.finals, isEmpty);
      expect(host.restores.single.target, .25);
      expect(host.invalidated, [1]);
    },
  );

  test('logging failures cannot change scheduler or final ownership', () async {
    final host = _Host()..throwDiagnostic = true;
    final coordinator = ReaderProgressScrubCoordinator(host: host);
    coordinator.sliderStart(.2);
    coordinator.preview(.2);
    await Future<void>.delayed(Duration.zero);
    final finalizing = coordinator.finish(.91);
    host.previews.single.completion.complete();
    await finalizing;
    expect(host.finals.single.target, .91);
    coordinator.invalidate();
  });

  test('starts live previews at most once per cadence interval', () async {
    final host = _Host();
    final coordinator = ReaderProgressScrubCoordinator(host: host);
    coordinator.preview(.1);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(host.previews, hasLength(1));
    host.previews.single.completion.complete();
    await Future<void>.delayed(const Duration(milliseconds: 5));

    coordinator.preview(.2);
    await Future<void>.delayed(const Duration(milliseconds: 45));
    expect(host.previews, hasLength(1));
    await Future<void>.delayed(const Duration(milliseconds: 70));
    expect(host.previews.map((call) => call.target), <double>[.1, .2]);
    host.previews.last.completion.complete();
    coordinator.invalidate();
  });

  test(
    'keeps only the latest preview and serializes final after preview drain',
    () async {
      final host = _Host();
      final coordinator = ReaderProgressScrubCoordinator(host: host);

      coordinator.preview(.1);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(host.previews.map((call) => call.target), <double>[.1]);

      coordinator.preview(.2);
      coordinator.preview(.3);
      final finalizing = coordinator.finish(.8);
      host.previews.single.completion.complete();
      await finalizing;
      expect(host.finals.single.target, .8);
      expect(host.previews, hasLength(1));

      await Future<void>.delayed(const Duration(milliseconds: 110));
      expect(host.previews.map((call) => call.target), <double>[.1]);
      expect(host.isActive, isFalse);
      coordinator.detachUi();
    },
  );

  test(
    'Cancel restores the captured origin after a verified release',
    () async {
      final host = _Host();
      final coordinator = ReaderProgressScrubCoordinator(host: host);
      await coordinator.finish(.76);
      expect(host.isActive, isFalse);

      await coordinator.cancel();
      expect(host.restores.single.target, .25);
      coordinator.detachUi();
    },
  );

  test(
    'dispose invalidates an open session without starting queued preview',
    () async {
      final host = _Host();
      final coordinator = ReaderProgressScrubCoordinator(host: host);
      coordinator.preview(.2);
      coordinator.invalidate();
      await Future<void>.delayed(const Duration(milliseconds: 110));
      expect(host.invalidated, <int>[1]);
      expect(host.previews, isEmpty);
    },
  );
}

final class _PreviewCall {
  _PreviewCall(this.sessionId, this.requestId, this.target);
  final int sessionId;
  final int requestId;
  final double target;
  final completion = Completer<void>();
}

final class _ActionCall {
  _ActionCall(this.sessionId, this.requestId, this.target);
  final int sessionId;
  final int requestId;
  final double target;
}

final class _Host
    implements
        ReaderProgressScrubHost,
        ReaderProgressDiagnosticHost,
        ReaderProgressOriginHost {
  @override
  ReaderProgressOrigin captureProgressOrigin() => const _Origin();
  @override
  Future<void> restoreProgressOrigin({
    required ReaderProgressOrigin origin,
    required int sessionId,
    required int requestId,
    required ReaderProgressCommandIdentity command,
  }) => restoreProgressScrub(
    sessionId: sessionId,
    requestId: requestId,
    target: origin.totalProgression!,
  );
  final diagnostics = <Map<String, Object?>>[];
  bool throwDiagnostic = false;
  @override
  void progressDiagnostic(Map<String, Object?> fields) {
    if (throwDiagnostic) throw StateError('diagnostic unavailable');
    diagnostics.add(fields);
  }

  final previews = <_PreviewCall>[];
  final finals = <_ActionCall>[];
  final restores = <_ActionCall>[];
  final invalidated = <int>[];
  var isActive = false;
  int openedSessions = 0;

  @override
  Future<int> openProgressScrub({
    bool checkpointCurrentPosition = true,
    ReaderProgressCommandIdentity? command,
  }) async {
    isActive = true;
    return ++openedSessions;
  }

  @override
  bool isProgressScrubActive(int sessionId) =>
      isActive && sessionId == openedSessions;

  @override
  Future<void> previewProgressScrub({
    required int sessionId,
    required int requestId,
    required double target,
    ReaderProgressCommandIdentity? command,
  }) async {
    previews.add(_PreviewCall(sessionId, requestId, target));
    await previews.last.completion.future;
  }

  @override
  Future<void> finishProgressScrub({
    required int sessionId,
    required int requestId,
    required double target,
    ReaderProgressCommandIdentity? command,
  }) async {
    finals.add(_ActionCall(sessionId, requestId, target));
    isActive = false;
  }

  @override
  Future<void> restoreProgressScrub({
    required int sessionId,
    required int requestId,
    required double target,
  }) async {
    restores.add(_ActionCall(sessionId, requestId, target));
    isActive = false;
  }

  @override
  Future<void> closeProgressScrub(int sessionId) async {
    isActive = false;
  }

  @override
  Future<void> invalidateProgressScrub(int sessionId) async {
    invalidated.add(sessionId);
    isActive = false;
  }
}

final class _Origin implements ReaderProgressOrigin {
  const _Origin();
  @override
  int get readingOrderIndex => 2;
  @override
  double get resourceProgression => .375;
  @override
  double get totalProgression => .25;
  @override
  int get logicalPosition => 42;
}

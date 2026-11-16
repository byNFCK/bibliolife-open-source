import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'readium_bridge_constants.dart';
import 'readium_bridge_models.dart';
import '../readium_models.dart';

const _progressSeekLogsEnabled = bool.fromEnvironment(
  'BIBLIOLIFE_READIUM_PROGRESS_LOGS',
  defaultValue: false,
);

abstract interface class ReadiumBridgeClient {
  Stream<ReadiumReaderEvent> get events;

  Future<void> attachToPlatform();
  Future<ReadiumBridgeInfo> getBridgeInfo();
  Future<ReadiumReaderSnapshot> getSnapshot();
  Future<ReadiumNavigationResult> next({bool animated = false});
  Future<ReadiumNavigationResult> previous({bool animated = false});
  Future<ReadiumNavigationResult> goToProgression(
    double progression, {
    bool animated = false,
  });
  Future<ReadiumNavigationResult> goToLocatorJson(
    String locatorJson, {
    bool animated = false,
  });
  Future<ReadiumPreferenceResult> applyPreferences(
    ReadiumEpubPreferences preferences,
  );
  Future<ReadiumNavigationResult> goToTocEntry(
    String entryId, {
    bool animated = true,
  });
  Future<ReadiumSearchCommandResult> search(String query);
  Future<ReadiumSearchCommandResult> cancelSearch();
  Future<ReadiumSearchCommandResult> clearSearch();
  Future<ReadiumSearchCommandResult> goToSearchResult(
    String resultId, {
    bool animated = false,
  });
  Future<ReadiumDecorationResult> setDecorations(
    ReadiumDecorationGroup group,
    List<ReadiumDecorationSpec> decorations,
  );
  Future<ReadiumDecorationResult> upsertDecoration(
    ReadiumDecorationGroup group,
    ReadiumDecorationSpec decoration,
  );
  Future<ReadiumDecorationResult> removeDecoration(
    ReadiumDecorationGroup group,
    String id,
  );
  Future<ReadiumDecorationResult> clearDecorations(
    ReadiumDecorationGroup group,
  );
  Future<ReadiumSelectionResult> requestCurrentSelection();
  Future<ReadiumSelectionResult> clearSelection();
  Future<void> dispose();
}

abstract interface class ReadiumReflowDiagnosticClient {
  Future<ReadiumPreferenceResult> applyPreferencesWithDiagnostics(
    ReadiumEpubPreferences preferences,
    ReadiumReflowDiagnosticContext context,
  );
}

abstract interface class ReadiumReflowGestureClient {
  Future<void> settingsReflowGesture(
    int gestureId,
    String slider,
    String action,
    double value,
  );
}

/// Optional control plane for bounded latest-wins settings previews.
abstract interface class ReadiumSettingsPreviewClient {
  Future<ReadiumPreferenceResult> applySettingsPreview(
    ReadiumEpubPreferences preferences,
    int requestId, {
    ReadiumReflowDiagnosticContext? diagnosticContext,
  });
  Future<void> supersedeSettingsPreviewsBefore(int requestId);
}

abstract interface class ReadiumSelectionActionResolver {
  Future<ReadiumSelectionActionResolution> resolveSelectionAction(
    ReadiumSelectionActionResolution resolution,
  );
}

abstract interface class ReadiumAnnotationActionResolver {
  Future<ReadiumAnnotationActionResolution> resolveAnnotationAction(
    ReadiumAnnotationActionResolution resolution,
  );
}

abstract interface class ReadiumProgressLocatorClient {
  Future<ReadiumNavigationResult> goToProgressLocatorOwned({
    required double progression,
    required String locatorJson,
    int? readingOrderIndex,
    required ReadiumProgressNavigationOwner progressOwner,
  });
}

abstract interface class ReadiumProgressScrubClient {
  Future<void> openProgressScrubSession(int sessionId);
  Future<void> invalidateProgressScrubSession(int sessionId);
  Future<void> reserveProgressScrubFinal(
    ReadiumProgressNavigationOwner progressOwner,
  );
  Future<ReadiumNavigationResult> goToProgressionOwned(
    double progression, {
    bool animated = false,
    required ReadiumProgressNavigationOwner progressOwner,
  });
}

extension ReadiumSelectionActionBridgeClient on ReadiumBridgeClient {
  Future<ReadiumSelectionActionResolution> resolveSelectionAction(
    ReadiumSelectionActionResolution resolution,
  ) {
    if (this is ReadiumSelectionActionResolver) {
      return (this as ReadiumSelectionActionResolver).resolveSelectionAction(
        resolution,
      );
    }
    if (this is MethodChannelReadiumBridgeClient) {
      return (this as MethodChannelReadiumBridgeClient).resolveSelectionAction(
        resolution,
      );
    }
    throw UnsupportedError('Selection action acknowledgements are unavailable');
  }
}

extension ReadiumAnnotationActionBridgeClient on ReadiumBridgeClient {
  Future<ReadiumAnnotationActionResolution> resolveAnnotationAction(
    ReadiumAnnotationActionResolution resolution,
  ) {
    if (this is ReadiumAnnotationActionResolver) {
      return (this as ReadiumAnnotationActionResolver).resolveAnnotationAction(
        resolution,
      );
    }
    if (this is MethodChannelReadiumBridgeClient) {
      return (this as MethodChannelReadiumBridgeClient).resolveAnnotationAction(
        resolution,
      );
    }
    throw UnsupportedError(
      'Annotation action acknowledgements are unavailable',
    );
  }
}

typedef ReadiumBridgeClientFactory =
    ReadiumBridgeClient Function(ReadiumEpubOpenConfiguration configuration);

final class MethodChannelReadiumBridgeClient
    implements
        ReadiumBridgeClient,
        ReadiumProgressScrubClient,
        ReadiumProgressLocatorClient,
        ReadiumReflowDiagnosticClient,
        ReadiumReflowGestureClient,
        ReadiumSettingsPreviewClient {
  MethodChannelReadiumBridgeClient(
    this.configuration, {
    MethodChannel? commandChannel,
    EventChannel? eventChannel,
  }) : channelNames = ReadiumBridgeConstants.channelNames(
         configuration.instanceId ??
             (throw const FormatException('invalid_instance_id')),
       ),
       _commandChannel =
           commandChannel ??
           MethodChannel(
             ReadiumBridgeConstants.channelNames(
               configuration.instanceId ??
                   (throw const FormatException('invalid_instance_id')),
             ).command,
           ),
       _eventChannel =
           eventChannel ??
           EventChannel(
             ReadiumBridgeConstants.channelNames(
               configuration.instanceId ??
                   (throw const FormatException('invalid_instance_id')),
             ).events,
           );

  final ReadiumEpubOpenConfiguration configuration;
  final ReadiumBridgeChannelNames channelNames;
  final MethodChannel _commandChannel;
  final EventChannel _eventChannel;
  final StreamController<ReadiumReaderEvent> _events =
      StreamController<ReadiumReaderEvent>.broadcast();
  final Completer<void> _disposedSignal = Completer<void>();
  StreamSubscription<Object?>? _nativeSubscription;
  bool _attached = false;
  bool _disposed = false;
  bool _subscriptionStarted = false;

  @override
  Stream<ReadiumReaderEvent> get events => _events.stream;

  @override
  Future<void> attachToPlatform() async {
    if (_disposed) throw _disposedException();
    if (_subscriptionStarted) return;
    _subscriptionStarted = true;
    _attached = true;
    try {
      _nativeSubscription = _eventChannel
          .receiveBroadcastStream(const <String, Object?>{
            'listenerGeneration': 1,
          })
          .listen(
            _handleNativeEvent,
            onError: _handleNativeStreamError,
            onDone: _handleNativeStreamDone,
            cancelOnError: false,
          );
    } on Object catch (error) {
      _subscriptionStarted = false;
      _attached = false;
      final bridgeError = _transportError(error);
      _events.addError(ReadiumBridgeException(bridgeError));
      throw ReadiumBridgeException(bridgeError);
    }
  }

  @override
  Future<ReadiumBridgeInfo> getBridgeInfo() async {
    final value = await _invoke(ReadiumBridgeConstants.getBridgeInfo);
    final info = ReadiumBridgeInfo.fromMap(value);
    _validateMetadata(info.protocolVersion, info.instanceId);
    return info;
  }

  @override
  Future<ReadiumReaderSnapshot> getSnapshot() async {
    final value = await _invoke(ReadiumBridgeConstants.getSnapshot);
    final event = ReadiumReaderEvent.parse(value);
    if (event is! ReadiumSnapshotEvent) {
      throw ReadiumBridgeFormatException('expected_snapshot');
    }
    _validateMetadata(event.protocolVersion, event.instanceId);
    return event.snapshot;
  }

  @override
  Future<ReadiumNavigationResult> next({bool animated = false}) => _navigation(
    ReadiumBridgeConstants.next,
    animated ? {'animated': true} : null,
  );

  @override
  Future<ReadiumNavigationResult> previous({bool animated = false}) =>
      _navigation(
        ReadiumBridgeConstants.previous,
        animated ? {'animated': true} : null,
      );

  @override
  Future<ReadiumNavigationResult> goToProgression(
    double progression, {
    bool animated = false,
  }) {
    return _goToProgression(progression, animated: animated);
  }

  @override
  Future<ReadiumNavigationResult> goToProgressionOwned(
    double progression, {
    bool animated = false,
    required ReadiumProgressNavigationOwner progressOwner,
  }) => _goToProgression(
    progression,
    animated: animated,
    progressOwner: progressOwner,
  );

  Future<ReadiumNavigationResult> _goToProgression(
    double progression, {
    bool animated = false,
    ReadiumProgressNavigationOwner? progressOwner,
  }) {
    _requireFinite(progression, 'progression');
    if (_progressSeekLogsEnabled) {
      debugPrint('READIUM_PROGRESS_SEEK_DART_BRIDGE target=$progression');
    }
    return _navigation(
      ReadiumBridgeConstants.goToProgression,
      <String, Object?>{
        'progression': progression,
        'animated': animated,
        if (progressOwner != null) 'progressOwner': progressOwner.toMap(),
      },
    );
  }

  @override
  Future<ReadiumNavigationResult> goToProgressLocatorOwned({
    required double progression,
    required String locatorJson,
    int? readingOrderIndex,
    required ReadiumProgressNavigationOwner progressOwner,
  }) {
    _requireFinite(progression, 'progression');
    if (locatorJson.trim().isEmpty || progressOwner.phase != 'final') {
      throw const FormatException('invalid_progress_origin');
    }
    return _navigation(ReadiumBridgeConstants.goToProgression, {
      'progression': progression,
      'animated': false,
      'originLocatorJson': locatorJson,
      'originReadingOrderIndex': readingOrderIndex,
      'progressOwner': progressOwner.toMap(),
    });
  }

  @override
  Future<void> openProgressScrubSession(int sessionId) async {
    _requirePositive(sessionId, 'sessionId');
    final value = await _invoke(
      ReadiumBridgeConstants.openProgressScrubSession,
      <String, Object?>{'sessionId': sessionId},
    );
    if (_status(value) != 'accepted') {
      throw ReadiumBridgeFormatException('progress_session_not_accepted');
    }
  }

  @override
  Future<void> invalidateProgressScrubSession(int sessionId) async {
    _requirePositive(sessionId, 'sessionId');
    final value = await _invoke(
      ReadiumBridgeConstants.invalidateProgressScrubSession,
      <String, Object?>{'sessionId': sessionId},
    );
    if (_status(value) != 'accepted') {
      throw ReadiumBridgeFormatException('progress_session_not_invalidated');
    }
  }

  @override
  Future<void> reserveProgressScrubFinal(
    ReadiumProgressNavigationOwner progressOwner,
  ) async {
    if (progressOwner.phase != 'final') {
      throw ArgumentError.value(
        progressOwner,
        'progressOwner',
        'must be final',
      );
    }
    final value = await _invoke(
      ReadiumBridgeConstants.reserveProgressScrubFinal,
      <String, Object?>{'progressOwner': progressOwner.toMap()},
    );
    if (_status(value) != 'accepted') {
      throw ReadiumBridgeFormatException('progress_final_not_reserved');
    }
  }

  @override
  Future<ReadiumNavigationResult> goToLocatorJson(
    String locatorJson, {
    bool animated = false,
  }) {
    if (locatorJson.trim().isEmpty) {
      throw const FormatException('invalid_locator');
    }
    return _navigation(ReadiumBridgeConstants.goToLocator, <String, Object?>{
      'locatorJson': locatorJson,
      'animated': animated,
    });
  }

  @override
  Future<ReadiumPreferenceResult> applyPreferences(
    ReadiumEpubPreferences preferences,
  ) async {
    return _applyPreferences(preferences);
  }

  @override
  Future<ReadiumPreferenceResult> applyPreferencesWithDiagnostics(
    ReadiumEpubPreferences preferences,
    ReadiumReflowDiagnosticContext context,
  ) async {
    return _applyPreferences(preferences, diagnosticContext: context);
  }

  @override
  Future<ReadiumPreferenceResult> applySettingsPreview(
    ReadiumEpubPreferences preferences,
    int requestId, {
    ReadiumReflowDiagnosticContext? diagnosticContext,
  }) => _applyPreferences(
    preferences,
    diagnosticContext: diagnosticContext,
    previewRequestId: requestId,
  );

  @override
  Future<void> supersedeSettingsPreviewsBefore(int requestId) async {
    if (requestId <= 0) throw ArgumentError.value(requestId, 'requestId');
    final value = await _invoke(
      ReadiumBridgeConstants.supersedeSettingsPreviews,
      <String, Object?>{'requestId': requestId},
    );
    if (_status(value) != 'accepted') {
      throw StateError('settings_preview_supersede_rejected');
    }
  }

  @override
  Future<void> settingsReflowGesture(
    int gestureId,
    String slider,
    String action,
    double value,
  ) async {
    await _invoke(
      ReadiumBridgeConstants.settingsReflowGesture,
      <String, Object?>{
        'gestureId': gestureId,
        'slider': slider,
        'action': action,
        'value': value,
      },
    );
  }

  Future<ReadiumPreferenceResult> _applyPreferences(
    ReadiumEpubPreferences preferences, {
    ReadiumReflowDiagnosticContext? diagnosticContext,
    int? previewRequestId,
  }) async {
    _validatePreferences(preferences);
    final value = await _invoke(
      ReadiumBridgeConstants.applyPreferences,
      <String, Object?>{
        'preferences': preferences.toMap(),
        if (diagnosticContext != null)
          'diagnosticContext': diagnosticContext.toMap(),
        'previewRequestId': ?previewRequestId,
      },
    );
    return ReadiumPreferenceResult(_status(value));
  }

  @override
  Future<ReadiumNavigationResult> goToTocEntry(
    String entryId, {
    bool animated = true,
  }) {
    _requireNonBlank(entryId, 'entryId');
    return _navigation(ReadiumBridgeConstants.goToTocEntry, <String, Object?>{
      'entryId': entryId.trim(),
      'animated': animated,
    });
  }

  @override
  Future<ReadiumSearchCommandResult> search(String query) async {
    final value = await _invoke(
      ReadiumBridgeConstants.search,
      <String, Object?>{'query': query.trim()},
    );
    return ReadiumSearchCommandResult(
      _status(value),
      details: _safeDetails(value),
    );
  }

  @override
  Future<ReadiumSearchCommandResult> cancelSearch() async =>
      ReadiumSearchCommandResult(
        _status(await _invoke(ReadiumBridgeConstants.cancelSearch)),
      );

  @override
  Future<ReadiumSearchCommandResult> clearSearch() async =>
      ReadiumSearchCommandResult(
        _status(await _invoke(ReadiumBridgeConstants.clearSearch)),
      );

  @override
  Future<ReadiumSearchCommandResult> goToSearchResult(
    String resultId, {
    bool animated = false,
  }) async {
    _requireNonBlank(resultId, 'resultId');
    final value = await _invoke(
      ReadiumBridgeConstants.goToSearchResult,
      <String, Object?>{'resultId': resultId.trim(), 'animated': animated},
    );
    return ReadiumSearchCommandResult(
      _status(value),
      details: _safeDetails(value),
    );
  }

  @override
  Future<ReadiumDecorationResult> setDecorations(
    ReadiumDecorationGroup group,
    List<ReadiumDecorationSpec> decorations,
  ) async {
    final value =
        await _invoke(ReadiumBridgeConstants.setDecorations, <String, Object?>{
          'group': group.wireValue,
          'decorations': decorations
              .map((decoration) => decoration.toMap())
              .toList(growable: false),
        });
    return ReadiumDecorationResult(
      _status(value),
      details: _safeDetails(value),
    );
  }

  @override
  Future<ReadiumDecorationResult> upsertDecoration(
    ReadiumDecorationGroup group,
    ReadiumDecorationSpec decoration,
  ) async {
    final value = await _invoke(
      ReadiumBridgeConstants.upsertDecoration,
      <String, Object?>{
        'group': group.wireValue,
        'decoration': decoration.toMap(),
      },
    );
    return ReadiumDecorationResult(
      _status(value),
      details: _safeDetails(value),
    );
  }

  @override
  Future<ReadiumDecorationResult> removeDecoration(
    ReadiumDecorationGroup group,
    String id,
  ) async {
    _requireNonBlank(id, 'id');
    final value = await _invoke(
      ReadiumBridgeConstants.removeDecoration,
      <String, Object?>{'group': group.wireValue, 'id': id.trim()},
    );
    return ReadiumDecorationResult(
      _status(value),
      details: _safeDetails(value),
    );
  }

  @override
  Future<ReadiumDecorationResult> clearDecorations(
    ReadiumDecorationGroup group,
  ) async {
    final value = await _invoke(
      ReadiumBridgeConstants.clearDecorations,
      <String, Object?>{'group': group.wireValue},
    );
    return ReadiumDecorationResult(
      _status(value),
      details: _safeDetails(value),
    );
  }

  @override
  Future<ReadiumSelectionResult> requestCurrentSelection() async {
    final value = await _invoke(ReadiumBridgeConstants.requestCurrentSelection);
    return ReadiumSelectionResult(_status(value), details: _safeDetails(value));
  }

  @override
  Future<ReadiumSelectionResult> clearSelection() async {
    final value = await _invoke(ReadiumBridgeConstants.clearSelection);
    return ReadiumSelectionResult(_status(value), details: _safeDetails(value));
  }

  Future<ReadiumSelectionActionResolution> resolveSelectionAction(
    ReadiumSelectionActionResolution resolution,
  ) async {
    if (resolution.requestId < 1 || resolution.selectionSessionId < 1) {
      throw ArgumentError('Invalid selection action resolution');
    }
    await _invoke(
      ReadiumBridgeConstants.resolveSelectionAction,
      resolution.toMap(),
    );
    return resolution;
  }

  Future<ReadiumAnnotationActionResolution> resolveAnnotationAction(
    ReadiumAnnotationActionResolution resolution,
  ) async {
    if (resolution.requestId < 1) {
      throw ArgumentError('Invalid annotation action resolution');
    }
    await _invoke(
      ReadiumBridgeConstants.resolveAnnotationAction,
      resolution.toMap(),
    );
    return resolution;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _attached = false;
    if (!_disposedSignal.isCompleted) _disposedSignal.complete();
    await _nativeSubscription?.cancel();
    _nativeSubscription = null;
    await _events.close();
  }

  Future<ReadiumNavigationResult> _navigation(
    String method,
    Object? arguments,
  ) async {
    final value = await _invoke(method, arguments);
    return ReadiumNavigationResult(
      _status(value),
      details: _safeDetails(value),
    );
  }

  Future<Map<Object?, Object?>> _invoke(
    String method, [
    Object? arguments,
  ]) async {
    if (_disposed) throw _disposedException();
    if (!_attached) throw _notCreatedException();
    final invocation = _commandChannel.invokeMethod<Object?>(method, arguments);
    try {
      final raw = await Future.any<Object?>(<Future<Object?>>[
        invocation,
        _disposedSignal.future.then<Object?>((_) => null),
      ]);
      if (_disposed) throw _disposedException();
      return _decodeEnvelope(raw);
    } on ReadiumBridgeException {
      rethrow;
    } on PlatformException catch (error) {
      throw ReadiumBridgeException(_transportError(error));
    } on MissingPluginException catch (error) {
      throw ReadiumBridgeException(_transportError(error));
    } on Object catch (error) {
      throw ReadiumBridgeException(
        ReadiumBridgeError(
          code: 'transport_unavailable',
          messageKey: error.toString().split(':').first,
        ),
      );
    }
  }

  Map<Object?, Object?> _decodeEnvelope(Object? raw) {
    if (raw is! Map) {
      throw ReadiumBridgeFormatException('invalid_result_envelope');
    }
    final map = Map<Object?, Object?>.from(raw);
    final ok = map[ReadiumBridgeConstants.ok];
    if (ok is! bool) {
      throw ReadiumBridgeFormatException('invalid_result_envelope');
    }
    if (!ok) {
      throw ReadiumBridgeException(
        ReadiumBridgeError.fromMap(map[ReadiumBridgeConstants.error]),
      );
    }
    final value = map[ReadiumBridgeConstants.value];
    if (value is! Map) {
      throw ReadiumBridgeFormatException('invalid_result_value');
    }
    return Map<Object?, Object?>.from(value);
  }

  String _status(Map<Object?, Object?> value) {
    final status = value['status'];
    if (status is! String || status.isEmpty) {
      throw ReadiumBridgeFormatException('missing_status');
    }
    return status;
  }

  void _handleNativeEvent(Object? value) {
    if (_disposed) return;
    try {
      final event = ReadiumReaderEvent.parse(value);
      _validateMetadata(event.protocolVersion, event.instanceId);
      _events.add(event);
    } on ReadiumBridgeException catch (error, stackTrace) {
      _events.addError(error, stackTrace);
    } on Object catch (error, stackTrace) {
      _events.addError(
        ReadiumBridgeException(
          ReadiumBridgeError(code: 'malformed_native_payload'),
        ),
        stackTrace,
      );
    }
  }

  void _handleNativeStreamError(Object error, StackTrace stackTrace) {
    if (_disposed) return;
    final bridgeError = _transportError(error);
    _events.addError(ReadiumBridgeException(bridgeError), stackTrace);
  }

  void _handleNativeStreamDone() {
    if (_disposed) return;
    _events.addError(
      const ReadiumBridgeException(
        ReadiumBridgeError(code: 'bridge_stream_closed', retryable: true),
      ),
    );
  }

  void _validateMetadata(int protocolVersion, String instanceId) {
    if (protocolVersion != ReadiumBridgeConstants.protocolVersion) {
      throw ReadiumBridgeFormatException('protocol_mismatch');
    }
    if (instanceId != (configuration.instanceId ?? '').trim()) {
      throw ReadiumBridgeFormatException('stale_event');
    }
  }

  ReadiumBridgeException _disposedException() => const ReadiumBridgeException(
    ReadiumBridgeError(code: 'controller_disposed'),
  );

  ReadiumBridgeException _notCreatedException() => const ReadiumBridgeException(
    ReadiumBridgeError(code: 'platform_not_created'),
  );

  ReadiumBridgeError _transportError(Object error) {
    if (error is PlatformException) {
      return ReadiumBridgeError(
        code: error.code.isEmpty ? 'transport_unavailable' : error.code,
        messageKey: 'transport_error',
      );
    }
    if (error is MissingPluginException) {
      return const ReadiumBridgeError(code: 'transport_unavailable');
    }
    return const ReadiumBridgeError(code: 'transport_unavailable');
  }
}

void _requireNonBlank(String value, String key) {
  if (value.trim().isEmpty) throw FormatException('missing_$key');
}

void _requirePositive(int value, String key) {
  if (value <= 0) throw FormatException('invalid_$key');
}

void _requireFinite(double value, String key) {
  if (!value.isFinite) throw FormatException('invalid_$key');
}

void _validatePreferences(ReadiumEpubPreferences preferences) {
  if (!const {'system', 'light', 'dark', 'sepia'}.contains(preferences.theme)) {
    throw const FormatException('invalid_theme');
  }
  if (!const {
    'original',
    'serif',
    'sansSerif',
    'dyslexic',
    'monospace',
  }.contains(preferences.fontFamily)) {
    throw const FormatException('invalid_font_family');
  }
  if (!preferences.fontSize.isFinite ||
      preferences.fontSize < .5 ||
      preferences.fontSize > 3) {
    throw const FormatException('invalid_font_size');
  }
  if (!preferences.fontWeight.isFinite ||
      preferences.fontWeight < 0 ||
      preferences.fontWeight > 2.5) {
    throw const FormatException('invalid_font_weight');
  }
  if (!preferences.lineHeight.isFinite ||
      preferences.lineHeight < 1 ||
      preferences.lineHeight > 2.5) {
    throw const FormatException('invalid_line_height');
  }
  if (!preferences.pageMargins.isFinite ||
      preferences.pageMargins < 0 ||
      preferences.pageMargins > 4) {
    throw const FormatException('invalid_page_margins');
  }
  if (!const {'start', 'justify'}.contains(preferences.textAlignment)) {
    throw const FormatException('invalid_text_alignment');
  }
  if (!const {'auto', 'one', 'two'}.contains(preferences.columns)) {
    throw const FormatException('invalid_columns');
  }
}

Object? _safeDetails(Object? value) {
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (value is List) {
    return List.unmodifiable(value.map(_safeDetails));
  }
  if (value is Map) {
    return Map.unmodifiable(
      value.map((key, entry) => MapEntry(key.toString(), _safeDetails(entry))),
    );
  }
  return value.toString();
}

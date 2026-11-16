import 'dart:async';

import 'package:flutter/foundation.dart';

import 'readium_bridge_client.dart';
import 'readium_bridge_constants.dart';
import 'readium_bridge_models.dart';
import '../readium_models.dart';

const Object _stateValueUnchanged = Object();

typedef ReadiumInstanceIdFactory = String Function();

final class ReadiumEpubController {
  factory ReadiumEpubController({
    required ReadiumEpubOpenConfiguration configuration,
    ReadiumBridgeClient? client,
    ReadiumBridgeClientFactory? clientFactory,
    ReadiumInstanceIdFactory? instanceIdFactory,
  }) {
    final resolved = _resolveConfiguration(configuration, instanceIdFactory);
    final resolvedClient =
        client ?? (clientFactory ?? _defaultClientFactory)(resolved);
    return ReadiumEpubController._(resolved, resolvedClient);
  }

  ReadiumEpubController._(this.configuration, this._client)
    : _state = ValueNotifier<ReadiumEpubControllerState>(
        ReadiumEpubControllerState(
          lifecycle: ReadiumControllerLifecycle.notCreated,
          instanceId: configuration.instanceId!,
        ),
      );

  final ReadiumEpubOpenConfiguration configuration;
  final ReadiumBridgeClient _client;
  final ValueNotifier<ReadiumEpubControllerState> _state;
  final StreamController<ReadiumReaderInteractionEvent> _interactions =
      StreamController<ReadiumReaderInteractionEvent>.broadcast();
  final StreamController<ReadiumDiagnosticEvent> _diagnostics =
      StreamController<ReadiumDiagnosticEvent>.broadcast();
  StreamSubscription<ReadiumReaderEvent>? _eventsSubscription;
  bool _started = false;
  bool _disposed = false;
  var _lastEventSequence = 0;

  ValueListenable<ReadiumEpubControllerState> get listenable => _state;
  ReadiumEpubControllerState get state => _state.value;
  Stream<ReadiumEpubControllerState> get stateChanges => _stateStream();
  Stream<ReadiumReaderInteractionEvent> get interactions =>
      _interactions.stream;
  Stream<ReadiumDiagnosticEvent> get diagnostics => _diagnostics.stream;

  /// Delivered in bridge order, before the associated fatal or ready state.
  ValueChanged<ReadiumDiagnosticEvent>? onOpenDiagnostic;
  Stream<ReadiumSelectionActionRequest> get selectionActionRequests =>
      _interactions.stream
          .where((event) => event is ReadiumSelectionActionRequestedEvent)
          .cast<ReadiumSelectionActionRequestedEvent>()
          .map((event) => event.request);
  Stream<ReadiumAnnotationActionRequest> get annotationActionRequests =>
      _interactions.stream
          .where((event) => event is ReadiumAnnotationActionRequestedEvent)
          .cast<ReadiumAnnotationActionRequestedEvent>()
          .map((event) => event.request);
  Stream<ReadiumDecorationActivatedEvent> get decorationActivations =>
      _interactions.stream
          .where((event) => event is ReadiumDecorationActivatedReaderEvent)
          .cast<ReadiumDecorationActivatedReaderEvent>()
          .map((event) => event.activation);
  String get instanceId => configuration.instanceId!;
  ReadiumPosition? get position => state.position;
  double? get progression => state.progression;
  ReadiumChapter get chapter => state.chapter;
  ReadiumTocState get toc => state.toc;
  ReadiumSearchState get searchState => state.search;
  ReadiumSelectionState get selection => state.selection;
  ReadiumEpubPreferences? get appliedPreferences => state.preferences.applied;
  bool get isReady => state.isReady;
  ReadiumBridgeError? get fatalError =>
      state.hasFatalError ? state.latestError : null;

  Future<void> start() async {
    _ensureNotDisposed();
    if (_started) return;
    _started = true;
    _setState(state.copyWith(lifecycle: ReadiumControllerLifecycle.creating));
    _eventsSubscription = _client.events.listen(
      _reduceEvent,
      onError: _reduceTransportError,
      cancelOnError: false,
    );
    _setState(
      state.copyWith(lifecycle: ReadiumControllerLifecycle.initializing),
    );
    try {
      await _client.attachToPlatform();
      if (_disposed) return;
    } on ReadiumBridgeException catch (error) {
      await _eventsSubscription?.cancel();
      _eventsSubscription = null;
      _setError(error.error);
      rethrow;
    } on Object {
      await _eventsSubscription?.cancel();
      _eventsSubscription = null;
      final error = const ReadiumBridgeError(
        code: 'transport_unavailable',
        fatal: true,
      );
      _setError(error);
      throw ReadiumBridgeException(error);
    }
  }

  Future<ReadiumBridgeInfo> getBridgeInfo() => _client.getBridgeInfo();
  Future<ReadiumReaderSnapshot> getSnapshot() => _client.getSnapshot();
  Future<ReadiumNavigationResult> next({bool animated = false}) =>
      _client.next(animated: animated);
  Future<ReadiumNavigationResult> previous({bool animated = false}) =>
      _client.previous(animated: animated);
  Future<ReadiumNavigationResult> goToProgression(
    double progression, {
    bool animated = false,
  }) => _client.goToProgression(progression, animated: animated);
  Future<ReadiumNavigationResult> goToProgressionOwned(
    double progression, {
    bool animated = false,
    required ReadiumProgressNavigationOwner progressOwner,
  }) {
    final client = _client;
    if (client is! ReadiumProgressScrubClient) {
      throw UnsupportedError('Progress scrub ownership is unavailable');
    }
    return (client as ReadiumProgressScrubClient).goToProgressionOwned(
      progression,
      animated: animated,
      progressOwner: progressOwner,
    );
  }

  Future<ReadiumNavigationResult> goToProgressLocatorOwned(
    ReadiumPosition origin, {
    required ReadiumProgressNavigationOwner progressOwner,
  }) {
    final client = _client;
    final normalized = origin.totalProgression ?? origin.progression;
    final locator = origin.locatorJson;
    if (client is! ReadiumProgressLocatorClient ||
        normalized == null ||
        locator == null) {
      throw StateError('Canonical progress origin navigation is unavailable.');
    }
    return (client as ReadiumProgressLocatorClient).goToProgressLocatorOwned(
      progression: normalized,
      locatorJson: locator,
      readingOrderIndex: origin.readingOrderIndex,
      progressOwner: progressOwner,
    );
  }

  Future<void> openProgressScrubSession(int sessionId) {
    final client = _client;
    if (client is! ReadiumProgressScrubClient) {
      throw UnsupportedError('Progress scrub ownership is unavailable');
    }
    return (client as ReadiumProgressScrubClient).openProgressScrubSession(
      sessionId,
    );
  }

  Future<void> invalidateProgressScrubSession(int sessionId) {
    final client = _client;
    if (client is! ReadiumProgressScrubClient) {
      throw UnsupportedError('Progress scrub ownership is unavailable');
    }
    return (client as ReadiumProgressScrubClient)
        .invalidateProgressScrubSession(sessionId);
  }

  Future<void> reserveProgressScrubFinal(
    ReadiumProgressNavigationOwner progressOwner,
  ) {
    final client = _client;
    if (client is! ReadiumProgressScrubClient) {
      throw UnsupportedError('Progress scrub ownership is unavailable');
    }
    return (client as ReadiumProgressScrubClient).reserveProgressScrubFinal(
      progressOwner,
    );
  }

  Future<ReadiumNavigationResult> goToLocatorJson(
    String locatorJson, {
    bool animated = false,
  }) => _client.goToLocatorJson(locatorJson, animated: animated);
  Future<ReadiumPreferenceResult> applyPreferences(
    ReadiumEpubPreferences preferences, {
    ReadiumReflowDiagnosticContext? diagnosticContext,
    int? previewRequestId,
  }) {
    final client = _client;
    if (previewRequestId != null && client is ReadiumSettingsPreviewClient) {
      return (client as ReadiumSettingsPreviewClient).applySettingsPreview(
        preferences,
        previewRequestId,
        diagnosticContext: diagnosticContext,
      );
    }
    if (diagnosticContext != null && client is ReadiumReflowDiagnosticClient) {
      return (client as ReadiumReflowDiagnosticClient)
          .applyPreferencesWithDiagnostics(preferences, diagnosticContext);
    }
    return client.applyPreferences(preferences);
  }

  Future<void> supersedeSettingsPreviewsBefore(int requestId) {
    final client = _client;
    if (client is ReadiumSettingsPreviewClient) {
      return (client as ReadiumSettingsPreviewClient)
          .supersedeSettingsPreviewsBefore(requestId);
    }
    return Future<void>.value();
  }

  Future<void> settingsReflowGesture(
    int id,
    String slider,
    String action,
    double value,
  ) {
    final client = _client;
    return client is ReadiumReflowGestureClient
        ? (client as ReadiumReflowGestureClient).settingsReflowGesture(
            id,
            slider,
            action,
            value,
          )
        : Future<void>.value();
  }

  Future<ReadiumNavigationResult> goToTocEntry(
    String entryId, {
    bool animated = true,
  }) => _client.goToTocEntry(entryId, animated: animated);
  Future<ReadiumSearchCommandResult> search(String query) =>
      _client.search(query);
  Future<ReadiumSearchCommandResult> cancelSearch() => _client.cancelSearch();
  Future<ReadiumSearchCommandResult> clearSearch() => _client.clearSearch();
  Future<ReadiumSearchCommandResult> goToSearchResult(
    String resultId, {
    bool animated = false,
  }) => _client.goToSearchResult(resultId, animated: animated);
  Future<ReadiumDecorationResult> setDecorations(
    ReadiumDecorationGroup group,
    List<ReadiumDecorationSpec> decorations,
  ) => _client.setDecorations(group, decorations);
  Future<ReadiumDecorationResult> upsertDecoration(
    ReadiumDecorationGroup group,
    ReadiumDecorationSpec decoration,
  ) => _client.upsertDecoration(group, decoration);
  Future<ReadiumDecorationResult> removeDecoration(
    ReadiumDecorationGroup group,
    String id,
  ) => _client.removeDecoration(group, id);
  Future<ReadiumDecorationResult> clearDecorations(
    ReadiumDecorationGroup group,
  ) => _client.clearDecorations(group);
  Future<ReadiumSelectionResult> requestCurrentSelection() =>
      _client.requestCurrentSelection();
  Future<ReadiumSelectionResult> clearSelection() => _client.clearSelection();
  Future<ReadiumSelectionActionResolution> resolveSelectionAction(
    ReadiumSelectionActionResolution resolution,
  ) {
    _ensureNotDisposed();
    return _client.resolveSelectionAction(resolution);
  }

  Future<ReadiumAnnotationActionResolution> resolveAnnotationAction(
    ReadiumAnnotationActionResolution resolution,
  ) {
    _ensureNotDisposed();
    return _client.resolveAnnotationAction(resolution);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final cancelFuture = _eventsSubscription?.cancel();
    _eventsSubscription = null;
    _setState(state.copyWith(lifecycle: ReadiumControllerLifecycle.disposed));
    await _client.dispose();
    await cancelFuture;
    await _interactions.close();
    await _diagnostics.close();
    _state.dispose();
  }

  void _reduceEvent(ReadiumReaderEvent event) {
    if (_disposed || state.isDisposed) return;
    if (event.instanceId != instanceId) {
      _setError(const ReadiumBridgeError(code: 'stale_event'));
      return;
    }
    if (event.protocolVersion != ReadiumBridgeConstants.protocolVersion) {
      _setError(
        const ReadiumBridgeError(code: 'protocol_mismatch', fatal: true),
      );
      return;
    }
    if (event.sequence <= _lastEventSequence) {
      return;
    }
    _lastEventSequence = event.sequence;
    final nextSequence = event.sequence;
    switch (event) {
      case ReadiumSnapshotEvent(:final snapshot):
        final lifecycle = _lifecycleForSnapshot(snapshot);
        _setState(
          ReadiumEpubControllerState(
            lifecycle: lifecycle,
            instanceId: instanceId,
            snapshot: snapshot,
            position: snapshot.position,
            chapter: snapshot.chapter,
            preferences: snapshot.preferences,
            toc: snapshot.toc,
            search: snapshot.search,
            selection: snapshot.selection,
            decorations: snapshot.decorations,
            latestError: snapshot.latestError,
            lastSequence: nextSequence,
            manualScrollActive: false,
            positionLiveManual: false,
          ),
        );
      case ReadiumLifecycleEvent(:final lifecycle):
        _setState(
          state.copyWith(
            lifecycle: _lifecycleForPhase(lifecycle.phase),
            lastSequence: nextSequence,
            lastNavigationStartedSequence:
                lifecycle.phase == 'navigationStarted' ? nextSequence : null,
            lastNavigationCommand: lifecycle.phase == 'navigationStarted'
                ? lifecycle.command
                : null,
            lastNavigationProgressOwner: lifecycle.phase == 'navigationStarted'
                ? lifecycle.progressOwner
                : _stateValueUnchanged,
            progressOwner:
                lifecycle.phase == 'navigationStarted' &&
                    lifecycle.command != 'progression'
                ? null
                : _stateValueUnchanged,
          ),
        );
      case ReadiumPositionEvent(
        :final position,
        :final liveManual,
        :final progressOwner,
      ):
        if (liveManual && !state.manualScrollActive) {
          _setState(state.copyWith(lastSequence: nextSequence));
          return;
        }
        _setState(
          state.copyWith(
            position: position,
            positionLiveManual: liveManual,
            progressOwner: progressOwner,
            lastSequence: nextSequence,
          ),
        );
      case ReadiumManualScrollActivityEvent(:final active):
        _setState(
          state.copyWith(
            manualScrollActive: active,
            lastSequence: nextSequence,
          ),
        );
      case ReadiumChapterEvent(:final chapter):
        _setState(state.copyWith(chapter: chapter, lastSequence: nextSequence));
      case ReadiumPreferencesEvent(:final preferences):
        _setState(
          state.copyWith(preferences: preferences, lastSequence: nextSequence),
        );
      case final ReadiumDiagnosticEvent diagnostic:
        if (diagnostic.fields['category'] == 'Reader.Open') {
          onOpenDiagnostic?.call(diagnostic);
        } else if (!_diagnostics.isClosed) {
          _diagnostics.add(diagnostic);
        }
      case ReadiumTocEvent(:final toc):
        _setState(state.copyWith(toc: toc, lastSequence: nextSequence));
      case ReadiumSearchEvent(:final search):
        _setState(state.copyWith(search: search, lastSequence: nextSequence));
      case ReadiumSelectionEvent(:final selection):
        _setState(
          state.copyWith(selection: selection, lastSequence: nextSequence),
        );
      case ReadiumDecorationEvent(:final decoration):
        final decorations =
            Map<ReadiumDecorationGroup, ReadiumDecorationGroupState>.from(
              state.decorations,
            )..[decoration.group] = decoration;
        _setState(
          state.copyWith(
            decorations: Map.unmodifiable(decorations),
            lastSequence: nextSequence,
          ),
        );
      case final ReadiumContentTapEvent event:
        debugPrint('READIUM_CONTENT_TAP_RECEIVED id=${event.interactionId}');
        _interactions.add(event);
        _setState(state.copyWith(lastSequence: nextSequence));
      case ReadiumSelectionActionRequestedEvent():
        _interactions.add(event);
        _setState(state.copyWith(lastSequence: nextSequence));
      case ReadiumDecorationActivatedReaderEvent():
        _interactions.add(event);
        _setState(state.copyWith(lastSequence: nextSequence));
      case ReadiumAnnotationActionRequestedEvent():
        _interactions.add(event);
        _setState(state.copyWith(lastSequence: nextSequence));
      case ReadiumErrorEvent(:final error):
        _setState(
          state.copyWith(
            latestError: error,
            lifecycle: error.fatal
                ? ReadiumControllerLifecycle.failed
                : state.lifecycle,
            lastSequence: nextSequence,
          ),
        );
      case ReadiumDisposedEvent():
        _setState(
          state.copyWith(
            lifecycle: ReadiumControllerLifecycle.disposed,
            lastSequence: nextSequence,
          ),
        );
      case ReadiumUnknownEvent():
        _setState(state.copyWith(lastSequence: nextSequence));
    }
  }

  void _reduceTransportError(Object error, StackTrace stackTrace) {
    if (_disposed) return;
    final bridgeError = error is ReadiumBridgeException
        ? error.error
        : const ReadiumBridgeError(code: 'transport_unavailable');
    _setError(bridgeError);
  }

  void _setError(ReadiumBridgeError error) {
    if (_disposed) return;
    _setState(
      state.copyWith(
        latestError: error,
        lifecycle: error.fatal
            ? ReadiumControllerLifecycle.failed
            : state.lifecycle,
      ),
    );
  }

  void _setState(ReadiumEpubControllerState value) {
    if (_disposed && value.lifecycle != ReadiumControllerLifecycle.disposed) {
      return;
    }
    _state.value = value;
  }

  Stream<ReadiumEpubControllerState> _stateStream() async* {
    yield state;
    late VoidCallback listener;
    final controller = StreamController<ReadiumEpubControllerState>();
    listener = () => controller.add(state);
    _state.addListener(listener);
    try {
      yield* controller.stream;
    } finally {
      _state.removeListener(listener);
      await controller.close();
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw const ReadiumBridgeException(
        ReadiumBridgeError(code: 'controller_disposed'),
      );
    }
  }
}

ReadiumEpubOpenConfiguration _resolveConfiguration(
  ReadiumEpubOpenConfiguration configuration,
  ReadiumInstanceIdFactory? factory,
) {
  final id = configuration.instanceId?.trim();
  if (id != null && id.isNotEmpty) return configuration.withInstanceId(id);
  final generated = (factory ?? _defaultInstanceId)().trim();
  if (generated.isEmpty) throw const FormatException('invalid_instance_id');
  return configuration.withInstanceId(generated);
}

ReadiumBridgeClient _defaultClientFactory(
  ReadiumEpubOpenConfiguration configuration,
) => MethodChannelReadiumBridgeClient(configuration);

String _defaultInstanceId() {
  _instanceCounter++;
  return 'dart-reader-${DateTime.now().microsecondsSinceEpoch}-$_instanceCounter';
}

int _instanceCounter = 0;

ReadiumControllerLifecycle _lifecycleForSnapshot(
  ReadiumReaderSnapshot snapshot,
) {
  if (snapshot.latestError?.fatal == true) {
    return ReadiumControllerLifecycle.failed;
  }
  return _lifecycleForPhase(snapshot.lifecycle.phase);
}

ReadiumControllerLifecycle _lifecycleForPhase(String phase) => switch (phase) {
  // These are all emitted after the navigator is usable. Treating the
  // follow-up initial-locator/navigation notifications as "initializing"
  // made the Dart adapter discard the native PositionChanged event which
  // follows them, leaving EPUB progress permanently unavailable.
  'navigatorReady' ||
  'ready' ||
  'initialLocatorRestored' ||
  'navigationStarted' ||
  'navigationCompleted' => ReadiumControllerLifecycle.ready,
  'disposed' => ReadiumControllerLifecycle.disposed,
  'navigationFailed' => ReadiumControllerLifecycle.ready,
  _ => ReadiumControllerLifecycle.initializing,
};

extension on ReadiumEpubControllerState {
  ReadiumEpubControllerState copyWith({
    ReadiumControllerLifecycle? lifecycle,
    ReadiumReaderSnapshot? snapshot,
    ReadiumPosition? position,
    ReadiumChapter? chapter,
    ReadiumPreferencesState? preferences,
    ReadiumTocState? toc,
    ReadiumSearchState? search,
    ReadiumSelectionState? selection,
    Map<ReadiumDecorationGroup, ReadiumDecorationGroupState>? decorations,
    ReadiumBridgeError? latestError,
    int? lastSequence,
    bool? manualScrollActive,
    bool? positionLiveManual,
    Object? progressOwner = _stateValueUnchanged,
    int? lastNavigationStartedSequence,
    Object? lastNavigationCommand = _stateValueUnchanged,
    Object? lastNavigationProgressOwner = _stateValueUnchanged,
  }) => ReadiumEpubControllerState(
    lifecycle: lifecycle ?? this.lifecycle,
    instanceId: instanceId,
    snapshot: snapshot ?? this.snapshot,
    position: position ?? this.position,
    chapter: chapter ?? this.chapter,
    preferences: preferences ?? this.preferences,
    toc: toc ?? this.toc,
    search: search ?? this.search,
    selection: selection ?? this.selection,
    decorations: decorations ?? this.decorations,
    latestError: latestError ?? this.latestError,
    lastSequence: lastSequence ?? this.lastSequence,
    manualScrollActive: manualScrollActive ?? this.manualScrollActive,
    positionLiveManual: positionLiveManual ?? this.positionLiveManual,
    progressOwner: identical(progressOwner, _stateValueUnchanged)
        ? this.progressOwner
        : progressOwner as ReadiumProgressNavigationOwner?,
    lastNavigationStartedSequence:
        lastNavigationStartedSequence ?? this.lastNavigationStartedSequence,
    lastNavigationCommand:
        identical(lastNavigationCommand, _stateValueUnchanged)
        ? this.lastNavigationCommand
        : lastNavigationCommand as String?,
    lastNavigationProgressOwner:
        identical(lastNavigationProgressOwner, _stateValueUnchanged)
        ? this.lastNavigationProgressOwner
        : lastNavigationProgressOwner as ReadiumProgressNavigationOwner?,
  );
}

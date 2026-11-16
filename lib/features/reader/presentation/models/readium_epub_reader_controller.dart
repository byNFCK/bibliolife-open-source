import 'dart:async';
import 'dart:convert';

import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';
import 'package:bibliolife/features/bookmarks/domain/repositories/bookmark_repository.dart';
import 'package:bibliolife/features/reader/application/services/reader_bookmark_coordinator.dart';
import 'package:bibliolife/features/reader/application/services/readium_epub_annotation_coordinator.dart';
import 'package:bibliolife/features/reader/application/mappers/epub_reader_settings_readium_mapper.dart';
import 'package:bibliolife/features/reader/application/services/reader_open_attempt.dart';
import 'package:bibliolife/features/reader/domain/models/epub_reader_settings.dart';
import 'package:bibliolife/features/reader/domain/models/reader_capabilities.dart';
import 'package:bibliolife/features/reader/domain/models/reader_bookmark_target.dart';
import 'package:bibliolife/features/reader/domain/models/reader_kind.dart';
import 'package:bibliolife/features/reader/domain/models/reader_progress_state.dart';
import 'package:bibliolife/features/reader/domain/models/reader_search.dart';
import 'package:bibliolife/features/reader/domain/models/reader_settings.dart';
import 'package:bibliolife/features/reader/domain/models/reading_progress.dart';
import 'package:bibliolife/features/reader/domain/repositories/epub_reader_settings_repository.dart';
import 'package:bibliolife/features/reader/domain/repositories/reader_settings_repository.dart';
import 'package:bibliolife/features/reader/domain/repositories/reading_progress_repository.dart';
import 'package:bibliolife/features/reader/presentation/models/reader_ui_controller.dart';
import 'package:bibliolife/features/reader/performance/reader_performance.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:bibliolife/shared/application/logging/app_log_provider.dart';
import 'package:bibliolife_readium/bibliolife_readium.dart';
import 'package:flutter/foundation.dart';

typedef ReadiumEpubControllerBuilder =
    ReadiumEpubController Function(ReadiumEpubOpenConfiguration configuration);

const _progressSeekLogsEnabled = bool.fromEnvironment(
  'BIBLIOLIFE_READIUM_PROGRESS_LOGS',
  defaultValue: false,
);

var _nextReaderReflowGestureId = 0;

/// Adapts the typed Readium PlatformView bridge to the shared Flutter reader
/// shell. The adapter owns one controller and is the only EPUB progress writer.
final class ReadiumEpubReaderController extends ReaderUiController
    implements
        ReaderTextSettingsSessionController,
        ReaderSettingsHost,
        ReaderSettingsDiagnosticHost,
        ReaderSettingsGestureBaselineHost,
        ReaderSettingsPreviewRequestHost,
        ReaderTocController,
        ReaderProgressScrubHost,
        ReaderProgressOriginHost,
        ReaderProgressCommandAuthorityHost,
        ReaderProgressDiagnosticHost {
  ReadiumEpubReaderController({
    required this.book,
    required this.progressRepository,
    required this.settingsRepository,
    this.readerSettingsRepository = const EmptyReaderSettingsRepository(),
    this.libraryRepository,
    BookmarkRepository? bookmarkRepository,
    this.initialLocatorJson,
    this.chromeBrightness,
    this.localFilePath,
    this.onReadingModeCommitted,
    this.appLogService,
    ReaderOpenAttempt? openAttempt,
    ReadiumEpubControllerBuilder? controllerBuilder,
  }) : _opening = openAttempt,
       _controllerBuilder =
           controllerBuilder ??
           ((configuration) =>
               ReadiumEpubController(configuration: configuration)),
       super(capabilities: ReaderCapabilities.forKind(ReaderKind.epub)) {
    if (bookmarkRepository != null) {
      _bookmarkCoordinator = ReaderBookmarkCoordinator(
        bookId: book.id,
        readerKind: ReaderKind.epub,
        repository: bookmarkRepository,
        navigator: _navigateBookmark,
      )..addListener(_notifyBookmarkChange);
    }
  }

  final LibraryBook book;
  final ReadingProgressRepository progressRepository;
  final EpubReaderSettingsRepository settingsRepository;
  final ReaderSettingsRepository readerSettingsRepository;
  final LibraryRepository? libraryRepository;
  final String? initialLocatorJson;
  final Brightness? chromeBrightness;
  final String? localFilePath;
  final Future<void> Function(String? locatorJson)? onReadingModeCommitted;
  final AppLogService? appLogService;
  final ReadiumEpubControllerBuilder _controllerBuilder;

  ReaderOpenAttempt? _opening;
  ReadiumEpubController? _nativeController;
  StreamSubscription<ReadiumDiagnosticEvent>? _diagnosticSubscription;
  ReaderBookmarkCoordinator? _bookmarkCoordinator;
  ReaderAnnotationMenuController? _annotationMenuController;
  ReadiumEpubOpenConfiguration? _configuration;
  EpubReaderSettings _settings = EpubReaderSettings.defaults;
  EpubReaderSettings _committedSettings = EpubReaderSettings.defaults;
  bool _persistedPublisherStyles = true;
  ReadiumPosition? _lastPosition;
  ReadiumPosition? _persistablePosition;
  ReadiumPosition? _lastNativePositionEvent;
  ReadiumChapter? _lastNativeChapterEvent;
  Timer? _persistTimer;
  Future<void>? _initialization;
  Future<void> _progressWriteTail = Future<void>.value();
  Future<void>? _disposal;
  _ActiveProgressScrub? _activeProgressScrub;
  _CompletedProgressScrub? _completedProgressScrub;
  var _progressScrubSequence = 0;
  var _progressWriteGeneration = 0;
  var _lastObservedNavigationStartedSequence = 0;
  var _disposed = false;
  var _settingsApplyGeneration = 0;
  var _settingsAppliesInFlight = 0;
  var _settingsNativeApplyPending = false;
  var _settingsPreviewRequestSequence = 0;
  var _reflowDiagnosticApplySequence = 0;
  final Map<int, Stopwatch> _reflowDiagnosticGestureWatches =
      <int, Stopwatch>{};
  var _readerChromeSuppressed = false;
  var _ready = false;
  var _markedOpened = false;
  var _lastManualScrollActive = false;
  var _progressSavePending = false;
  int? _lastContentTapId;
  int? _lastContentTapViewportGeneration;
  ReadiumEpubController? get nativeController => _nativeController;
  @override
  ReaderProgressScrubHost? get progressScrubHost => this;
  ReadiumEpubOpenConfiguration? get configuration => _configuration;
  String get controllerInstanceId =>
      _nativeController?.instanceId ?? 'not-created';
  bool get isInitialized => _nativeController != null;
  String? get locatorJson => _lastPosition?.locatorJson;
  double? get normalizedProgression =>
      _lastPosition == null ? null : _positionProgression(_lastPosition!);

  String? get currentChapterTitle => _nativeController?.chapter.title;

  @override
  bool get readerChromeSuppressed => _readerChromeSuppressed;

  @override
  ReaderBookmarkCoordinator? get bookmarkCoordinator => _bookmarkCoordinator;

  @override
  ReaderAnnotationMenuController? get annotationMenuController =>
      _annotationMenuController;

  void attachAnnotationMenuController(ReaderAnnotationMenuController value) {
    if (_disposed || identical(_annotationMenuController, value)) return;
    _annotationMenuController?.removeListener(_notifyAnnotationChange);
    _annotationMenuController = value..addListener(_notifyAnnotationChange);
    notifyListeners();
  }

  @override
  ReaderTextSettingsController? get textSettings => this;

  @override
  ReaderSettingsHost get readerSettings => this;

  bool get _isGeneratedSource =>
      book.format == BookFormat.fb2 || book.format == BookFormat.txt;

  @override
  ReaderSettingsCapabilities get settingsCapabilities =>
      readiumSettingsCapabilitiesForSource(book.format);

  @override
  ReaderSettingsState get state => _toReaderSettingsState(
    _isGeneratedSource ? _settings.copyWith(publisherStyles: false) : _settings,
  );

  ReaderSettingsState _toReaderSettingsState(EpubReaderSettings settings) =>
      ReaderSettingsState(
        profile: ReaderSettingsProfile.readiumReflowable,
        appearance: ReaderAppearanceSettings(
          theme: ReaderTheme.values.firstWhere(
            (value) => value.name == settings.theme.name,
          ),
        ),
        typography: ReaderTypographySettings(
          fontFamily: settings.fontFamily,
          fontSize: settings.fontSize,
          fontWeight: settings.fontWeight,
        ),
        spacing: ReaderSpacingSettings(
          lineHeight: settings.lineHeight,
          textMargins: settings.pageMargins,
        ),
        textLayout: ReaderTextLayoutSettings(
          alignment: settings.textAlignment,
          readingMode: settings.readingMode,
          columns: settings.columns,
        ),
        sourceSpecific: ReaderSourceSpecificSettings(
          publisherStyles: settings.publisherStyles,
        ),
      );

  @override
  ReaderTocController? get tocController => this;

  @override
  ReaderTextSettings get settings => ReaderTextSettings(
    theme: _settings.theme.name,
    fontSize: _settings.fontSize,
    lineHeight: _settings.lineHeight,
    pageMargins: _settings.pageMargins,
    publisherStyles: _isGeneratedSource ? false : _settings.publisherStyles,
  );

  @override
  List<ReaderTocEntry> get entries => _nativeController == null
      ? const <ReaderTocEntry>[]
      : _nativeController!.toc.entries
            .map(_mapTocEntry)
            .toList(growable: false);

  @override
  bool get isReady =>
      _nativeController?.toc.status == ReadiumTocStatus.ready &&
      _nativeController!.toc.entries.isNotEmpty;

  Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    final log = appLogService;
    if (_opening == null &&
        log != null &&
        (book.format == BookFormat.epub || _isGeneratedSource)) {
      _opening = ReaderOpenAttempt(
        log,
        bookId: book.id,
        source: 'other',
        format: book.format.name.toUpperCase(),
      );
    }
    final opening = _opening;
    opening?.resolveFile(localFilePath ?? book.filePath);
    opening?.stage('reader_bootstrap', 'started', 'reader_repositories');
    try {
      final values = await Future.wait<Object?>([
        progressRepository.getForBook(book.id),
        settingsRepository.load(),
        readerSettingsRepository.load(ReaderSettingsProfile.readiumReflowable),
      ]);
      if (_disposed) return;
      final saved = values[0] as ReadingProgress?;
      final legacy = (values[1] as EpubReaderSettings).normalized();
      final expanded = values[2] as ReaderSettingsState?;
      _settings = expanded == null
          ? legacy
          : _mergePersistedSettings(legacy: legacy, expanded: expanded);
      _persistedPublisherStyles = _settings.publisherStyles;
      if (_isGeneratedSource) {
        // Generated FB2/TXT publications have no publisher appearance to
        // preserve. Readium requires this flag off for line-height and text
        // alignment preferences to become effective.
        _settings = _settings.copyWith(publisherStyles: false);
      }
      _committedSettings = _settings;
      final requestedLocator = _nonBlank(initialLocatorJson);
      final savedLocator = _nonBlank(saved?.locatorJson);
      final locator = _normalizeInitialLocator(
        requestedLocator ?? savedLocator,
      );
      opening?.stage('reader_bootstrap', 'success', 'reader_repositories');
      opening?.stage('dart_readium_controller', 'started', 'readium_adapter');
      final configuration = ReadiumEpubOpenConfiguration(
        bookId: book.id,
        localFilePath: localFilePath ?? book.filePath,
        initialLocatorJson: locator,
        initialPreferences: _settings.toReadiumPreferences(),
        initialPreferencesAreAuthoritative: true,
        isNightMode: chromeBrightness == Brightness.dark,
        openAttemptId: opening?.id,
        initialLocatorSource: opening == null
            ? null
            : locator == null
            ? 'none'
            : requestedLocator != null
            ? 'launch_request'
            : 'saved_progress',
      );
      _configuration = configuration;
      final controller = _controllerBuilder(configuration);
      _nativeController = controller;
      controller.onOpenDiagnostic = opening?.onNativeDiagnostic;
      opening?.stage('dart_readium_controller', 'success', 'readium_adapter');
      opening?.stage('platform_view', 'started', 'android_platform_view');
      _diagnosticSubscription = controller.diagnostics.listen(
        _forwardReadiumDiagnostic,
        onError: (Object _) {},
      );
      controller.listenable.addListener(_handleNativeState);
      if (!_disposed) notifyListeners();
      _handleNativeState();
      unawaited(_bookmarkCoordinator?.start());
    } catch (error) {
      if (!_disposed) setError(error);
    }
  }

  String? _normalizeInitialLocator(String? locator) {
    if (locator == null ||
        (book.format != BookFormat.fb2 && book.format != BookFormat.txt)) {
      return locator;
    }
    try {
      final value = jsonDecode(locator);
      if (value is! Map<String, dynamic>) return null;
      if (value['href'] is String) return locator;
      final block = value['type'] == 'reflowable' ? value['block'] : null;
      if (block is! int || block < 0) return null;
      return jsonEncode(<String, Object>{
        'href': 'text/content.xhtml',
        'type': 'application/xhtml+xml',
        'locations': <String, Object>{'cssSelector': '#block-$block'},
      });
    } on FormatException {
      return null;
    }
  }

  void handleContentTap(ReadiumContentTapEvent event, {String? controllerId}) {
    if (_disposed || event.interactionId == _lastContentTapId) return;
    if (controllerId != null && controllerId != _nativeController?.instanceId) {
      return;
    }
    final generation = event.viewportGeneration;
    if (generation != null &&
        generation != (_lastContentTapViewportGeneration ?? 0)) {
      return;
    }
    _lastContentTapId = event.interactionId;
    // The event is emitted by the native navigator only after it has a
    // rendered content surface, so it is safe to toggle chrome even while
    // the bridge lifecycle is still publishing its first ready snapshot.
    if (error == null) {
      if (kDebugMode) {
        debugPrint('READIUM_CONTENT_TAP_APPLIED id=${event.interactionId}');
      }
      toggleControls();
    }
  }

  @override
  void setError(Object error) {
    _opening?.fail(error: error);
    super.setError(error);
  }

  void handlePlatformViewCreationError(Object error) {
    if (_disposed) return;
    _opening?.fail(
      error: error,
      stageName: 'platform_view',
      component: 'android_platform_view',
    );
  }

  void handleViewportError(ReadiumBridgeError error, {String? controllerId}) {
    if (_disposed ||
        (controllerId != null &&
            controllerId != _nativeController?.instanceId)) {
      return;
    }
    setError(error);
  }

  Future<void> next({bool animated = false}) async {
    await _nativeController?.next(animated: animated);
  }

  Future<void> previous({bool animated = false}) async {
    await _nativeController?.previous(animated: animated);
  }

  @override
  Future<ReaderSearchCommandResult> search(String query) async {
    final value = query.trim();
    if (value.isEmpty) return clearSearch();
    final controller = _nativeController;
    if (_disposed) return const ReaderSearchCommandResult.disposed();
    if (controller == null) {
      return const ReaderSearchCommandResult.unsupported();
    }
    try {
      return _mapSearchCommand(await controller.search(value));
    } catch (_) {
      setSearchState(
        ReaderSearchFailure(
          query: value,
          error: const ReaderSearchError(code: 'search_unavailable'),
        ),
      );
      return const ReaderSearchCommandResult(
        ReaderSearchCommandStatus.failed,
        errorCode: 'search_unavailable',
      );
    }
  }

  @override
  Future<ReaderSearchCommandResult> cancelSearch() async {
    final controller = _nativeController;
    if (_disposed) return const ReaderSearchCommandResult.disposed();
    if (controller == null) {
      return const ReaderSearchCommandResult.unsupported();
    }
    try {
      return _mapSearchCommand(await controller.cancelSearch());
    } catch (_) {
      return const ReaderSearchCommandResult(
        ReaderSearchCommandStatus.failed,
        errorCode: 'search_cancel_failed',
      );
    }
  }

  @override
  Future<ReaderSearchCommandResult> clearSearch() async {
    final controller = _nativeController;
    if (_disposed) return const ReaderSearchCommandResult.disposed();
    if (controller == null) {
      return const ReaderSearchCommandResult.unsupported();
    }
    try {
      return _mapSearchCommand(await controller.clearSearch());
    } catch (_) {
      return const ReaderSearchCommandResult(
        ReaderSearchCommandStatus.failed,
        errorCode: 'search_clear_failed',
      );
    }
  }

  @override
  Future<ReaderSearchCommandResult> goToSearchResult(String resultId) async {
    final controller = _nativeController;
    if (_disposed) return const ReaderSearchCommandResult.disposed();
    if (controller == null) {
      return const ReaderSearchCommandResult.unsupported();
    }
    final state = searchState;
    if (state is! ReaderSearchReady ||
        !state.results.any((result) => result.id == resultId)) {
      return const ReaderSearchCommandResult.stale();
    }
    try {
      return _mapSearchCommand(await controller.goToSearchResult(resultId));
    } catch (_) {
      return const ReaderSearchCommandResult(
        ReaderSearchCommandStatus.failed,
        errorCode: 'search_navigation_failed',
      );
    }
  }

  @override
  Future<void> clearSelectionForSearch() async {
    if (_disposed) return;
    try {
      await _nativeController?.clearSelection();
    } catch (_) {
      // Search remains available if selection cleanup races route disposal.
    }
  }

  Future<void> applyDecorations(
    ReadiumDecorationGroup group,
    List<ReadiumDecorationSpec> decorations,
  ) async {
    await _nativeController?.setDecorations(group, decorations);
  }

  Future<ReadiumSelectionResult?> requestCurrentSelection() async =>
      _nativeController?.requestCurrentSelection();

  @override
  Future<void> update(ReaderTextSettings next) =>
      _applySettings(next, persist: true);

  @override
  Future<void> preview(ReaderTextSettings next) =>
      _applySettings(next, persist: false);

  @override
  Future<void> commit(ReaderTextSettings next) =>
      _applySettings(next, persist: true);

  @override
  Future<void> restore(ReaderTextSettings next) =>
      _applySettings(next, persist: false);

  @override
  Future<void> previewSettings(ReaderSettingsState next) =>
      _applyExpandedSettings(next, persist: false);

  @override
  ReaderSettingsDiagnosticGesture beginSettingsDiagnostic(
    ReaderSliderId sliderId,
    double uiValue,
  ) {
    final gesture = ReaderSettingsDiagnosticGesture(
      id: ++_nextReaderReflowGestureId,
      sliderId: sliderId,
      uiStartValue: uiValue,
    );
    _reflowDiagnosticGestureWatches[gesture.id] = Stopwatch()..start();
    _gestureBaselines[gesture.id] = gesture;
    _gestureBaselineStarts[gesture.id] =
        (_nativeController?.settingsReflowGesture(
                  gesture.id,
                  sliderId.name,
                  'begin',
                  uiValue,
                ) ??
                Future<void>.value())
            .catchError((Object _) {
              _writeDiagnostic('warning', <String, Object?>{
                'kind': 'gesture_reflow_baseline',
                'result': 'capture_failed',
                'gestureId': gesture.id,
              });
            });
    _writeDiagnostic('info', <String, Object?>{
      'kind': 'slider_start',
      'gestureId': gesture.id,
      'slider': sliderId.name,
      'uiValue': uiValue,
    });
    return gesture;
  }

  final Map<int, Future<void>> _gestureBaselineStarts = <int, Future<void>>{};
  final Map<int, ReaderSettingsDiagnosticGesture> _gestureBaselines =
      <int, ReaderSettingsDiagnosticGesture>{};

  @override
  Future<void> finishSettingsGestureBaseline(
    ReaderSettingsDiagnosticGesture gesture, {
    bool cancelled = false,
  }) async {
    if (_gestureBaselines.remove(gesture.id) == null) return;
    final capture = _gestureBaselineStarts.remove(gesture.id);
    // Cancellation must fence an outstanding DOM callback immediately.
    if (!cancelled) await capture;
    if (_disposed) return;
    await _nativeController?.settingsReflowGesture(
      gesture.id,
      gesture.sliderId.name,
      cancelled ? 'cancel' : 'end',
      gesture.uiStartValue,
    );
  }

  @override
  Future<void> cancelSettingsGestureBaselines() async {
    for (final gesture in _gestureBaselines.values.toList()) {
      await finishSettingsGestureBaseline(gesture, cancelled: true);
    }
  }

  @override
  void endSettingsDiagnostic(
    ReaderSettingsDiagnosticGesture gesture,
    double uiValue,
  ) {
    final watch = _reflowDiagnosticGestureWatches.remove(gesture.id);
    watch?.stop();
    _writeDiagnostic('info', <String, Object?>{
      'kind': 'slider_end',
      'gestureId': gesture.id,
      'slider': gesture.sliderId.name,
      'uiValue': uiValue,
      if (watch != null) 'elapsedMs': watch.elapsedMicroseconds / 1000,
    });
  }

  @override
  Future<void> previewSettingsWithDiagnostics(
    ReaderSettingsState next, {
    required ReaderSettingsDiagnosticGesture? gesture,
  }) =>
      _applyExpandedSettings(next, persist: false, diagnosticGesture: gesture);

  @override
  int allocateSettingsPreviewRequestId() => ++_settingsPreviewRequestSequence;

  @override
  Future<void> supersedeSettingsPreviewsBefore(int requestId) async {
    if (_disposed || requestId <= 0) return;
    final controller = _nativeController;
    if (controller == null || !controller.isReady) return;
    await controller.supersedeSettingsPreviewsBefore(requestId);
  }

  @override
  Future<void> previewSettingsWithRequestId(
    ReaderSettingsState next, {
    required int requestId,
    required ReaderSettingsDiagnosticGesture? gesture,
  }) => _applyExpandedSettings(
    next,
    persist: false,
    diagnosticGesture: gesture,
    previewRequestId: requestId,
  );

  @override
  void logSettingsDiagnosticAction(String action) {
    if (action != 'apply' && action != 'cancel') return;
    _writeDiagnostic('info', <String, Object?>{'kind': 'sheet_$action'});
  }

  @override
  Future<void> commitSettings(ReaderSettingsState next) =>
      _applyExpandedSettings(next, persist: true);

  @override
  Future<void> restoreSettings(ReaderSettingsState next) =>
      _applyExpandedSettings(next, persist: false);

  Future<void> _applyExpandedSettings(
    ReaderSettingsState next, {
    required bool persist,
    ReaderSettingsDiagnosticGesture? diagnosticGesture,
    int? previewRequestId,
  }) {
    if (next.profile != ReaderSettingsProfile.readiumReflowable) {
      throw ArgumentError.value(next.profile, 'next.profile');
    }
    return _applyEpubSettings(
      _fromReaderSettingsState(next, fallback: _settings),
      persist: persist,
      diagnosticGesture: diagnosticGesture,
      previewRequestId: previewRequestId,
      diagnosticValueOverride:
          diagnosticGesture?.sliderId == ReaderSliderId.pageSpacing
          ? next.spacing?.pageGap
          : null,
    );
  }

  Future<void> _applySettings(
    ReaderTextSettings next, {
    required bool persist,
  }) async {
    final updated = _settings.copyWith(
      theme: EpubReaderTheme.values.firstWhere(
        (value) => value.name == next.theme,
        orElse: () => EpubReaderTheme.system,
      ),
      fontSize: next.fontSize,
      lineHeight: next.lineHeight,
      pageMargins: next.pageMargins,
      publisherStyles: _isGeneratedSource ? false : next.publisherStyles,
    );
    return _applyEpubSettings(updated, persist: persist);
  }

  Future<void> _applyEpubSettings(
    EpubReaderSettings updated, {
    required bool persist,
    ReaderSettingsDiagnosticGesture? diagnosticGesture,
    double? diagnosticValueOverride,
    int? previewRequestId,
  }) async {
    final generation = ++_settingsApplyGeneration;
    _settingsAppliesInFlight++;
    final controller = _nativeController;
    try {
      if (_disposed) throw StateError('reader_disposed');
      if (controller == null || !controller.isReady) {
        throw StateError('reader_not_ready');
      }
      if (diagnosticGesture != null) {
        await _gestureBaselineStarts[diagnosticGesture.id];
      }
      if (_disposed || generation != _settingsApplyGeneration) return;
      if (_isGeneratedSource) {
        updated = updated.copyWith(publisherStyles: false);
      }
      final committedBefore = _committedSettings;
      final readingModeChanged =
          updated.readingMode != committedBefore.readingMode;
      final previousPersistedPublisherStyles = _persistedPublisherStyles;
      // A restore must reach Readium even when Flutter still holds the initial
      // value: an older preview may already be changing the native rendition.
      final needsNativeApply =
          updated != _settings ||
          _settingsAppliesInFlight > 1 ||
          _settingsNativeApplyPending;
      final diagnosticPreferences = updated.toReadiumPreferences().normalized();
      final diagnosticApplyId = diagnosticGesture == null
          ? null
          : ++_reflowDiagnosticApplySequence;
      final diagnosticValue = switch (diagnosticGesture?.sliderId) {
        ReaderSliderId.fontSize => diagnosticPreferences.fontSize,
        ReaderSliderId.fontWeight => diagnosticPreferences.fontWeight,
        ReaderSliderId.lineHeight => diagnosticPreferences.lineHeight,
        ReaderSliderId.margins => diagnosticPreferences.pageMargins,
        ReaderSliderId.pageSpacing => diagnosticValueOverride,
        _ => null,
      };
      final diagnosticContext =
          diagnosticGesture == null ||
              diagnosticApplyId == null ||
              diagnosticValue == null
          ? null
          : ReadiumReflowDiagnosticContext(
              gestureId: diagnosticGesture.id,
              slider: diagnosticGesture.sliderId.name,
              applyId: diagnosticApplyId,
              normalizedValue: diagnosticValue,
            );
      Stopwatch? applyWatch;
      final replacesBackend =
          persist && readingModeChanged && onReadingModeCommitted != null;
      if (needsNativeApply && !replacesBackend) {
        if (diagnosticContext != null) {
          applyWatch = Stopwatch()..start();
          _writeDiagnostic('debug', <String, Object?>{
            'kind': 'adapter_apply_start',
            'gestureId': diagnosticContext.gestureId,
            'applyId': diagnosticContext.applyId,
            'slider': diagnosticContext.slider,
            'normalizedValue': diagnosticContext.normalizedValue,
          });
        }
        _settingsNativeApplyPending = true;
        final result = await controller.applyPreferences(
          updated.toReadiumPreferences(),
          diagnosticContext: diagnosticContext,
          previewRequestId: previewRequestId,
        );
        if (generation != _settingsApplyGeneration) {
          applyWatch?.stop();
          if (diagnosticContext != null) {
            _writeDiagnostic('debug', <String, Object?>{
              'kind': 'adapter_apply_superseded',
              'gestureId': diagnosticContext.gestureId,
              'applyId': diagnosticContext.applyId,
              'slider': diagnosticContext.slider,
              'normalizedValue': diagnosticContext.normalizedValue,
              if (applyWatch != null)
                'elapsedMs': applyWatch.elapsedMicroseconds / 1000,
            });
          }
          return;
        }
        if (!result.isSuccess) {
          if (diagnosticContext != null) {
            applyWatch?.stop();
            _writeDiagnostic('warning', <String, Object?>{
              'kind': 'adapter_apply_fail',
              'gestureId': diagnosticContext.gestureId,
              'applyId': diagnosticContext.applyId,
              'slider': diagnosticContext.slider,
              'normalizedValue': diagnosticContext.normalizedValue,
              'result': result.status,
              if (applyWatch != null)
                'elapsedMs': applyWatch.elapsedMicroseconds / 1000,
            });
          }
          throw StateError('preference_${result.status}');
        }
        _settingsNativeApplyPending = false;
        applyWatch?.stop();
        if (diagnosticContext != null) {
          _writeDiagnostic('debug', <String, Object?>{
            'kind': 'adapter_apply_done',
            'gestureId': diagnosticContext.gestureId,
            'applyId': diagnosticContext.applyId,
            'slider': diagnosticContext.slider,
            'normalizedValue': diagnosticContext.normalizedValue,
            'result': result.status,
            if (applyWatch != null)
              'elapsedMs': applyWatch.elapsedMicroseconds / 1000,
          });
        }
      } else if (diagnosticContext != null) {
        _writeDiagnostic('debug', <String, Object?>{
          'kind': 'adapter_apply_skipped',
          'gestureId': diagnosticContext.gestureId,
          'applyId': diagnosticContext.applyId,
          'slider': diagnosticContext.slider,
          'normalizedValue': diagnosticContext.normalizedValue,
          'result': 'skipped',
        });
      }
      if (generation != _settingsApplyGeneration) return;
      if (_disposed) return;
      _settings = updated;
      if (!_isGeneratedSource) {
        _persistedPublisherStyles = updated.publisherStyles;
      }
      if (persist) {
        final persisted = _isGeneratedSource
            ? updated.copyWith(publisherStyles: _persistedPublisherStyles)
            : updated;
        try {
          await settingsRepository.save(persisted);
          await readerSettingsRepository.save(
            _toReaderSettingsState(persisted),
          );
        } on Object {
          final rollback = await controller.applyPreferences(
            committedBefore.toReadiumPreferences(),
          );
          if (rollback.isSuccess) {
            _settings = committedBefore;
            _persistedPublisherStyles = previousPersistedPublisherStyles;
          }
          await _restorePersistedSettings(
            committedBefore,
            publisherStyles: previousPersistedPublisherStyles,
          );
          notifyListeners();
          rethrow;
        }
        _committedSettings = updated;
        if (replacesBackend) {
          await onReadingModeCommitted!(_lastPosition?.locatorJson);
        }
      }
      if (!_disposed) notifyListeners();
    } catch (error) {
      if (generation != _settingsApplyGeneration) return;
      // Preference failures are recoverable and must not replace the reader.
      if (kDebugMode) debugPrint('Readium preference update failed: $error');
      rethrow;
    } finally {
      _settingsAppliesInFlight--;
    }
  }

  Future<void> _restorePersistedSettings(
    EpubReaderSettings previous, {
    required bool publisherStyles,
  }) async {
    final persisted = _isGeneratedSource
        ? previous.copyWith(publisherStyles: publisherStyles)
        : previous;
    try {
      await settingsRepository.save(persisted);
    } on Object {
      // Preserve the original Apply failure. The repository itself guarantees
      // that a failed replacement leaves its last valid value readable.
    }
    try {
      await readerSettingsRepository.save(_toReaderSettingsState(persisted));
    } on Object {
      // Same best-effort rollback for the optional sidecar extension.
    }
  }

  EpubReaderSettings _fromReaderSettingsState(
    ReaderSettingsState value, {
    required EpubReaderSettings fallback,
  }) {
    final appearance = value.appearance;
    final typography = value.typography;
    final spacing = value.spacing;
    final layout = value.textLayout;
    final source = value.sourceSpecific;
    return fallback.copyWith(
      theme: appearance == null
          ? fallback.theme
          : EpubReaderTheme.values.firstWhere(
              (theme) => theme.name == appearance.theme.name,
              orElse: () => EpubReaderTheme.system,
            ),
      fontFamily: typography?.fontFamily,
      fontSize: typography?.fontSize,
      fontWeight: typography?.fontWeight,
      lineHeight: spacing?.lineHeight,
      pageMargins: spacing?.textMargins,
      textAlignment: layout?.alignment,
      readingMode: layout?.readingMode,
      columns: layout?.columns,
      publisherStyles: source?.publisherStyles,
    );
  }

  /// Drift owns the five pre-A1 EPUB fields. The JSON sidecar extends that
  /// state with the remaining Readium preferences and must never override the
  /// legacy source of truth during route reopen.
  EpubReaderSettings _mergePersistedSettings({
    required EpubReaderSettings legacy,
    required ReaderSettingsState expanded,
  }) {
    final typography = expanded.typography;
    final layout = expanded.textLayout;
    return legacy.copyWith(
      fontFamily: typography?.fontFamily,
      fontWeight: typography?.fontWeight,
      textAlignment: layout?.alignment,
      readingMode: layout?.readingMode,
      columns: layout?.columns,
    );
  }

  @override
  Future<void> goTo(String entryId) async {
    _acceptedProgressCommandId = null;
    final controller = _nativeController;
    if (_disposed || controller == null || !controller.isReady) return;
    final previous = _activeProgressScrub;
    if (previous != null) await _invalidateProgressLease(previous);
    await controller.goToTocEntry(entryId);
  }

  Future<void> _seek(double progression) async {
    _acceptedProgressCommandId = null;
    final controller = _nativeController;
    if (_disposed || controller == null || !controller.isReady) return;
    final target = progression.clamp(0.0, 1.0);
    if (_progressSeekLogsEnabled) {
      debugPrint('READIUM_PROGRESS_SEEK_REQUEST target=$target');
    }
    await controller.goToProgression(target);
  }

  int _greatestProgressCommandId = 0;
  int? _acceptedProgressCommandId;
  @override
  bool acceptProgressCommand(ReaderProgressCommandIdentity command) {
    if (_disposed || command.commandId < _greatestProgressCommandId) {
      return false;
    }
    if (command.commandId > _greatestProgressCommandId) {
      _greatestProgressCommandId = command.commandId;
      _acceptedProgressCommandId = command.commandId;
      final previous = _activeProgressScrub;
      if (previous != null) unawaited(_invalidateProgressLease(previous));
    }
    return _acceptedProgressCommandId == command.commandId;
  }

  @override
  bool isProgressCommandCurrent(ReaderProgressCommandIdentity command) =>
      !_disposed && _acceptedProgressCommandId == command.commandId;

  final _progressCommandContexts = <int, ReaderProgressCommandIdentity>{};

  void _rememberProgressCommand(
    int nativeSession,
    ReaderProgressCommandIdentity? command,
  ) {
    if (command == null) return;
    _progressCommandContexts[nativeSession] = command;
    if (_progressCommandContexts.length > 32) {
      _progressCommandContexts.remove(_progressCommandContexts.keys.first);
    }
  }

  Map<String, Object?> _progressCommandFields(
    ReaderProgressCommandIdentity command,
  ) => {
    'uiSessionId': command.uiSessionId,
    'gestureId': command.gestureId,
    'commandId': command.commandId,
    'commandType': command.commandType,
    'authorityGeneration': command.commandId,
  };

  @override
  ReaderProgressOrigin? captureProgressOrigin() {
    final position = _lastPosition ?? _nativeController?.state.position;
    if (_disposed ||
        position == null ||
        _nonBlank(position.locatorJson) == null ||
        (position.totalProgression ?? position.progression) == null) {
      return null;
    }
    return _ReadiumProgressOrigin(this, position);
  }

  @override
  Future<void> restoreProgressOrigin({
    required ReaderProgressOrigin origin,
    required int sessionId,
    required int requestId,
    required ReaderProgressCommandIdentity command,
  }) {
    if (origin is! _ReadiumProgressOrigin || !identical(origin.owner, this)) {
      return Future<void>.error(
        StateError('Canonical origin belongs to another reader.'),
      );
    }
    return _runProgressScrubFinal(
      sessionId: sessionId,
      requestId: requestId,
      target: origin.totalProgression!,
      persist: true,
      closeAfter: true,
      canonicalOrigin: origin.position,
      command: command,
    );
  }

  @override
  Future<int> openProgressScrub({
    bool checkpointCurrentPosition = true,
    ReaderProgressCommandIdentity? command,
  }) async {
    final controller = _nativeController;
    if (_disposed || controller == null || !controller.isReady) {
      throw StateError('Reader is not ready for progress scrubbing.');
    }
    if (command != null && !isProgressCommandCurrent(command)) {
      throw ReaderProgressCommandFailure(
        'A newer reader command already owns navigation.',
        'superseded',
      );
    }
    if (command == null) _acceptedProgressCommandId = null;
    final previous = _activeProgressScrub;
    if (previous != null) await _invalidateProgressLease(previous);
    _persistTimer?.cancel();
    _persistTimer = null;
    if (checkpointCurrentPosition && _progressSavePending) {
      await _flushProgress(force: true);
    }
    await _progressWriteTail;
    if (command != null && !isProgressCommandCurrent(command)) {
      throw ReaderProgressCommandFailure(
        'A newer command superseded session opening.',
        'superseded',
      );
    }
    _completedProgressScrub = null;
    if (_disposed || controller != _nativeController) {
      throw StateError('Reader changed before progress scrubbing began.');
    }
    _persistTimer?.cancel();
    _persistTimer = null;
    final sessionId = ++_progressScrubSequence;
    final lease = _ActiveProgressScrub(
      sessionId: sessionId,
      originalPosition: _persistablePosition,
      writeGeneration: ++_progressWriteGeneration,
    );
    _rememberProgressCommand(sessionId, command);
    _activeProgressScrub = lease;
    try {
      await controller.openProgressScrubSession(sessionId);
      if (!identical(_activeProgressScrub, lease)) {
        throw StateError('Progress scrub was interrupted while opening.');
      }
      return sessionId;
    } on Object {
      if (identical(_activeProgressScrub, lease)) _activeProgressScrub = null;
      rethrow;
    }
  }

  @override
  bool isProgressScrubActive(int sessionId) =>
      !_disposed && _activeProgressScrub?.sessionId == sessionId;

  @override
  Future<void> previewProgressScrub({
    required int sessionId,
    required int requestId,
    required double target,
    ReaderProgressCommandIdentity? command,
  }) async {
    final controller = _nativeController;
    final lease = _activeProgressScrub;
    if (_disposed ||
        controller == null ||
        lease == null ||
        lease.sessionId != sessionId ||
        lease.finalRequestId != null ||
        requestId <= lease.latestRequestId) {
      return;
    }
    _rememberProgressCommand(sessionId, command);
    lease.latestRequestId = requestId;
    final owner = ReadiumProgressNavigationOwner(
      sessionId: sessionId,
      requestId: requestId,
      phase: 'preview',
    );
    try {
      final result = await controller.goToProgressionOwned(
        target,
        progressOwner: owner,
      );
      final current =
          identical(_activeProgressScrub, lease) &&
          lease.finalRequestId == null &&
          lease.latestRequestId == requestId;
      if ((!current || !result.isCompleted) &&
          result.status != 'recoveredTimeout') {
        progressDiagnostic({
          'kind': 'progress_preview_result',
          'gestureId': sessionId,
          'previewId': requestId,
          'isFinal': false,
          'result': !current
              ? 'superseded'
              : result.isCompleted
              ? 'completed'
              : 'failed',
          'newestPreviewId': lease.latestRequestId,
          'sideEffectsApplied': false,
        });
      }
      if (current && result.isCompleted) {
        progressDiagnostic({
          'kind': 'progress_persistence',
          'gestureId': sessionId,
          'previewId': requestId,
          'isFinal': false,
          'result': 'skipped_preview',
        });
      }
      if (!current || !result.isCompleted) {
        throw ReaderProgressCommandFailure(
          'Native preview did not commit.',
          result.status == 'recoveredTimeout'
              ? 'recovered_timeout'
              : !current || result.status == 'cancelled'
              ? 'superseded'
              : 'failed',
        );
      }
    } on ReaderProgressCommandFailure {
      rethrow;
    } on Object {
      progressDiagnostic({
        'kind': 'progress_preview_result',
        'gestureId': sessionId,
        'previewId': requestId,
        'isFinal': false,
        'result': 'failed',
        'reason': 'bridge_error',
      });
      rethrow;
    }
  }

  @override
  Future<void> finishProgressScrub({
    required int sessionId,
    required int requestId,
    required double target,
    ReaderProgressCommandIdentity? command,
  }) => _runProgressScrubFinal(
    sessionId: sessionId,
    requestId: requestId,
    target: target,
    persist: true,
    closeAfter: true,
    rememberForCancel: true,
    command: command,
  );

  @override
  Future<void> restoreProgressScrub({
    required int sessionId,
    required int requestId,
    required double target,
  }) async {
    final activePrevious = _activeProgressScrub?.sessionId == sessionId
        ? _activeProgressScrub
        : null;
    final completedPrevious = _completedProgressScrub?.sessionId == sessionId
        ? _completedProgressScrub
        : null;
    if (_disposed || (activePrevious == null && completedPrevious == null)) {
      return;
    }
    final originalPosition =
        activePrevious?.originalPosition ?? completedPrevious?.originalPosition;
    final controller = _nativeController;
    if (controller == null) return;
    if (activePrevious != null) await _invalidateProgressLease(activePrevious);
    _completedProgressScrub = null;
    if (_disposed || controller != _nativeController) return;
    final restoreSessionId = ++_progressScrubSequence;
    final lease = _ActiveProgressScrub(
      sessionId: restoreSessionId,
      originalPosition: originalPosition,
      writeGeneration: ++_progressWriteGeneration,
    );
    _activeProgressScrub = lease;
    try {
      await controller.openProgressScrubSession(restoreSessionId);
      await _runProgressScrubFinal(
        sessionId: restoreSessionId,
        requestId: requestId,
        target: target,
        persist: originalPosition == null
            ? _persistablePosition != null
            : !sameReadiumPositionForPerformance(
                originalPosition,
                _persistablePosition,
              ),
        expectedLease: lease,
        closeAfter: true,
      );
    } catch (_) {
      if (identical(_activeProgressScrub, lease)) {
        await _invalidateProgressLease(lease);
      }
      rethrow;
    }
  }

  @override
  Future<void> invalidateProgressScrub(int sessionId) async {
    final lease = _activeProgressScrub;
    if (lease != null && lease.sessionId == sessionId) {
      await _invalidateProgressLease(lease);
    }
    if (_completedProgressScrub?.sessionId == sessionId) {
      _completedProgressScrub = null;
    }
  }

  @override
  Future<void> closeProgressScrub(int sessionId) async {
    final lease = _activeProgressScrub;
    if (lease != null && lease.sessionId == sessionId) {
      await _invalidateProgressLease(lease);
    }
    if (_completedProgressScrub?.sessionId == sessionId) {
      _completedProgressScrub = null;
    }
  }

  Future<void> _runProgressScrubFinal({
    required int sessionId,
    required int requestId,
    required double target,
    required bool persist,
    _ActiveProgressScrub? expectedLease,
    required bool closeAfter,
    bool rememberForCancel = false,
    ReadiumPosition? canonicalOrigin,
    ReaderProgressCommandIdentity? command,
  }) async {
    final controller = _nativeController;
    final lease = expectedLease ?? _activeProgressScrub;
    if (_disposed ||
        controller == null ||
        lease == null ||
        lease.sessionId != sessionId ||
        !identical(_activeProgressScrub, lease) ||
        requestId <= lease.latestRequestId) {
      throw StateError('Progress scrub final request is stale.');
    }
    _rememberProgressCommand(sessionId, command);
    lease.latestRequestId = requestId;
    lease.finalRequestId = requestId;
    final finalPosition = Completer<ReadiumPosition>();
    unawaited(
      finalPosition.future.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      ),
    );
    lease.finalPosition = null;
    lease.finalPositionWaiter = finalPosition;
    final owner = ReadiumProgressNavigationOwner(
      sessionId: sessionId,
      requestId: requestId,
      phase: 'final',
    );
    var accepted = false;
    var navigationCommitted = false;
    var recoveredTimeout = false;
    var failureStage = 'publication';
    try {
      await controller.reserveProgressScrubFinal(owner);
      if (!identical(_activeProgressScrub, lease) || _disposed) {
        throw StateError('Progress scrub was interrupted before final seek.');
      }
      final result = canonicalOrigin == null
          ? await controller.goToProgressionOwned(target, progressOwner: owner)
          : await controller.goToProgressLocatorOwned(
              canonicalOrigin,
              progressOwner: owner,
            );
      recoveredTimeout = result.status == 'recoveredTimeout';
      if (!result.isCompleted) {
        throw ReaderProgressCommandFailure(
          'Native reader did not verify the final position.',
          recoveredTimeout
              ? 'recovered_timeout'
              : result.status == 'cancelled'
              ? 'superseded'
              : 'failed',
        );
      }
      navigationCommitted = true;
      if (result.positionPublicationFailed) {
        throw StateError('Verified navigation could not publish its position.');
      }
      final position = await finalPosition.future.timeout(
        const Duration(seconds: 8),
      );
      if (_disposed || !identical(_activeProgressScrub, lease)) {
        throw StateError('Progress scrub was interrupted before publication.');
      }
      if (persist &&
          (!sameReadiumPositionForPerformance(position, _persistablePosition) ||
              _progressSavePending)) {
        failureStage = 'persistence';
        _persistablePosition = position;
        _progressSavePending = true;
        await _flushProgress(
          force: true,
          scrubWriteGeneration: lease.writeGeneration,
        );
      }
      if (persist &&
          sameReadiumPositionForPerformance(position, _persistablePosition) &&
          !_diagnosticFinalPersisted) {
        progressDiagnostic({
          'kind': 'progress_persistence',
          'gestureId': sessionId,
          'previewId': requestId,
          'isFinal': true,
          'result': 'skipped_unchanged',
        });
      }
      _diagnosticFinalObserved = position.progression;
      accepted = true;
      if (rememberForCancel) {
        _completedProgressScrub = _CompletedProgressScrub(
          sessionId: lease.sessionId,
          originalPosition: lease.originalPosition,
        );
      }
    } on Object {
      progressDiagnostic({
        'kind': recoveredTimeout
            ? 'progress_final_target'
            : navigationCommitted
            ? failureStage == 'persistence'
                  ? 'progress_persistence'
                  : 'progress_position_publication'
            : 'progress_final_target',
        'gestureId': sessionId,
        'previewId': requestId,
        'isFinal': true,
        'result': recoveredTimeout ? 'recovered_timeout' : 'failed',
        'reason': navigationCommitted
            ? '${failureStage}_failed_after_verified_navigation'
            : 'final_not_committed',
      });
      if (rememberForCancel && identical(_activeProgressScrub, lease)) {
        _completedProgressScrub = _CompletedProgressScrub(
          sessionId: lease.sessionId,
          originalPosition: lease.originalPosition,
        );
      }
      rethrow;
    } finally {
      if ((!accepted || closeAfter) && identical(_activeProgressScrub, lease)) {
        await _invalidateProgressLease(lease);
      }
    }
  }

  Future<void> _invalidateProgressLease(_ActiveProgressScrub lease) async {
    if (!identical(_activeProgressScrub, lease)) return;
    _activeProgressScrub = null;
    ++_progressWriteGeneration;
    if (lease.finalPositionWaiter case final Completer<ReadiumPosition> waiter
        when !waiter.isCompleted) {
      waiter.completeError(StateError('Progress scrub was interrupted.'));
    }
    final controller = _nativeController;
    if (controller != null && !_disposed) {
      try {
        await controller.invalidateProgressScrubSession(lease.sessionId);
      } on Object {
        // The native session may already have been invalidated by navigation.
      }
    }
    notifyListeners();
  }

  void _interruptProgressScrub() {
    _acceptedProgressCommandId = null;
    final lease = _activeProgressScrub;
    if (lease == null) return;
    unawaited(_invalidateProgressLease(lease));
  }

  void _handleNativeState() {
    if (_disposed) return;
    final controller = _nativeController;
    if (controller == null) return;
    final state = controller.state;
    if (state.lastNavigationStartedSequence >
        _lastObservedNavigationStartedSequence) {
      _lastObservedNavigationStartedSequence =
          state.lastNavigationStartedSequence;
      final lease = _activeProgressScrub;
      final owner = state.lastNavigationProgressOwner;
      if (lease != null &&
          owner?.sessionId != lease.sessionId &&
          (owner == null || owner.sessionId > lease.sessionId)) {
        // A late NavigationStarted from an older command cannot revoke the new lease.
        _interruptProgressScrub();
      }
    }
    if (state.manualScrollActive != _lastManualScrollActive) {
      _lastManualScrollActive = state.manualScrollActive;
      if (_lastManualScrollActive) {
        if (_activeProgressScrub case final active?) {
          progressDiagnostic({
            'kind': 'progress_external_viewport_change',
            'source': 'user_scroll',
            'gestureId': active.sessionId,
            'activePreviewId': active.latestRequestId,
            'result': 'invalidated',
            'a11State': 'invalidated',
          });
        }
        _interruptProgressScrub();
        _persistTimer?.cancel();
        _persistTimer = null;
      } else if (_progressSavePending) {
        _scheduleProgressSave();
      }
    }
    final lease = _activeProgressScrub;
    final progressOwner = state.progressOwner;
    final positionEventIsCurrent = switch ((progressOwner, lease)) {
      (null, null) => true,
      (null, _) => false,
      (final owner?, final active?) =>
        owner.sessionId == active.sessionId &&
            ((owner.phase == 'preview' &&
                    active.finalRequestId == null &&
                    owner.requestId == active.latestRequestId) ||
                (owner.phase == 'final' &&
                    owner.requestId == active.finalRequestId)),
      _ => false,
    };
    final nativePosition = positionEventIsCurrent ? state.position : null;
    if (nativePosition != null &&
        lease != null &&
        progressOwner?.phase == 'final' &&
        progressOwner?.requestId == lease.finalRequestId) {
      lease.finalPosition = nativePosition;
      final waiter = lease.finalPositionWaiter;
      if (waiter != null && !waiter.isCompleted) {
        waiter.complete(nativePosition);
      }
    }
    final isNativePositionEvent =
        nativePosition != null &&
        !identical(nativePosition, _lastNativePositionEvent);
    if (isNativePositionEvent) {
      _lastNativePositionEvent = nativePosition;
      ReaderPerformance.recordNativePositionEvent(
        renderedPage:
            nativePosition.presentation is ReadiumPaginatedPresentation,
      );
    }
    if (!identical(state.chapter, _lastNativeChapterEvent)) {
      _lastNativeChapterEvent = state.chapter;
      ReaderPerformance.recordNativeChapterEvent();
    }
    final suppressReaderChrome = state.selection.sessionActive;
    if (_readerChromeSuppressed != suppressReaderChrome) {
      _readerChromeSuppressed = suppressReaderChrome;
      notifyListeners();
    }
    _lastContentTapViewportGeneration = state.selection.viewportEpoch;
    final mappedSearch = _mapSearchState(state.search);
    if (!_sameSearchState(searchState, mappedSearch)) {
      setSearchState(mappedSearch);
    }
    final appliedPreferences = state.preferences.applied;
    if (appliedPreferences != null) {
      _settings = appliedPreferences.toEpubReaderSettings();
    }
    if (state.hasFatalError ||
        state.lifecycle == ReadiumControllerLifecycle.failed) {
      setError(
        state.latestError ??
            controller.fatalError ??
            StateError('Readium reader failed'),
      );
      return;
    }
    if (state.lifecycle == ReadiumControllerLifecycle.disposed) {
      setError(StateError('Readium reader disposed'));
      return;
    }
    if (!state.isReady) {
      return;
    }
    if (!_ready) {
      _ready = true;
      ReaderPerformance.mark('READER_PERF_FIRST_CONTENT', type: 'readium');
      unawaited(_markOpened());
    }
    final position = nativePosition;
    if (isNativePositionEvent &&
        position != null &&
        !state.positionLiveManual &&
        _activeProgressScrub == null &&
        progressOwner == null) {
      _persistablePosition = position;
      _progressSavePending = true;
      _scheduleProgressSave();
    }
    if (position != null &&
        !sameReadiumPositionForPerformance(position, _lastPosition)) {
      _lastPosition = position;
      _bookmarkCoordinator?.updateCurrentTarget(
        ReaderLocatorBookmarkTarget.tryParse(
          locatorJson: position.locatorJson ?? '',
          progression: _positionProgression(position),
          chapterTitle: state.chapter.title,
          href: position.href,
        ),
      );
      final progression = _positionProgression(position);
      if (progression != null) {
        final locatorJson = _nonBlank(position.locatorJson);
        final presentation = position.presentation;
        final readerProgress = switch (presentation) {
          ReadiumPaginatedPresentation(
            :final pageIndex,
            :final pageCount,
            :final publicationScoped,
            progression: final renderedProgression,
          ) =>
            ReaderProgressState.renderedPage(
              pageIndex: pageIndex,
              pageCount: pageCount,
              progression: publicationScoped
                  ? renderedProgression
                  : progression,
              publicationScoped: publicationScoped,
            ),
          _ => ReaderProgressState.progression(progression: progression),
        };
        setProgress(
          readerProgress,
          seek: _seek,
          restore: locatorJson == null
              ? null
              : () => _restoreLocator(locatorJson),
        );
        if (!state.positionLiveManual) _scheduleProgressSave();
        return;
      }
    } else if (isNativePositionEvent) {
      // Keep identity aligned with the reducer while avoiding duplicate
      // bookmark updates and persistence timer restarts for equal payloads.
      _lastPosition = position;
    }
    if (position == null) setReady(seek: _seek);
  }

  Future<void> _restoreLocator(String locatorJson) async {
    final controller = _nativeController;
    if (_disposed || controller == null || !controller.isReady) return;
    await controller.goToLocatorJson(locatorJson);
  }

  double? _positionProgression(ReadiumPosition position) {
    // Native `progression` is the session's effective live viewport value.
    // In a one-resource publication it deliberately outranks the coarse
    // positions-service totalProgression carried by older locators.
    final value = position.progression ?? position.totalProgression;
    if (value != null && value.isFinite && value >= 0 && value <= 1) {
      return value;
    }
    return null;
  }

  void _scheduleProgressSave() {
    _persistTimer?.cancel();
    if (_lastManualScrollActive) {
      _persistTimer = null;
      _progressSavePending = true;
      return;
    }
    _persistTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_flushProgress());
    });
  }

  Future<void> _flushProgress({bool force = false, int? scrubWriteGeneration}) {
    final activeScrub = _activeProgressScrub;
    if (activeScrub != null &&
        activeScrub.writeGeneration != scrubWriteGeneration) {
      _progressSavePending = true;
      return _progressWriteTail;
    }
    if (scrubWriteGeneration != null &&
        (activeScrub == null ||
            activeScrub.writeGeneration != scrubWriteGeneration)) {
      return _progressWriteTail;
    }
    if (_lastManualScrollActive && !force) {
      _progressSavePending = true;
      return _progressWriteTail;
    }
    final position = _persistablePosition;
    final progression = position == null
        ? null
        : _positionProgression(position);
    final locator = _nonBlank(position?.locatorJson);
    if (_disposed && position == null) return _progressWriteTail;
    if (locator == null || progression == null) {
      if (scrubWriteGeneration != null) {
        return Future<void>.error(
          StateError('Final position cannot be persisted.'),
        );
      }
      return _progressWriteTail;
    }
    final progress = ReadingProgress(
      bookId: book.id,
      locatorJson: locator,
      progression: progression,
      currentChapterTitle: _nativeController?.chapter.title,
      currentPage: null,
      totalPages: null,
      updatedAt: DateTime.now(),
    );
    final writeGeneration = _progressWriteGeneration;
    final write = _progressWriteTail.then((_) async {
      if (writeGeneration != _progressWriteGeneration) return;
      final latestScrub = _activeProgressScrub;
      if (latestScrub != null &&
          latestScrub.writeGeneration != scrubWriteGeneration) {
        _progressSavePending = true;
        return;
      }
      if (scrubWriteGeneration != null &&
          latestScrub?.writeGeneration != scrubWriteGeneration) {
        return;
      }
      if (_lastManualScrollActive && !_disposed) {
        _progressSavePending = true;
        return;
      }
      await progressRepository.save(progress);
      if (scrubWriteGeneration != null) {
        progressDiagnostic({
          'kind': 'progress_persistence',
          'gestureId': latestScrub?.sessionId,
          'previewId': latestScrub?.finalRequestId,
          'isFinal': true,
          'result': 'written',
          'resourceHref': position?.href,
          'progression': position?.resourceProgression,
          'totalProgression': position?.totalProgression,
          'logicalPosition': position?.position,
        });
      }
      if (identical(_persistablePosition, position)) {
        _progressSavePending = false;
      }
    });
    _progressWriteTail = write.catchError((Object _) {});
    return scrubWriteGeneration != null ? write : _progressWriteTail;
  }

  Future<void> _markOpened() async {
    if (_markedOpened || libraryRepository == null) return;
    _markedOpened = true;
    try {
      await libraryRepository!.markBookOpened(book.id, DateTime.now());
    } catch (_) {
      // Opening remains successful when the auxiliary timestamp cannot save.
    }
  }

  Future<void> flushProgress() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    await _flushProgress();
  }

  void _notifyBookmarkChange() {
    if (!_disposed) notifyListeners();
  }

  void _notifyAnnotationChange() {
    if (!_disposed) notifyListeners();
  }

  Future<bool> _navigateBookmark(ReaderBookmarkTarget target) async {
    final controller = _nativeController;
    if (_disposed || controller == null || !controller.isReady) return false;
    if (target case ReaderLocatorBookmarkTarget(:final locatorJson)) {
      return (await controller.goToLocatorJson(locatorJson)).isSuccess;
    }
    return false;
  }

  bool _diagnosticFinalPersisted = false;
  bool _diagnosticFinalVerified = false;
  int _diagnosticSuperseded = 0;
  int _diagnosticActualNavigationCount = 0;
  double? _diagnosticFinalObserved;

  final _diagnosticNavigationGenerations = <String, int>{};
  int? _diagnosticActiveNavigationGeneration;
  bool _diagnosticNativeNavigationInFlight = false;

  @override
  void progressDiagnostic(Map<String, Object?> fields) {
    final context = _progressCommandContexts[fields['gestureId']];
    if (context != null &&
        fields['commandId'] == null &&
        fields['uiSessionId'] == null) {
      fields = {
        ...fields,
        'nativeSessionId': fields['gestureId'],
        ..._progressCommandFields(context),
      };
    }
    if (fields['kind'] == 'progress_command_authority') {
      fields = {
        ...fields,
        'navigationGeneration':
            _diagnosticNavigationGenerations['${fields['nativeSessionId']}:${fields['commandId']}'],
      };
    }
    final position = _nativeController?.state.position;
    if (fields['kind'] == 'progress_slider_start') {
      _diagnosticFinalPersisted = false;
      _diagnosticFinalVerified = false;
      _diagnosticSuperseded = 0;
      _diagnosticActualNavigationCount = 0;
      _diagnosticFinalObserved = null;
    }
    if (fields['kind'] == 'progress_navigation_terminal' &&
        fields['result'] == 'superseded') {
      _diagnosticSuperseded++;
    }
    if (fields['kind'] == 'progress_persistence' &&
        fields['result'] == 'written') {
      _diagnosticFinalPersisted = true;
    }
    _writeDiagnostic('debug', {
      'category': 'Reader.Progress',
      'currentResourceHref': position?.href,
      'currentCanonicalProgress': position?.progression,
      'currentTotalProgression': position?.totalProgression,
      'currentLogicalPosition': position?.position,
      ...fields,
      if (fields['kind'] == 'progress_ui_action') ...{
        'activeNavigationGeneration': _diagnosticNativeNavigationInFlight
            ? _diagnosticActiveNavigationGeneration
            : null,
        'nativeNavigationInFlight': _diagnosticNativeNavigationInFlight,
        if (fields['action'] == 'go_to_position')
          'dispatchState': _diagnosticNativeNavigationInFlight
              ? 'pending_active_navigation'
              : 'immediate',
      },
      if (fields['kind'] == 'progress_ui_callback_fence')
        'navigationGeneration':
            _diagnosticNavigationGenerations['${fields['nativeSessionId'] ?? fields['gestureId']}:${fields['previewId']}'],
      if (fields['gestureId'] == null)
        'gestureId': _activeProgressScrub?.sessionId,
      if (fields['kind'] == 'progress_gesture_terminal') ...{
        'finalObservedProgress': _diagnosticFinalObserved,
        'finalProgressError':
            _diagnosticFinalObserved == null ||
                fields['finalRequestedProgress'] is! double
            ? null
            : _diagnosticFinalObserved! -
                  (fields['finalRequestedProgress'] as double),
        'finalPersisted': _diagnosticFinalPersisted,
        'finalNavigationVerified': _diagnosticFinalVerified,
        'supersededNavigationCount': _diagnosticSuperseded,
        'actualNavigationCount': _diagnosticActualNavigationCount,
      },
    });
  }

  void _forwardReadiumDiagnostic(ReadiumDiagnosticEvent event) {
    final fields = event.fields;
    if (fields['category'] == 'Reader.Progress') {
      if (fields['kind'] == 'progress_navigation_start') {
        _diagnosticActiveNavigationGeneration =
            fields['navigationGeneration'] as int?;
        _diagnosticNativeNavigationInFlight = true;
        final generation = _diagnosticActiveNavigationGeneration;
        if (generation != null) {
          _diagnosticNavigationGenerations['${fields['gestureId']}:${fields['previewId']}'] =
              generation;
          if (_diagnosticNavigationGenerations.length > 16) {
            _diagnosticNavigationGenerations.remove(
              _diagnosticNavigationGenerations.keys.first,
            );
          }
        }
      } else if (fields['kind'] == 'progress_navigation_ownership' &&
          fields['result'] == 'released' &&
          fields['navigationGeneration'] ==
              _diagnosticActiveNavigationGeneration) {
        _diagnosticNativeNavigationInFlight = false;
      }
    }
    if (fields['category'] == 'Reader.Progress' &&
        fields['kind'] == 'progress_navigation_verified' &&
        fields['isFinal'] == true) {
      _diagnosticFinalVerified = fields['result'] == 'verified';
    }
    if (fields['category'] == 'Reader.Progress' &&
        fields['kind'] == 'progress_navigation_start') {
      _diagnosticActualNavigationCount++;
    }
    final level = switch (fields['level']) {
      'warning' => 'warning',
      'error' => 'error',
      'info' => 'info',
      _ => 'debug',
    };
    final context = _progressCommandContexts[fields['gestureId']];
    _writeDiagnostic(level, {
      ...fields,
      if (context != null) ...{
        'nativeSessionId': fields['gestureId'],
        ..._progressCommandFields(context),
      },
    });
  }

  void _writeDiagnostic(String level, Map<String, Object?> fields) {
    final logger = appLogService;
    if (logger == null) return;
    final category = fields['category'] == 'Reader.Progress'
        ? 'Reader.Progress'
        : 'Reader.Reflow';
    final message = fields.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    try {
      switch (level) {
        case 'error':
          logger.error(category: category, message: message);
        case 'warning':
          logger.warning(category: category, message: message);
        case 'info':
          logger.info(category: category, message: message);
        default:
          logger.debug(category: category, message: message);
      }
    } on Object {
      // Diagnostics are observers only and cannot affect reader behavior.
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _opening?.cancel();
    final activeScrub = _activeProgressScrub;
    _activeProgressScrub = null;
    ++_progressWriteGeneration;
    if (activeScrub?.finalPositionWaiter
        case final Completer<ReadiumPosition> waiter when !waiter.isCompleted) {
      waiter.completeError(
        StateError('Reader disposed during progress scrub.'),
      );
    }
    final controller = _nativeController;
    final diagnosticSubscription = _diagnosticSubscription;
    _diagnosticSubscription = null;
    final scrubInvalidation = activeScrub == null || controller == null
        ? Future<void>.value()
        : controller.invalidateProgressScrubSession(activeScrub.sessionId);
    _completedProgressScrub = null;
    _disposed = true;
    _persistTimer?.cancel();
    _persistTimer = null;
    if (controller != null) {
      controller.listenable.removeListener(_handleNativeState);
    }
    _bookmarkCoordinator?.removeListener(_notifyBookmarkChange);
    _bookmarkCoordinator?.dispose();
    _annotationMenuController?.removeListener(_notifyAnnotationChange);
    _annotationMenuController = null;
    final progress = _flushProgress(force: true);
    super.dispose();
    _disposal = () async {
      await scrubInvalidation.catchError((Object _) {});
      await progress;
      await diagnosticSubscription?.cancel();
      await controller?.dispose();
    }();
  }

  Future<void> disposeAndWait() {
    final existing = _disposal;
    if (existing != null) return existing;
    dispose();
    return _disposal ?? Future<void>.value();
  }
}

final class _ActiveProgressScrub {
  _ActiveProgressScrub({
    required this.sessionId,
    required this.originalPosition,
    required this.writeGeneration,
  });

  final int sessionId;
  final ReadiumPosition? originalPosition;
  final int writeGeneration;
  int latestRequestId = 0;
  int? finalRequestId;
  ReadiumPosition? finalPosition;
  Completer<ReadiumPosition>? finalPositionWaiter;
}

final class _CompletedProgressScrub {
  const _CompletedProgressScrub({
    required this.sessionId,
    required this.originalPosition,
  });

  final int sessionId;
  final ReadiumPosition? originalPosition;
}

@visibleForTesting
bool sameReadiumPositionForPerformance(
  ReadiumPosition value,
  ReadiumPosition? other,
) {
  if (other == null ||
      value.locatorJson != other.locatorJson ||
      value.href != other.href ||
      value.progression != other.progression ||
      value.resourceProgression != other.resourceProgression ||
      value.totalProgression != other.totalProgression ||
      value.position != other.position ||
      value.totalLogicalPositions != other.totalLogicalPositions ||
      !_sameStringList(value.fragments, other.fragments)) {
    return false;
  }
  return _sameReadiumPresentation(value.presentation, other.presentation);
}

bool _sameStringList(List<String> value, List<String> other) {
  if (value.length != other.length) return false;
  for (var index = 0; index < value.length; index++) {
    if (value[index] != other[index]) return false;
  }
  return true;
}

bool _sameReadiumPresentation(
  ReadiumPresentation value,
  ReadiumPresentation other,
) => switch ((value, other)) {
  (ReadiumUnknownPresentation(), ReadiumUnknownPresentation()) => true,
  (ReadiumScrollingPresentation(), ReadiumScrollingPresentation()) => true,
  (
    ReadiumPaginatedPresentation(
      :final pageIndex,
      :final pageCount,
      :final progression,
      :final layoutGeneration,
      :final publicationScoped,
    ),
    ReadiumPaginatedPresentation other,
  ) =>
    pageIndex == other.pageIndex &&
        pageCount == other.pageCount &&
        progression == other.progression &&
        layoutGeneration == other.layoutGeneration &&
        publicationScoped == other.publicationScoped,
  _ => false,
};

ReaderSearchState _mapSearchState(ReadiumSearchState state) =>
    switch (state.status) {
      ReadiumSearchStatus.idle => const ReaderSearchIdle(),
      ReadiumSearchStatus.loading => ReaderSearchLoading(
        query: state.query?.trim() ?? '',
      ),
      ReadiumSearchStatus.ready => ReaderSearchReady(
        query: state.query?.trim() ?? '',
        results: state.results
            .map(
              (result) => ReaderSearchResult(
                id: result.id,
                title: result.title,
                before: result.before,
                match: result.highlight,
                after: result.after,
                position: result.position,
                progression: result.progression,
              ),
            )
            .toList(growable: false),
        isComplete: !state.hasMore && !state.loadingMore,
      ),
      ReadiumSearchStatus.empty => ReaderSearchEmpty(
        query: state.query?.trim() ?? '',
      ),
      ReadiumSearchStatus.failed ||
      ReadiumSearchStatus.unknown => ReaderSearchFailure(
        query: state.query?.trim() ?? '',
        error: ReaderSearchError(code: state.errorCode ?? 'search_failed'),
      ),
    };

ReaderSearchCommandResult _mapSearchCommand(
  ReadiumSearchCommandResult result,
) => switch (result.status) {
  'started' => const ReaderSearchCommandResult.started(),
  'completed' => const ReaderSearchCommandResult(
    ReaderSearchCommandStatus.completed,
  ),
  'cleared' => const ReaderSearchCommandResult(
    ReaderSearchCommandStatus.cleared,
  ),
  'cancelled' => const ReaderSearchCommandResult(
    ReaderSearchCommandStatus.cancelled,
  ),
  'disposed' => const ReaderSearchCommandResult.disposed(),
  'unknownResultId' ||
  'obsoleteResultId' => const ReaderSearchCommandResult.stale(),
  _ => ReaderSearchCommandResult(
    ReaderSearchCommandStatus.failed,
    errorCode: result.status,
  ),
};

bool _sameSearchState(ReaderSearchState a, ReaderSearchState b) {
  if (a.runtimeType != b.runtimeType || a.query != b.query) return false;
  if (a is ReaderSearchLoading || a is ReaderSearchIdle) return true;
  if (a is ReaderSearchEmpty && b is ReaderSearchEmpty) return true;
  if (a is ReaderSearchFailure && b is ReaderSearchFailure) {
    return a.error.code == b.error.code;
  }
  if (a is ReaderSearchReady && b is ReaderSearchReady) {
    if (a.isComplete != b.isComplete || a.results.length != b.results.length) {
      return false;
    }
    for (var index = 0; index < a.results.length; index++) {
      final left = a.results[index];
      final right = b.results[index];
      if (left.id != right.id ||
          left.title != right.title ||
          left.before != right.before ||
          left.match != right.match ||
          left.after != right.after ||
          left.position != right.position ||
          left.progression != right.progression) {
        return false;
      }
    }
    return true;
  }
  return false;
}

ReaderTocEntry _mapTocEntry(ReadiumReaderTocEntry entry) => ReaderTocEntry(
  id: entry.id,
  title: entry.title,
  children: entry.children.map(_mapTocEntry).toList(growable: false),
);

String? _nonBlank(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

/// The snapshot retains the engine's actual PositionState/Locator, never a slider approximation.
final class _ReadiumProgressOrigin implements ReaderProgressOrigin {
  const _ReadiumProgressOrigin(this.owner, this.position);
  final Object owner;
  final ReadiumPosition position;
  @override
  int? get readingOrderIndex => position.readingOrderIndex;
  @override
  double? get resourceProgression => position.resourceProgression;
  @override
  double? get totalProgression =>
      position.totalProgression ?? position.progression;
  @override
  int? get logicalPosition => position.position;
}

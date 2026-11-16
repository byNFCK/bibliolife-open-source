import 'dart:async';

import 'package:bibliolife/features/reader/domain/models/reader_progress_state.dart';
import 'package:bibliolife/features/reader/presentation/models/reader_ui_controller.dart';
import 'package:bibliolife/features/reader/presentation/models/reader_progress_scrub_coordinator.dart';
import 'package:bibliolife/features/reader/presentation/models/reader_settings_preview_scheduler.dart';
import 'package:bibliolife/features/reader/domain/models/reader_settings.dart';
import 'package:bibliolife/features/reader/presentation/widgets/reader_search_sheet.dart';
import 'package:bibliolife/features/reader/presentation/widgets/reader_saved_items_sheet.dart';
import 'package:bibliolife/features/reader/presentation/widgets/reader_stable_components.dart';
import 'package:bibliolife/features/reader/performance/reader_performance.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:bibliolife/shared/presentation/widgets/app_modal_sheet_scaffold.dart';
import 'package:bibliolife/shared/presentation/widgets/biblio_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Shared Flutter chrome for every reader viewport.
class UnifiedReaderScreen extends StatefulWidget {
  const UnifiedReaderScreen({
    required this.book,
    required this.controller,
    required this.viewport,
    super.key,
  });

  final LibraryBook book;
  final ReaderUiController controller;
  final Widget viewport;

  @override
  State<UnifiedReaderScreen> createState() => _UnifiedReaderScreenState();
}

class _UnifiedReaderScreenState extends State<UnifiedReaderScreen> {
  Offset? _tapStart;
  var _pointerCount = 0;

  @override
  void initState() {
    super.initState();
    _syncSystemUi();
  }

  void _syncSystemUi() {
    // Chrome is an overlay. Keep the window edge-to-edge for both states so
    // toggling it cannot change insets, resize the PlatformView, or trigger
    // native re-pagination.
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  }

  @override
  void dispose() {
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointerCount++;
    if (_pointerCount == 1) _tapStart = event.position;
  }

  void _onPointerUp(PointerUpEvent event) {
    final start = _tapStart;
    final isTap =
        _pointerCount == 1 &&
        start != null &&
        (event.position - start).distance <= kTouchSlop;
    _pointerCount = (_pointerCount - 1).clamp(0, 99);
    if (_pointerCount == 0) _tapStart = null;
    if (isTap &&
        !widget.controller.isLoading &&
        widget.controller.error == null) {
      widget.controller.toggleControls();
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointerCount = (_pointerCount - 1).clamp(0, 99);
    if (_pointerCount == 0) _tapStart = null;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    resizeToAvoidBottomInset: false,
    backgroundColor: Theme.of(context).colorScheme.surface,
    body: Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          key: const Key('reader-stable-viewport-boundary'),
          child: _viewport(),
        ),
        AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => Stack(
            fit: StackFit.expand,
            children: [
              // Native Readium owns the loading surface once its PlatformView
              // is attached. Flutter-owned renderers keep a cheap overlay.
              if (widget.controller.isLoading &&
                  !widget.controller.capabilities.supportsNativeContentTap)
                const ColoredBox(
                  color: Color(0x33000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (widget.controller.error != null)
                _ReaderFailure(onClose: _close),
            ],
          ),
        ),
        Positioned.fill(
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) => _ReaderChrome(
              book: widget.book,
              controller: widget.controller,
              onClose: _close,
            ),
          ),
        ),
      ],
    ),
  );

  void _close() {
    ReaderPerformance.mark('READER_PERF_ROUTE_POP_START');
    if (context.canPop()) context.pop();
  }

  Widget _viewport() {
    ReaderPerformance.recordViewportWrapperBuild();
    // Readium emits a validated native content-tap event. Keeping Flutter's
    // pointer listener away from that PlatformView preserves selection,
    // handles, and Android ActionMode. Other Flutter-owned viewports retain
    // the existing central-tap chrome behavior.
    if (widget.controller.capabilities.supportsNativeContentTap) {
      return widget.viewport;
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: widget.viewport,
    );
  }
}

class _ReaderChrome extends StatelessWidget {
  const _ReaderChrome({
    required this.book,
    required this.controller,
    required this.onClose,
  });

  final LibraryBook book;
  final ReaderUiController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    ReaderPerformance.recordBackgroundChromeBuild();
    // Android's WebView magnifier copies pixels from the native window
    // surface. Remove Flutter reader chrome completely during a native text
    // selection so the lens can contain only publication content.
    if (controller.readerChromeSuppressed) return const SizedBox.shrink();
    final shown = controller.controlsVisible || controller.error != null;
    return IgnorePointer(
      ignoring: !shown,
      child: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Align(
                alignment: Alignment.topCenter,
                child: AnimatedSlide(
                  offset: shown ? Offset.zero : const Offset(0, -1.0),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: shown ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: ReaderSliderFocusOpacity(
                      activeSliderId: controller.activeSliderId,
                      child: _ReaderTopBar(
                        title: book.title,
                        onClose: onClose,
                        onToc: controller.tocController?.isReady == true
                            ? () => _showToc(context)
                            : null,
                        onSearch: _searchActionEnabled
                            ? () => unawaited(_showSearch(context))
                            : null,
                        onToggleBookmark: _bookmarkActionEnabled
                            ? () => unawaited(_toggleBookmark(context))
                            : null,
                        isBookmarked: controller
                            .bookmarkState
                            .isCurrentPositionBookmarked,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedSlide(
                  offset: shown ? Offset.zero : const Offset(0, 1.0),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: shown ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: ReaderSliderFocusOpacity(
                      activeSliderId: controller.activeSliderId,
                      child: _ReaderBottomBar(
                        controller: controller,
                        onBookmarks: _bookmarkActionEnabled
                            ? () => unawaited(_showBookmarks(context))
                            : null,
                        onProgress: controller.progress.canSeek
                            ? () => _showProgress(context)
                            : null,
                        onSettings: _settingsActionEnabled
                            ? () => _showSettings(context)
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _bookmarkActionEnabled {
    if (!controller.capabilities.supportsBookmarks) return false;
    final state = controller.bookmarkState;
    return controller.bookmarkCoordinator != null ||
        controller.annotationMenuController != null ||
        (state.currentTarget != null && !state.isLoading);
  }

  bool get _searchActionEnabled =>
      !controller.isLoading &&
      controller.error == null &&
      controller.capabilities.supportsSearch;

  bool get _settingsActionEnabled =>
      !controller.isLoading &&
      controller.error == null &&
      controller.readerSettings?.settingsCapabilities.isEmpty == false;

  Future<void> _toggleBookmark(BuildContext context) async {
    final result = controller.bookmarkState.isCurrentPositionBookmarked
        ? await controller.removeCurrentBookmark()
        : await controller.addBookmark();
    if (!context.mounted || result.isSuccess) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not save this bookmark.')),
    );
  }

  Future<void> _showBookmarks(BuildContext context) async {
    controller.showControls();
    await showReaderSavedItemsMenu<void>(
      context: context,
      controller: controller,
    );
  }

  void _showSettings(BuildContext context) {
    controller.showControls();
    showReaderMenu<void>(
      context: context,
      title: 'Reader settings',
      sliderInteractionController: controller,
      child: ReaderSettingsSheet(controller: controller),
    );
  }

  void _showToc(BuildContext context) {
    final toc = controller.tocController;
    if (toc == null || !toc.isReady) return;
    controller.showControls();
    showReaderMenu<void>(
      context: context,
      title: 'Table of contents',
      footer: const ReaderMenuSingleActionFooter(),
      child: _ReaderTocList(
        entries: toc.entries,
        onSelected: (id) async {
          Navigator.of(context).pop();
          await toc.goTo(id);
        },
      ),
    );
  }

  void _showProgress(BuildContext context) {
    controller.showControls();
    showReaderMenu<void>(
      context: context,
      title: 'Reading progress',
      sliderInteractionController: controller,
      child: _ReaderPageSheet(controller: controller),
    );
  }

  Future<void> _showSearch(BuildContext context) async {
    controller.showControls();
    await controller.clearSelectionForSearch();
    if (!context.mounted) return;
    try {
      await showReaderMenu<void>(
        context: context,
        title: 'Search in book',
        child: ReaderSearchSheet(controller: controller),
      );
    } finally {
      // Dismissal policy: close the UI, cancel active work, and clear only the
      // native temporary SEARCH_RESULT decoration.
      await controller.clearSearch();
    }
  }
}

class ReaderSettingsSheet extends StatefulWidget {
  const ReaderSettingsSheet({required this.controller, super.key});
  final ReaderUiController controller;

  @override
  State<ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<ReaderSettingsSheet> {
  late final ReaderSettingsHost? _host = widget.controller.readerSettings;
  late final ReaderSettingsState? _initial = _host?.state;
  late ReaderSettingsState? _draft = _initial;
  Future<void> _previewTail = Future<void>.value();
  late final ReaderSettingsPreviewScheduler _previewScheduler =
      ReaderSettingsPreviewScheduler(
        onCadence: () {
          unawaited(_onPreviewCadence());
        },
        requestRenderOpportunity: (onFrame) {
          SchedulerBinding.instance.addPostFrameCallback((_) => onFrame());
          SchedulerBinding.instance.scheduleFrame();
        },
      );
  var _previewGeneration = 0;
  ReaderSettingsState? _pendingPreview;
  int? _pendingPreviewRequestId;
  int? _activePreviewRequestId;
  var _pendingPreviewReportsErrors = false;
  ReaderSettingsDiagnosticGesture? _pendingPreviewDiagnosticGesture;
  final Map<ReaderSliderId, ReaderSettingsDiagnosticGesture>
  _diagnosticGestures = <ReaderSliderId, ReaderSettingsDiagnosticGesture>{};
  Future<void>? _previewTask;
  var _hasPreviewIntent = false;
  var _pendingPreviewReady = false;
  String? _error;
  var _actionInProgress = false;
  var _completed = false;

  Future<void> _preview(
    ReaderSettingsState next, {
    bool reportError = true,
    bool flush = true,
    ReaderSettingsDiagnosticGesture? diagnosticGesture,
  }) async {
    final host = _host;
    if (_actionInProgress || host == null) return;
    ++_previewGeneration;
    _hasPreviewIntent = true;
    setState(() {
      _draft = next;
      _error = null;
    });
    _pendingPreview = next;
    _pendingPreviewRequestId = null;
    _pendingPreviewReady = false;
    _pendingPreviewReportsErrors = reportError;
    _pendingPreviewDiagnosticGesture = diagnosticGesture;
    if (flush) {
      _previewScheduler.flush();
    } else {
      _previewScheduler.schedule();
    }
    final operation = _previewTask;
    if (operation != null) await operation;
  }

  Future<void> _onPreviewCadence() async {
    if (!mounted || _pendingPreview == null) {
      _previewScheduler.consumeUrgentTick();
      return;
    }
    final urgent = _previewScheduler.consumeUrgentTick();
    final current = _previewTask;
    if (current != null) {
      if (!urgent) {
        _previewScheduler.holdUntilActiveCompletes();
        await current;
        if (mounted) _previewScheduler.resume();
        return;
      }
      _pendingPreviewReady = true;
      final host = _host;
      final previewHost = host is ReaderSettingsPreviewRequestHost
          ? host as ReaderSettingsPreviewRequestHost
          : null;
      final nextRequestId = _pendingPreviewRequestId ??= previewHost
          ?.allocateSettingsPreviewRequestId();
      final activeRequestId = _activePreviewRequestId;
      if (previewHost != null &&
          nextRequestId != null &&
          activeRequestId != null) {
        await previewHost.supersedeSettingsPreviewsBefore(nextRequestId);
      }
      await current;
      if (mounted && _pendingPreviewReady && _pendingPreview != null) {
        _startPreviewDrain();
      }
      return;
    }
    _pendingPreviewReady = true;
    _startPreviewDrain();
  }

  void _startPreviewDrain() {
    final host = _host;
    if (host == null || _previewTask != null || !_pendingPreviewReady) return;
    final operation = _drainPreviews(host);
    _previewTask = operation;
    _previewTail = operation;
    unawaited(operation);
  }

  Future<void> _drainPreviews(ReaderSettingsHost host) async {
    if (_pendingPreview == null || !_pendingPreviewReady) {
      _previewTask = null;
      return;
    }
    final next = _pendingPreview!;
    final reportsErrors = _pendingPreviewReportsErrors;
    final diagnosticGesture = _pendingPreviewDiagnosticGesture;
    final previewHost = host is ReaderSettingsPreviewRequestHost
        ? host as ReaderSettingsPreviewRequestHost
        : null;
    final previewRequestId =
        _pendingPreviewRequestId ??
        previewHost?.allocateSettingsPreviewRequestId();
    final generation = _previewGeneration;
    _pendingPreview = null;
    _pendingPreviewReady = false;
    _pendingPreviewRequestId = null;
    _pendingPreviewDiagnosticGesture = null;
    _activePreviewRequestId = previewRequestId;
    _previewScheduler.recordDispatchStarted();
    try {
      if (host is ReaderSettingsPreviewRequestHost &&
          previewRequestId != null) {
        await (host as ReaderSettingsPreviewRequestHost)
            .previewSettingsWithRequestId(
              next,
              requestId: previewRequestId,
              gesture: diagnosticGesture,
            );
      } else if (host case final ReaderSettingsDiagnosticHost diagnosticHost) {
        await diagnosticHost.previewSettingsWithDiagnostics(
          next,
          gesture: diagnosticGesture,
        );
      } else {
        await host.previewSettings(next);
      }
    } catch (_) {
      if (reportsErrors && mounted && generation == _previewGeneration) {
        setState(() => _error = 'Could not apply this setting.');
      }
    } finally {
      _previewScheduler.recordCommitCompleted();
      if (_activePreviewRequestId == previewRequestId) {
        _activePreviewRequestId = null;
      }
      _previewTask = null;
    }
  }

  double _diagnosticSliderValue(ReaderSliderId sliderId) {
    final draft = _draft;
    if (draft == null) return 0;
    return switch (sliderId) {
      ReaderSliderId.fontSize => draft.typography?.fontSize ?? 0,
      ReaderSliderId.fontWeight => draft.typography?.fontWeight ?? 0,
      ReaderSliderId.lineHeight => draft.spacing?.lineHeight ?? 0,
      ReaderSliderId.margins => draft.spacing?.textMargins ?? 0,
      ReaderSliderId.pageSpacing => draft.spacing?.pageGap ?? 0,
      ReaderSliderId.progress => 0,
    };
  }

  Object? _startSettingsSliderInteraction(ReaderSliderId sliderId) {
    final focusToken = widget.controller.beginSliderInteraction(sliderId);
    final host = _host;
    final gesture = switch (sliderId) {
      ReaderSliderId.fontSize ||
      ReaderSliderId.fontWeight ||
      ReaderSliderId.lineHeight ||
      ReaderSliderId.margins ||
      ReaderSliderId.pageSpacing =>
        host is ReaderSettingsDiagnosticHost
            ? (host as ReaderSettingsDiagnosticHost).beginSettingsDiagnostic(
                sliderId,
                _diagnosticSliderValue(sliderId),
              )
            : null,
      ReaderSliderId.progress => null,
    };
    if (gesture != null) _diagnosticGestures[sliderId] = gesture;
    return _SettingsSliderInteractionToken(focusToken, gesture);
  }

  void _endSettingsSliderInteraction(ReaderSliderId sliderId, Object? value) {
    final token = value is _SettingsSliderInteractionToken
        ? value
        : _SettingsSliderInteractionToken(value, null);
    widget.controller.endSliderInteraction(sliderId, token.focusToken);
    final gesture = token.diagnosticGesture;
    if (gesture == null) return;
    if (_diagnosticGestures[sliderId]?.id == gesture.id) {
      _diagnosticGestures.remove(sliderId);
    }
    final host = _host;
    if (host is ReaderSettingsDiagnosticHost) {
      (host as ReaderSettingsDiagnosticHost).endSettingsDiagnostic(
        gesture,
        _diagnosticSliderValue(sliderId),
      );
    }
    unawaited(_releaseSettingsGestureAfterFinalPreview(gesture));
  }

  Future<void> _releaseSettingsGestureAfterFinalPreview(
    ReaderSettingsDiagnosticGesture gesture,
  ) async {
    final host = _host;
    if (host is! ReaderSettingsGestureBaselineHost) return;
    try {
      // onChangeEnd has already queued the exact final value. Its commit (and
      // any protected predecessor) must finish before releasing the baseline.
      while (mounted &&
          !_actionInProgress &&
          (_previewTask != null || _pendingPreview != null)) {
        if (_pendingPreview != null) _previewScheduler.flush();
        final current = _previewTask;
        if (current != null) await current;
      }
      await (host as ReaderSettingsGestureBaselineHost)
          .finishSettingsGestureBaseline(
            gesture,
            cancelled: !mounted || _actionInProgress || _error != null,
          );
    } on Object {
      // Route/session disposal also releases the native baseline.
    }
  }

  ReaderSettingsDiagnosticGesture? _diagnosticGestureFor(
    ReaderSliderId sliderId,
  ) => _diagnosticGestures[sliderId];

  @override
  Widget build(BuildContext context) {
    final host = _host;
    final draft = _draft;
    if (host == null || draft == null) return const SizedBox.shrink();
    final capabilities = host.settingsCapabilities;
    return PopScope<void>(
      canPop: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            fit: FlexFit.loose,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                ReaderStableTokens.sheetHorizontalPadding,
                ReaderStableTokens.menuContentTopPadding,
                ReaderStableTokens.sheetHorizontalPadding,
                ReaderStableTokens.menuContentBottomPadding,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_error != null) ...[
                    ReaderMenuCard(
                      minimumHeight: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: ReaderSliderFocusOpacity(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: ReaderStableTokens.menuRowGap),
                  ],
                  if (!capabilities.appearance.isEmpty) ...[
                    ReaderMenuSection(
                      title: 'Appearance',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _choice<ReaderTheme>(
                            label: 'Theme',
                            selected: draft.appearance?.theme,
                            values: const [
                              (ReaderTheme.system, 'System'),
                              (ReaderTheme.light, 'Light'),
                              (ReaderTheme.sepia, 'Sepia'),
                              (ReaderTheme.dark, 'Dark'),
                            ],
                            onSelected: (value) => _preview(
                              draft.copyWith(
                                appearance: draft.appearance!.copyWith(
                                  theme: value,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: ReaderStableTokens.menuRowGap),
                  ],
                  if (!capabilities.typography.isEmpty) ...[
                    ReaderMenuSection(
                      title: 'Typography',
                      child: Column(
                        children: [
                          if (capabilities.typography.fontFamily)
                            ReaderSettingsDropdownField<ReaderFontFamily>(
                              key: const Key('reader-font-family'),
                              label: 'Font family',
                              value: draft.typography!.fontFamily,
                              items: const [
                                DropdownMenuItem(
                                  value: ReaderFontFamily.original,
                                  child: Text('Original'),
                                ),
                                DropdownMenuItem(
                                  value: ReaderFontFamily.serif,
                                  child: Text('Serif'),
                                ),
                                DropdownMenuItem(
                                  value: ReaderFontFamily.sansSerif,
                                  child: Text('Sans serif'),
                                ),
                                DropdownMenuItem(
                                  value: ReaderFontFamily.dyslexic,
                                  child: Text('OpenDyslexic'),
                                ),
                                DropdownMenuItem(
                                  value: ReaderFontFamily.monospace,
                                  child: Text('Monospace'),
                                ),
                              ],
                              onChanged: _actionInProgress
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        _preview(
                                          draft.copyWith(
                                            typography: draft.typography!
                                                .copyWith(fontFamily: value),
                                          ),
                                        );
                                      }
                                    },
                            ),
                          if (capabilities.typography.fontFamily &&
                              capabilities.typography.fontSize)
                            const ReaderSettingsFieldDivider(),
                          if (capabilities.typography.fontSize)
                            ReaderStableSettingSlider(
                              sliderId: ReaderSliderId.fontSize,
                              label: 'Font size',
                              value: draft.typography!.fontSize,
                              min: .5,
                              max: 3,
                              enabled: !_actionInProgress,
                              onChanged: (value) => _preview(
                                _draft!.copyWith(
                                  typography: _draft!.typography!.copyWith(
                                    fontSize: value,
                                  ),
                                ),
                                flush: false,
                                reportError: false,
                                diagnosticGesture: _diagnosticGestureFor(
                                  ReaderSliderId.fontSize,
                                ),
                              ),
                              onChangeEnd: (value) => _preview(
                                _draft!.copyWith(
                                  typography: _draft!.typography!.copyWith(
                                    fontSize: value,
                                  ),
                                ),
                                flush: true,
                                diagnosticGesture: _diagnosticGestureFor(
                                  ReaderSliderId.fontSize,
                                ),
                              ),
                              onInteractionStart:
                                  _startSettingsSliderInteraction,
                              onInteractionEnd: _endSettingsSliderInteraction,
                            ),
                          if (capabilities.typography.fontWeight &&
                              (capabilities.typography.fontFamily ||
                                  capabilities.typography.fontSize))
                            const ReaderSettingsFieldDivider(),
                          if (capabilities.typography.fontWeight)
                            ReaderStableSettingSlider(
                              sliderId: ReaderSliderId.fontWeight,
                              label: 'Font weight',
                              value: draft.typography!.fontWeight,
                              min: 0,
                              max: 2.5,
                              enabled: !_actionInProgress,
                              onChanged: (value) => _preview(
                                _draft!.copyWith(
                                  typography: _draft!.typography!.copyWith(
                                    fontWeight: value,
                                  ),
                                ),
                                flush: false,
                                reportError: false,
                                diagnosticGesture: _diagnosticGestureFor(
                                  ReaderSliderId.fontWeight,
                                ),
                              ),
                              onChangeEnd: (value) => _preview(
                                _draft!.copyWith(
                                  typography: _draft!.typography!.copyWith(
                                    fontWeight: value,
                                  ),
                                ),
                                flush: true,
                                diagnosticGesture: _diagnosticGestureFor(
                                  ReaderSliderId.fontWeight,
                                ),
                              ),
                              onInteractionStart:
                                  _startSettingsSliderInteraction,
                              onInteractionEnd: _endSettingsSliderInteraction,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: ReaderStableTokens.menuRowGap),
                  ],
                  if (!capabilities.spacing.isEmpty) ...[
                    ReaderMenuSection(
                      title:
                          capabilities.profile ==
                              ReaderSettingsProfile.readiumReflowable
                          ? 'Spacing'
                          : 'Page',
                      child: Column(
                        children: [
                          if (capabilities.spacing.lineHeight)
                            ReaderStableSettingSlider(
                              sliderId: ReaderSliderId.lineHeight,
                              label: 'Line height',
                              value: draft.spacing!.lineHeight,
                              min: 1,
                              max: 2,
                              enabled: !_actionInProgress,
                              onChanged: (value) => _preview(
                                _withPublisherStylesDisabled(
                                  _draft!.copyWith(
                                    spacing: _draft!.spacing!.copyWith(
                                      lineHeight: value,
                                    ),
                                  ),
                                ),
                                flush: false,
                                reportError: false,
                                diagnosticGesture: _diagnosticGestureFor(
                                  ReaderSliderId.lineHeight,
                                ),
                              ),
                              onChangeEnd: (value) => _preview(
                                _withPublisherStylesDisabled(
                                  _draft!.copyWith(
                                    spacing: _draft!.spacing!.copyWith(
                                      lineHeight: value,
                                    ),
                                  ),
                                ),
                                flush: true,
                                diagnosticGesture: _diagnosticGestureFor(
                                  ReaderSliderId.lineHeight,
                                ),
                              ),
                              onInteractionStart:
                                  _startSettingsSliderInteraction,
                              onInteractionEnd: _endSettingsSliderInteraction,
                            ),
                          if (capabilities.spacing.lineHeight &&
                              capabilities.spacing.textMargins)
                            const ReaderSettingsFieldDivider(),
                          if (capabilities.spacing.textMargins)
                            ReaderStableSettingSlider(
                              sliderId: ReaderSliderId.margins,
                              label: 'Margins',
                              value: draft.spacing!.textMargins,
                              min: 0,
                              max: 4,
                              enabled: !_actionInProgress,
                              onChanged: (value) => _preview(
                                _draft!.copyWith(
                                  spacing: _draft!.spacing!.copyWith(
                                    textMargins: value,
                                  ),
                                ),
                                flush: false,
                                reportError: false,
                                diagnosticGesture: _diagnosticGestureFor(
                                  ReaderSliderId.margins,
                                ),
                              ),
                              onChangeEnd: (value) => _preview(
                                _draft!.copyWith(
                                  spacing: _draft!.spacing!.copyWith(
                                    textMargins: value,
                                  ),
                                ),
                                flush: true,
                                diagnosticGesture: _diagnosticGestureFor(
                                  ReaderSliderId.margins,
                                ),
                              ),
                              onInteractionStart:
                                  _startSettingsSliderInteraction,
                              onInteractionEnd: _endSettingsSliderInteraction,
                            ),
                          if (capabilities.spacing.pageGap &&
                              (capabilities.spacing.lineHeight ||
                                  capabilities.spacing.textMargins))
                            const ReaderSettingsFieldDivider(),
                          if (capabilities.spacing.pageGap)
                            ReaderStableSettingSlider(
                              sliderId: ReaderSliderId.pageSpacing,
                              label: 'Page gap',
                              value: draft.spacing!.pageGap,
                              min: 0,
                              max: 40,
                              enabled: !_actionInProgress,
                              onChanged: (value) => _preview(
                                _draft!.copyWith(
                                  spacing: _draft!.spacing!.copyWith(
                                    pageGap: value,
                                  ),
                                ),
                                flush: false,
                                reportError: false,
                                diagnosticGesture: _diagnosticGestureFor(
                                  ReaderSliderId.pageSpacing,
                                ),
                              ),
                              onChangeEnd: (value) => _preview(
                                _draft!.copyWith(
                                  spacing: _draft!.spacing!.copyWith(
                                    pageGap: value,
                                  ),
                                ),
                                flush: true,
                                diagnosticGesture: _diagnosticGestureFor(
                                  ReaderSliderId.pageSpacing,
                                ),
                              ),
                              onInteractionStart:
                                  _startSettingsSliderInteraction,
                              onInteractionEnd: _endSettingsSliderInteraction,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: ReaderStableTokens.menuRowGap),
                  ],
                  if (!capabilities.textLayout.isEmpty) ...[
                    ReaderMenuSection(
                      title: 'Text layout',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (capabilities.textLayout.alignment) ...[
                            _choice<ReaderTextAlignment>(
                              label: 'Text alignment',
                              selected: draft.textLayout!.alignment,
                              values: const [
                                (ReaderTextAlignment.start, 'Start'),
                                (ReaderTextAlignment.justify, 'Justify'),
                              ],
                              onSelected: (value) => _preview(
                                _withPublisherStylesDisabled(
                                  draft.copyWith(
                                    textLayout: draft.textLayout!.copyWith(
                                      alignment: value,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (capabilities.textLayout.alignment &&
                              capabilities.textLayout.readingMode)
                            const ReaderSettingsFieldDivider(),
                          if (capabilities.textLayout.readingMode) ...[
                            _choice<ReaderReadingMode>(
                              label: 'Reading mode',
                              selected: draft.textLayout!.readingMode,
                              values: _readingModeChoices(capabilities),
                              onSelected: (value) => _preview(
                                draft.copyWith(
                                  textLayout: draft.textLayout!.copyWith(
                                    readingMode: value,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (capabilities.textLayout.columns &&
                              (capabilities.textLayout.alignment ||
                                  capabilities.textLayout.readingMode))
                            const ReaderSettingsFieldDivider(),
                          if (capabilities.textLayout.columns) ...[
                            _choice<ReaderColumnCount>(
                              label: MediaQuery.sizeOf(context).width >= 600
                                  ? 'Columns'
                                  : 'Columns (wide screens)',
                              selected: draft.textLayout!.columns,
                              values: const [
                                (ReaderColumnCount.auto, 'Auto'),
                                (ReaderColumnCount.one, '1'),
                                (ReaderColumnCount.two, '2'),
                              ],
                              onSelected:
                                  draft.textLayout!.readingMode ==
                                          ReaderReadingMode.continuous ||
                                      MediaQuery.sizeOf(context).width < 600
                                  ? null
                                  : (value) => _preview(
                                      draft.copyWith(
                                        textLayout: draft.textLayout!.copyWith(
                                          columns: value,
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: ReaderStableTokens.menuRowGap),
                  ],
                  if (!capabilities.pageLayout.isEmpty) ...[
                    ReaderMenuSection(
                      title: 'Layout',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (capabilities.pageLayout.readingMode) ...[
                            _choice<ReaderReadingMode>(
                              label: 'Reading mode',
                              selected: draft.page!.readingMode,
                              values: _readingModeChoices(capabilities),
                              onSelected: (value) => _preview(
                                draft.copyWith(
                                  page: draft.page!.copyWith(
                                    readingMode: value,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (capabilities.pageLayout.readingMode &&
                              capabilities.pageLayout.readingDirection)
                            const ReaderSettingsFieldDivider(),
                          if (capabilities.pageLayout.readingDirection) ...[
                            _choice<ReaderReadingDirection>(
                              label: 'Reading direction',
                              selected: draft.page!.readingDirection,
                              values: const [
                                (ReaderReadingDirection.leftToRight, 'LTR'),
                                (
                                  ReaderReadingDirection.rightToLeft,
                                  'RTL Manga',
                                ),
                              ],
                              onSelected:
                                  draft.page!.readingMode ==
                                      ReaderReadingMode.continuous
                                  ? null
                                  : (value) => _preview(
                                      draft.copyWith(
                                        page: draft.page!.copyWith(
                                          readingDirection: value,
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: ReaderStableTokens.menuRowGap),
                  ],
                  if (!capabilities.image.isEmpty) ...[
                    ReaderMenuSection(
                      title: 'Image fitting',
                      child: _choice<ReaderImageFit>(
                        label: 'Scaling',
                        selected: draft.page!.imageFit,
                        values: const [
                          (ReaderImageFit.page, 'Fit page'),
                          (ReaderImageFit.width, 'Fit width'),
                        ],
                        onSelected: (value) => _preview(
                          draft.copyWith(
                            page: draft.page!.copyWith(imageFit: value),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: ReaderStableTokens.menuRowGap),
                  ],
                  if (!capabilities.sourceSpecific.isEmpty) ...[
                    ReaderMenuSection(
                      title: 'Advanced',
                      child: ReaderSettingsSwitchRow(
                        title: 'Publisher styles',
                        subtitle: 'Use the publication’s original formatting',
                        value: draft.sourceSpecific!.publisherStyles,
                        onChanged: _actionInProgress
                            ? null
                            : (value) => _preview(
                                draft.copyWith(
                                  sourceSpecific: draft.sourceSpecific!
                                      .copyWith(publisherStyles: value),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: ReaderStableTokens.menuRowGap),
                  ],
                ],
              ),
            ),
          ),
          ReaderSliderFocusOpacity(
            child: AppModalSheetDivider(
              key: const Key('reader-menu-lower-decorative-strip'),
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          ReaderSliderFocusOpacity(
            child: ReaderMenuFooter(
              onCancel: _actionInProgress ? null : _cancel,
              onApply: _actionInProgress || _draft == _initial ? null : _apply,
            ),
          ),
        ],
      ),
    );
  }

  List<(ReaderReadingMode, String)> _readingModeChoices(
    ReaderSettingsCapabilities capabilities,
  ) => [
    if (capabilities.readingModes.supportsPaginated)
      (ReaderReadingMode.paginated, 'Paginated'),
    if (capabilities.readingModes.supportsContinuousScroll)
      (ReaderReadingMode.continuous, 'Scroll'),
  ];

  Widget _choice<T extends Object>({
    required String label,
    required T? selected,
    required List<(T, String)> values,
    required ValueChanged<T>? onSelected,
  }) => ReaderSettingsChoiceField<T>(
    label: label,
    items: [
      for (final value in values)
        BiblioTabItem<T>(id: value.$1, label: value.$2),
    ],
    selectedId: selected,
    onSelected: _actionInProgress || onSelected == null
        ? null
        : (value) {
            if (value != selected) onSelected(value);
          },
  );

  ReaderSettingsState _withPublisherStylesDisabled(
    ReaderSettingsState settings,
  ) {
    final sourceSpecific = settings.sourceSpecific;
    if (_host?.settingsCapabilities.sourceSpecific.publisherStyles != true ||
        sourceSpecific == null ||
        !sourceSpecific.publisherStyles) {
      return settings;
    }
    return settings.copyWith(
      sourceSpecific: sourceSpecific.copyWith(publisherStyles: false),
    );
  }

  Future<void> _apply() async {
    if (_actionInProgress) return;
    final host = _host;
    if (host == null) return;
    if (host is ReaderSettingsDiagnosticHost) {
      (host as ReaderSettingsDiagnosticHost).logSettingsDiagnosticAction(
        'apply',
      );
    }
    setState(() => _actionInProgress = true);
    try {
      if (_pendingPreview != null) _previewScheduler.flush();
      while (_previewTask != null || _pendingPreview != null) {
        final current = _previewTask;
        if (current != null) {
          await current;
        } else if (_pendingPreview != null) {
          _previewScheduler.flush();
        }
      }
      final draft = _draft;
      if (draft == null) return;
      await host.commitSettings(draft);
      if (!mounted) return;
      _completed = true;
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save reader settings.');
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _cancel() async {
    if (_actionInProgress) return;
    final host = _host;
    if (host is ReaderSettingsDiagnosticHost) {
      (host as ReaderSettingsDiagnosticHost).logSettingsDiagnosticAction(
        'cancel',
      );
    }
    _previewScheduler.cancel();
    final baselineHost = host is ReaderSettingsGestureBaselineHost
        ? host as ReaderSettingsGestureBaselineHost
        : null;
    for (final gesture in _diagnosticGestures.values.toList()) {
      unawaited(
        baselineHost?.finishSettingsGestureBaseline(gesture, cancelled: true) ??
            Future<void>.value(),
      );
    }
    _diagnosticGestures.clear();
    _pendingPreview = null;
    _pendingPreviewReady = false;
    // Start the reverse transform before a potentially expensive Readium
    // reflow. PopScope restores the preview after the route is removed.
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _restoreDismissedPreview() async {
    final host = _host;
    final initial = _initial;
    if (_completed || host == null || initial == null) return;
    ++_previewGeneration;
    _previewScheduler.dispose();
    _pendingPreview = null;
    _pendingPreviewReady = false;
    if (_completed) return;
    if (!_hasPreviewIntent && host.state == initial) {
      if (host is ReaderSettingsGestureBaselineHost) {
        await (host as ReaderSettingsGestureBaselineHost)
            .cancelSettingsGestureBaselines();
      }
      return;
    }
    final previewHost = host is ReaderSettingsPreviewRequestHost
        ? host as ReaderSettingsPreviewRequestHost
        : null;
    final restoreRequestId = previewHost?.allocateSettingsPreviewRequestId();
    if (previewHost != null && restoreRequestId != null) {
      // Supersede first so an outstanding native preview cannot hold Cancel
      // behind its reflow barrier. The restore reuses this owner id below.
      await previewHost.supersedeSettingsPreviewsBefore(restoreRequestId);
    }
    if (host is ReaderSettingsGestureBaselineHost) {
      await (host as ReaderSettingsGestureBaselineHost)
          .cancelSettingsGestureBaselines();
    }
    try {
      try {
        await _previewTail;
      } on Object {
        // A superseded preview is expected to finish with a cancellation result.
      }
      if (previewHost != null && restoreRequestId != null) {
        await previewHost.previewSettingsWithRequestId(
          initial,
          requestId: restoreRequestId,
          gesture: null,
        );
      } else {
        await host.restoreSettings(initial);
      }
      _completed = true;
    } on Object {
      // The route has already closed, so there is no surviving Settings UI in
      // which to surface this recoverable renderer error.
    }
  }

  @override
  void dispose() {
    // Route removal follows the reverse animation, so restoring a preview here
    // cannot compete with the visible close transform.
    unawaited(_restoreDismissedPreview());
    _previewScheduler.dispose();
    super.dispose();
  }
}

class _SettingsSliderInteractionToken {
  const _SettingsSliderInteractionToken(
    this.focusToken,
    this.diagnosticGesture,
  );

  final Object? focusToken;
  final ReaderSettingsDiagnosticGesture? diagnosticGesture;
}

class _ReaderPageSheet extends StatefulWidget {
  const _ReaderPageSheet({required this.controller});
  final ReaderUiController controller;

  @override
  State<_ReaderPageSheet> createState() => _ReaderPageSheetState();
}

class _ReaderPageSheetState extends State<_ReaderPageSheet> {
  static int _nextUiSessionId = 0;
  late final int _uiSessionId = ++_nextUiSessionId;
  int _commandId = 0;
  bool _closed = false;
  late bool _lastCanSeek;
  late double _target = widget.controller.progress.progression;
  Future<void> _previewTail = Future<void>.value();
  ReaderProgressScrubCoordinator? _scrub;
  Future<void>? _finishFuture;
  String? _scrubError;
  var _isInteracting = false;
  Object? _interactionToken;

  @override
  void didUpdateWidget(covariant _ReaderPageSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _scrub?.invalidate();
      _scrub = null;
      _ensureScrub();
      widget.controller.addListener(_onControllerChanged);
      if (_isInteracting) {
        _isInteracting = false;
        oldWidget.controller.endSliderInteraction(
          ReaderSliderId.progress,
          _interactionToken,
        );
        _interactionToken = null;
      }
    } else if (_isInteracting && !widget.controller.progress.canSeek) {
      _endSliderInteraction();
    }
  }

  @override
  void initState() {
    super.initState();
    _lastCanSeek = widget.controller.progress.canSeek;
    widget.controller.addListener(_onControllerChanged);
    _ensureScrub();
  }

  void _onControllerChanged() {
    final canSeek = widget.controller.progress.canSeek;
    if (_isInteracting && !canSeek) _endSliderInteraction();
    if (_lastCanSeek != canSeek) {
      _lastCanSeek = canSeek;
      if (mounted && !_closed) setState(() {});
    }
  }

  void _startSliderInteraction() {
    if (_closed || _isInteracting) return;
    _isInteracting = true;
    _interactionToken = widget.controller.beginSliderInteraction(
      ReaderSliderId.progress,
    );
    _ensureScrub();
  }

  ReaderProgressScrubCoordinator? _ensureScrub() {
    final host = widget.controller.progressScrubHost;
    if (host == null) return null;
    return _scrub ??= ReaderProgressScrubCoordinator(
      host: host,
      uiSessionId: _uiSessionId,
    );
  }

  void _endSliderInteraction() {
    if (!_isInteracting) return;
    _isInteracting = false;
    widget.controller.endSliderInteraction(
      ReaderSliderId.progress,
      _interactionToken,
    );
    _interactionToken = null;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _scrub?.detachUi();
    _endSliderInteraction();
    super.dispose();
  }

  Future<void> _preview(double value) async {
    final target = _snapTarget(value, widget.controller.progress);
    _previewTail = _previewTail.then((_) async {
      if (_closed || !mounted) return;
      await widget.controller.seek(target);
      await _waitForNativePosition(target);
      if (mounted && !_closed && !_isAtTarget(target)) {
        setState(() => _target = widget.controller.progress.progression);
      }
    });
    await _previewTail;
  }

  void _previewProgress(double value, {double? uiValue}) {
    if (_closed) return;
    final target = _snapTarget(value, widget.controller.progress);
    final scrub = _scrub;
    if (scrub == null) {
      unawaited(_preview(target));
    } else {
      scrub.preview(target, uiValue: uiValue ?? value);
    }
  }

  void _finishProgress(double value) {
    if (_closed) return;
    final target = _snapTarget(value, widget.controller.progress);
    final scrub = _scrub;
    if (scrub == null) {
      unawaited(_preview(target).whenComplete(_endSliderInteraction));
      return;
    }
    final operation = scrub.finish(target, uiValue: value);
    final commandId = scrub.activeCommandId;
    _finishFuture = operation;
    // Finger ownership ends now; an old async result must not end a new gesture.
    _endSliderInteraction();
    unawaited(
      operation.then(
        (_) {
          if (mounted &&
              !_closed &&
              identical(_scrub, scrub) &&
              identical(_finishFuture, operation) &&
              scrub.isCommandCommitted(commandId)) {
            setState(() => _scrubError = null);
          }
        },
        onError: (Object error) {
          if (mounted &&
              !_closed &&
              identical(_scrub, scrub) &&
              identical(_finishFuture, operation) &&
              scrub.activeCommandId == commandId) {
            setState(() => _scrubError = error.toString());
          }
        },
      ),
    );
  }

  Future<void> _waitForNativePosition(double target) {
    if (_isAtTarget(target)) return Future<void>.value();
    final completer = Completer<void>();
    late VoidCallback listener;
    listener = () {
      if (_isAtTarget(target) && !completer.isCompleted) {
        completer.complete();
      }
    };
    widget.controller.addListener(listener);
    return completer.future
        .timeout(const Duration(milliseconds: 1200), onTimeout: () {})
        .whenComplete(() => widget.controller.removeListener(listener));
  }

  bool _isAtTarget(double target) {
    final progress = widget.controller.progress;
    if ((progress.metric == ReaderProgressMetric.fixedPage ||
            progress.metric == ReaderProgressMetric.renderedPage) &&
        progress.total > 1) {
      return progress.current + 1 == progress.pageFor(target);
    }
    return (progress.progression - target).abs() <= .02;
  }

  double _snapTarget(double value, ReaderProgressState progress) {
    final normalized = value.clamp(0.0, 1.0);
    if (progress.metric != ReaderProgressMetric.fixedPage ||
        progress.total <= 1) {
      return normalized;
    }
    final page = progress.pageFor(normalized);
    return (page - 1) / (progress.total - 1);
  }

  void _dismissed() {
    if (_closed) return;
    _closed = true;
    ++_commandId;
    _scrub?.detachUi();
    _endSliderInteraction();
  }

  void _cancel() {
    if (_closed) return;
    _closed = true;
    ++_commandId;
    // The rollback belongs to the reader command, not the disappearing widget.
    final rollback = _scrub?.cancel();
    if (rollback != null) unawaited(rollback);
    _endSliderInteraction();
    Navigator.of(context).pop();
  }

  void _apply() {
    if (_closed || !widget.controller.progress.canSeek || !_target.isFinite) {
      return;
    }
    final target = _snapTarget(_target, widget.controller.progress);
    final uiAction = ++_commandId;
    final scrub = _ensureScrub();
    setState(() => _scrubError = null);
    _endSliderInteraction();
    final operation = scrub != null
        ? scrub.goToPosition(target)
        : _preview(target);
    final commandId = scrub?.activeCommandId;
    _finishFuture = operation;
    unawaited(
      operation.then<void>(
        (_) {
          if (!mounted ||
              _closed ||
              uiAction != _commandId ||
              !identical(_scrub, scrub) ||
              (scrub != null && !scrub.isCommandCommitted(commandId))) {
            return;
          }
          _closed = true;
          scrub?.detachUi();
          Navigator.of(context).pop();
        },
        onError: (Object error) {
          if (mounted &&
              !_closed &&
              uiAction == _commandId &&
              identical(_scrub, scrub) &&
              (scrub == null || scrub.activeCommandId == commandId)) {
            setState(() => _scrubError = error.toString());
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.controller.progress;
    final available = progress.canSeek;
    final label = available
        ? 'Progress ${(_target * 100).round()}%'
        : 'Progress unavailable';
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _dismissed();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_scrubError case final error?)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(error, key: const Key('reader-progress-scrub-error')),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: ReaderMenuSection(
              title: label,
              child: ReaderSliderFocusOpacity(
                key: const ValueKey('reader-slider-focus-progress'),
                sliderId: ReaderSliderId.progress,
                child: Slider(
                  value: _target,
                  divisions:
                      progress.metric == ReaderProgressMetric.fixedPage &&
                          progress.total > 1
                      ? progress.total - 1
                      : null,
                  onChangeStart: available
                      ? (value) {
                          _startSliderInteraction();
                          _scrub?.sliderStart(value);
                        }
                      : null,
                  onChanged: !available
                      ? null
                      : (value) {
                          if (_closed) return;
                          final target = _snapTarget(value, progress);
                          setState(() => _target = target);
                          _previewProgress(target, uiValue: value);
                        },
                  onChangeEnd: !available ? null : _finishProgress,
                ),
              ),
            ),
          ),
          ReaderSliderFocusOpacity(
            child: AppModalSheetDivider(
              key: const Key('reader-menu-lower-decorative-strip'),
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          ReaderSliderFocusOpacity(
            child: ReaderMenuFooter(
              onCancel: _cancel,
              onApply: !available || !_target.isFinite ? null : _apply,
              applyLabel: 'Go to position',
            ),
          ),
        ],
      ),
    );
  }
}

class _ReaderTocList extends StatefulWidget {
  const _ReaderTocList({required this.entries, required this.onSelected});
  final List<ReaderTocEntry> entries;
  final ValueChanged<String> onSelected;

  @override
  State<_ReaderTocList> createState() => _ReaderTocListState();
}

class _ReaderTocListState extends State<_ReaderTocList> {
  late List<({ReaderTocEntry entry, int depth})> _rows = _flatten(
    widget.entries,
  );

  @override
  void didUpdateWidget(covariant _ReaderTocList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.entries, widget.entries)) {
      _rows = _flatten(widget.entries);
    }
  }

  List<({ReaderTocEntry entry, int depth})> _flatten(
    List<ReaderTocEntry> entries,
  ) {
    final rows = <({ReaderTocEntry entry, int depth})>[];
    void flatten(List<ReaderTocEntry> values, int depth) {
      for (final entry in values) {
        rows.add((entry: entry, depth: depth));
        flatten(entry.children, depth + 1);
      }
    }

    flatten(entries, 0);
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const Key('reader-toc-list'),
      padding: const EdgeInsets.symmetric(
        horizontal: ReaderStableTokens.sheetHorizontalPadding,
        vertical: 16,
      ),
      itemCount: _rows.length,
      separatorBuilder: (_, _) =>
          const SizedBox(height: ReaderStableTokens.menuRowGap),
      itemBuilder: (context, index) {
        ReaderMenuPerformanceScope.recordRowBuild(context);
        final row = _rows[index];
        final indent = row.depth.clamp(0, 3) * 16.0;
        return Semantics(
          button: true,
          label: row.entry.title,
          child: ReaderMenuCard(
            key: ValueKey('reader-toc-entry-${row.entry.id}'),
            minimumHeight: ReaderStableTokens.menuRowMinimumHeight,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => widget.onSelected(row.entry.id),
              child: Padding(
                padding: EdgeInsets.fromLTRB(16 + indent, 14, 8, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    row.entry.title,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReaderTopBar extends StatelessWidget {
  const _ReaderTopBar({
    required this.title,
    required this.onClose,
    required this.onToc,
    required this.onSearch,
    required this.onToggleBookmark,
    required this.isBookmarked,
  });
  final String title;
  final VoidCallback onClose;
  final VoidCallback? onToc;
  final VoidCallback? onSearch;
  final VoidCallback? onToggleBookmark;
  final bool isBookmarked;

  @override
  Widget build(BuildContext context) => ReaderStableChromeSurface(
    key: const Key('reader-top-chrome-surface'),
    margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
    child: Row(
      children: [
        ReaderStableIconButton(
          tooltip: 'Close reader',
          asset: 'assets/readium/stable/ic_reader_close.svg',
          onPressed: onClose,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Material(
              key: const Key('reader-title-toc-control'),
              color: ReaderChromeReferenceTokens.controlBackground(context),
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onToc,
                child: SizedBox(
                  height: 48,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color:
                                  ReaderChromeReferenceTokens.controlForeground(
                                    context,
                                  ),
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        ReaderStableIconButton(
          tooltip: 'Search',
          asset: 'assets/readium/stable/ic_reader_search.svg',
          onPressed: onSearch,
        ),
        if (onToggleBookmark != null)
          ReaderStableIconButton(
            key: const Key('reader-bookmark-toggle'),
            tooltip: isBookmarked ? 'Remove bookmark' : 'Add bookmark',
            asset: isBookmarked
                ? 'assets/readium/stable/ic_reader_bookmark_filled.svg'
                : 'assets/readium/stable/ic_reader_bookmark.svg',
            color: isBookmarked ? Theme.of(context).colorScheme.primary : null,
            onPressed: onToggleBookmark,
          ),
      ],
    ),
  );
}

class _ReaderBottomBar extends StatelessWidget {
  const _ReaderBottomBar({
    required this.controller,
    required this.onBookmarks,
    required this.onProgress,
    required this.onSettings,
  });
  final ReaderUiController controller;
  final VoidCallback? onBookmarks;
  final VoidCallback? onProgress;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) => ReaderStableChromeSurface(
    key: const Key('reader-bottom-chrome-surface'),
    floatingNavigationShell: true,
    margin: const EdgeInsets.only(bottom: 18),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onBookmarks != null)
          ReaderStableIconButton(
            key: const Key('reader-bookmarks-list'),
            tooltip: 'Bookmarks and annotations',
            asset: 'assets/readium/stable/ic_reader_annotations.svg',
            onPressed: onBookmarks,
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Material(
            key: const Key('reader-page-control'),
            color: ReaderChromeReferenceTokens.controlBackground(context),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: onProgress,
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: 112,
                height: 40,
                child: Center(
                  child: Text(
                    controller.progress.metric == ReaderProgressMetric.unknown
                        ? 'Progress unavailable'
                        : 'Progress ${(controller.progress.progression * 100).round()}%',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: ReaderChromeReferenceTokens.controlForeground(
                        context,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        ReaderStableIconButton(
          tooltip: 'Reader settings',
          asset: 'assets/readium/stable/ic_reader_settings.svg',
          onPressed: onSettings,
        ),
      ],
    ),
  );
}

class _ReaderFailure extends StatelessWidget {
  const _ReaderFailure({required this.onClose});
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            const Text(
              'This book could not be opened.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onClose, child: const Text('Close')),
          ],
        ),
      ),
    ),
  );
}

import 'dart:async';

import 'package:bibliolife_readium/bibliolife_readium.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

const readerPerformanceLogsEnabled = bool.fromEnvironment(
  'BIBLIOLIFE_READER_PERF_LOGS',
  defaultValue: false,
);

abstract final class ReaderPerformance {
  static var _nativePositionEvents = 0;
  static var _nativeRenderedPageEvents = 0;
  static var _nativeChapterEvents = 0;
  static var _controllerNotifications = 0;
  static var _backgroundChromeBuilds = 0;
  static var _viewportWrapperBuilds = 0;

  static void mark(String name, {Duration? elapsed, String? type}) {
    if (!readerPerformanceLogsEnabled) return;
    final fields = <String>[
      name,
      if (type != null) 'type=$type',
      if (elapsed != null) 'durationMs=${elapsed.inMicroseconds / 1000}',
    ];
    debugPrint(fields.join(' '));
  }

  static void recordNativePositionEvent({required bool renderedPage}) {
    if (!readerPerformanceLogsEnabled) return;
    _nativePositionEvents++;
    if (renderedPage) _nativeRenderedPageEvents++;
  }

  static void recordNativeChapterEvent() {
    if (readerPerformanceLogsEnabled) _nativeChapterEvents++;
  }

  static void recordControllerNotification() {
    if (readerPerformanceLogsEnabled) _controllerNotifications++;
  }

  static void recordBackgroundChromeBuild() {
    if (readerPerformanceLogsEnabled) _backgroundChromeBuilds++;
  }

  static void recordViewportWrapperBuild() {
    if (readerPerformanceLogsEnabled) _viewportWrapperBuilds++;
  }

  static ReaderPerformanceActivitySnapshot activitySnapshot() =>
      ReaderPerformanceActivitySnapshot(
        nativePositionEvents: _nativePositionEvents,
        nativeRenderedPageEvents: _nativeRenderedPageEvents,
        nativeChapterEvents: _nativeChapterEvents,
        controllerNotifications: _controllerNotifications,
        backgroundChromeBuilds: _backgroundChromeBuilds,
        viewportWrapperBuilds: _viewportWrapperBuilds,
      );
}

class ReaderPerformanceActivitySnapshot {
  const ReaderPerformanceActivitySnapshot({
    required this.nativePositionEvents,
    required this.nativeRenderedPageEvents,
    required this.nativeChapterEvents,
    required this.controllerNotifications,
    required this.backgroundChromeBuilds,
    required this.viewportWrapperBuilds,
  });

  final int nativePositionEvents;
  final int nativeRenderedPageEvents;
  final int nativeChapterEvents;
  final int controllerNotifications;
  final int backgroundChromeBuilds;
  final int viewportWrapperBuilds;

  ReaderPerformanceActivitySnapshot since(
    ReaderPerformanceActivitySnapshot earlier,
  ) => ReaderPerformanceActivitySnapshot(
    nativePositionEvents: nativePositionEvents - earlier.nativePositionEvents,
    nativeRenderedPageEvents:
        nativeRenderedPageEvents - earlier.nativeRenderedPageEvents,
    nativeChapterEvents: nativeChapterEvents - earlier.nativeChapterEvents,
    controllerNotifications:
        controllerNotifications - earlier.controllerNotifications,
    backgroundChromeBuilds:
        backgroundChromeBuilds - earlier.backgroundChromeBuilds,
    viewportWrapperBuilds:
        viewportWrapperBuilds - earlier.viewportWrapperBuilds,
  );

  int get backgroundReaderRebuilds =>
      backgroundChromeBuilds + viewportWrapperBuilds;
}

final class ReaderFrameTimingObserver {
  ReaderFrameTimingObserver({
    this.summaryMarker = 'READER_PERF_FRAME_SUMMARY',
    this.type,
  });

  final String summaryMarker;
  final String? type;
  final List<FrameTiming> _timings = <FrameTiming>[];
  var _started = false;

  void start() {
    if (!readerPerformanceLogsEnabled || _started) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> values) => _timings.addAll(values);

  ReaderFrameTimingSummary stop() {
    if (!_started) return ReaderFrameTimingSummary.empty;
    _started = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    final over16 = _timings
        .where((value) => value.totalSpan.inMicroseconds > 16667)
        .length;
    final over33 = _timings
        .where((value) => value.totalSpan.inMicroseconds > 33333)
        .length;
    final over8 = _timings
        .where((value) => value.totalSpan.inMicroseconds > 8333)
        .length;
    final worstBuild = _timings.fold<int>(
      0,
      (value, timing) => value > timing.buildDuration.inMicroseconds
          ? value
          : timing.buildDuration.inMicroseconds,
    );
    final worstRaster = _timings.fold<int>(
      0,
      (value, timing) => value > timing.rasterDuration.inMicroseconds
          ? value
          : timing.rasterDuration.inMicroseconds,
    );
    final summary = ReaderFrameTimingSummary(
      frames: _timings.length,
      over8: over8,
      over16: over16,
      over33: over33,
      worstBuildMicros: worstBuild,
      worstRasterMicros: worstRaster,
    );
    debugPrint(
      '$summaryMarker ${type == null ? '' : 'type=$type '}${summary.fields}',
    );
    _timings.clear();
    return summary;
  }
}

class ReaderFrameTimingSummary {
  const ReaderFrameTimingSummary({
    required this.frames,
    required this.over8,
    required this.over16,
    required this.over33,
    required this.worstBuildMicros,
    required this.worstRasterMicros,
  });

  static const empty = ReaderFrameTimingSummary(
    frames: 0,
    over8: 0,
    over16: 0,
    over33: 0,
    worstBuildMicros: 0,
    worstRasterMicros: 0,
  );
  final int frames;
  final int over8;
  final int over16;
  final int over33;
  final int worstBuildMicros;
  final int worstRasterMicros;

  String get fields =>
      'frames=$frames over8=$over8 over16=$over16 over33=$over33 '
      'worstBuildMs=${worstBuildMicros / 1000} worstRasterMs=${worstRasterMicros / 1000}';
}

/// Debug-only lifecycle and scroll diagnostics for one reader modal.
///
/// The counters deliberately live outside the menu subtree: observing them
/// never makes the child listen to frame timings or scroll notifications.
class ReaderMenuPerformanceScope extends StatefulWidget {
  const ReaderMenuPerformanceScope({
    required this.type,
    required this.child,
    super.key,
  });

  final String type;
  final Widget child;

  static void recordRowBuild(BuildContext context) {
    context
        .findAncestorStateOfType<_ReaderMenuPerformanceScopeState>()
        ?._rowBuilds++;
  }

  @override
  State<ReaderMenuPerformanceScope> createState() =>
      _ReaderMenuPerformanceScopeState();
}

class _ReaderMenuPerformanceScopeState
    extends State<ReaderMenuPerformanceScope> {
  late final ReaderPerformanceActivitySnapshot _activityAtOpen =
      ReaderPerformance.activitySnapshot();
  late final ReaderFrameTimingObserver _openFrames = ReaderFrameTimingObserver(
    summaryMarker: 'READER_PERF_MENU_OPEN',
    type: widget.type,
  );
  late final ReaderFrameTimingObserver _scrollFrames =
      ReaderFrameTimingObserver(
        summaryMarker: 'READER_PERF_MENU_SCROLL',
        type: widget.type,
      );
  late final ReaderFrameTimingObserver _closeFrames = ReaderFrameTimingObserver(
    summaryMarker: 'READER_PERF_MENU_CLOSE',
    type: widget.type,
  );
  ReaderFrameTimingSummary _openSummary = ReaderFrameTimingSummary.empty;
  ReaderFrameTimingSummary _scrollSummary = ReaderFrameTimingSummary.empty;
  ReaderFrameTimingSummary _closeSummary = ReaderFrameTimingSummary.empty;
  Animation<double>? _routeAnimation;
  var _rootBuilds = 0;
  var _contentBuilds = 0;
  var _rowBuilds = 0;
  var _scrollSessions = 0;
  var _scrolling = false;

  @override
  void initState() {
    super.initState();
    _openFrames.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || identical(animation, _routeAnimation)) return;
    _routeAnimation = animation;
    animation.addStatusListener(_onRouteStatus);
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _openSummary = _openFrames.stop();
    if (status == AnimationStatus.reverse) _closeFrames.start();
    if (status == AnimationStatus.dismissed) {
      _closeSummary = _closeFrames.stop();
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification && !_scrolling) {
      _scrolling = true;
      _scrollSessions++;
      _scrollFrames.start();
    } else if (notification is ScrollEndNotification && _scrolling) {
      _scrolling = false;
      _scrollSummary = _scrollFrames.stop();
    }
    return false;
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    if (_scrolling) _scrollSummary = _scrollFrames.stop();
    _openSummary = _openFrames.stop();
    _closeSummary = _closeFrames.stop();
    if (readerPerformanceLogsEnabled) {
      final activity = ReaderPerformance.activitySnapshot().since(
        _activityAtOpen,
      );
      debugPrint(
        'READER_PERF_MENU_SUMMARY type=${widget.type} '
        'open${_summaryFields(_openSummary)} '
        'scroll${_summaryFields(_scrollSummary)} '
        'close${_summaryFields(_closeSummary)} '
        'menuRootBuilds=$_rootBuilds menuContentBuilds=$_contentBuilds '
        'rowBuilds=$_rowBuilds '
        'scrollSessions=$_scrollSessions classification=${_classification()} '
        'nativePositionEvents=${activity.nativePositionEvents} '
        'nativeRenderedPageEvents=${activity.nativeRenderedPageEvents} '
        'nativeChapterEvents=${activity.nativeChapterEvents} '
        'controllerNotifications=${activity.controllerNotifications} '
        'backgroundReaderRebuilds=${activity.backgroundReaderRebuilds} '
        'backgroundChromeBuilds=${activity.backgroundChromeBuilds} '
        'viewportWrapperBuilds=${activity.viewportWrapperBuilds} '
        'platformViewBackend='
        '${ReadiumAndroidCompositionDiagnostics.activeBackendLabel}',
      );
    }
    super.dispose();
  }

  String _summaryFields(ReaderFrameTimingSummary value) =>
      'Frames=${value.frames} Over8=${value.over8} Over16=${value.over16} '
      'Over33=${value.over33} WorstBuildMs=${value.worstBuildMicros / 1000} '
      'WorstRasterMs=${value.worstRasterMicros / 1000}';

  String _classification() {
    final build = [_openSummary, _scrollSummary, _closeSummary].fold(
      0,
      (max, value) =>
          value.worstBuildMicros > max ? value.worstBuildMicros : max,
    );
    final raster = [_openSummary, _scrollSummary, _closeSummary].fold(
      0,
      (max, value) =>
          value.worstRasterMicros > max ? value.worstRasterMicros : max,
    );
    if (build == 0 && raster == 0) return 'noEvidence';
    if (build > raster * 3 ~/ 2) return 'likelyBuildBound';
    if (raster > build * 3 ~/ 2) return 'likelyRasterBound';
    return 'mixed';
  }

  @override
  Widget build(BuildContext context) {
    _rootBuilds++;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: _ReaderMenuContentBuildCounter(
        onBuild: () => _contentBuilds++,
        child: widget.child,
      ),
    );
  }
}

class _ReaderMenuContentBuildCounter extends StatelessWidget {
  const _ReaderMenuContentBuildCounter({
    required this.onBuild,
    required this.child,
  });

  final VoidCallback onBuild;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    onBuild();
    return child;
  }
}

class ReaderPerformanceFirstFrame extends StatefulWidget {
  const ReaderPerformanceFirstFrame({
    required this.marker,
    required this.child,
    this.type,
    this.settledMarker,
    this.settleDelay = const Duration(milliseconds: 200),
    super.key,
  });

  final String marker;
  final String? type;
  final String? settledMarker;
  final Duration settleDelay;
  final Widget child;

  @override
  State<ReaderPerformanceFirstFrame> createState() =>
      _ReaderPerformanceFirstFrameState();
}

class _ReaderPerformanceFirstFrameState
    extends State<ReaderPerformanceFirstFrame> {
  Timer? _settleTimer;

  @override
  void initState() {
    super.initState();
    if (readerPerformanceLogsEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ReaderPerformance.mark(widget.marker, type: widget.type);
      });
      if (widget.settledMarker != null) {
        _settleTimer = Timer(widget.settleDelay, () {
          if (mounted) {
            ReaderPerformance.mark(widget.settledMarker!, type: widget.type);
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

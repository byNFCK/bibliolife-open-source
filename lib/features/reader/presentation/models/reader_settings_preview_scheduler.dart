import 'dart:async';

typedef ReaderPreviewFrameRequest = void Function(void Function() onFrame);

/// Coalesces raw slider samples and paces ordinary native reflows.
class ReaderSettingsPreviewScheduler {
  ReaderSettingsPreviewScheduler({
    required this.onCadence,
    this.interval = const Duration(milliseconds: 120),
    this.requestRenderOpportunity,
    Duration Function()? elapsed,
  }) : _clock = Stopwatch()..start() {
    _elapsedOverride = elapsed;
  }

  final void Function() onCadence;
  final Duration interval;
  final ReaderPreviewFrameRequest? requestRenderOpportunity;

  final Stopwatch _clock;
  Duration Function()? _elapsedOverride;
  Timer? _timer;
  Duration? _lastStart;
  var _disposed = false;
  var _held = false;
  var _urgentTick = false;
  var _renderOpportunityNeeded = false;
  var _renderOpportunityPending = false;
  var _renderGeneration = 0;

  Duration get _elapsed => _elapsedOverride?.call() ?? _clock.elapsed;

  void schedule() {
    if (_disposed || _held || _timer != null || _renderOpportunityPending) {
      return;
    }
    final lastStart = _lastStart;
    final wait = lastStart == null
        ? interval
        : interval - (_elapsed - lastStart);
    _timer = Timer(wait.isNegative ? Duration.zero : wait, () {
      _timer = null;
      if (!_disposed && !_held) _runCadence();
    });
  }

  /// Records the actual start of an expensive native apply, not a slider tick.
  void recordDispatchStarted() => _lastStart = _elapsed;

  /// Requires an ordinary pending preview to yield one UI render opportunity.
  /// This is not evidence that the WebView compositor presented a frame.
  void recordCommitCompleted() => _renderOpportunityNeeded = true;

  void holdUntilActiveCompletes() {
    _held = true;
    _timer?.cancel();
    _timer = null;
  }

  void resume() {
    if (_disposed) return;
    _held = false;
    schedule();
  }

  bool consumeUrgentTick() {
    final urgent = _urgentTick;
    _urgentTick = false;
    return urgent;
  }

  void _runCadence() {
    if (_renderOpportunityNeeded && requestRenderOpportunity != null) {
      _renderOpportunityNeeded = false;
      _renderOpportunityPending = true;
      final generation = ++_renderGeneration;
      requestRenderOpportunity!(() {
        if (_disposed || generation != _renderGeneration) return;
        _renderOpportunityPending = false;
        onCadence();
      });
      return;
    }
    _renderOpportunityNeeded = false;
    onCadence();
  }

  /// Final slider values and Apply bypass both the interval and frame gate.
  void flush() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    _held = false;
    _renderOpportunityPending = false;
    _renderOpportunityNeeded = false;
    ++_renderGeneration;
    _urgentTick = true;
    onCadence();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _held = false;
    _urgentTick = false;
    _renderOpportunityPending = false;
    _renderOpportunityNeeded = false;
    ++_renderGeneration;
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}

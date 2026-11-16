enum ReaderProgressMetric {
  unknown,
  fixedPage,
  renderedPage,
  reflowablePosition,
  progression,
}

class ReaderProgressState {
  const ReaderProgressState({
    required this.current,
    required this.total,
    required this.label,
    required this.metric,
    this.progressionOverride,
  }) : assert(current >= 0),
       assert(total >= 0);

  const ReaderProgressState.unknown()
    : current = 0,
      total = 0,
      label = null,
      metric = ReaderProgressMetric.unknown,
      progressionOverride = null;

  final int current;
  final int total;
  final String? label;
  final ReaderProgressMetric metric;

  /// A normalized progression for readers which do not have page counts.
  final double? progressionOverride;

  bool get canSeek => total > 1 || progressionOverride != null;
  double get progression =>
      progressionOverride ??
      (total <= 1 ? 0 : current.clamp(0, total - 1) / (total - 1));

  static ReaderProgressState page({required int page, required int total}) {
    final safeTotal = total < 0 ? 0 : total;
    final current = safeTotal == 0 ? 0 : (page - 1).clamp(0, safeTotal - 1);
    return ReaderProgressState(
      current: current,
      total: safeTotal,
      label: safeTotal == 0 ? null : 'Page ${current + 1} of $safeTotal',
      metric: ReaderProgressMetric.fixedPage,
    );
  }

  factory ReaderProgressState.progression({
    required double progression,
    String? label,
  }) {
    if (!progression.isFinite) {
      return const ReaderProgressState.unknown();
    }
    return ReaderProgressState(
      current: 0,
      total: 0,
      label:
          label ?? 'Progress ${(progression.clamp(0.0, 1.0) * 100).round()}%',
      metric: ReaderProgressMetric.progression,
      progressionOverride: progression.clamp(0.0, 1.0),
    );
  }

  factory ReaderProgressState.reflowable({
    required double progression,
    int? logicalPosition,
    int? totalLogicalPositions,
  }) {
    if (!progression.isFinite) {
      return const ReaderProgressState.unknown();
    }
    final normalized = progression.clamp(0.0, 1.0);
    final position = logicalPosition != null && logicalPosition >= 1
        ? logicalPosition
        : null;
    final total =
        totalLogicalPositions != null &&
            totalLogicalPositions >= 1 &&
            (position == null || totalLogicalPositions >= position)
        ? totalLogicalPositions
        : 0;
    final label = 'Progress ${(normalized * 100).round()}%';
    return ReaderProgressState(
      current: position == null ? 0 : position - 1,
      total: total,
      label: label,
      metric: ReaderProgressMetric.reflowablePosition,
      progressionOverride: normalized,
    );
  }

  factory ReaderProgressState.renderedPage({
    required int pageIndex,
    required int pageCount,
    required double progression,
    required bool publicationScoped,
  }) {
    if (!progression.isFinite ||
        pageCount < 1 ||
        pageIndex < 0 ||
        pageIndex >= pageCount) {
      return const ReaderProgressState.unknown();
    }
    final normalized = progression.clamp(0.0, 1.0);
    return ReaderProgressState(
      current: publicationScoped ? pageIndex : 0,
      total: publicationScoped ? pageCount : 0,
      label: publicationScoped
          ? 'Page ${pageIndex + 1} of $pageCount'
          : 'Page ${pageIndex + 1}',
      metric: ReaderProgressMetric.renderedPage,
      progressionOverride: normalized,
    );
  }

  int pageFor(double progression) {
    if (total <= 1) return total == 0 ? 0 : 1;
    return (progression.clamp(0.0, 1.0) * (total - 1)).round() + 1;
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderProgressState &&
      other.current == current &&
      other.total == total &&
      other.label == label &&
      other.metric == metric &&
      other.progressionOverride == progressionOverride;

  @override
  int get hashCode =>
      Object.hash(current, total, label, metric, progressionOverride);
}

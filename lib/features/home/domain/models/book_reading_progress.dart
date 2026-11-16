class BookReadingProgress {
  const BookReadingProgress({
    required this.percent,
    required this.hasStarted,
    required this.isCompleted,
  });

  factory BookReadingProgress.fromProgression(double progression) {
    final normalized = progression.isFinite ? progression.clamp(0.0, 1.0) : 0.0;
    return BookReadingProgress(
      percent: (normalized * 100).round(),
      hasStarted: normalized > 0,
      isCompleted: normalized >= 1,
    );
  }

  final int percent;
  final bool hasStarted;
  final bool isCompleted;
}

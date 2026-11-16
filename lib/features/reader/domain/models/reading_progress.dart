class ReadingProgress {
  const ReadingProgress({
    required this.bookId,
    required this.locatorJson,
    required this.progression,
    required this.currentChapterTitle,
    required this.currentPage,
    required this.totalPages,
    required this.updatedAt,
  }) : assert(progression >= 0.0 && progression <= 1.0);

  final String bookId;
  final String? locatorJson;
  final double progression;
  final String? currentChapterTitle;
  final int? currentPage;
  final int? totalPages;
  final DateTime updatedAt;
}

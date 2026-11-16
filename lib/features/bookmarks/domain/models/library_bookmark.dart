class LibraryBookmark {
  const LibraryBookmark({
    required this.id,
    required this.bookId,
    required this.locatorJson,
    required this.href,
    required this.progression,
    required this.position,
    required this.chapterTitle,
    required this.title,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final String bookId;
  final String locatorJson;
  final String? href;
  final double? progression;
  final int? position;
  final String? chapterTitle;
  final String? title;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      other is LibraryBookmark &&
      other.id == id &&
      other.bookId == bookId &&
      other.locatorJson == locatorJson &&
      other.href == href &&
      other.progression == progression &&
      other.position == position &&
      other.chapterTitle == chapterTitle &&
      other.title == title &&
      other.note == note &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    locatorJson,
    href,
    progression,
    position,
    chapterTitle,
    title,
    note,
    createdAt,
    updatedAt,
  );
}

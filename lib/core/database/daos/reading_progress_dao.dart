part of '../app_database.dart';

@DriftAccessor(tables: [ReadingProgressEntries])
class ReadingProgressDao extends DatabaseAccessor<AppDatabase>
    with _$ReadingProgressDaoMixin {
  ReadingProgressDao(super.db);

  Stream<List<ReadingProgressEntry>> watchAllProgress() =>
      select(readingProgressEntries).watch();

  Stream<ReadingProgressEntry?> watchProgressForBook(String bookId) {
    return (select(
      readingProgressEntries,
    )..where((entry) => entry.bookId.equals(bookId))).watchSingleOrNull();
  }

  Future<ReadingProgressEntry?> getProgressForBook(String bookId) {
    return (select(
      readingProgressEntries,
    )..where((entry) => entry.bookId.equals(bookId))).getSingleOrNull();
  }

  Future<int> upsertProgress(ReadingProgressEntriesCompanion progress) {
    return into(readingProgressEntries).insertOnConflictUpdate(progress);
  }

  Future<int> deleteProgressForBook(String bookId) {
    return (delete(
      readingProgressEntries,
    )..where((entry) => entry.bookId.equals(bookId))).go();
  }
}

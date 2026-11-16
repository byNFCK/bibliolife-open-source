import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/core/database/mappers/reading_progress_mapper.dart';
import 'package:bibliolife/features/reader/domain/models/reading_progress.dart';
import 'package:bibliolife/features/reader/domain/repositories/reading_progress_repository.dart';

class DriftReadingProgressRepository implements ReadingProgressRepository {
  const DriftReadingProgressRepository(this._readingProgressDao);

  final ReadingProgressDao _readingProgressDao;

  @override
  Stream<List<ReadingProgress>> watchAll() => _readingProgressDao
      .watchAllProgress()
      .map((rows) => rows.map((row) => row.toReadingProgress()).toList());

  @override
  Stream<ReadingProgress?> watchForBook(String bookId) {
    return _readingProgressDao
        .watchProgressForBook(bookId)
        .map((progress) => progress?.toReadingProgress());
  }

  @override
  Future<ReadingProgress?> getForBook(String bookId) async {
    return (await _readingProgressDao.getProgressForBook(
      bookId,
    ))?.toReadingProgress();
  }

  @override
  Future<void> save(ReadingProgress progress) async {
    await _readingProgressDao.upsertProgress(
      progress.toReadingProgressCompanion(),
    );
  }

  @override
  Future<void> deleteForBook(String bookId) async {
    await _readingProgressDao.deleteProgressForBook(bookId);
  }
}

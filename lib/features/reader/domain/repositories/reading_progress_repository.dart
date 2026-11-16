import 'package:bibliolife/features/reader/domain/models/reading_progress.dart';

abstract interface class ReadingProgressRepository {
  Stream<List<ReadingProgress>> watchAll();
  Stream<ReadingProgress?> watchForBook(String bookId);
  Future<ReadingProgress?> getForBook(String bookId);
  Future<void> save(ReadingProgress progress);
  Future<void> deleteForBook(String bookId);
}

import 'package:bibliolife/features/reader/domain/repositories/reading_progress_repository.dart';

class DeleteReadingProgress {
  const DeleteReadingProgress(this._repository);

  final ReadingProgressRepository _repository;

  Future<void> call(String bookId) => _repository.deleteForBook(bookId);
}

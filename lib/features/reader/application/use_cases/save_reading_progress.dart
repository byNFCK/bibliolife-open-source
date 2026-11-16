import 'package:bibliolife/features/reader/domain/models/reading_progress.dart';
import 'package:bibliolife/features/reader/domain/repositories/reading_progress_repository.dart';

class SaveReadingProgress {
  const SaveReadingProgress(this._repository);

  final ReadingProgressRepository _repository;

  Future<void> call(ReadingProgress progress) => _repository.save(progress);
}

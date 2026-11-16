import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';

class MarkBookOpened {
  const MarkBookOpened(this._repository);

  final LibraryRepository _repository;

  Future<void> call(String id, DateTime openedAt) {
    return _repository.markBookOpened(id, openedAt);
  }
}

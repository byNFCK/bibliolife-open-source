import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';

class SetBookFavorite {
  const SetBookFavorite(this._repository);

  final LibraryRepository _repository;

  Future<void> call(String id, bool isFavorite) {
    return _repository.setFavorite(id, isFavorite);
  }
}

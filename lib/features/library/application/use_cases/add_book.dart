import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';
import 'package:bibliolife/shared/models/library_book.dart';

class AddBook {
  const AddBook(this._repository);

  final LibraryRepository _repository;

  Future<void> call(LibraryBook book) => _repository.addBook(book);
}

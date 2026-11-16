import 'package:bibliolife/shared/models/library_book.dart';

abstract interface class LibraryRepository {
  Stream<List<LibraryBook>> watchAllBooks();
  Stream<List<LibraryBook>> watchFavoriteBooks();
  Stream<List<LibraryBook>> watchUnsortedBooks();
  Future<List<LibraryBook>> getAllBooks();
  Future<LibraryBook?> getBookById(String id);
  Future<LibraryBook?> findBookByFilePath(String filePath);
  Future<LibraryBook?> findBookByOriginalFilePath(String originalFilePath);
  Future<void> addBook(LibraryBook book);
  Future<void> updateBook(LibraryBook book);
  Future<void> deleteBook(String id);
  Future<void> setFavorite(String id, bool isFavorite);
  Future<void> markBookOpened(String id, DateTime openedAt);
}

extension LibraryRepositoryBookWatch on LibraryRepository {
  Stream<LibraryBook?> watchById(String id) {
    return watchAllBooks().map(
      (books) =>
          books.where((book) => book.id == id).cast<LibraryBook?>().firstOrNull,
    );
  }
}

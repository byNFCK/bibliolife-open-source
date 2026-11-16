import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/core/database/mappers/book_mapper.dart';
import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';
import 'package:bibliolife/shared/models/library_book.dart';

class DriftLibraryRepository implements LibraryRepository {
  const DriftLibraryRepository(this._booksDao);

  final BooksDao _booksDao;

  @override
  Stream<List<LibraryBook>> watchAllBooks() {
    return _booksDao.watchAllBooks().map(
      (books) => books.map((book) => book.toLibraryBook()).toList(),
    );
  }

  @override
  Stream<List<LibraryBook>> watchFavoriteBooks() {
    return _booksDao.watchFavoriteBooks().map(
      (books) => books.map((book) => book.toLibraryBook()).toList(),
    );
  }

  @override
  Stream<List<LibraryBook>> watchUnsortedBooks() {
    return _booksDao.watchUnsortedBooks().map(
      (books) => books.map((book) => book.toLibraryBook()).toList(),
    );
  }

  @override
  Future<List<LibraryBook>> getAllBooks() async {
    final books = await _booksDao.getAllBooks();
    return books.map((book) => book.toLibraryBook()).toList();
  }

  @override
  Future<LibraryBook?> getBookById(String id) async {
    return (await _booksDao.getBookById(id))?.toLibraryBook();
  }

  @override
  Future<LibraryBook?> findBookByFilePath(String filePath) async {
    return (await _booksDao.findBookByFilePath(filePath))?.toLibraryBook();
  }

  @override
  Future<LibraryBook?> findBookByOriginalFilePath(
    String originalFilePath,
  ) async {
    return (await _booksDao.findBookByOriginalFilePath(
      originalFilePath,
    ))?.toLibraryBook();
  }

  @override
  Future<void> addBook(LibraryBook book) async {
    await _booksDao.insertBook(book.toBooksCompanion());
  }

  @override
  Future<void> updateBook(LibraryBook book) async {
    await _booksDao.updateBook(book.toDriftBook());
  }

  @override
  Future<void> deleteBook(String id) async {
    await _booksDao.deleteBookById(id);
  }

  @override
  Future<void> setFavorite(String id, bool isFavorite) async {
    await _booksDao.setFavorite(id, isFavorite);
  }

  @override
  Future<void> markBookOpened(String id, DateTime openedAt) async {
    await _booksDao.updateLastOpenedAt(id, openedAt);
  }
}

import 'package:bibliolife/features/bookmarks/domain/models/bookmark_metadata_update.dart';
import 'package:bibliolife/features/bookmarks/domain/models/library_bookmark.dart';
import 'package:bibliolife/features/bookmarks/domain/models/bookmark_location_key.dart';

abstract interface class BookmarkRepository {
  Stream<List<LibraryBookmark>> watchBookmarksForBook(String bookId);
  Stream<List<LibraryBookmark>> watchAllBookmarks();
  Future<LibraryBookmark?> getBookmarkById(String bookmarkId);
  Future<LibraryBookmark> createBookmark({
    required String bookId,
    required String locatorJson,
    String? href,
    double? progression,
    String? chapterTitle,
    int? position,
    String? title,
    String? note,
  });
  Future<LibraryBookmark> updateBookmarkMetadata({
    required String bookmarkId,
    required BookmarkMetadataUpdate update,
  });
  Future<void> deleteBookmark(String bookmarkId);
  Future<void> deleteBookmarksForBook(String bookId);
  Future<int> countBookmarksForBook(String bookId);
  Future<bool> isBookmarked(BookmarkLocationKey key);
  Future<void> removeBookmarksAt(BookmarkLocationKey key);
}

sealed class BookmarkRepositoryFailure implements Exception {
  const BookmarkRepositoryFailure(this.message);
  final String message;
}

class InvalidBookmarkLocator extends BookmarkRepositoryFailure {
  const InvalidBookmarkLocator() : super('Некоректний locator закладки.');
}

class InvalidBookmarkProgression extends BookmarkRepositoryFailure {
  const InvalidBookmarkProgression() : super('Некоректна позиція закладки.');
}

class MissingBookmarkBook extends BookmarkRepositoryFailure {
  const MissingBookmarkBook(this.bookId) : super('Книгу не знайдено.');
  final String bookId;
}

class MissingBookmark extends BookmarkRepositoryFailure {
  const MissingBookmark(this.bookmarkId) : super('Закладку не знайдено.');
  final String bookmarkId;
}

class InvalidBookmarkTitle extends BookmarkRepositoryFailure {
  const InvalidBookmarkTitle() : super('Назва закладки надто довга.');
}

class InvalidBookmarkNote extends BookmarkRepositoryFailure {
  const InvalidBookmarkNote() : super('Нотатка надто довга.');
}

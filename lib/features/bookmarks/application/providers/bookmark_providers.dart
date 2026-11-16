import 'package:bibliolife/features/bookmarks/application/providers/bookmark_repository_provider.dart';
import 'package:bibliolife/features/bookmarks/domain/models/library_bookmark.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final bookmarksForBookProvider =
    StreamProvider.family<List<LibraryBookmark>, String>(
      (ref, bookId) =>
          ref.watch(bookmarkRepositoryProvider).watchBookmarksForBook(bookId),
    );
final allBookmarksProvider = StreamProvider<List<LibraryBookmark>>(
  (ref) => ref.watch(bookmarkRepositoryProvider).watchAllBookmarks(),
);
final bookmarkByIdProvider = FutureProvider.family<LibraryBookmark?, String>(
  (ref, id) => ref.watch(bookmarkRepositoryProvider).getBookmarkById(id),
);
final bookmarkCountForBookProvider = Provider.family<AsyncValue<int>, String>(
  (ref, bookId) => ref
      .watch(bookmarksForBookProvider(bookId))
      .whenData((bookmarks) => bookmarks.length),
);

import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/bookmarks/domain/models/library_bookmark.dart';
import 'package:drift/drift.dart';

extension BookmarkMapper on Bookmark {
  LibraryBookmark toLibraryBookmark() => LibraryBookmark(
    id: id,
    bookId: bookId,
    locatorJson: locatorJson,
    href: href,
    progression: progression,
    position: position,
    chapterTitle: chapterTitle,
    title: title,
    note: note,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension LibraryBookmarkMapper on LibraryBookmark {
  BookmarksCompanion toBookmarksCompanion() => BookmarksCompanion.insert(
    id: id,
    bookId: bookId,
    locatorJson: locatorJson,
    href: Value(href),
    progression: Value(progression),
    position: Value(position),
    chapterTitle: Value(chapterTitle),
    title: Value(title),
    note: Value(note),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

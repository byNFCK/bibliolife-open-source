part of '../app_database.dart';

@DriftAccessor(tables: [Bookmarks, Books])
class BookmarksDao extends DatabaseAccessor<AppDatabase>
    with _$BookmarksDaoMixin {
  BookmarksDao(super.db);
  Stream<List<Bookmark>> watchForBook(String id) =>
      (select(bookmarks)
            ..where((b) => b.bookId.equals(id))
            ..orderBy([
              // SQLite orders NULL first ascending. Put unlocated bookmarks last.
              (b) => OrderingTerm(expression: b.progression.isNull()),
              (b) => OrderingTerm(expression: b.progression),
              (b) => OrderingTerm(expression: b.createdAt),
              (b) => OrderingTerm(expression: b.id),
            ]))
          .watch();
  Stream<List<Bookmark>> watchAll() =>
      (select(bookmarks)..orderBy([
            (b) =>
                OrderingTerm(expression: b.createdAt, mode: OrderingMode.desc),
            (b) => OrderingTerm(expression: b.id),
          ]))
          .watch();
  Future<Bookmark?> findById(String id) =>
      (select(bookmarks)..where((b) => b.id.equals(id))).getSingleOrNull();
  Future<List<Bookmark>> getForBook(String id) =>
      (select(bookmarks)..where((b) => b.bookId.equals(id))).get();
  Future<void> insertBookmark(BookmarksCompanion value) async =>
      into(bookmarks).insert(value);
  Future<bool> updateBookmarkMetadata({
    required String id,
    required String? title,
    required String? note,
    required DateTime updatedAt,
  }) async =>
      (await (update(
        bookmarks,
      )..where((bookmark) => bookmark.id.equals(id))).write(
        BookmarksCompanion(
          title: Value(title),
          note: Value(note),
          updatedAt: Value(updatedAt),
        ),
      )) >
      0;
  Future<int> deleteById(String id) =>
      (delete(bookmarks)..where((b) => b.id.equals(id))).go();
  Future<int> deleteForBook(String id) =>
      (delete(bookmarks)..where((b) => b.bookId.equals(id))).go();
  Future<int> deleteByIds(Iterable<String> ids) => ids.isEmpty
      ? Future.value(0)
      : (delete(bookmarks)..where((b) => b.id.isIn(ids))).go();
  Future<T> inTransaction<T>(Future<T> Function() action) =>
      attachedDatabase.transaction(action);
  Future<int> countForBook(String id) =>
      (selectOnly(bookmarks)
            ..addColumns([bookmarks.id.count()])
            ..where(bookmarks.bookId.equals(id)))
          .map((r) => r.read(bookmarks.id.count()) ?? 0)
          .getSingle();
  Future<bool> bookExists(String id) async =>
      await (select(books)..where((b) => b.id.equals(id))).getSingleOrNull() !=
      null;
}

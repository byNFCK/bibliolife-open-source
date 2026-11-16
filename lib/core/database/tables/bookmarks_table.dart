import 'package:bibliolife/core/database/tables/books_table.dart';
import 'package:drift/drift.dart';

@TableIndex(name: 'bookmarks_book_id', columns: {#bookId})
@TableIndex(
  name: 'bookmarks_book_progression',
  columns: {#bookId, #progression},
)
class Bookmarks extends Table {
  TextColumn get id => text()();
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get locatorJson => text()();
  TextColumn get href => text().nullable()();
  RealColumn get progression => real().nullable()();
  IntColumn get position => integer().nullable()();
  TextColumn get chapterTitle => text().nullable()();
  TextColumn get title => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

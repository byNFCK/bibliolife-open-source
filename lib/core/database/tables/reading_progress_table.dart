import 'package:bibliolife/core/database/tables/books_table.dart';
import 'package:drift/drift.dart';

class ReadingProgressEntries extends Table {
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get locatorJson => text().nullable()();
  RealColumn get progression => real().withDefault(const Constant(0.0))();
  TextColumn get currentChapterTitle => text().nullable()();
  IntColumn get currentPage => integer().nullable()();
  IntColumn get totalPages => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {bookId};
}

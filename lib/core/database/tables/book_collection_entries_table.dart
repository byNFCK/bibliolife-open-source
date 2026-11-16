import 'package:bibliolife/core/database/tables/books_table.dart';
import 'package:bibliolife/core/database/tables/collections_table.dart';
import 'package:drift/drift.dart';

@TableIndex(
  name: 'book_collection_entries_collection_id',
  columns: {#collectionId},
)
class BookCollectionEntries extends Table {
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get collectionId =>
      text().references(Collections, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {bookId, collectionId};
}

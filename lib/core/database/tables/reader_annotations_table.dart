import 'package:bibliolife/core/database/tables/books_table.dart';
import 'package:drift/drift.dart';

@TableIndex(name: 'reader_annotations_book_id', columns: {#bookId})
@TableIndex(
  name: 'reader_annotations_book_order',
  columns: {#bookId, #totalProgression, #href, #progression},
)
class ReaderAnnotations extends Table {
  TextColumn get id => text()();
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get locatorJson => text()();
  TextColumn get locationKey => text()();
  TextColumn get selectedText => text()();
  TextColumn get textBefore => text().nullable()();
  TextColumn get textAfter => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get style => text().withDefault(const Constant('highlight'))();
  TextColumn get color => text().withDefault(const Constant('yellow'))();
  TextColumn get href => text()();
  RealColumn get progression => real().nullable()();
  RealColumn get totalProgression => real().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {bookId, locationKey},
  ];
}

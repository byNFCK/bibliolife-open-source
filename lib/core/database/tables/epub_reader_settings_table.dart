import 'package:drift/drift.dart';

class EpubReaderSettingsEntries extends Table {
  IntColumn get id => integer()();
  TextColumn get theme => text()();
  RealColumn get fontSize => real()();
  RealColumn get lineHeight => real()();
  RealColumn get pageMargins => real()();
  BoolColumn get publisherStyles => boolean()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

import 'package:drift/drift.dart';

class LibrarySectionSettingsEntries extends Table {
  IntColumn get id => integer()();
  TextColumn get defaultSection => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

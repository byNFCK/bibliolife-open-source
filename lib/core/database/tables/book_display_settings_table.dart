import 'package:drift/drift.dart';

class BookDisplaySettingsEntries extends Table {
  IntColumn get id => integer()();
  TextColumn get layout => text().withDefault(const Constant('grid'))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

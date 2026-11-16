import 'package:drift/drift.dart';

class HomeDefaultCarouselSettingsEntries extends Table {
  IntColumn get id => integer()();
  TextColumn get defaultCarousel => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

import 'package:drift/drift.dart';

class AppConnectivitySettingsEntries extends Table {
  IntColumn get id => integer()();
  TextColumn get mode => text()();
  BoolColumn get hasAcknowledgedOnline => boolean()();
  @override
  Set<Column> get primaryKey => {id};
}

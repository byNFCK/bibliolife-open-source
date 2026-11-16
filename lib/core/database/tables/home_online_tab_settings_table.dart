import 'package:drift/drift.dart';

/// Per-provider presentation preferences for Home.  This is deliberately
/// separate from CatalogSourcesEntries.isEnabled, which controls Search.
class HomeOnlineTabSettingsEntries extends Table {
  TextColumn get sourceId => text()();
  BoolColumn get visibleOnHome => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {sourceId};
}

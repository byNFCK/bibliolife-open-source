import 'package:drift/drift.dart';

/// The one persistent preference for the anonymous online cache.
///
/// This is deliberately separate from connectivity: choosing a cache capacity
/// neither enables network access nor changes the user's online-mode consent.
class RemoteCacheSettingsEntries extends Table {
  IntColumn get id => integer()();
  IntColumn get maximumBytes => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

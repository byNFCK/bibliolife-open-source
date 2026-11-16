import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/catalog_sources/data/built_in_catalog_sources.dart';
import 'package:bibliolife/features/home/domain/home_online_tab_settings_repository.dart';
import 'package:drift/drift.dart';

class DriftHomeOnlineTabSettingsRepository
    implements HomeOnlineTabSettingsRepository {
  DriftHomeOnlineTabSettingsRepository(this._database);

  final AppDatabase _database;

  static final supportedSourceIds = Set<String>.unmodifiable(
    builtInCatalogSources.map((source) => source.id),
  );

  @override
  Stream<Map<String, bool>> watchVisibility() => _database
      .select(_database.homeOnlineTabSettingsEntries)
      .watch()
      .map(
        (rows) => Map.unmodifiable({
          for (final row in rows)
            if (supportedSourceIds.contains(row.sourceId))
              row.sourceId: row.visibleOnHome,
        }),
      );

  @override
  Future<void> setVisible({
    required String sourceId,
    required bool visible,
  }) async {
    // Removed/unknown registry entries are intentionally harmless.
    if (!supportedSourceIds.contains(sourceId)) return;
    await _database
        .into(_database.homeOnlineTabSettingsEntries)
        .insertOnConflictUpdate(
          HomeOnlineTabSettingsEntriesCompanion.insert(
            sourceId: sourceId,
            visibleOnHome: Value(visible),
          ),
        );
  }
}

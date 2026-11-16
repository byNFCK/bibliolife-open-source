part of '../app_database.dart';

@DriftAccessor(tables: [AppConnectivitySettingsEntries])
class AppConnectivitySettingsDao extends DatabaseAccessor<AppDatabase>
    with _$AppConnectivitySettingsDaoMixin {
  AppConnectivitySettingsDao(super.db);

  Future<AppConnectivitySettingsEntry?> load() => (select(
    appConnectivitySettingsEntries,
  )..where((row) => row.id.equals(1))).getSingleOrNull();

  Future<void> upsert(AppConnectivitySettingsEntriesCompanion entry) =>
      into(appConnectivitySettingsEntries).insertOnConflictUpdate(entry);
}

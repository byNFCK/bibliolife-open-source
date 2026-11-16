part of '../app_database.dart';

@DriftAccessor(tables: [RemoteCacheSettingsEntries])
class RemoteCacheSettingsDao extends DatabaseAccessor<AppDatabase>
    with _$RemoteCacheSettingsDaoMixin {
  RemoteCacheSettingsDao(super.db);

  Future<RemoteCacheSettingsEntry?> load() => (select(
    remoteCacheSettingsEntries,
  )..where((row) => row.id.equals(1))).getSingleOrNull();

  Stream<RemoteCacheSettingsEntry?> watch() => (select(
    remoteCacheSettingsEntries,
  )..where((row) => row.id.equals(1))).watchSingleOrNull();

  Future<void> upsert(RemoteCacheSettingsEntriesCompanion entry) =>
      into(remoteCacheSettingsEntries).insertOnConflictUpdate(entry);
}

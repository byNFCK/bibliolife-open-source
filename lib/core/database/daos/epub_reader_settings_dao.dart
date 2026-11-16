part of '../app_database.dart';

@DriftAccessor(tables: [EpubReaderSettingsEntries])
class EpubReaderSettingsDao extends DatabaseAccessor<AppDatabase>
    with _$EpubReaderSettingsDaoMixin {
  EpubReaderSettingsDao(super.db);
  Future<EpubReaderSettingsEntry?> load() => (select(
    epubReaderSettingsEntries,
  )..where((r) => r.id.equals(1))).getSingleOrNull();
  Future<void> upsert(EpubReaderSettingsEntriesCompanion entry) async =>
      into(epubReaderSettingsEntries).insertOnConflictUpdate(entry);
  Future<void> deleteSettings() async =>
      (delete(epubReaderSettingsEntries)..where((r) => r.id.equals(1))).go();
}

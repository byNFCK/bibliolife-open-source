part of '../app_database.dart';

@DriftAccessor(tables: [LibrarySectionSettingsEntries])
class LibrarySectionSettingsDao extends DatabaseAccessor<AppDatabase>
    with _$LibrarySectionSettingsDaoMixin {
  LibrarySectionSettingsDao(super.db);

  Future<LibrarySectionSettingsEntry?> load() => (select(
    librarySectionSettingsEntries,
  )..where((row) => row.id.equals(1))).getSingleOrNull();

  Future<void> upsert(LibrarySectionSettingsEntriesCompanion entry) =>
      into(librarySectionSettingsEntries).insertOnConflictUpdate(entry);
}

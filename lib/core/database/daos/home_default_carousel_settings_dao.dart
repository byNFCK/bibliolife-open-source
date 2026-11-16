part of '../app_database.dart';

@DriftAccessor(tables: [HomeDefaultCarouselSettingsEntries])
class HomeDefaultCarouselSettingsDao extends DatabaseAccessor<AppDatabase>
    with _$HomeDefaultCarouselSettingsDaoMixin {
  HomeDefaultCarouselSettingsDao(super.db);

  Future<HomeDefaultCarouselSettingsEntry?> load() => (select(
    homeDefaultCarouselSettingsEntries,
  )..where((row) => row.id.equals(1))).getSingleOrNull();

  Future<void> upsert(HomeDefaultCarouselSettingsEntriesCompanion entry) =>
      into(homeDefaultCarouselSettingsEntries).insertOnConflictUpdate(entry);
}

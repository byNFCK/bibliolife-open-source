import 'package:bibliolife/core/database/app_database.dart';
import 'package:drift/drift.dart';

// The previous Library provider was memory-only: there is no legacy disk key
// to migrate. Creating this independent settings row leaves all existing
// Library section and other preferences untouched.
class DriftBookDisplaySettingsRepository {
  const DriftBookDisplaySettingsRepository(this.database);

  final AppDatabase database;

  Future<String?> load() async {
    final row = await (database.select(
      database.bookDisplaySettingsEntries,
    )..where((row) => row.id.equals(1))).getSingleOrNull();
    return row?.layout;
  }

  Future<void> save(String layout) async {
    await database
        .into(database.bookDisplaySettingsEntries)
        .insertOnConflictUpdate(
          BookDisplaySettingsEntriesCompanion.insert(
            id: const Value(1),
            layout: Value(layout),
          ),
        );
  }
}

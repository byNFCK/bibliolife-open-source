import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/library/domain/library_section.dart';
import 'package:bibliolife/features/library/domain/library_section_settings_repository.dart';
import 'package:drift/drift.dart';

class DriftLibrarySectionSettingsRepository
    implements LibrarySectionSettingsRepository {
  const DriftLibrarySectionSettingsRepository(this._dao);

  final LibrarySectionSettingsDao _dao;

  @override
  Future<LibrarySection> load() async {
    final stored = await _dao.load();
    final section = LibrarySectionPreferenceCodec.decode(
      stored?.defaultSection,
    );
    if (stored != null &&
        stored.defaultSection !=
            LibrarySectionPreferenceCodec.encode(section)) {
      await save(section);
    }
    return section;
  }

  @override
  Future<void> save(LibrarySection section) => _dao.upsert(
    LibrarySectionSettingsEntriesCompanion.insert(
      id: const Value(1),
      defaultSection: LibrarySectionPreferenceCodec.encode(section),
    ),
  );
}

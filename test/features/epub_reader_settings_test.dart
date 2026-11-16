import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/reader/data/repositories/drift_epub_reader_settings_repository.dart';
import 'package:bibliolife/features/reader/domain/models/epub_reader_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('model defaults, serialization and normalization are stable', () {
    expect(EpubReaderSettings.defaults.theme, EpubReaderTheme.system);
    final value = EpubReaderSettings.defaults.copyWith(
      fontSize: 9,
      lineHeight: 0,
      pageMargins: -1,
    );
    expect(value.fontSize, 3);
    expect(value.lineHeight, 1);
    expect(value.pageMargins, 0);
    expect(EpubReaderSettings.fromJson(value.toJson()), value);
    expect(
      EpubReaderSettings.fromJson({'theme': 'unknown', 'fontSize': '1'}),
      EpubReaderSettings.defaults,
    );
    expect(value.normalized().normalized(), value);
  });

  test(
    'repository uses one singleton row and reset returns defaults',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = DriftEpubReaderSettingsRepository(db.epubReaderSettingsDao);
      expect(await repo.load(), EpubReaderSettings.defaults);
      await repo.save(
        const EpubReaderSettings(theme: EpubReaderTheme.sepia, fontSize: 2),
      );
      await repo.save(
        const EpubReaderSettings(theme: EpubReaderTheme.dark, lineHeight: 2),
      );
      expect((await repo.load()).theme, EpubReaderTheme.dark);
      expect((await db.select(db.epubReaderSettingsEntries).get()).length, 1);
      await repo.reset();
      expect(await repo.load(), EpubReaderSettings.defaults);
    },
  );
}

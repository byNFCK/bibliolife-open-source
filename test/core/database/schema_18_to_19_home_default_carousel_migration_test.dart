import 'dart:io';

import 'package:bibliolife/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'v18 migration creates the Home default carousel settings table',
    () async {
      final directory = await Directory.systemTemp.createTemp('bibliolife_v18');
      final file = File(
        '${directory.path}${Platform.pathSeparator}bibliolife.db',
      );
      final old = AppDatabase(NativeDatabase(file));
      await old.customStatement(
        'DROP TABLE home_default_carousel_settings_entries',
      );
      await old.customStatement(
        'ALTER TABLE collections DROP COLUMN description',
      );
      await old.customStatement(
        'ALTER TABLE collections DROP COLUMN custom_cover_path',
      );
      await old.customStatement('PRAGMA user_version = 18');
      await old.close();

      final migrated = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await migrated.close();
        await directory.delete(recursive: true);
      });

      expect(migrated.schemaVersion, 23);
      expect(
        await migrated
            .select(migrated.homeDefaultCarouselSettingsEntries)
            .get(),
        isEmpty,
      );
      expect(
        await migrated.select(migrated.librarySectionSettingsEntries).get(),
        isEmpty,
      );
      expect(
        (await migrated.customSelect('PRAGMA table_info(collections)').get())
            .map((row) => row.read<String>('name')),
        containsAll(<String>['description', 'custom_cover_path']),
      );
    },
  );
}

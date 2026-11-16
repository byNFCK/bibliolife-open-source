import 'dart:io';

import 'package:bibliolife/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v15 migration preserves data and adds Home tab settings', () async {
    final directory = await Directory.systemTemp.createTemp('bibliolife_v15');
    final file = File(
      '${directory.path}${Platform.pathSeparator}bibliolife.db',
    );
    final migrated = AppDatabase(
      NativeDatabase(
        file,
        setup: (database) {
          database.execute(
            'CREATE TABLE collections (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, normalized_name TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, sort_order INTEGER)',
          );
          database.execute(
            'CREATE TABLE preserved_search (source_id TEXT NOT NULL)',
          );
          database.execute(
            "INSERT INTO preserved_search VALUES ('builtin-google-books')",
          );
          database.execute('PRAGMA user_version = 15');
        },
      ),
    );
    addTearDown(() async {
      await migrated.close();
      await directory.delete(recursive: true);
    });

    expect(
      (await migrated
              .customSelect('SELECT source_id FROM preserved_search')
              .getSingle())
          .read<String>('source_id'),
      'builtin-google-books',
    );
    expect(
      await migrated.select(migrated.homeOnlineTabSettingsEntries).get(),
      isEmpty,
    );
  });
}

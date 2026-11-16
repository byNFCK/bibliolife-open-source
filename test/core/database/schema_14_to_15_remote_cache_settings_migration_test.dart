import 'dart:io';

import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_cache_budget.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v14 migration preserves local data and adds the cache default', () async {
    final directory = await Directory.systemTemp.createTemp('bibliolife_v14');
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
          database.execute('CREATE TABLE preserved_data (value TEXT NOT NULL)');
          database.execute(
            "INSERT INTO preserved_data VALUES ('book/progress/note')",
          );
          database.execute('PRAGMA user_version = 14');
        },
      ),
    );
    addTearDown(() async {
      await migrated.close();
      await directory.delete(recursive: true);
    });

    expect(
      (await migrated
              .customSelect('SELECT value FROM preserved_data')
              .getSingle())
          .read<String>('value'),
      'book/progress/note',
    );
    expect(
      (await migrated.remoteCacheSettingsDao.load())?.maximumBytes,
      remoteCacheDefaultMaximumBytes,
    );
  });
}

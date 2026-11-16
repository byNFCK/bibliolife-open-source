import 'dart:io';

import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/catalog_sources/data/remote_cache_settings_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_cache_budget.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DriftRemoteCacheSettingsRepository', () {
    late AppDatabase database;
    late DriftRemoteCacheSettingsRepository repository;

    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
      repository = DriftRemoteCacheSettingsRepository(
        database.remoteCacheSettingsDao,
      );
    });
    tearDown(() => database.close());

    test('a new database has the 1.25 GB default', () async {
      expect(
        (await repository.load()).maximumBytes,
        remoteCacheDefaultMaximumBytes,
      );
    });

    test(
      'an unsupported stored capacity is safely normalised and repaired',
      () async {
        await database.remoteCacheSettingsDao.upsert(
          RemoteCacheSettingsEntriesCompanion.insert(
            id: const Value(1),
            maximumBytes: 999,
          ),
        );

        expect(
          (await repository.load()).maximumBytes,
          remoteCacheDefaultMaximumBytes,
        );
        expect(
          (await database.remoteCacheSettingsDao.load())?.maximumBytes,
          remoteCacheDefaultMaximumBytes,
        );
      },
    );

    test(
      'persists every supported selection across database recreation',
      () async {
        await database.close();
        final directory = await Directory.systemTemp.createTemp(
          'cache-settings-',
        );
        final file = File(
          '${directory.path}${Platform.pathSeparator}settings.db',
        );
        final first = AppDatabase(NativeDatabase(file));
        final firstRepository = DriftRemoteCacheSettingsRepository(
          first.remoteCacheSettingsDao,
        );
        await firstRepository.save(
          RemoteCacheBudget.fromStored(remoteCacheMaximumMaximumBytes),
        );
        await first.close();
        final reopened = AppDatabase(NativeDatabase(file));
        addTearDown(() async {
          await reopened.close();
          await directory.delete(recursive: true);
        });

        expect(
          (await DriftRemoteCacheSettingsRepository(
            reopened.remoteCacheSettingsDao,
          ).load()).maximumBytes,
          remoteCacheMaximumMaximumBytes,
        );
      },
    );
  });
}

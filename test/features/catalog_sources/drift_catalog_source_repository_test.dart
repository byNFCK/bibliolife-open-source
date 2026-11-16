import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/catalog_sources/data/built_in_catalog_sources.dart';
import 'package:bibliolife/features/catalog_sources/data/drift_catalog_source_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftCatalogSourceRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftCatalogSourceRepository(
      database,
      idGenerator: () => 'custom-id',
    );
  });
  tearDown(() => database.close());

  test(
    'seeds stable built-ins once and preserves user enabled state',
    () async {
      await repository.ensureBuiltInSources();
      final first = await repository.getAll();
      expect(
        first.map((source) => source.id).toSet(),
        builtInCatalogSources.map((source) => source.id).toSet(),
      );
      expect(first, hasLength(builtInCatalogSources.length));
      final archive = first.singleWhere(
        (source) => source.id == 'builtin-internet-archive',
      );
      expect(archive.isEnabled, isTrue);
      expect(archive.supportsSearch, isFalse);
      expect(archive.supportsAcquisition, isTrue);

      await repository.setEnabled(id: first.first.id, enabled: false);
      await repository.ensureBuiltInSources();
      final second = await repository.getAll();
      expect(second, hasLength(builtInCatalogSources.length));
      expect(second.first.isEnabled, isFalse);
    },
  );

  test(
    'reseed repairs stale authoritative fields without replacing createdAt',
    () async {
      await repository.ensureBuiltInSources();
      final original = (await repository.getAll()).first;
      await (database.update(
        database.catalogSourcesEntries,
      )..where((entry) => entry.id.equals(original.id))).write(
        const CatalogSourcesEntriesCompanion(
          name: Value('Stale'),
          baseUrl: Value('https://stale.example/'),
          type: Value('unknownOpds'),
        ),
      );
      await repository.ensureBuiltInSources();
      final repaired = await repository.getById(original.id);
      expect(repaired!.name, original.name);
      expect(repaired.baseUri, original.baseUri);
      expect(repaired.createdAt, original.createdAt);
    },
  );

  test(
    'custom add, edit, toggle and delete preserve the correct fields',
    () async {
      final added = await repository.addCustomSource(
        name: 'Zulu',
        baseUri: Uri.parse('https://z.example/'),
      );
      expect(added.id, 'custom-id');
      expect(added.isEnabled, isTrue);
      expect(added.type, CatalogSourceType.unknownOpds);
      expect(added.supportsSearch, isFalse);

      final persistedBeforeEdit = (await repository.getById(added.id))!;
      await repository.updateCustomSource(
        id: added.id,
        name: 'Alpha',
        baseUri: added.baseUri,
      );
      final renamed = (await repository.getById(added.id))!;
      expect(renamed.id, added.id);
      expect(
        renamed.createdAt.millisecondsSinceEpoch,
        persistedBeforeEdit.createdAt.millisecondsSinceEpoch,
      );
      expect(renamed.type, CatalogSourceType.unknownOpds);

      await repository.setEnabled(id: added.id, enabled: false);
      expect((await repository.getById(added.id))!.isEnabled, isFalse);
      await repository.deleteCustomSource(added.id);
      expect(await repository.getById(added.id), isNull);
    },
  );

  test(
    'URL edit resets capabilities and health, name-only edit does not',
    () async {
      final added = await repository.addCustomSource(
        name: 'Custom',
        baseUri: Uri.parse('https://one.example/'),
      );
      await (database.update(
        database.catalogSourcesEntries,
      )..where((entry) => entry.id.equals(added.id))).write(
        CatalogSourcesEntriesCompanion(
          type: const Value('opds2'),
          supportsSearch: const Value(true),
          health: const Value('available'),
          lastCheckedAt: Value(DateTime(2026)),
          lastErrorCode: const Value('old-error'),
        ),
      );
      await repository.updateCustomSource(
        id: added.id,
        name: 'Renamed',
        baseUri: added.baseUri,
      );
      expect(
        (await repository.getById(added.id))!.health,
        CatalogSourceHealth.available,
      );

      await repository.updateCustomSource(
        id: added.id,
        name: 'Renamed',
        baseUri: Uri.parse('https://two.example/'),
      );
      final changed = (await repository.getById(added.id))!;
      expect(changed.type, CatalogSourceType.unknownOpds);
      expect(changed.supportsSearch, isFalse);
      expect(changed.health, CatalogSourceHealth.unknown);
      expect(changed.lastCheckedAt, isNull);
      expect(changed.lastErrorCode, isNull);
    },
  );

  test(
    'rejects duplicate URLs and built-in mutation, and orders deterministically',
    () async {
      await repository.ensureBuiltInSources();
      await repository.addCustomSource(
        name: 'Zulu',
        baseUri: Uri.parse('https://z.example/'),
      );
      expect(
        () => repository.addCustomSource(
          name: 'Again',
          baseUri: Uri.parse('https://z.example/'),
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        repository.deleteCustomSource(builtInCatalogSources.first.id),
        throwsA(isA<StateError>()),
      );
      final all = await repository.getAll();
      expect(all.take(3).every((source) => source.isBuiltIn), isTrue);
      expect(all.last.name, 'Zulu');
    },
  );
}

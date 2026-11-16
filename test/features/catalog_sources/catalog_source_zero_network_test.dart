import 'dart:async';

import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_controller.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/data/built_in_catalog_sources.dart';
import 'package:bibliolife/features/catalog_sources/data/catalog_source_url_normalizer.dart';
import 'package:bibliolife/features/catalog_sources/data/drift_catalog_source_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_failure.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/catalog_sources_screen.dart';
import 'package:bibliolife/features/connectivity/application/app_connectivity_mode_provider.dart';
import 'package:bibliolife/features/connectivity/application/network_access_policy.dart';
import 'package:bibliolife/features/connectivity/domain/app_connectivity_mode.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'fresh Offline bootstrap and repeated built-in seeding make zero network calls',
    () async {
      final harness = await _ZeroNetworkHarness.create();
      try {
        final builtInsReady = Completer<List<CatalogSource>>();
        final sourceSubscription = harness.container.listen(
          catalogSourcesProvider,
          (_, next) {
            next.whenData((sources) {
              if (sources.where((source) => source.isBuiltIn).length ==
                      builtInCatalogSources.length &&
                  !builtInsReady.isCompleted) {
                builtInsReady.complete(sources);
              }
            });
          },
        );
        final connectivity = await _loadedConnectivity(harness.container);

        expect(connectivity.mode, AppConnectivityMode.offline);
        expect(connectivity.hasAcknowledgedOnline, isFalse);
        await harness.container
            .read(catalogSourcesBootstrapProvider.future)
            .timeout(const Duration(seconds: 5));
        final sources = await builtInsReady.future.timeout(
          const Duration(seconds: 5),
        );
        expect(
          sources.where((source) => source.isBuiltIn),
          hasLength(builtInCatalogSources.length),
        );
        _expectNoNetwork(harness, connectivity);

        await harness.repository.ensureBuiltInSources();
        await harness.repository.ensureBuiltInSources();
        final reseeded = await harness.repository.getAll();
        final builtIns = reseeded.where((source) => source.isBuiltIn).toList();
        expect(builtIns, hasLength(builtInCatalogSources.length));
        expect(
          builtIns.map((source) => source.id).toSet(),
          hasLength(builtInCatalogSources.length),
        );
        _expectNoNetwork(
          harness,
          harness.container.read(appConnectivityModeProvider),
        );
        sourceSubscription.close();
      } finally {
        await harness.close();
      }
    },
  );

  test(
    'production controllers persist all local mutations and URL validation with zero network calls',
    () async {
      final harness = await _ZeroNetworkHarness.create(
        generatedIds: ['custom-source', 'trailing-source'],
      );
      try {
        final sourceSubscription = harness.container.listen(
          catalogSourcesProvider,
          (_, _) {},
        );
        await harness.container
            .read(catalogSourcesBootstrapProvider.future)
            .timeout(const Duration(seconds: 5));
        await _seedLocalData(harness.database);
        final controller = harness.container.read(
          catalogSourcesControllerProvider.notifier,
        );

        expect(
          await controller.add(
            ' Local Library ',
            ' https://LOCAL.example:443/catalog#ignored ',
          ),
          isTrue,
        );
        var custom = await harness.repository.getById('custom-source');
        expect(custom, isNotNull);
        expect(custom!.name, 'Local Library');
        expect(custom.baseUri.toString(), 'https://local.example/catalog');
        _expectOfflineUnchanged(harness);

        expect(
          await controller.update(
            custom.id,
            'Renamed Library',
            custom.baseUri.toString(),
          ),
          isTrue,
        );
        custom = await harness.repository.getById(custom.id);
        expect(custom!.name, 'Renamed Library');
        expect(custom.baseUri.toString(), 'https://local.example/catalog');
        _expectOfflineUnchanged(harness);

        expect(
          await controller.update(
            custom.id,
            custom.name,
            'https://EDITED.example:443/new-path#fragment',
          ),
          isTrue,
        );
        custom = await harness.repository.getById(custom.id);
        expect(custom!.baseUri.toString(), 'https://edited.example/new-path');
        _expectOfflineUnchanged(harness);

        expect(await controller.setEnabled(custom.id, false), isTrue);
        expect(
          (await harness.repository.getById(custom.id))!.isEnabled,
          isFalse,
        );
        _expectOfflineUnchanged(harness);
        expect(await controller.setEnabled(custom.id, true), isTrue);
        expect(
          (await harness.repository.getById(custom.id))!.isEnabled,
          isTrue,
        );
        _expectOfflineUnchanged(harness);

        final builtIn = (await harness.repository.getAll()).firstWhere(
          (source) => source.isBuiltIn,
        );
        expect(await controller.setEnabled(builtIn.id, false), isTrue);
        await harness.repository.ensureBuiltInSources();
        await harness.repository.ensureBuiltInSources();
        expect(
          (await harness.repository.getById(builtIn.id))!.isEnabled,
          isFalse,
        );
        expect(
          (await harness.repository.getAll()).where(
            (source) => source.isBuiltIn,
          ),
          hasLength(builtInCatalogSources.length),
        );
        _expectOfflineUnchanged(harness);

        expect(
          await controller.add(
            'Duplicate',
            'https://EDITED.EXAMPLE:443/new-path#different',
          ),
          isFalse,
        );
        expect(
          harness.container.read(catalogSourcesControllerProvider).failure,
          CatalogSourceFailure.duplicateUrl,
        );
        _expectOfflineUnchanged(harness);

        expect(
          await controller.add('Invalid HTTP', 'http://invalid.example/opds'),
          isFalse,
        );
        expect(
          harness.container.read(catalogSourcesControllerProvider).failure,
          CatalogSourceFailure.insecureHttp,
        );
        _expectOfflineUnchanged(harness);

        expect(
          CatalogSourceUrlNormalizer.normalize(
            'https://TRAILING.example:443',
          ).uri.toString(),
          'https://trailing.example/',
        );
        expect(
          await controller.add(
            'Trailing Slash',
            'https://TRAILING.example:443',
          ),
          isTrue,
        );
        expect(
          (await harness.repository.getById(
            'trailing-source',
          ))!.baseUri.toString(),
          'https://trailing.example/',
        );
        _expectOfflineUnchanged(harness);

        expect(await controller.delete(custom.id), isTrue);
        expect(await harness.repository.getById(custom.id), isNull);
        _expectOfflineUnchanged(harness);

        await _expectLocalDataPreserved(harness.database);
        final persistedConnectivity = await harness
            .database
            .appConnectivitySettingsDao
            .load();
        expect(persistedConnectivity, isNull);
        expect(harness.spy.callCount, 0);
        sourceSubscription.close();
      } finally {
        await harness.close();
      }
    },
  );

  testWidgets(
    'production Offline source screen with local source makes zero network calls',
    (tester) async {
      final harness = (await tester.runAsync(
        () => _ZeroNetworkHarness.create(generatedIds: ['ui-source']),
      ))!;
      addTearDown(() => tester.runAsync(harness.close));
      await tester.runAsync(
        () => harness.repository.addCustomSource(
          name: 'UI Local Library',
          baseUri: Uri.parse('https://ui-local.example/opds'),
        ),
      );
      await tester.pumpWidget(harness.app());
      await _boundedPump(tester);

      expect(find.text('Offline mode is enabled'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('UI Local Library'),
        400,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 20,
      );
      expect(find.text('UI Local Library'), findsOneWidget);
      expect(
        find.byKey(const Key('online-library-search-toggle-ui-source')),
        findsNothing,
      );
      expect(harness.spy.callCount, 0);

      await tester.pump(const Duration(milliseconds: 750));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(harness.spy.callCount, 0);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(harness.close);
    },
  );

  test(
    'Online mode does not eagerly network for a local source operation',
    () async {
      final harness = await _ZeroNetworkHarness.create(
        generatedIds: ['online-local-source'],
        initialConnectivity: const AppConnectivityState(
          mode: AppConnectivityMode.online,
          hasAcknowledgedOnline: true,
        ),
      );
      try {
        final connectivity = await _loadedConnectivity(harness.container);
        expect(connectivity.mode, AppConnectivityMode.online);
        expect(connectivity.hasAcknowledgedOnline, isTrue);

        final controller = harness.container.read(
          catalogSourcesControllerProvider.notifier,
        );
        expect(
          await controller.add(
            'Online Mode Local Source',
            'https://online-local.example/opds',
          ),
          isTrue,
        );
        final stored = await harness.repository.getById('online-local-source');
        expect(stored, isNotNull);
        expect(stored!.baseUri.toString(), 'https://online-local.example/opds');
        expect(harness.spy.callCount, 0);
        final after = harness.container.read(appConnectivityModeProvider);
        expect(after.mode, AppConnectivityMode.online);
        expect(after.hasAcknowledgedOnline, isTrue);
      } finally {
        await harness.close();
      }
    },
  );
}

class _UnexpectedNetworkSpy implements NetworkAccessPolicy {
  int callCount = 0;

  Never _unexpected(String operation) {
    callCount++;
    throw StateError('unexpected network access during M1A: $operation');
  }

  @override
  bool get isOnlineAccessAllowed => _unexpected('isOnlineAccessAllowed');

  @override
  void requireOnlineAccess(String operation) => _unexpected(operation);
}

class _ZeroNetworkHarness {
  _ZeroNetworkHarness._(
    this.database,
    this.repository,
    this.spy,
    this.container,
  );

  final AppDatabase database;
  final DriftCatalogSourceRepository repository;
  final _UnexpectedNetworkSpy spy;
  final ProviderContainer container;
  bool _closed = false;

  static Future<_ZeroNetworkHarness> create({
    List<String> generatedIds = const [],
    AppConnectivityState? initialConnectivity,
  }) async {
    final database = AppDatabase(NativeDatabase.memory());
    if (initialConnectivity != null) {
      await database.appConnectivitySettingsDao.upsert(
        AppConnectivitySettingsEntriesCompanion.insert(
          id: const Value(1),
          mode: initialConnectivity.mode.name,
          hasAcknowledgedOnline: initialConnectivity.hasAcknowledgedOnline,
        ),
      );
    }
    final ids = generatedIds.iterator;
    final repository = DriftCatalogSourceRepository(
      database,
      idGenerator: () {
        if (!ids.moveNext()) {
          throw StateError('No deterministic catalog-source ID remains');
        }
        return ids.current;
      },
    );
    final spy = _UnexpectedNetworkSpy();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        catalogSourceRepositoryProvider.overrideWithValue(repository),
        networkAccessPolicyProvider.overrideWithValue(spy),
      ],
    );
    return _ZeroNetworkHarness._(database, repository, spy, container);
  }

  Widget app() => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: const CatalogSourcesScreen(),
    ),
  );

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    container.dispose();
    await database.close();
  }
}

Future<AppConnectivityState> _loadedConnectivity(
  ProviderContainer container,
) async {
  final completer = Completer<AppConnectivityState>();
  final subscription = container.listen(appConnectivityModeProvider, (_, next) {
    if (next.isLoaded && !completer.isCompleted) completer.complete(next);
  }, fireImmediately: true);
  try {
    return await completer.future.timeout(const Duration(seconds: 5));
  } finally {
    subscription.close();
  }
}

void _expectNoNetwork(
  _ZeroNetworkHarness harness,
  AppConnectivityState connectivity,
) {
  expect(harness.spy.callCount, 0);
  expect(connectivity.mode, AppConnectivityMode.offline);
  expect(connectivity.hasAcknowledgedOnline, isFalse);
}

void _expectOfflineUnchanged(_ZeroNetworkHarness harness) {
  _expectNoNetwork(
    harness,
    harness.container.read(appConnectivityModeProvider),
  );
}

Future<void> _boundedPump(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
}

Future<void> _seedLocalData(AppDatabase database) async {
  await database.booksDao.insertBook(
    BooksCompanion.insert(
      id: 'zero-network-book',
      title: 'Zero Network Book',
      author: const Value('Local Author'),
      filePath: '/books/zero-network.epub',
      originalFilePath: const Value('/imports/zero-network.epub'),
      fileName: 'zero-network.epub',
      fileExtension: 'epub',
      fileSizeBytes: 8192,
      dateAdded: DateTime.utc(2026, 3, 1),
      isFavorite: const Value(true),
    ),
  );
  await database.readingProgressDao.upsertProgress(
    ReadingProgressEntriesCompanion.insert(
      bookId: 'zero-network-book',
      locatorJson: const Value(
        '{"href":"local.xhtml","locations":{"progression":0.33}}',
      ),
      progression: const Value(0.33),
      currentChapterTitle: const Value('Local Chapter'),
      currentPage: const Value(33),
      totalPages: const Value(100),
      updatedAt: DateTime.utc(2026, 3, 2),
    ),
  );
  await database.bookmarksDao.insertBookmark(
    BookmarksCompanion.insert(
      id: 'zero-network-bookmark',
      bookId: 'zero-network-book',
      locatorJson: '{"href":"local.xhtml","locations":{"progression":0.33}}',
      href: const Value('local.xhtml'),
      progression: const Value(0.33),
      position: const Value(33),
      title: const Value('Local bookmark'),
      note: const Value('Local note'),
      createdAt: DateTime.utc(2026, 3, 2),
      updatedAt: DateTime.utc(2026, 3, 2),
    ),
  );
  await database
      .into(database.readerAnnotations)
      .insert(
        ReaderAnnotationsCompanion.insert(
          id: 'zero-network-annotation',
          bookId: 'zero-network-book',
          locatorJson:
              '{"href":"local.xhtml","locations":{"progression":0.33}}',
          locationKey: 'local.xhtml|0.33',
          selectedText: 'Local annotation',
          note: const Value('Annotation note'),
          style: const Value('underline'),
          color: const Value('purple'),
          href: 'local.xhtml',
          progression: const Value(0.33),
          totalProgression: const Value(0.43),
          createdAt: DateTime.utc(2026, 3, 2),
          updatedAt: DateTime.utc(2026, 3, 2),
        ),
      );
}

Future<void> _expectLocalDataPreserved(AppDatabase database) async {
  final book = await database.booksDao.getBookById('zero-network-book');
  expect(book, isNotNull);
  expect(book!.title, 'Zero Network Book');
  expect(book.author, 'Local Author');
  expect(book.filePath, '/books/zero-network.epub');
  expect(book.originalFilePath, '/imports/zero-network.epub');
  expect(book.isFavorite, isTrue);

  final progress = await database.readingProgressDao.getProgressForBook(
    'zero-network-book',
  );
  expect(progress, isNotNull);
  expect(
    progress!.locatorJson,
    '{"href":"local.xhtml","locations":{"progression":0.33}}',
  );
  expect(progress.progression, 0.33);
  expect(progress.currentChapterTitle, 'Local Chapter');
  expect(progress.currentPage, 33);
  expect(progress.totalPages, 100);

  final bookmark = await database.bookmarksDao.findById(
    'zero-network-bookmark',
  );
  expect(bookmark, isNotNull);
  expect(bookmark!.bookId, 'zero-network-book');
  expect(bookmark.locatorJson, progress.locatorJson);
  expect(bookmark.position, 33);
  expect(bookmark.title, 'Local bookmark');
  expect(bookmark.note, 'Local note');

  final annotation =
      await (database.select(database.readerAnnotations)
            ..where((row) => row.id.equals('zero-network-annotation')))
          .getSingleOrNull();
  expect(annotation, isNotNull);
  expect(annotation!.bookId, 'zero-network-book');
  expect(annotation.locatorJson, progress.locatorJson);
  expect(annotation.locationKey, 'local.xhtml|0.33');
  expect(annotation.selectedText, 'Local annotation');
  expect(annotation.note, 'Annotation note');
  expect(annotation.style, 'underline');
  expect(annotation.color, 'purple');
}

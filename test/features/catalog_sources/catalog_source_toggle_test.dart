import 'dart:async';
import 'dart:ui' as ui;

import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/data/built_in_catalog_sources.dart';
import 'package:bibliolife/features/catalog_sources/data/drift_catalog_source_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_repository.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/catalog_sources_screen.dart';
import 'package:bibliolife/features/connectivity/application/app_connectivity_mode_provider.dart';
import 'package:bibliolife/features/connectivity/data/app_connectivity_mode_repository.dart';
import 'package:bibliolife/features/connectivity/domain/app_connectivity_mode.dart';
import 'package:bibliolife/features/home/application/providers/home_online_tab_settings_provider.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Custom source toggles disabled to enabled and preserves metadata',
    (tester) async {
      final fixture = (await tester.runAsync(
        () => _RealToggleFixture.create(
          customEnabled: false,
          seedLocalData: true,
        ),
      ))!;
      addTearDown(() => tester.runAsync(fixture.close));
      await tester.pumpWidget(fixture.app());
      await _pumpAuthoritative(tester);
      final semantics = tester.ensureSemantics();
      await tester.pump();
      final before = await tester.runAsync(
        () => fixture.repository.getById('toggle-source'),
      );

      await _ensureSourceVisible(tester, 'Toggle Test Library');
      final sourceSwitch = _sourceSwitch('Toggle Test Library');
      expect(tester.widget<Switch>(sourceSwitch).value, isFalse);
      expect(
        find.bySemanticsLabel(RegExp('Use Toggle Test Library in Search')),
        findsOneWidget,
      );

      await tester.tap(sourceSwitch);
      await _pumpAuthoritative(tester);

      final after = await tester.runAsync(
        () => fixture.repository.getById('toggle-source'),
      );
      expect(after, isNotNull);
      expect(after!.isEnabled, isTrue);
      _expectMetadataPreserved(before!, after);
      expect(after.updatedAt.isAfter(before.updatedAt), isTrue);
      expect(fixture.repository.setEnabledCalls, 1);
      expect(tester.widget<Switch>(sourceSwitch).value, isTrue);
      await tester.runAsync(() => _expectLocalDataPreserved(fixture.database));
      expect(tester.takeException(), isNull);

      semantics.dispose();
      await _closeRealFixture(tester, fixture);
    },
  );

  testWidgets(
    'Custom source toggles enabled to disabled offline and preserves local data',
    (tester) async {
      final fixture = (await tester.runAsync(
        () =>
            _RealToggleFixture.create(customEnabled: true, seedLocalData: true),
      ))!;
      addTearDown(() => tester.runAsync(fixture.close));
      await tester.pumpWidget(fixture.app());
      await _pumpAuthoritative(tester);
      expect(find.text('Offline mode is enabled'), findsOneWidget);
      final before = await tester.runAsync(
        () => fixture.repository.getById('toggle-source'),
      );
      final connectivityBefore = await tester.runAsync(
        fixture.database.appConnectivitySettingsDao.load,
      );

      await _ensureSourceVisible(tester, 'Toggle Test Library');
      final sourceSwitch = _sourceSwitch('Toggle Test Library');
      expect(tester.widget<Switch>(sourceSwitch).value, isTrue);
      await tester.tap(sourceSwitch);
      await _pumpAuthoritative(tester);

      final after = await tester.runAsync(
        () => fixture.repository.getById('toggle-source'),
      );
      expect(after, isNotNull);
      expect(after!.isEnabled, isFalse);
      _expectMetadataPreserved(before!, after);
      expect(after.updatedAt.isAfter(before.updatedAt), isTrue);
      expect(fixture.repository.setEnabledCalls, 1);
      expect(await tester.runAsync(fixture.repository.getAll), isNotEmpty);
      expect(tester.widget<Switch>(sourceSwitch).value, isFalse);
      await tester.runAsync(() => _expectLocalDataPreserved(fixture.database));
      final connectivityAfter = await tester.runAsync(
        fixture.database.appConnectivitySettingsDao.load,
      );
      expect(connectivityAfter!.mode, AppConnectivityMode.offline.name);
      expect(connectivityAfter.mode, connectivityBefore!.mode);
      expect(
        connectivityAfter.hasAcknowledgedOnline,
        connectivityBefore.hasAcknowledgedOnline,
      );
      expect(tester.takeException(), isNull);

      await _closeRealFixture(tester, fixture);
    },
  );

  testWidgets(
    'Built-in toggle persists in both directions and reseeding is idempotent',
    (tester) async {
      final fixture = (await tester.runAsync(
        () =>
            _RealToggleFixture.create(customEnabled: true, seedBuiltIns: true),
      ))!;
      addTearDown(() => tester.runAsync(fixture.close));
      await tester.pumpWidget(fixture.app());
      await _pumpAuthoritative(tester);
      final semantics = tester.ensureSemantics();
      await tester.pump();
      final target = builtInCatalogSources.first;
      await _ensureSourceVisible(tester, 'Toggle Test Library');
      final customSemantics = find.bySemanticsLabel(
        RegExp('Use Toggle Test Library in Search'),
      );
      expect(customSemantics, findsOneWidget);
      final builtInSwitchFinder = find.byKey(
        Key('online-library-search-toggle-${target.id}'),
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, 900));
      await tester.pump();
      expect(builtInSwitchFinder, findsOneWidget);
      final before = await tester.runAsync(
        () => fixture.repository.getById(target.id),
      );
      final builtInSwitch = _sourceSwitch(target.name);

      await tester.tap(builtInSwitch);
      await _pumpAuthoritative(tester);
      final disabled = await tester.runAsync(
        () => fixture.repository.getById(target.id),
      );
      expect(disabled, isNotNull);
      expect(disabled!.isEnabled, isFalse);
      expect(disabled.id, before!.id);
      expect(disabled.name, before.name);
      expect(disabled.baseUri, before.baseUri);
      expect(disabled.isBuiltIn, isTrue);

      await tester.runAsync(() async {
        await fixture.repository.ensureBuiltInSources();
        await fixture.repository.ensureBuiltInSources();
      });
      final afterReseed = await tester.runAsync(
        () => fixture.repository.getById(target.id),
      );
      expect(afterReseed!.isEnabled, isFalse);
      var builtIns = (await tester.runAsync(
        fixture.repository.getAll,
      ))!.where((source) => source.isBuiltIn).toList();
      expect(builtIns, hasLength(builtInCatalogSources.length));
      expect(
        builtIns.map((source) => source.id).toSet(),
        hasLength(builtInCatalogSources.length),
      );

      await tester.tap(builtInSwitch);
      await _pumpAuthoritative(tester);
      final enabled = await tester.runAsync(
        () => fixture.repository.getById(target.id),
      );
      expect(enabled!.isEnabled, isTrue);
      await tester.runAsync(() async {
        await fixture.repository.ensureBuiltInSources();
        await fixture.repository.ensureBuiltInSources();
      });
      expect(
        (await tester.runAsync(
          () => fixture.repository.getById(target.id),
        ))!.isEnabled,
        isTrue,
      );
      builtIns = (await tester.runAsync(
        fixture.repository.getAll,
      ))!.where((source) => source.isBuiltIn).toList();
      expect(builtIns, hasLength(builtInCatalogSources.length));
      expect(fixture.repository.setEnabledCalls, 2);
      expect(
        find.descendant(
          of: _sourceCard(target.name),
          matching: find.byIcon(Icons.more_vert),
        ),
        findsNothing,
      );

      semantics.dispose();
      await _closeRealFixture(tester, fixture);
    },
  );

  testWidgets(
    'Pending rapid semantic activation submits once and waits for stream',
    (tester) async {
      final pending = Completer<void>();
      final repository = _ControlledToggleRepository(
        [_customSource(enabled: false), _otherSource],
        pendingSetEnabled: pending,
        emitAfterSetEnabled: false,
      );
      final harness = _ControlledHarness(repository);
      await tester.pumpWidget(harness.app());
      await _pumpAuthoritative(tester);
      final semanticsHandle = tester.ensureSemantics();
      await tester.pump();
      await _ensureSourceVisible(tester, 'Toggle Test Library');
      final sourceSwitch = _sourceSwitch('Toggle Test Library');
      final semanticsFinder = find.bySemanticsLabel(
        RegExp('Use Toggle Test Library in Search'),
      );
      final semanticsActionFinder = find.semantics.byLabel(
        RegExp('Use Toggle Test Library in Search'),
      );
      final node = tester.getSemantics(semanticsFinder);
      expect(
        node.getSemanticsData().flagsCollection.isToggled,
        ui.Tristate.isFalse,
      );

      tester.semantics.tap(semanticsActionFinder);
      await tester.pump();
      expect(repository.setEnabledCalls, 1);
      expect(tester.widget<Switch>(sourceSwitch).value, isFalse);
      expect(tester.widget<Switch>(sourceSwitch).onChanged, isNull);
      expect(
        tester
            .getSemantics(semanticsFinder)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
      );

      await tester.tap(sourceSwitch, warnIfMissed: false);
      await tester.pump();
      expect(repository.setEnabledCalls, 1);
      expect(find.byType(SnackBar), findsNothing);

      pending.complete();
      await _pumpAuthoritative(tester);
      expect(repository.setEnabledCalls, 1);
      expect(tester.widget<Switch>(sourceSwitch).value, isFalse);
      expect(tester.widget<Switch>(sourceSwitch).onChanged, isNotNull);

      repository.emitEnabled('toggle-source', true);
      await _pumpAuthoritative(tester);
      expect(tester.widget<Switch>(sourceSwitch).value, isTrue);
      expect(find.text('Other Library'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      semanticsHandle.dispose();
      await harness.close(tester);
    },
  );

  testWidgets('Persistence failure restores control without optimistic state', (
    tester,
  ) async {
    final repository = _ControlledToggleRepository([
      _customSource(enabled: true),
      _otherSource,
    ], setEnabledError: StateError('persistenceFailure'));
    final harness = _ControlledHarness(repository);
    await tester.pumpWidget(harness.app());
    await _pumpAuthoritative(tester);
    await _ensureSourceVisible(tester, 'Toggle Test Library');
    final sourceSwitch = _sourceSwitch('Toggle Test Library');

    await tester.tap(sourceSwitch);
    await _pumpAuthoritative(tester);
    await _ensureSourceVisible(tester, 'Toggle Test Library');

    expect(repository.setEnabledCalls, 1);
    expect(tester.widget<Switch>(sourceSwitch).value, isTrue);
    expect(tester.widget<Switch>(sourceSwitch).onChanged, isNotNull);
    expect(
      find.text('The library could not be updated. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Other Library'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await harness.close(tester);
  });

  testWidgets(
    'Successful toggle remains old until authoritative stream emits',
    (tester) async {
      final repository = _ControlledToggleRepository([
        _customSource(enabled: false),
        _otherSource,
      ], emitAfterSetEnabled: false);
      final harness = _ControlledHarness(repository);
      await tester.pumpWidget(harness.app());
      await _pumpAuthoritative(tester);
      await _ensureSourceVisible(tester, 'Toggle Test Library');
      final sourceSwitch = _sourceSwitch('Toggle Test Library');

      await tester.tap(sourceSwitch);
      await _pumpAuthoritative(tester);
      await _ensureSourceVisible(tester, 'Toggle Test Library');

      expect(repository.setEnabledCalls, 1);
      expect(tester.widget<Switch>(sourceSwitch).value, isFalse);
      expect(tester.widget<Switch>(sourceSwitch).onChanged, isNotNull);

      repository.emitEnabled('toggle-source', true);
      await _pumpAuthoritative(tester);
      await _ensureSourceVisible(tester, 'Toggle Test Library');
      expect(tester.widget<Switch>(sourceSwitch).value, isTrue);
      await harness.close(tester);
    },
  );

  testWidgets(
    'Source disappearing during toggle is a safe failure and preserves local data',
    (tester) async {
      final database = (await tester.runAsync(
        () async => AppDatabase(NativeDatabase.memory()),
      ))!;
      addTearDown(() => tester.runAsync(database.close));
      await tester.runAsync(() => _seedLocalData(database));
      final pending = Completer<void>();
      final repository = _ControlledToggleRepository(
        [_customSource(enabled: true), _otherSource],
        pendingSetEnabled: pending,
        failWhenMissing: true,
      );
      final harness = _ControlledHarness(repository, database: database);
      await tester.pumpWidget(harness.app());
      await _pumpAuthoritative(tester);

      await _ensureSourceVisible(tester, 'Toggle Test Library');
      await tester.tap(_sourceSwitch('Toggle Test Library'));
      await tester.pump();
      expect(repository.setEnabledCalls, 1);
      repository.emitWithout('toggle-source');
      await tester.pump();
      pending.complete();
      await _pumpAuthoritative(tester);
      await _ensureSourceVisible(tester, 'Other Library');

      expect(find.text('Toggle Test Library'), findsNothing);
      expect(find.text('Other Library'), findsOneWidget);
      expect(repository.setEnabledCalls, 1);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => _expectLocalDataPreserved(database));
      await harness.close(tester);
    },
  );
}

Finder _sourceCard(String sourceName) => find.ancestor(
  of: find.text(sourceName, skipOffstage: false),
  matching: find.byType(Card),
);

Finder _sourceSwitch(String sourceName) {
  final id = switch (sourceName) {
    'Toggle Test Library' => 'toggle-source',
    'Other Library' => 'other-source',
    _ =>
      builtInCatalogSources
          .firstWhere((source) => source.name == sourceName)
          .id,
  };
  return find.byKey(Key('online-library-search-toggle-$id'));
}

Future<void> _ensureSourceVisible(
  WidgetTester tester,
  String sourceName,
) async {
  await tester.scrollUntilVisible(
    find.text(sourceName),
    400,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 20,
  );
  await tester.pump();
}

Future<void> _pumpAuthoritative(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _closeRealFixture(
  WidgetTester tester,
  _RealToggleFixture fixture,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.runAsync(fixture.close);
}

void _expectMetadataPreserved(CatalogSource before, CatalogSource after) {
  expect(after.id, before.id);
  expect(after.name, before.name);
  expect(after.baseUri, before.baseUri);
  expect(after.type, before.type);
  expect(after.isBuiltIn, before.isBuiltIn);
  expect(after.supportsSearch, before.supportsSearch);
  expect(after.supportsNavigation, before.supportsNavigation);
  expect(after.supportsAcquisition, before.supportsAcquisition);
  expect(after.createdAt, before.createdAt);
  expect(after.lastSuccessfulAccessAt, before.lastSuccessfulAccessAt);
  expect(after.lastCheckedAt, before.lastCheckedAt);
  expect(after.health, before.health);
  expect(after.lastErrorCode, before.lastErrorCode);
}

CatalogSource _customSource({required bool enabled}) => CatalogSource(
  id: 'toggle-source',
  name: 'Toggle Test Library',
  baseUri: Uri.parse('https://toggle.example/opds'),
  type: CatalogSourceType.opds2,
  isBuiltIn: false,
  isEnabled: enabled,
  supportsSearch: true,
  supportsNavigation: true,
  supportsAcquisition: true,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 2),
  lastSuccessfulAccessAt: DateTime.utc(2026, 1, 3),
  lastCheckedAt: DateTime.utc(2026, 1, 4),
  health: CatalogSourceHealth.available,
  lastErrorCode: 'preserved-error',
);

final _otherSource = CatalogSource(
  id: 'other-source',
  name: 'Other Library',
  baseUri: Uri.parse('https://other.example/opds'),
  type: CatalogSourceType.unknownOpds,
  isBuiltIn: false,
  isEnabled: true,
  supportsSearch: false,
  supportsNavigation: false,
  supportsAcquisition: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _RealToggleFixture {
  _RealToggleFixture._(this.database, this.repository, this.container);

  final AppDatabase database;
  final _CountingToggleRepository repository;
  final ProviderContainer container;
  bool _closed = false;

  static Future<_RealToggleFixture> create({
    required bool customEnabled,
    bool seedBuiltIns = false,
    bool seedLocalData = false,
  }) async {
    final database = AppDatabase(NativeDatabase.memory());
    final driftRepository = DriftCatalogSourceRepository(
      database,
      idGenerator: () => 'toggle-source',
    );
    if (seedBuiltIns) await driftRepository.ensureBuiltInSources();
    await driftRepository.addCustomSource(
      name: 'Toggle Test Library',
      baseUri: Uri.parse('https://toggle.example/opds'),
    );
    await (database.update(
      database.catalogSourcesEntries,
    )..where((row) => row.id.equals('toggle-source'))).write(
      CatalogSourcesEntriesCompanion(
        type: const Value('opds2'),
        isEnabled: Value(customEnabled),
        supportsSearch: const Value(true),
        supportsNavigation: const Value(true),
        supportsAcquisition: const Value(true),
        createdAt: Value(DateTime.utc(2026, 1, 1)),
        updatedAt: Value(DateTime.utc(2026, 1, 2)),
        lastSuccessfulAccessAt: Value(DateTime.utc(2026, 1, 3)),
        lastCheckedAt: Value(DateTime.utc(2026, 1, 4)),
        health: const Value('available'),
        lastErrorCode: const Value('preserved-error'),
      ),
    );
    await database.appConnectivitySettingsDao.upsert(
      AppConnectivitySettingsEntriesCompanion.insert(
        id: const Value(1),
        mode: AppConnectivityMode.offline.name,
        hasAcknowledgedOnline: true,
      ),
    );
    if (seedLocalData) await _seedLocalData(database);
    final repository = _CountingToggleRepository(driftRepository);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        catalogSourceRepositoryProvider.overrideWithValue(repository),
      ],
    );
    return _RealToggleFixture._(database, repository, container);
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

class _CountingToggleRepository implements CatalogSourceRepository {
  _CountingToggleRepository(this.delegate);

  final DriftCatalogSourceRepository delegate;
  int setEnabledCalls = 0;

  @override
  Stream<List<CatalogSource>> watchAll() => delegate.watchAll();
  @override
  Future<List<CatalogSource>> getAll() => delegate.getAll();
  @override
  Future<CatalogSource?> getById(String id) => delegate.getById(id);
  @override
  Future<void> ensureBuiltInSources() => delegate.ensureBuiltInSources();
  @override
  Future<CatalogSource> addCustomSource({
    required String name,
    required Uri baseUri,
  }) => delegate.addCustomSource(name: name, baseUri: baseUri);
  @override
  Future<void> updateCustomSource({
    required String id,
    required String name,
    required Uri baseUri,
  }) => delegate.updateCustomSource(id: id, name: name, baseUri: baseUri);
  @override
  Future<void> setEnabled({required String id, required bool enabled}) {
    setEnabledCalls++;
    return delegate.setEnabled(id: id, enabled: enabled);
  }

  @override
  Future<void> deleteCustomSource(String id) => delegate.deleteCustomSource(id);
  @override
  Future<bool> normalizedUrlExists(Uri uri, {String? excludingSourceId}) =>
      delegate.normalizedUrlExists(uri, excludingSourceId: excludingSourceId);
}

class _ControlledHarness {
  _ControlledHarness(this.repository, {this.database})
    : container = ProviderContainer(
        overrides: [
          catalogSourceRepositoryProvider.overrideWithValue(repository),
          appConnectivityModeRepositoryProvider.overrideWithValue(
            database == null
                ? const _FixedConnectivityRepository()
                : DriftAppConnectivityModeRepository(
                    database.appConnectivitySettingsDao,
                  ),
          ),
          homeOnlineTabVisibilityProvider.overrideWith(
            (ref) => Stream.value(const <String, bool>{}),
          ),
          if (database != null) appDatabaseProvider.overrideWithValue(database),
        ],
      );

  final CatalogSourceRepository repository;
  final AppDatabase? database;
  final ProviderContainer container;

  Widget app() => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: const CatalogSourcesScreen(),
    ),
  );

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
  }
}

class _ControlledToggleRepository implements CatalogSourceRepository {
  _ControlledToggleRepository(
    List<CatalogSource> sources, {
    this.pendingSetEnabled,
    this.setEnabledError,
    this.emitAfterSetEnabled = true,
    this.failWhenMissing = false,
  }) : _sources = List.of(sources);

  final _controller = StreamController<List<CatalogSource>>.broadcast();
  final Completer<void>? pendingSetEnabled;
  final Object? setEnabledError;
  final bool emitAfterSetEnabled;
  final bool failWhenMissing;
  List<CatalogSource> _sources;
  int setEnabledCalls = 0;

  @override
  Stream<List<CatalogSource>> watchAll() async* {
    yield List.unmodifiable(_sources);
    yield* _controller.stream;
  }

  void emitEnabled(String id, bool enabled) {
    _sources = _sources
        .map(
          (source) =>
              source.id == id ? source.copyWith(isEnabled: enabled) : source,
        )
        .toList();
    _controller.add(List.unmodifiable(_sources));
  }

  void emitWithout(String id) {
    _sources = _sources.where((source) => source.id != id).toList();
    _controller.add(List.unmodifiable(_sources));
  }

  @override
  Future<void> setEnabled({required String id, required bool enabled}) async {
    setEnabledCalls++;
    if (pendingSetEnabled != null) await pendingSetEnabled!.future;
    if (setEnabledError case final error?) throw error;
    if (failWhenMissing && !_sources.any((source) => source.id == id)) {
      throw StateError('sourceNotFound');
    }
    if (emitAfterSetEnabled) emitEnabled(id, enabled);
  }

  @override
  Future<List<CatalogSource>> getAll() async => List.unmodifiable(_sources);
  @override
  Future<CatalogSource?> getById(String id) async {
    for (final source in _sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  @override
  Future<void> ensureBuiltInSources() async {}
  @override
  Future<CatalogSource> addCustomSource({
    required String name,
    required Uri baseUri,
  }) => throw UnimplementedError();
  @override
  Future<void> updateCustomSource({
    required String id,
    required String name,
    required Uri baseUri,
  }) => throw UnimplementedError();
  @override
  Future<void> deleteCustomSource(String id) => throw UnimplementedError();
  @override
  Future<bool> normalizedUrlExists(
    Uri uri, {
    String? excludingSourceId,
  }) async => false;
}

class _FixedConnectivityRepository implements AppConnectivityModeRepository {
  const _FixedConnectivityRepository();
  @override
  Future<AppConnectivityState> load() async =>
      const AppConnectivityState.offline();
  @override
  Future<void> save(AppConnectivityState state) async {}
}

Future<void> _seedLocalData(AppDatabase database) async {
  await database.booksDao.insertBook(
    BooksCompanion.insert(
      id: 'toggle-local-book',
      title: 'Toggle Preserved Book',
      author: const Value('Toggle Author'),
      filePath: '/books/toggle-preserved.epub',
      originalFilePath: const Value('/imports/toggle-preserved.epub'),
      fileName: 'toggle-preserved.epub',
      fileExtension: 'epub',
      mediaType: const Value('application/epub+zip'),
      fileSizeBytes: 4096,
      dateAdded: DateTime.utc(2026, 2, 1),
      isFavorite: const Value(true),
    ),
  );
  await database.readingProgressDao.upsertProgress(
    ReadingProgressEntriesCompanion.insert(
      bookId: 'toggle-local-book',
      locatorJson: const Value(
        '{"href":"toggle.xhtml","locations":{"progression":0.64}}',
      ),
      progression: const Value(0.64),
      currentChapterTitle: const Value('Toggle Chapter'),
      currentPage: const Value(64),
      totalPages: const Value(100),
      updatedAt: DateTime.utc(2026, 2, 2),
    ),
  );
  await database.bookmarksDao.insertBookmark(
    BookmarksCompanion.insert(
      id: 'toggle-bookmark',
      bookId: 'toggle-local-book',
      locatorJson: '{"href":"toggle.xhtml","locations":{"progression":0.64}}',
      href: const Value('toggle.xhtml'),
      progression: const Value(0.64),
      position: const Value(64),
      title: const Value('Toggle bookmark'),
      note: const Value('Toggle note'),
      createdAt: DateTime.utc(2026, 2, 2),
      updatedAt: DateTime.utc(2026, 2, 2),
    ),
  );
  await database
      .into(database.readerAnnotations)
      .insert(
        ReaderAnnotationsCompanion.insert(
          id: 'toggle-annotation',
          bookId: 'toggle-local-book',
          locatorJson:
              '{"href":"toggle.xhtml","locations":{"progression":0.64}}',
          locationKey: 'toggle.xhtml|0.64',
          selectedText: 'Toggle preserved annotation',
          note: const Value('Toggle annotation note'),
          style: const Value('underline'),
          color: const Value('green'),
          href: 'toggle.xhtml',
          progression: const Value(0.64),
          totalProgression: const Value(0.74),
          createdAt: DateTime.utc(2026, 2, 2),
          updatedAt: DateTime.utc(2026, 2, 2),
        ),
      );
}

Future<void> _expectLocalDataPreserved(AppDatabase database) async {
  final book = await database.booksDao.getBookById('toggle-local-book');
  expect(book, isNotNull);
  expect(book!.title, 'Toggle Preserved Book');
  expect(book.author, 'Toggle Author');
  expect(book.filePath, '/books/toggle-preserved.epub');
  expect(book.originalFilePath, '/imports/toggle-preserved.epub');
  expect(book.isFavorite, isTrue);

  final progress = await database.readingProgressDao.getProgressForBook(
    'toggle-local-book',
  );
  expect(progress, isNotNull);
  expect(
    progress!.locatorJson,
    '{"href":"toggle.xhtml","locations":{"progression":0.64}}',
  );
  expect(progress.progression, 0.64);
  expect(progress.currentChapterTitle, 'Toggle Chapter');
  expect(progress.currentPage, 64);
  expect(progress.totalPages, 100);

  final bookmark = await database.bookmarksDao.findById('toggle-bookmark');
  expect(bookmark, isNotNull);
  expect(bookmark!.bookId, 'toggle-local-book');
  expect(bookmark.locatorJson, progress.locatorJson);
  expect(bookmark.position, 64);
  expect(bookmark.title, 'Toggle bookmark');
  expect(bookmark.note, 'Toggle note');

  final annotation = await (database.select(
    database.readerAnnotations,
  )..where((row) => row.id.equals('toggle-annotation'))).getSingleOrNull();
  expect(annotation, isNotNull);
  expect(annotation!.bookId, 'toggle-local-book');
  expect(annotation.locatorJson, progress.locatorJson);
  expect(annotation.locationKey, 'toggle.xhtml|0.64');
  expect(annotation.selectedText, 'Toggle preserved annotation');
  expect(annotation.note, 'Toggle annotation note');
  expect(annotation.style, 'underline');
  expect(annotation.color, 'green');
}

import 'dart:async';

import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Delete confirmation uses exact Material 3 copy and Cancel persists nothing',
    (tester) async {
      final fixture = (await tester.runAsync(_RealDeleteFixture.create))!;
      await tester.pumpWidget(fixture.app());
      await _pumpSources(tester);
      final before = (await tester.runAsync(fixture.repository.getAll))!;

      await _ensureSourceVisible(tester, 'Delete Test Library');
      await _openDeleteDialog(tester, 'Delete Test Library');

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byType(AlertDialog))).useMaterial3,
        isTrue,
      );
      expect(find.text(AppStrings.removeLibrarySourceTitle), findsOneWidget);
      expect(find.text(AppStrings.removeLibrarySourceBody), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, AppStrings.cancel),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, AppStrings.remove),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, AppStrings.cancel));
      await _boundedPump(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        await tester.runAsync(
          () => fixture.repository.getById('delete-source'),
        ),
        isNotNull,
      );
      expect(
        await tester.runAsync(() => fixture.repository.getById('keep-source')),
        isNotNull,
      );
      expect(fixture.repository.deleteCalls, 0);
      final after = (await tester.runAsync(fixture.repository.getAll))!;
      expect(
        after.map((source) => source.id).toSet(),
        before.map((source) => source.id).toSet(),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(fixture.close);
    },
  );

  testWidgets(
    'Remove persists once and preserves other sources and all local book data',
    (tester) async {
      final fixture = (await tester.runAsync(_RealDeleteFixture.create))!;
      await tester.pumpWidget(fixture.app());
      await _pumpSources(tester);
      final sourcesBefore = (await tester.runAsync(fixture.repository.getAll))!;
      final builtInsBefore = sourcesBefore
          .where((source) => source.isBuiltIn)
          .map((source) => (source.id, source.name, source.baseUri))
          .toList();
      final keepBefore = await tester.runAsync(
        () => fixture.repository.getById('keep-source'),
      );
      final connectivityBefore = await tester.runAsync(
        fixture.database.appConnectivitySettingsDao.load,
      );

      await _ensureSourceVisible(tester, 'Delete Test Library');
      await _openDeleteDialog(tester, 'Delete Test Library');
      await tester.tap(find.widgetWithText(FilledButton, AppStrings.remove));
      await _boundedPump(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        await tester.runAsync(
          () => fixture.repository.getById('delete-source'),
        ),
        isNull,
      );
      final keepAfter = await tester.runAsync(
        () => fixture.repository.getById('keep-source'),
      );
      expect(keepAfter, isNotNull);
      expect(keepAfter!.name, keepBefore!.name);
      expect(keepAfter.baseUri, keepBefore.baseUri);
      expect(fixture.repository.deleteCalls, 1);
      expect(find.text('Delete Test Library'), findsNothing);

      final sourcesAfter = (await tester.runAsync(fixture.repository.getAll))!;
      final builtInsAfter = sourcesAfter
          .where((source) => source.isBuiltIn)
          .map((source) => (source.id, source.name, source.baseUri))
          .toList();
      expect(builtInsAfter, builtInsBefore);
      await tester.runAsync(fixture.expectLocalDataPreserved);
      final connectivityAfter = await tester.runAsync(
        fixture.database.appConnectivitySettingsDao.load,
      );
      expect(connectivityAfter!.mode, connectivityBefore!.mode);
      expect(
        connectivityAfter.hasAcknowledgedOnline,
        connectivityBefore.hasAcknowledgedOnline,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(fixture.close);
    },
  );

  testWidgets('Built-in source does not expose Delete', (tester) async {
    final repository = _ControlledDeleteRepository([
      _source(
        id: 'built-in-source',
        name: 'Built-in Test Library',
        url: 'https://built-in.example/opds',
        builtIn: true,
      ),
      _deleteSource,
    ]);
    await tester.pumpWidget(_controlledApp(repository));
    await _pumpSources(tester);

    final builtInCard = _sourceCard('Built-in Test Library');
    expect(
      find.descendant(of: builtInCard, matching: find.byIcon(Icons.more_vert)),
      findsNothing,
    );
    expect(find.text('Built-in Test Library'), findsOneWidget);
    expect(repository.deleteCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Missing source is recoverable and does not affect local data', (
    tester,
  ) async {
    final database = (await tester.runAsync(
      () async => AppDatabase(NativeDatabase.memory()),
    ))!;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await database.close();
    });
    await tester.runAsync(() => _seedLocalData(database));
    final repository = _ControlledDeleteRepository([
      _deleteSource,
      _keepSource,
    ], failWhenMissing: true);
    await tester.pumpWidget(_controlledApp(repository, database: database));
    await _pumpSources(tester);
    await _ensureSourceVisible(tester, 'Delete Test Library');
    await _openDeleteDialog(tester, 'Delete Test Library');

    repository.emitWithout('delete-source');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, AppStrings.remove));
    await _boundedPump(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(_deleteFailureMessage), findsOneWidget);
    expect(find.widgetWithText(TextButton, AppStrings.cancel), findsOneWidget);
    expect(find.text('Keep Test Library'), findsOneWidget);
    expect(repository.deleteCalls, 1);
    await _expectLocalDataPreserved(database);

    await tester.tap(find.widgetWithText(TextButton, AppStrings.cancel));
    await _boundedPump(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Persistence failure keeps the dialog recoverable without optimistic removal',
    (tester) async {
      final repository = _ControlledDeleteRepository([
        _deleteSource,
        _keepSource,
      ], deleteError: StateError('persistenceFailure'));
      await tester.pumpWidget(_controlledApp(repository));
      await _pumpSources(tester);
      await _openDeleteDialog(tester, 'Delete Test Library');

      await tester.tap(find.widgetWithText(FilledButton, AppStrings.remove));
      await _boundedPump(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(_deleteFailureMessage), findsOneWidget);
      expect(find.text('Delete Test Library'), findsOneWidget);
      expect(find.text('Keep Test Library'), findsOneWidget);
      expect(repository.deleteCalls, 1);
      expect(
        find.widgetWithText(FilledButton, AppStrings.remove),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextButton, AppStrings.cancel),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(TextButton, AppStrings.cancel));
      await _boundedPump(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Delete Test Library'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Pending Remove is disabled, submits once, and closes once', (
    tester,
  ) async {
    final pending = Completer<void>();
    final repository = _ControlledDeleteRepository([
      _deleteSource,
      _keepSource,
    ], pendingDelete: pending);
    final observer = _CountingNavigatorObserver();
    await tester.pumpWidget(_controlledApp(repository, observer: observer));
    await _pumpSources(tester);
    await _openDeleteDialog(tester, 'Delete Test Library');
    final popsBeforeRemove = observer.popCalls;

    expect(
      find.bySemanticsLabel(AppStrings.removeLibrarySourceTitle),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, AppStrings.remove));
    await tester.pump();

    expect(repository.deleteCalls, 1);
    final removeButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, AppStrings.remove),
    );
    expect(removeButton.onPressed, isNull);
    final removeSemantics = tester
        .getSemantics(find.widgetWithText(FilledButton, AppStrings.remove))
        .getSemanticsData();
    expect(removeSemantics.hasAction(SemanticsAction.tap), isFalse);

    await tester.tap(
      find.widgetWithText(FilledButton, AppStrings.remove),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(repository.deleteCalls, 1);
    expect(observer.popCalls, popsBeforeRemove);
    expect(find.text('Delete Test Library'), findsOneWidget);

    pending.complete();
    await _boundedPump(tester);
    expect(repository.deleteCalls, 1);
    expect(observer.popCalls, popsBeforeRemove + 1);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Delete Test Library'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Successful delete remains visible until repository stream emits',
    (tester) async {
      final repository = _ControlledDeleteRepository([
        _deleteSource,
        _keepSource,
      ], emitAfterDelete: false);
      await tester.pumpWidget(_controlledApp(repository));
      await _pumpSources(tester);
      await _openDeleteDialog(tester, 'Delete Test Library');

      await tester.tap(find.widgetWithText(FilledButton, AppStrings.remove));
      await _boundedPump(tester);

      expect(repository.deleteCalls, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Delete Test Library'), findsOneWidget);

      repository.emitWithout('delete-source');
      await tester.pump();
      expect(find.text('Delete Test Library'), findsNothing);
      expect(find.text('Keep Test Library'), findsOneWidget);
    },
  );
}

const _deleteFailureMessage =
    'The library could not be removed. Try again or Cancel.';

final _deleteSource = _source(
  id: 'delete-source',
  name: 'Delete Test Library',
  url: 'https://delete.example/opds',
);
final _keepSource = _source(
  id: 'keep-source',
  name: 'Keep Test Library',
  url: 'https://keep.example/opds',
);

CatalogSource _source({
  required String id,
  required String name,
  required String url,
  bool builtIn = false,
}) => CatalogSource(
  id: id,
  name: name,
  baseUri: Uri.parse(url),
  type: CatalogSourceType.unknownOpds,
  isBuiltIn: builtIn,
  isEnabled: true,
  supportsSearch: false,
  supportsNavigation: false,
  supportsAcquisition: false,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Finder _sourceCard(String sourceName) => find.ancestor(
  of: find.text(sourceName, skipOffstage: false),
  matching: find.byType(Card),
);

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

Future<void> _openDeleteDialog(WidgetTester tester, String sourceName) async {
  await _ensureSourceVisible(tester, sourceName);
  final menu = find.descendant(
    of: _sourceCard(sourceName),
    matching: find.byIcon(Icons.more_vert),
  );
  expect(menu, findsOneWidget);
  await tester.tap(menu);
  await _boundedPump(tester);
  final semantics = tester.ensureSemantics();
  await tester.pump();
  expect(find.bySemanticsLabel(RegExp('Delete $sourceName')), findsOneWidget);
  await tester.tap(find.text('Delete').last);
  await _boundedPump(tester);
  semantics.dispose();
  expect(find.byType(AlertDialog), findsOneWidget);
}

Future<void> _pumpSources(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _boundedPump(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Widget _controlledApp(
  CatalogSourceRepository repository, {
  AppDatabase? database,
  NavigatorObserver? observer,
}) => ProviderScope(
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
  child: MaterialApp(
    theme: ThemeData(useMaterial3: true),
    navigatorObservers: [?observer],
    home: const CatalogSourcesScreen(),
  ),
);

class _RealDeleteFixture {
  _RealDeleteFixture._(this.database, this.repository, this.container);

  final AppDatabase database;
  final _CountingRepository repository;
  final ProviderContainer container;

  static Future<_RealDeleteFixture> create() async {
    final database = AppDatabase(NativeDatabase.memory());
    final ids = ['delete-source', 'keep-source'].iterator;
    final driftRepository = DriftCatalogSourceRepository(
      database,
      idGenerator: () {
        ids.moveNext();
        return ids.current;
      },
    );
    await driftRepository.ensureBuiltInSources();
    await driftRepository.addCustomSource(
      name: 'Delete Test Library',
      baseUri: Uri.parse('https://delete.example/opds'),
    );
    await driftRepository.addCustomSource(
      name: 'Keep Test Library',
      baseUri: Uri.parse('https://keep.example/opds'),
    );
    await _seedLocalData(database);
    await database.appConnectivitySettingsDao.upsert(
      AppConnectivitySettingsEntriesCompanion.insert(
        id: const Value(1),
        mode: AppConnectivityMode.online.name,
        hasAcknowledgedOnline: true,
      ),
    );
    final repository = _CountingRepository(driftRepository);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        catalogSourceRepositoryProvider.overrideWithValue(repository),
      ],
    );
    return _RealDeleteFixture._(database, repository, container);
  }

  Widget app() => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: const CatalogSourcesScreen(),
    ),
  );

  Future<void> expectLocalDataPreserved() =>
      _expectLocalDataPreserved(database);

  Future<void> close() async {
    container.dispose();
    await database.close();
  }
}

class _CountingRepository implements CatalogSourceRepository {
  _CountingRepository(this.delegate);

  final DriftCatalogSourceRepository delegate;
  int deleteCalls = 0;

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
  Future<void> setEnabled({required String id, required bool enabled}) =>
      delegate.setEnabled(id: id, enabled: enabled);
  @override
  Future<void> deleteCustomSource(String id) {
    deleteCalls++;
    return delegate.deleteCustomSource(id);
  }

  @override
  Future<bool> normalizedUrlExists(Uri uri, {String? excludingSourceId}) =>
      delegate.normalizedUrlExists(uri, excludingSourceId: excludingSourceId);
}

class _ControlledDeleteRepository implements CatalogSourceRepository {
  _ControlledDeleteRepository(
    List<CatalogSource> sources, {
    this.pendingDelete,
    this.deleteError,
    this.emitAfterDelete = true,
    this.failWhenMissing = false,
  }) : _sources = List.of(sources);

  final _controller = StreamController<List<CatalogSource>>.broadcast();
  final Completer<void>? pendingDelete;
  final Object? deleteError;
  final bool emitAfterDelete;
  final bool failWhenMissing;
  List<CatalogSource> _sources;
  int deleteCalls = 0;

  @override
  Stream<List<CatalogSource>> watchAll() async* {
    yield List.unmodifiable(_sources);
    yield* _controller.stream;
  }

  void emitWithout(String id) {
    _sources = _sources.where((source) => source.id != id).toList();
    _controller.add(List.unmodifiable(_sources));
  }

  @override
  Future<void> deleteCustomSource(String id) async {
    deleteCalls++;
    if (pendingDelete != null) await pendingDelete!.future;
    if (deleteError case final error?) throw error;
    if (failWhenMissing && !_sources.any((source) => source.id == id)) {
      throw StateError('sourceNotFound');
    }
    if (emitAfterDelete) emitWithout(id);
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
  Future<void> setEnabled({required String id, required bool enabled}) =>
      throw UnimplementedError();
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

class _CountingNavigatorObserver extends NavigatorObserver {
  int popCalls = 0;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCalls++;
    super.didPop(route, previousRoute);
  }
}

Future<void> _seedLocalData(AppDatabase database) async {
  await database.booksDao.insertBook(
    BooksCompanion.insert(
      id: 'local-book',
      title: 'Preserved Local Book',
      author: const Value('Local Author'),
      filePath: '/books/preserved.epub',
      originalFilePath: const Value('/imports/preserved.epub'),
      fileName: 'preserved.epub',
      fileExtension: 'epub',
      mediaType: const Value('application/epub+zip'),
      fileSizeBytes: 2048,
      dateAdded: DateTime.utc(2026, 1, 2),
      isFavorite: const Value(true),
    ),
  );
  await database.readingProgressDao.upsertProgress(
    ReadingProgressEntriesCompanion.insert(
      bookId: 'local-book',
      locatorJson: const Value(
        '{"href":"chapter.xhtml","locations":{"progression":0.42}}',
      ),
      progression: const Value(0.42),
      currentChapterTitle: const Value('Chapter 4'),
      currentPage: const Value(42),
      totalPages: const Value(100),
      updatedAt: DateTime.utc(2026, 1, 3),
    ),
  );
  await database.bookmarksDao.insertBookmark(
    BookmarksCompanion.insert(
      id: 'local-bookmark',
      bookId: 'local-book',
      locatorJson: '{"href":"chapter.xhtml","locations":{"progression":0.42}}',
      href: const Value('chapter.xhtml'),
      progression: const Value(0.42),
      position: const Value(42),
      chapterTitle: const Value('Chapter 4'),
      title: const Value('Preserved bookmark'),
      note: const Value('Keep this note'),
      createdAt: DateTime.utc(2026, 1, 3),
      updatedAt: DateTime.utc(2026, 1, 3),
    ),
  );
  await database
      .into(database.readerAnnotations)
      .insert(
        ReaderAnnotationsCompanion.insert(
          id: 'local-annotation',
          bookId: 'local-book',
          locatorJson:
              '{"href":"chapter.xhtml","locations":{"progression":0.42}}',
          locationKey: 'chapter.xhtml|0.42',
          selectedText: 'Preserved annotation',
          note: const Value('Annotation note'),
          style: const Value('underline'),
          color: const Value('blue'),
          href: 'chapter.xhtml',
          progression: const Value(0.42),
          totalProgression: const Value(0.52),
          createdAt: DateTime.utc(2026, 1, 3),
          updatedAt: DateTime.utc(2026, 1, 3),
        ),
      );
}

Future<void> _expectLocalDataPreserved(AppDatabase database) async {
  final book = await database.booksDao.getBookById('local-book');
  expect(book, isNotNull);
  expect(book!.title, 'Preserved Local Book');
  expect(book.author, 'Local Author');
  expect(book.filePath, '/books/preserved.epub');
  expect(book.originalFilePath, '/imports/preserved.epub');
  expect(book.isFavorite, isTrue);

  final progress = await database.readingProgressDao.getProgressForBook(
    'local-book',
  );
  expect(progress, isNotNull);
  expect(
    progress!.locatorJson,
    '{"href":"chapter.xhtml","locations":{"progression":0.42}}',
  );
  expect(progress.progression, 0.42);
  expect(progress.currentChapterTitle, 'Chapter 4');
  expect(progress.currentPage, 42);
  expect(progress.totalPages, 100);

  final bookmark = await database.bookmarksDao.findById('local-bookmark');
  expect(bookmark, isNotNull);
  expect(bookmark!.bookId, 'local-book');
  expect(bookmark.locatorJson, progress.locatorJson);
  expect(bookmark.position, 42);
  expect(bookmark.title, 'Preserved bookmark');
  expect(bookmark.note, 'Keep this note');

  final annotation = await (database.select(
    database.readerAnnotations,
  )..where((row) => row.id.equals('local-annotation'))).getSingleOrNull();
  expect(annotation, isNotNull);
  expect(annotation!.bookId, 'local-book');
  expect(annotation.locatorJson, progress.locatorJson);
  expect(annotation.locationKey, 'chapter.xhtml|0.42');
  expect(annotation.selectedText, 'Preserved annotation');
  expect(annotation.note, 'Annotation note');
  expect(annotation.style, 'underline');
  expect(annotation.color, 'blue');
}

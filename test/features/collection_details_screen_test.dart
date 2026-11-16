import 'package:bibliolife/shared/presentation/widgets/app_context_menu.dart';
import '../support/unified_book_list_assertions.dart';
import 'dart:async';
import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:bibliolife/features/library/application/providers/library_repository_provider.dart';
import 'package:bibliolife/features/library/data/repositories/drift_book_display_settings_repository.dart';
import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_book_tile.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_list.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_view_toggle.dart';
import 'package:bibliolife/features/settings/presentation/widgets/settings_body.dart';
import 'package:bibliolife/features/collections/presentation/widgets/collection_overview_cover.dart';
import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/core/database/database_provider.dart';
import 'package:drift/native.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/app/theme/app_theme.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_description_panel.dart';
import 'package:bibliolife/features/collections/application/providers/collection_providers.dart';
import 'package:bibliolife/features/collections/application/providers/collection_repository_provider.dart';
import 'package:bibliolife/features/collections/domain/models/library_collection.dart';
import 'package:bibliolife/features/collections/domain/repositories/collection_repository.dart';
import 'package:bibliolife/features/collections/presentation/screens/collection_details_screen.dart';
import 'package:bibliolife/features/collections/presentation/widgets/collection_book_cover.dart';
import 'package:bibliolife/features/collections/presentation/widgets/collection_cover.dart';
import 'package:bibliolife/features/metadata/application/providers/cover_storage_service_provider.dart';
import 'package:bibliolife/features/metadata/data/services/cover_storage_service.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_providers.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_book_card.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('default Grid is adaptive, lazy, and keeps collection padding', (
    tester,
  ) async {
    final h = await _layoutHarness(tester);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final entry in [(400.0, 2), (700.0, 3), (1000.0, 4)]) {
      tester.view.physicalSize = Size(entry.$1, 900);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      await _showLayoutBooks(tester);
      final grid = tester.widget<SliverGrid>(
        find.byKey(const Key('collection-details-book-grid')),
      );
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        entry.$2,
      );
      expect(find.byType(LibraryBookCard).evaluate().length, lessThan(30));
      expect(find.byType(LibraryBookTile), findsNothing);
      final first = find.byKey(
        const ValueKey('collection-details-book-book-0'),
      );
      expect(tester.getTopLeft(first).dx, 20);
      expect(find.byType(NestedScrollView), findsNothing);
    }
    expect(h.collection.watchCalls, {'collection-1': 1});
  });

  testWidgets('saved List loads through the existing persisted preference', (
    tester,
  ) async {
    final h = await _layoutHarness(tester, saved: LibraryViewMode.list);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    await _showLayoutBooks(tester);
    expect(
      find.byKey(const Key('collection-details-book-list')),
      findsOneWidget,
    );
    expect(find.byType(LibraryBookTile), findsWidgets);
    expect(find.byType(LibraryBookCard), findsNothing);
    expect(await tester.runAsync(h.storage.load), 'list');
    expect(h.container.read(libraryViewModeProvider), LibraryViewMode.list);
    expectUnifiedBookList(tester);
  });

  testWidgets(
    'Settings and Library toggle update only collection presentation',
    (tester) async {
      final h = await _layoutHarness(tester);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      final header = tester.element(find.byType(CollectionOverviewCover));
      h.router.push('/layout-settings');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('book-display-option-list')));
      await tester.pumpAndSettle();
      h.router.pop();
      await tester.pumpAndSettle();
      await _showLayoutBooks(tester);
      expect(find.byType(LibraryBookTile), findsWidgets);
      expect(find.byTooltip('Show grid view'), findsOneWidget);
      await tester.tap(find.byTooltip('Show grid view'));
      await tester.pumpAndSettle();
      await _showLayoutBooks(tester);
      expect(find.byType(LibraryBookCard), findsWidgets);
      expect(h.container.read(libraryViewModeProvider), LibraryViewMode.grid);
      // UI callbacks persist asynchronously; drain the real SQLite task and
      // its queued fake-zone microtasks before checking the durable value.
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(await tester.runAsync(h.storage.load), 'grid');
      expect(
        tester.element(find.byType(CollectionOverviewCover)),
        same(header),
      );
      expect(h.collection.watchCalls, {'collection-1': 1});
      expect(h.collection.getCalls, 1);
      expect(h.collection.membershipMutations, 0);
    },
  );

  for (final mode in LibraryViewMode.values) {
    testWidgets('favorite and authoritative book navigation in $mode', (
      tester,
    ) async {
      final h = await _layoutHarness(tester, saved: mode);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      await _showLayoutBooks(tester);
      final first = find.byKey(
        const ValueKey('collection-details-book-book-0'),
      );
      final favorite = find.descendant(
        of: first,
        matching: find.byType(IconButton),
      );
      await tester.tap(favorite);
      await tester.pumpAndSettle();
      if (mode == LibraryViewMode.list) {
        await tester.tap(find.textContaining('to favorites'));
        await tester.pumpAndSettle();
      }
      expect(h.library.favoriteRequests, [('book-0', true)]);
      expect(h.collection.membershipMutations, 0);
      expect(h.collection.books['collection-1']!.first.isFavorite, isTrue);
      if (mode == LibraryViewMode.list) {
        expect(tester.widget<LibraryBookTile>(first).allowDeleteBook, isTrue);
        final menu = find.descendant(
          of: first,
          matching: find.byType(AppContextMenuButton<String>),
        );
        expect(menu, findsOneWidget);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(find.text('Delete'), findsOneWidget);
        expect(find.text('Remove from favorites'), findsOneWidget);
        await tester.tap(find.text('Remove from favorites'));
        await tester.pumpAndSettle();
        expect(h.library.favoriteRequests, [
          ('book-0', true),
          ('book-0', false),
        ]);
        expect(h.collection.books['collection-1']!.first.isFavorite, isFalse);
        await tester.pumpAndSettle();
      } else {
        expect(
          find.descendant(
            of: first,
            matching: find.byType(AppContextMenuButton<String>),
          ),
          findsNothing,
        );
      }
      final before = _layoutPosition(tester).pixels;
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(find.text('Book details route:book-0'), findsOneWidget);
      h.router.pop();
      await tester.pumpAndSettle();
      expect(_layoutPosition(tester).pixels, closeTo(before, 1));
      expect(h.collection.watchCalls, {'collection-1': 1});
    });

    testWidgets(
      'empty collection and Add books route stay available in $mode',
      (tester) async {
        final h = await _layoutHarness(tester, saved: mode, count: 0);
        await tester.pumpWidget(h.app());
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('collection-details-add-books')),
          200,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('collection-details-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.text('No books in this collection.'), findsOneWidget);
        await tester.tap(find.byKey(const Key('collection-details-add-books')));
        await tester.pumpAndSettle();
        expect(find.text('Edit route:collection-1'), findsOneWidget);
        expect(h.collection.membershipMutations, 0);
      },
    );
  }

  testWidgets('Grid and List independently restore stable pixel positions', (
    tester,
  ) async {
    final h = await _layoutHarness(tester);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const Key('collection-details-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    _layoutPosition(tester).jumpTo(1600);
    await tester.pumpAndSettle();
    await h.setMode(tester, LibraryViewMode.list);
    expect(_layoutPosition(tester).pixels, closeTo(1600, 1));
    _layoutPosition(tester).jumpTo(900);
    await tester.pumpAndSettle();
    await h.setMode(tester, LibraryViewMode.grid);
    expect(_layoutPosition(tester).pixels, closeTo(1600, 1));
    await h.setMode(tester, LibraryViewMode.list);
    expect(_layoutPosition(tester).pixels, closeTo(900, 1));
    expect(
      tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const Key('collection-details-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      ),
      same(scrollable),
    );
    expect(h.collection.watchCalls, {'collection-1': 1});
  });

  testWidgets('different collection IDs do not share offsets', (tester) async {
    final h = await _layoutHarness(tester);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    _layoutPosition(tester).jumpTo(1800);
    await tester.pumpAndSettle();
    h.router.push('/collections/collection-2');
    await tester.pumpAndSettle();
    expect(_layoutPosition(tester).pixels, closeTo(0, 1));
    _layoutPosition(tester).jumpTo(700);
    await tester.pumpAndSettle();
    h.router.pop();
    await tester.pumpAndSettle();
    expect(_layoutPosition(tester).pixels, closeTo(1800, 1));
  });

  testWidgets('shortened books safely clamp a saved mode offset', (
    tester,
  ) async {
    final h = await _layoutHarness(tester);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    _layoutPosition(tester).jumpTo(3000);
    await tester.pumpAndSettle();
    await h.setMode(tester, LibraryViewMode.list);
    _layoutPosition(tester).jumpTo(4000);
    await tester.pumpAndSettle();
    h.collection.update('collection-1', [_book('book-0')]);
    await tester.pumpAndSettle();
    await h.setMode(tester, LibraryViewMode.grid);
    final position = _layoutPosition(tester);
    expect(
      position.pixels,
      inInclusiveRange(position.minScrollExtent, position.maxScrollExtent),
    );
    expect(tester.takeException(), isNull);
    expect(h.collection.watchCalls, {'collection-1': 1});
  });

  testWidgets('LibraryList default keeps its existing global Delete menu', (
    tester,
  ) async {
    final h = await _layoutHarness(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                LibraryList(books: [_book('book-0')]),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final tile = tester.widget<LibraryBookTile>(find.byType(LibraryBookTile));
    expect(tile.allowDeleteBook, isTrue);
    await tester.tap(find.byType(AppContextMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    expect(h.collection.membershipMutations, 0);
  });

  for (final dark in [false, true]) {
    for (final mode in LibraryViewMode.values) {
      testWidgets('320px large text has safe $mode presentation, dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = await _layoutHarness(tester, saved: mode, count: 12);
        await tester.pumpWidget(h.app(dark: dark, textScale: 2));
        await tester.pumpAndSettle();
        await _showLayoutBooks(tester);
        expect(
          mode == LibraryViewMode.grid
              ? find.byType(LibraryBookCard)
              : find.byType(LibraryBookTile),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('renders collection identity, description and book grid', (
    tester,
  ) async {
    final collection = _collection(description: 'A short description.');
    final books = [_book('book-a'), _book('book-b'), _book('book-c')];
    await tester.pumpWidget(_app(collection: collection, books: books));
    await tester.pumpAndSettle();

    expect(find.text('Reading'), findsOneWidget);
    expect(find.text('Created 01.08.2026'), findsOneWidget);
    expect(find.text('A short description.'), findsOneWidget);
    expect(find.byType(BookDescriptionPanel), findsOneWidget);
    await _scrollToBooks(tester);
    expect(find.text('Books · 3'), findsOneWidget);
    expect(
      find.byKey(const Key('collection-details-book-grid')),
      findsOneWidget,
    );
    expect(find.byType(LibraryBookCard), findsWidgets);
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('omits the description section when description is empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        collection: _collection(description: '   '),
        books: const [],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BookDescriptionPanel), findsNothing);
    expect(find.byKey(const Key('book-description-text')), findsNothing);
    expect(find.byKey(const Key('description-toggle')), findsNothing);
    await _scrollToBooks(tester);
    expect(find.text('Books · 0'), findsOneWidget);
    expect(find.text('No books in this collection.'), findsOneWidget);
    expect(
      find.byKey(const Key('collection-details-add-books')),
      findsOneWidget,
    );
  });

  testWidgets('long description exposes More and Less controls', (
    tester,
  ) async {
    final longDescription = List.filled(
      80,
      'This collection description contains enough words to exceed the collapsed text limit.',
    ).join(' ');
    await tester.pumpWidget(
      _app(
        collection: _collection(description: longDescription),
        books: const [],
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('collection-details-scroll')),
      const Offset(0, -500),
    );
    await tester.pump();
    expect(find.byType(BookDescriptionPanel), findsOneWidget);
    final more = find.text('More');
    await tester.ensureVisible(more);
    await tester.pump();
    expect(more, findsOneWidget);
    await tester.tap(more);
    await tester.pumpAndSettle();
    final less = find.text('Less');
    expect(less, findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('book-description-text')))
          .maxLines,
      isNull,
    );
  });

  testWidgets('shared collection menu retains cancel and confirmed deletion', (
    tester,
  ) async {
    final repository = _FakeCollectionRepository();
    await tester.pumpWidget(
      _app(
        collection: _collection(),
        books: const [],
        repository: repository,
        openFromHome: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open collection'));
    await tester.pumpAndSettle();
    for (final confirm in [false, true]) {
      await tester.tap(find.byKey(const Key('collection-details-overflow')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete collection'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Books will remain in your library.'), findsOneWidget);
      expect(repository.deletedIds, isEmpty);
      await tester.tap(find.text(confirm ? 'Delete' : 'Cancel'));
      await tester.pumpAndSettle();
      expect(repository.deletedIds, confirm ? ['collection-1'] : isEmpty);
    }
    expect(find.text('Open collection'), findsOneWidget);
  });

  testWidgets('overflow menu exposes edit and delete actions', (tester) async {
    await tester.pumpWidget(_app(collection: _collection(), books: const []));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('collection-details-overflow')));
    await tester.pumpAndSettle();

    expect(find.text('Edit collection'), findsOneWidget);
    expect(find.text('Delete collection'), findsOneWidget);
    await tester.tap(find.text('Edit collection'));
    await tester.pumpAndSettle();
    expect(find.text('Edit route'), findsOneWidget);
  });

  testWidgets('valid custom cover is preferred over fallback preview', (
    tester,
  ) async {
    final directory = Directory(
      'build/collection-details-test-${DateTime.now().microsecondsSinceEpoch}',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final storage = CoverStorageService(
      documentsDirectory: () async => directory,
      imageValidator: const _AlwaysValidImageValidator(),
    );
    late final String? customPath;
    await tester.runAsync(() async {
      customPath = await storage.storeValidatedCollectionCover(
        collectionKey: 'cover',
        bytes: Uint8List.fromList([1, 2, 3]),
        extension: 'png',
      );
    });
    final collection = _collection(customCoverPath: customPath);
    await tester.pumpWidget(
      _app(
        collection: collection,
        books: [_book('book-a')],
        coverStorage: storage,
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(
      find.byKey(const Key('collection-details-custom-cover')),
      findsOneWidget,
    );
    final coverSize = tester.getSize(
      find.byKey(const Key('collection-details-cover')),
    );
    expect(find.byKey(const Key('collection-details-cover')), findsOneWidget);
    expect(
      tester.widget(find.byKey(const Key('collection-details-cover'))),
      isA<CollectionCover>(),
    );
    expect(coverSize.width / coverSize.height, 16 / 9);
    final image = tester.widget<Image>(
      find.byKey(const Key('collection-details-custom-cover')),
    );
    expect(image.fit, BoxFit.cover);
  });

  testWidgets('details cover keeps 16:9 at common phone widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final width in [390.0, 412.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(_app(collection: _collection(), books: const []));
      await tester.pumpAndSettle();
      final size = tester.getSize(
        find.byKey(const Key('collection-details-cover')),
      );
      expect(size.width / size.height, 16 / 9);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('missing custom cover falls back without breaking the page', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        collection: _collection(customCoverPath: 'build/missing-cover.png'),
        books: [_book('book-a')],
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(
      find.byKey(const Key('collection-details-custom-cover')),
      findsNothing,
    );
    expect(find.byType(CollectionBookCover), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('book tap opens the existing Book Details route', (tester) async {
    await tester.pumpWidget(
      _app(collection: _collection(), books: [_book('book-a')]),
    );
    await tester.pumpAndSettle();
    await _scrollToBooks(tester);
    await tester.tap(
      find.byKey(const ValueKey('collection-details-book-book-a')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Book details route'), findsOneWidget);
  });
}

Future<void> _scrollToBooks(WidgetTester tester) async {
  await tester.drag(
    find.byKey(const Key('collection-details-scroll')),
    const Offset(0, -700),
  );
  await tester.pumpAndSettle();
}

Widget _app({
  required LibraryCollection collection,
  required List<LibraryBook> books,
  CoverStorageService? coverStorage,
  _FakeCollectionRepository? repository,
  bool openFromHome = false,
}) {
  final fake = repository ?? _FakeCollectionRepository();
  final router = GoRouter(
    initialLocation: openFromHome
        ? '/menu-test-home'
        : '/collections/${collection.id}',
    routes: [
      GoRoute(
        path: '/menu-test-home',
        builder: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () => context.pushNamed(
              AppRoutes.collectionDetailsName,
              pathParameters: {'collectionId': collection.id},
            ),
            child: const Text('Open collection'),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.collectionDetailsPath,
        name: AppRoutes.collectionDetailsName,
        builder: (context, state) => CollectionDetailsScreen(
          collectionId: state.pathParameters['collectionId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.editCollectionPath,
        name: AppRoutes.editCollectionName,
        builder: (context, state) => const Scaffold(body: Text('Edit route')),
      ),
      GoRoute(
        path: AppRoutes.bookDetailsPath,
        name: AppRoutes.bookDetailsName,
        builder: (context, state) =>
            const Scaffold(body: Text('Book details route')),
      ),
    ],
  );
  final overrides = [
    appDatabaseProvider.overrideWith((ref) {
      final database = AppDatabase(NativeDatabase.memory());
      ref.onDispose(database.close);
      return database;
    }),
    collectionRepositoryProvider.overrideWithValue(fake),
    collectionByIdProvider(
      collection.id,
    ).overrideWithValue(AsyncData<LibraryCollection?>(collection)),
    booksInCollectionProvider(
      collection.id,
    ).overrideWithValue(AsyncData<List<LibraryBook>>(books)),
    readingProgressProvider.overrideWith((ref, _) => Stream.value(null)),
    if (coverStorage != null)
      coverStorageServiceProvider.overrideWithValue(coverStorage),
  ];
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: buildAppTheme(fallbackLightColorScheme),
      routerConfig: router,
    ),
  );
}

LibraryCollection _collection({String? description, String? customCoverPath}) =>
    LibraryCollection(
      id: 'collection-1',
      name: 'Reading',
      normalizedName: 'reading',
      description: description,
      customCoverPath: customCoverPath,
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 1),
      sortOrder: null,
    );

LibraryBook _book(String id, {bool isFavorite = false}) => LibraryBook(
  id: id,
  title: 'Book ${id.substring(id.length - 1).toUpperCase()}',
  sortTitle: id,
  author: 'Author',
  description: null,
  filePath: '/books/$id.epub',
  fileName: '$id.epub',
  fileExtension: 'epub',
  format: BookFormat.epub,
  mediaType: null,
  coverPath: null,
  language: null,
  publisher: null,
  publishedDate: null,
  isbn: null,
  pageCount: null,
  fileSizeBytes: 1,
  dateAdded: DateTime(2026),
  lastOpenedAt: null,
  isFavorite: isFavorite,
);

class _FakeCollectionRepository implements CollectionRepository {
  final deletedIds = <String>[];
  @override
  Future<void> delete(String collectionId) async {
    deletedIds.add(collectionId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AlwaysValidImageValidator implements CoverImageValidator {
  const _AlwaysValidImageValidator();

  @override
  Future<bool> isDecodable(Uint8List bytes) async => bytes.isNotEmpty;
}

ScrollPosition _layoutPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const Key('collection-details-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

Future<void> _showLayoutBooks(WidgetTester tester) async {
  final heading = find.byKey(const Key('collection-details-books-header'));
  _layoutPosition(tester).jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    heading,
    200,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('collection-details-scroll')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  final position = _layoutPosition(tester);
  position.jumpTo(
    (position.pixels + tester.getTopLeft(heading).dy - 180)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble(),
  );
  await tester.pumpAndSettle();
}

Future<_LayoutHarness> _layoutHarness(
  WidgetTester tester, {
  LibraryViewMode saved = LibraryViewMode.grid,
  int count = 120,
}) async {
  final database = AppDatabase(NativeDatabase.memory());
  final storage = DriftBookDisplaySettingsRepository(database);
  await tester.runAsync(() async {
    if (saved != LibraryViewMode.grid) await storage.save(saved.name);
  });
  final collection = _LayoutCollectionRepository(
    List.generate(count, (i) => _book('book-$i')),
  );
  final library = _LayoutLibraryRepository(collection);
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      collectionRepositoryProvider.overrideWithValue(collection),
      libraryRepositoryProvider.overrideWithValue(library),
      readingProgressProvider.overrideWith((ref, _) => Stream.value(null)),
    ],
  );
  await tester.runAsync(() async {
    container.read(libraryViewModeProvider);
    await container.read(libraryViewModeProvider.notifier).ready;
  });
  final router = GoRouter(
    initialLocation: '/collections/collection-1',
    routes: [
      GoRoute(
        path: AppRoutes.collectionDetailsPath,
        name: AppRoutes.collectionDetailsName,
        builder: (_, state) => Column(
          children: [
            Material(
              child: Consumer(
                builder: (context, ref, _) => LibraryViewToggle(
                  viewMode: ref.watch(libraryViewModeProvider),
                  onPressed: () =>
                      ref.read(libraryViewModeProvider.notifier).toggle(),
                ),
              ),
            ),
            Expanded(
              child: CollectionDetailsScreen(
                collectionId: state.pathParameters['collectionId']!,
              ),
            ),
          ],
        ),
      ),
      GoRoute(
        path: AppRoutes.bookDetailsPath,
        name: AppRoutes.bookDetailsName,
        builder: (_, state) => Scaffold(
          body: Text('Book details route:${state.pathParameters['bookId']}'),
        ),
      ),
      GoRoute(
        path: AppRoutes.editCollectionPath,
        name: AppRoutes.editCollectionName,
        builder: (_, state) => Scaffold(
          body: Text('Edit route:${state.pathParameters['collectionId']}'),
        ),
      ),
      GoRoute(
        path: '/layout-settings',
        builder: (_, _) => const Scaffold(body: BookDisplayLayoutSettingTile()),
      ),
    ],
  );
  final result = _LayoutHarness(
    database,
    storage,
    container,
    collection,
    library,
    router,
  );
  addTearDown(() async {
    router.dispose();
    container.dispose();
    await tester.runAsync(() async {
      await database.close();
      unawaited(collection.changes.close());
    });
  });
  return result;
}

class _LayoutHarness {
  _LayoutHarness(
    this.database,
    this.storage,
    this.container,
    this.collection,
    this.library,
    this.router,
  );
  final AppDatabase database;
  final DriftBookDisplaySettingsRepository storage;
  final ProviderContainer container;
  final _LayoutCollectionRepository collection;
  final _LayoutLibraryRepository library;
  final GoRouter router;

  Future<void> setMode(WidgetTester tester, LibraryViewMode mode) async {
    await tester.runAsync(
      () => container.read(libraryViewModeProvider.notifier).setMode(mode),
    );
    await tester.pumpAndSettle();
  }

  Widget app({bool dark = false, double textScale = 1}) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: dark ? darkTheme : lightTheme,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      );
}

class _LayoutCollectionRepository extends _FakeCollectionRepository {
  _LayoutCollectionRepository(List<LibraryBook> items)
    : books = {'collection-1': items, 'collection-2': items};
  final Map<String, List<LibraryBook>> books;
  final changes = StreamController<(String, List<LibraryBook>)>.broadcast();
  final watchCalls = <String, int>{};
  int getCalls = 0;
  int membershipMutations = 0;
  @override
  Future<LibraryCollection?> getById(String id) async {
    getCalls++;
    return _collection().copyWith(id: id);
  }

  @override
  Stream<List<LibraryBook>> watchBooks(String id) async* {
    watchCalls.update(id, (n) => n + 1, ifAbsent: () => 1);
    yield books[id]!;
    yield* changes.stream
        .where((entry) => entry.$1 == id)
        .map((entry) => entry.$2);
  }

  void update(String id, List<LibraryBook> items) {
    books[id] = items;
    changes.add((id, items));
  }

  @override
  Future<void> addBook(String collectionId, String bookId) async {
    membershipMutations++;
  }

  @override
  Future<void> removeBook(String collectionId, String bookId) async {
    membershipMutations++;
  }
}

class _LayoutLibraryRepository implements LibraryRepository {
  _LayoutLibraryRepository(this.collection);
  final _LayoutCollectionRepository collection;
  final favoriteRequests = <(String, bool)>[];
  @override
  Future<void> setFavorite(String id, bool value) async {
    favoriteRequests.add((id, value));
    for (final entry in collection.books.entries.toList()) {
      collection.update(entry.key, [
        for (final book in entry.value)
          book.id == id ? _book(book.id, isFavorite: value) : book,
      ]);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

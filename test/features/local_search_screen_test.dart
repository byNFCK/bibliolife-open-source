import 'package:bibliolife/shared/presentation/widgets/app_context_menu.dart';
import '../support/unified_book_list_assertions.dart';
import 'dart:async';

import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/app/theme/app_theme.dart';
import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/import/application/services/managed_book_deletion_service.dart';
import 'package:bibliolife/features/library/application/providers/library_providers.dart';
import 'package:bibliolife/features/library/application/providers/library_repository_provider.dart';
import 'package:bibliolife/features/library/application/providers/library_use_case_providers.dart';
import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:bibliolife/features/library/application/use_cases/delete_book.dart';
import 'package:bibliolife/features/library/data/repositories/drift_book_display_settings_repository.dart';
import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_book_card.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_book_tile.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_view_toggle.dart';
import 'package:bibliolife/features/metadata/data/services/cover_storage_service.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_providers.dart';
import 'package:bibliolife/features/search/presentation/screens/search_screen.dart';
import 'package:bibliolife/features/settings/presentation/widgets/settings_body.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('default Grid reuses adaptive Library cards and builds lazily', (
    tester,
  ) async {
    final h = await _harness(tester, books: _manyBooks());
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final entry in [(400.0, 2), (700.0, 3), (1000.0, 4)]) {
      tester.view.physicalSize = Size(entry.$1, 900);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        entry.$2,
      );
      expect(find.byType(LibraryBookCard).evaluate().length, lessThan(30));
      expect(find.byType(LibraryBookTile), findsNothing);
      expect(find.byType(LibraryViewToggle), findsNothing);
      expect(find.byType(NestedScrollView), findsNothing);
      expect(find.byKey(const ValueKey('search-0')), findsOneWidget);
    }
    expect(h.repository.watchCalls, 1);
    expect(h.repository.mutations, isEmpty);
  });

  testWidgets('persisted List is respected when navigating to Search', (
    tester,
  ) async {
    final h = await _harness(tester, saved: LibraryViewMode.list);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    expect(find.byType(LibraryBookTile), findsNWidgets(3));
    expect(find.byType(LibraryBookCard), findsNothing);
    expect(
      tester
          .widget<LibraryBookTile>(find.byType(LibraryBookTile).first)
          .allowDeleteBook,
      isTrue,
    );
    expect(find.byType(Divider), findsNothing);
    expectUnifiedBookList(tester);
    expect(await tester.runAsync(h.storage.load), 'list');
  });

  testWidgets(
    'reactive modes keep query, SearchBar identity, and active focus',
    (tester) async {
      final h = await _harness(tester);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  OrChId  ');
      await tester.pumpAndSettle();
      final bar = tester.element(find.byType(SearchBar));
      final focus = tester.widget<SearchBar>(find.byType(SearchBar)).focusNode!;
      final controller = tester
          .widget<SearchBar>(find.byType(SearchBar))
          .controller!;
      expect(focus.hasFocus, isTrue);
      for (final mode in [LibraryViewMode.list, LibraryViewMode.grid]) {
        await h.setMode(tester, mode);
        expect(_visibleIds(tester, mode), ['title', 'author']);
        expect(controller.text, '  OrChId  ');
        expect(tester.element(find.byType(SearchBar)), same(bar));
        expect(
          tester.widget<SearchBar>(find.byType(SearchBar)).focusNode,
          same(focus),
        );
        expect(focus.hasFocus, isTrue);
      }
      expect(h.repository.watchCalls, 1);
      expect(h.repository.mutations, isEmpty);
      expect(find.byType(SearchScreen), findsOneWidget);
    },
  );

  testWidgets(
    'unfocused Search stays unfocused and keyboard stays closed on mode change',
    (tester) async {
      final h = await _harness(tester);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      final focus = tester.widget<SearchBar>(find.byType(SearchBar)).focusNode!;
      focus.unfocus();
      await tester.pumpAndSettle();
      tester.testTextInput.hide();
      await h.setMode(tester, LibraryViewMode.list);
      await h.setMode(tester, LibraryViewMode.grid);
      expect(focus.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
    },
  );

  for (final route in ['/layout-settings', '/library-toggle']) {
    testWidgets(
      'existing global control $route updates Search without losing text',
      (tester) async {
        final h = await _harness(tester);
        await tester.pumpWidget(h.app());
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'orchid');
        await tester.pumpAndSettle();
        h.router.push(route);
        await tester.pumpAndSettle();
        if (route == '/layout-settings') {
          await tester.tap(find.byKey(const Key('book-display-option-list')));
        } else {
          await tester.tap(find.byTooltip('Show list view'));
        }
        await tester.pumpAndSettle();
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        h.router.pop();
        await tester.pumpAndSettle();
        expect(_visibleIds(tester, LibraryViewMode.list), ['title', 'author']);
        expect(
          tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
          'orchid',
        );
        expect(h.repository.watchCalls, 1);
        expect(h.repository.mutations, isEmpty);
      },
    );
  }

  for (final mode in LibraryViewMode.values) {
    testWidgets(
      'title/author matching, ordering, and Clear remain correct in $mode',
      (tester) async {
        final h = await _harness(tester, saved: mode);
        await tester.pumpWidget(h.app());
        await tester.pumpAndSettle();
        expect(_visibleIds(tester, mode), ['title', 'author', 'other']);
        await tester.enterText(find.byType(TextField), '  ORCHID ');
        await tester.pumpAndSettle();
        expect(_visibleIds(tester, mode), ['title', 'author']);
        await tester.enterText(find.byType(TextField), 'bloom');
        await tester.pumpAndSettle();
        expect(_visibleIds(tester, mode), ['author']);
        await tester.enterText(find.byType(TextField), 'not-a-match');
        await tester.pumpAndSettle();
        expect(find.text('No matching books'), findsOneWidget);
        await tester.tap(find.byTooltip('Clear search'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
          isEmpty,
        );
        expect(find.byTooltip('Clear search'), findsNothing);
        expect(_visibleIds(tester, mode), ['title', 'author', 'other']);
        expect(h.repository.watchCalls, 1);
        expect(h.repository.mutations, isEmpty);
      },
    );

    testWidgets(
      'empty library retains the current no-matching state in $mode',
      (tester) async {
        final h = await _harness(tester, saved: mode, books: []);
        await tester.pumpWidget(h.app());
        await tester.pumpAndSettle();
        expect(find.text('No matching books'), findsOneWidget);
        expect(find.byType(SearchBar), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'orchid');
        await tester.pumpAndSettle();
        expect(find.text('No matching books'), findsOneWidget);
      },
    );

    testWidgets(
      'favorite uses the existing mutation and does not navigate in $mode',
      (tester) async {
        final h = await _harness(tester, saved: mode);
        await tester.pumpWidget(h.app());
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'bloom');
        await tester.pumpAndSettle();
        final book = find.byKey(const ValueKey('search-author'));
        await tester.tap(
          find.descendant(of: book, matching: find.byType(IconButton)).first,
        );
        await tester.pumpAndSettle();
        if (mode == LibraryViewMode.list) {
          await tester.tap(find.text('Add to favorites'));
          await tester.pumpAndSettle();
        }
        expect(h.repository.mutations, ['favorite:author:true']);
        expect(
          h.repository.items.firstWhere((b) => b.id == 'author').isFavorite,
          isTrue,
        );
        expect(find.byType(SearchScreen), findsOneWidget);
        expect(
          tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
          'bloom',
        );
      },
    );

    testWidgets('correct book Details and back preserve query and $mode', (
      tester,
    ) async {
      final h = await _harness(tester, saved: mode);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'bloom');
      await tester.pumpAndSettle();
      final before = _position(tester).pixels;
      await tester.tap(find.byKey(const ValueKey('search-author')));
      await tester.pumpAndSettle();
      expect(find.text('Details:author'), findsOneWidget);
      h.router.pop();
      await tester.pumpAndSettle();
      expect(
        tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
        'bloom',
      );
      expect(h.container.read(libraryViewModeProvider), mode);
      expect(_visibleIds(tester, mode), ['author']);
      expect(_position(tester).pixels, closeTo(before, 1));
      expect(h.repository.watchCalls, 1);
    });
  }

  testWidgets(
    'List Delete keeps confirmation, cancellation, and real removal flow',
    (tester) async {
      final h = await _harness(tester, saved: LibraryViewMode.list);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'bloom');
      await tester.pumpAndSettle();
      Future<void> openDelete() async {
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('search-author')),
            matching: find.byType(AppContextMenuButton<String>),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        expect(find.text('Delete book?'), findsOneWidget);
      }

      await openDelete();
      expect(h.repository.mutations, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.repository.items.any((b) => b.id == 'author'), isTrue);
      await openDelete();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(h.repository.mutations, ['delete:author']);
      expect(find.text('No matching books'), findsOneWidget);
      expect(find.text('Book deleted.'), findsOneWidget);
      expect(
        tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
        'bloom',
      );
    },
  );

  testWidgets(
    'mode-aware scroll restores independently without rebuilding SearchBar',
    (tester) async {
      final h = await _harness(tester, books: _manyBooks());
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      final bar = tester.element(find.byType(SearchBar));
      _position(tester).jumpTo(1800);
      await tester.pumpAndSettle();
      final gridKey = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .key;
      await h.setMode(tester, LibraryViewMode.list);
      expect(_position(tester).pixels, 0);
      _position(tester).jumpTo(700);
      await tester.pumpAndSettle();
      expect(find.byType(LibraryBookTile).evaluate().length, lessThan(30));
      final listKey = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .key;
      expect(listKey, isNot(gridKey));
      await h.setMode(tester, LibraryViewMode.grid);
      expect(_position(tester).pixels, closeTo(1800, 1));
      await h.setMode(tester, LibraryViewMode.list);
      expect(_position(tester).pixels, closeTo(700, 1));
      expect(tester.element(find.byType(SearchBar)), same(bar));
      expect(h.repository.watchCalls, 1);
    },
  );

  testWidgets('new and repeated queries reset old offsets in both layouts', (
    tester,
  ) async {
    final h = await _harness(tester, books: _manyBooks());
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Book');
    await tester.pumpAndSettle();
    _position(tester).jumpTo(1800);
    await tester.pumpAndSettle();
    await h.setMode(tester, LibraryViewMode.list);
    _position(tester).jumpTo(700);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Book 0000');
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, 0);
    expect(_visibleIds(tester, LibraryViewMode.list), ['0']);
    await h.setMode(tester, LibraryViewMode.grid);
    expect(_position(tester).pixels, 0);
    await tester.enterText(find.byType(TextField), 'Book');
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, 0);
    await h.setMode(tester, LibraryViewMode.list);
    expect(_position(tester).pixels, 0);
  });

  testWidgets(
    'stored offsets clamp safely when the same result dataset shrinks',
    (tester) async {
      final h = await _harness(tester, books: _manyBooks());
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      _position(tester).jumpTo(3000);
      await tester.pumpAndSettle();
      await h.setMode(tester, LibraryViewMode.list);
      _position(tester).jumpTo(2000);
      await tester.pumpAndSettle();
      h.repository.replace([h.repository.items.first]);
      await tester.pumpAndSettle();
      await h.setMode(tester, LibraryViewMode.grid);
      final position = _position(tester);
      expect(
        position.pixels,
        inInclusiveRange(position.minScrollExtent, position.maxScrollExtent),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('scrolled Search returns from Details at its prior offset', (
    tester,
  ) async {
    final h = await _harness(tester, books: _manyBooks());
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    _position(tester).jumpTo(1600);
    await tester.pumpAndSettle();
    final card = find.byType(LibraryBookCard).hitTestable().first;
    final id = tester.widget<LibraryBookCard>(card).book.id;
    final before = _position(tester).pixels;
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.text('Details:$id'), findsOneWidget);
    h.router.pop();
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, closeTo(before, 1));
  });

  for (final loading in [true, false]) {
    testWidgets(
      'loading=$loading retains field and status across layout change',
      (tester) async {
        final h = await _harness(
          tester,
          fixedBooks: loading
              ? const AsyncLoading<List<LibraryBook>>()
              : AsyncError<List<LibraryBook>>(
                  StateError('unavailable'),
                  StackTrace.current,
                ),
        );
        await tester.pumpWidget(h.app());
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'orchid');
        await tester.pump();
        await tester.runAsync(
          () => h.container
              .read(libraryViewModeProvider.notifier)
              .setMode(LibraryViewMode.list),
        );
        await tester.pump();
        expect(
          tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
          'orchid',
        );
        if (loading) {
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
        } else {
          expect(find.text('Search is unavailable.'), findsOneWidget);
        }
        expect(h.repository.mutations, isEmpty);
      },
    );
  }

  for (final dark in [false, true]) {
    for (final mode in LibraryViewMode.values) {
      testWidgets('320px text2 renders $mode safely, dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = await _harness(
          tester,
          saved: mode,
          books: [
            _book(
              'long',
              title:
                  'An extremely long book title with several words and metadata',
              author: 'A very long author name',
            ),
          ],
        );
        await tester.pumpWidget(h.app(dark: dark, textScale: 2));
        await tester.pumpAndSettle();
        expect(_visibleIds(tester, mode), ['long']);
        expect(find.byType(SearchBar), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

List<String> _visibleIds(WidgetTester tester, LibraryViewMode mode) =>
    mode == LibraryViewMode.grid
    ? tester
          .widgetList<LibraryBookCard>(find.byType(LibraryBookCard))
          .map((w) => w.book.id)
          .toList()
    : tester
          .widgetList<LibraryBookTile>(find.byType(LibraryBookTile))
          .map((w) => w.book.id)
          .toList();

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

Future<_Harness> _harness(
  WidgetTester tester, {
  LibraryViewMode saved = LibraryViewMode.grid,
  List<LibraryBook>? books,
  AsyncValue<List<LibraryBook>>? fixedBooks,
}) async {
  final database = AppDatabase(NativeDatabase.memory());
  final storage = DriftBookDisplaySettingsRepository(database);
  await tester.runAsync(() async {
    if (saved != LibraryViewMode.grid) await storage.save(saved.name);
  });
  final repository = _Repository(
    books ??
        [
          _book('title', title: 'Orchid atlas', author: 'Alice'),
          _book('author', title: 'Bloom guide', author: 'Orchid Society'),
          _book('other', title: 'Other title', author: null),
        ],
  );
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      libraryRepositoryProvider.overrideWithValue(repository),
      if (fixedBooks != null) allBooksProvider.overrideWithValue(fixedBooks),
      deleteBookProvider.overrideWithValue(DeleteBook(_Deletion(repository))),
      readingProgressProvider.overrideWith((ref, _) => Stream.value(null)),
    ],
  );
  await tester.runAsync(() async {
    container.read(libraryViewModeProvider);
    await container.read(libraryViewModeProvider.notifier).ready;
  });
  final router = GoRouter(
    initialLocation: '/search',
    routes: [
      GoRoute(
        path: AppRoutes.searchPath,
        builder: (_, _) => const SearchScreen(),
      ),
      GoRoute(
        path: AppRoutes.bookDetailsPath,
        name: AppRoutes.bookDetailsName,
        builder: (_, state) =>
            Scaffold(body: Text('Details:${state.pathParameters['bookId']}')),
      ),
      GoRoute(
        path: '/layout-settings',
        builder: (_, _) => const Scaffold(body: BookDisplayLayoutSettingTile()),
      ),
      GoRoute(
        path: '/library-toggle',
        builder: (_, _) => Scaffold(
          body: Consumer(
            builder: (context, ref, _) => LibraryViewToggle(
              viewMode: ref.watch(libraryViewModeProvider),
              onPressed: () =>
                  ref.read(libraryViewModeProvider.notifier).toggle(),
            ),
          ),
        ),
      ),
    ],
  );
  addTearDown(() async {
    router.dispose();
    container.dispose();
    await tester.runAsync(() async {
      await database.close();
      unawaited(repository.changes.close());
    });
  });
  return _Harness(container, repository, storage, router);
}

class _Harness {
  _Harness(this.container, this.repository, this.storage, this.router);
  final ProviderContainer container;
  final _Repository repository;
  final DriftBookDisplaySettingsRepository storage;
  final GoRouter router;
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
  Future<void> setMode(WidgetTester tester, LibraryViewMode mode) async {
    await tester.runAsync(
      () => container.read(libraryViewModeProvider.notifier).setMode(mode),
    );
    await tester.pumpAndSettle();
  }
}

class _Repository implements LibraryRepository {
  _Repository(this.items);
  List<LibraryBook> items;
  final changes = StreamController<List<LibraryBook>>.broadcast();
  final mutations = <String>[];
  int watchCalls = 0;
  @override
  Stream<List<LibraryBook>> watchAllBooks() async* {
    watchCalls++;
    yield items;
    yield* changes.stream;
  }

  void replace(List<LibraryBook> values) {
    items = values;
    changes.add(items);
  }

  @override
  Future<void> setFavorite(String id, bool value) async {
    mutations.add('favorite:$id:$value');
    replace([
      for (final book in items)
        book.id == id
            ? _book(
                book.id,
                title: book.title,
                author: book.author,
                favorite: value,
              )
            : book,
    ]);
  }

  @override
  Future<void> deleteBook(String id) async {
    mutations.add('delete:$id');
    replace(items.where((book) => book.id != id).toList());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Exercise the existing DeleteBook use case without touching real book files.
class _Deletion extends ManagedBookDeletionService {
  _Deletion(this.repository) : super(repository, CoverStorageService());
  final _Repository repository;
  @override
  Future<void> delete(String id) => repository.deleteBook(id);
}

List<LibraryBook> _manyBooks() => List.generate(
  1000,
  (i) => _book('$i', title: 'Book ${i.toString().padLeft(4, '0')}'),
);

LibraryBook _book(
  String id, {
  String? title,
  String? author = 'Author',
  bool favorite = false,
}) => LibraryBook(
  id: id,
  title: title ?? 'Book $id',
  sortTitle: title,
  author: author,
  description: null,
  filePath: '/unused-local-search-test/$id.epub',
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
  isFavorite: favorite,
);

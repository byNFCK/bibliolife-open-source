import 'package:bibliolife/shared/presentation/widgets/app_context_menu.dart';
import '../../support/unified_book_list_assertions.dart';
import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/multi_catalog_search_controller.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/remote_publication_details_screen.dart';
import 'package:bibliolife/shared/presentation/widgets/app_book_list_tile.dart';
import 'dart:async';

import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway_provider.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_access_hint.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/multi_catalog_search_screen.dart';
import 'package:bibliolife/features/library/application/providers/library_repository_provider.dart';
import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_providers.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets(
    'layout is reactive without replacing query, filters, identities or controller',
    (tester) async {
      final gateway = _Gateway();
      await tester.pumpWidget(
        _app(books: [_mergedBook(), _localOnlyBook()], gateway: gateway),
      );
      await _search(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MultiCatalogSearchScreen)),
      );
      final controller = container.read(
        multiCatalogSearchControllerProvider.notifier,
      );
      final state = container.read(multiCatalogSearchControllerProvider);
      final field = tester.widget<SearchBar>(find.byType(SearchBar)).controller;
      final focus = tester.widget<SearchBar>(find.byType(SearchBar)).focusNode;
      final rootCalls = gateway.rootCalls;
      for (final mode in [
        LibraryViewMode.list,
        LibraryViewMode.grid,
        LibraryViewMode.list,
      ]) {
        await container.read(libraryViewModeProvider.notifier).setMode(mode);
        await tester.pumpAndSettle();
        expect(
          container.read(multiCatalogSearchControllerProvider.notifier),
          same(controller),
        );
        expect(
          container.read(multiCatalogSearchControllerProvider).results,
          same(state.results),
        );
        expect(
          container.read(multiCatalogSearchControllerProvider).filters,
          same(state.filters),
        );
        expect(
          tester.widget<SearchBar>(find.byType(SearchBar)).controller,
          same(field),
        );
        expect(
          tester.widget<SearchBar>(find.byType(SearchBar)).focusNode,
          same(focus),
        );
        expect(field!.text, 'long');
        expect(gateway.searchCalls, 1);
        expect(gateway.rootCalls, rootCalls);
        expect(find.text('Downloaded'), findsOneWidget);
        expect(find.text('In library'), findsOneWidget);
        expect(
          find.byKey(
            const ValueKey(
              'catalog-search-publication-source\u0000remote-only',
            ),
          ),
          findsOneWidget,
        );
      }
      expect(find.byType(AppBookListTile), findsNWidgets(3));
      expectUnifiedBookList(tester);
      expect(find.byType(AppContextMenuButton<String>), findsNWidgets(2));
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'List shared rows fit narrow scale2 with local actions dark=$dark',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _app(
            books: [_mergedBook(), _localOnlyBook()],
            mode: LibraryViewMode.list,
            dark: dark,
            textScaler: const TextScaler.linear(2),
          ),
        );
        await _search(tester);
        expect(find.byType(AppBookListTile), findsNWidgets(3));
        expect(find.text('Downloaded'), findsOneWidget);
        expect(find.text('In library'), findsOneWidget);
        expect(find.byType(AppContextMenuButton<String>), findsNWidgets(2));
        for (final menu
            in find.byType(AppContextMenuButton<String>).evaluate().toList()) {
          await tester.tap(find.byElementPredicate((e) => identical(e, menu)));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('local-search-open')), findsOneWidget);
          expect(find.text('Delete'), findsOneWidget);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
        }
        expect(find.byType(AppContextMenuButton<String>), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'List routes local and canonical remote identities and back without search',
    (tester) async {
      final gateway = _Gateway();
      RemotePublicationDetailsRequest? request;
      final router = GoRouter(
        initialLocation: '/search',
        routes: [
          GoRoute(
            path: '/search',
            builder: (_, _) => const MultiCatalogSearchScreen(),
          ),
          GoRoute(
            path: AppRoutes.bookDetailsPath,
            name: AppRoutes.bookDetailsName,
            builder: (_, state) =>
                Text('Local ${state.pathParameters['bookId']}'),
          ),
          GoRoute(
            path: AppRoutes.publicationOnlineLibraryPath,
            name: AppRoutes.publicationOnlineLibraryName,
            builder: (_, state) {
              request = state.extra! as RemotePublicationDetailsRequest;
              return Text('Remote ${state.pathParameters['sourceId']}');
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        _app(
          books: [_mergedBook(), _localOnlyBook()],
          mode: LibraryViewMode.list,
          gateway: gateway,
          router: router,
        ),
      );
      await _search(tester);
      await tester.tap(find.byType(AppContextMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('local-search-open')).first);
      await tester.pumpAndSettle();
      expect(find.text('Local merged-local-id'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      final remote = find.byKey(
        const ValueKey('catalog-search-publication-source\u0000remote-only'),
      );
      await tester.ensureVisible(remote);
      await tester.pumpAndSettle();
      await tester.tap(remote);
      await tester.pumpAndSettle();
      expect(request!.sourceId, 'source');
      expect(request!.publication.remoteId, 'remote-only');
      expect(request!.canonicalBook, isNotNull);
      router.pop();
      await tester.pumpAndSettle();
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
        'long',
      );
      expect(gateway.searchCalls, 1);
    },
  );

  testWidgets(
    'lazy mode offsets restore and reflow does not cascade pagination',
    (tester) async {
      final gateway = _Gateway(paging: true);
      await tester.pumpWidget(
        _app(
          books: List.generate(
            200,
            (i) =>
                _book(id: 'local-$i', title: 'long book $i', author: 'Author'),
          ),
          gateway: gateway,
        ),
      );
      await _search(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MultiCatalogSearchScreen)),
      );
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      scroll.jumpTo(1300);
      await tester.pumpAndSettle();
      final pages = gateway.pageCalls;
      await container
          .read(libraryViewModeProvider.notifier)
          .setMode(LibraryViewMode.list);
      await tester.pumpAndSettle();
      expect(scroll.pixels, 0);
      expect(find.byType(AppBookListTile).evaluate().length, lessThan(30));
      expect(gateway.pageCalls, pages);
      scroll.jumpTo(800);
      await tester.pumpAndSettle();
      await container
          .read(libraryViewModeProvider.notifier)
          .setMode(LibraryViewMode.grid);
      await tester.pumpAndSettle();
      expect(scroll.pixels, closeTo(1300, 1));
      await container
          .read(libraryViewModeProvider.notifier)
          .setMode(LibraryViewMode.list);
      await tester.pumpAndSettle();
      expect(scroll.pixels, closeTo(800, 1));
      expect(gateway.pageCalls, pages);
      scroll.jumpTo(scroll.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(gateway.pageCalls, pages + 1);
      final after = gateway.pageCalls;
      await container
          .read(libraryViewModeProvider.notifier)
          .setMode(LibraryViewMode.grid);
      await tester.pumpAndSettle();
      expect(gateway.pageCalls, after);
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(SearchBar), 'new query');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(scroll.pixels, 0);
      expect(gateway.searchCalls, 2);
    },
  );

  testWidgets('shared Grid gap preserves source requests and assembled cards', (
    tester,
  ) async {
    final gateway = _Gateway();
    await tester.pumpWidget(
      _app(books: [_mergedBook(), _localOnlyBook()], gateway: gateway, gap: 22),
    );
    await _search(tester);
    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.mainAxisSpacing, 22);
    expect(delegate.crossAxisSpacing, 22);
    expect(find.text('Downloaded'), findsOneWidget);
    expect(find.text('In library'), findsOneWidget);
    expect(gateway.searchCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'merged and local-only cards keep status and Open visible at A065 widths',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final configuration in [
        (const Size(360, 800), 1.0),
        (const Size(320, 800), 1.3),
      ]) {
        await tester.binding.setSurfaceSize(configuration.$1);
        await tester.pumpWidget(
          _app(
            textScaler: TextScaler.linear(configuration.$2),
            books: [_mergedBook(), _localOnlyBook()],
          ),
        );
        await _search(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('Downloaded'), findsOneWidget);
        expect(find.text('In library'), findsOneWidget);
        expect(find.byKey(const Key('local-search-open')), findsNWidgets(2));
        expect(
          tester.getBottomRight(find.text('Downloaded')).dy,
          lessThanOrEqualTo(
            tester
                .getBottomRight(
                  find.byKey(const Key('local-search-open')).first,
                )
                .dy,
          ),
        );
        expect(
          tester.getBottomRight(find.text('In library')).dy,
          lessThanOrEqualTo(
            tester
                .getBottomRight(find.byKey(const Key('local-search-open')).last)
                .dy,
          ),
        );
      }
    },
  );

  testWidgets(
    'long metadata, missing covers, and remote-only cards do not overflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(
          textScaler: const TextScaler.linear(1.3),
          books: [_mergedBook(), _localOnlyBook()],
        ),
      );
      await _search(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(
          const ValueKey('catalog-search-publication-source\u0000remote-only'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('remote-book-cover-placeholder')),
        findsOneWidget,
      );
      expect(find.text('Downloaded'), findsOneWidget);
      expect(find.text('In library'), findsOneWidget);
    },
  );

  testWidgets('Open navigates with the authoritative local book ID', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/search',
      routes: [
        GoRoute(
          path: '/search',
          builder: (_, _) => const MultiCatalogSearchScreen(),
        ),
        GoRoute(
          path: AppRoutes.bookDetailsPath,
          name: AppRoutes.bookDetailsName,
          builder: (_, state) =>
              Text('Local ${state.pathParameters['bookId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      _app(books: [_mergedBook(), _localOnlyBook()], router: router),
    );
    await _search(tester);

    await tester.tap(find.byKey(const Key('local-search-open')).first);
    await tester.pumpAndSettle();

    expect(find.text('Local merged-local-id'), findsOneWidget);
  });

  testWidgets(
    'local repository updates recompute cards without restarting Search or requesting focus',
    (tester) async {
      final repository = _UpdatingLibraryRepository();
      final gateway = _Gateway();
      addTearDown(repository.dispose);
      await tester.pumpWidget(
        _app(repository: repository, gateway: gateway, books: const []),
      );
      await _search(tester);

      final focusBeforeUpdate = FocusManager.instance.primaryFocus;
      expect(gateway.searchCalls, 1);
      expect(find.text('In library'), findsNothing);

      repository.add([_localOnlyBook()]);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('In library'), findsOneWidget);
      expect(gateway.searchCalls, 1);
      expect(FocusManager.instance.primaryFocus, same(focusBeforeUpdate));
    },
  );

  testWidgets('replacing a query immediately replaces local-only matches', (
    tester,
  ) async {
    final first = _book(
      id: 'first-query-book',
      title: 'first local query title',
      author: 'First Author',
    );
    final second = _book(
      id: 'second-query-book',
      title: 'second local query title',
      author: 'Second Author',
    );
    await tester.pumpWidget(_app(books: [first, second]));

    await tester.enterText(find.byType(SearchBar), 'first local');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text(first.title), findsOneWidget);
    expect(find.text(second.title), findsNothing);

    await tester.enterText(find.byType(SearchBar), 'second local');
    await tester.pump();

    expect(find.text(first.title), findsNothing);
    expect(find.text(second.title), findsNothing);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text(second.title), findsOneWidget);
  });
}

Future<void> _search(WidgetTester tester) async {
  await tester.enterText(find.byType(SearchBar), 'long');
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

Widget _app({
  required List<LibraryBook> books,
  TextScaler textScaler = TextScaler.noScaling,
  GoRouter? router,
  LibraryRepository? repository,
  RemoteCatalogGateway? gateway,
  double? gap,
  LibraryViewMode mode = LibraryViewMode.grid,
  bool dark = false,
}) {
  final theme = gap == null
      ? (dark ? ThemeData.dark() : null)
      : ThemeData(
          extensions: [
            AppThemeTokens.standard().copyWith(bookCardGridGap: gap),
          ],
        );
  final child = router == null
      ? MaterialApp(theme: theme, home: const MultiCatalogSearchScreen())
      : MaterialApp.router(theme: theme, routerConfig: router);
  return MediaQuery(
    data: MediaQueryData(textScaler: textScaler),
    child: ProviderScope(
      overrides: [
        libraryViewModeProvider.overrideWith(() => _LayoutMode(mode)),
        catalogSourceRepositoryProvider.overrideWithValue(_CatalogRepository()),
        remoteCatalogGatewayProvider.overrideWithValue(gateway ?? _Gateway()),
        libraryRepositoryProvider.overrideWithValue(
          repository ?? _LibraryRepository(books),
        ),
        readingProgressProvider.overrideWith(
          (ref, bookId) => Stream.value(null),
        ),
      ],
      child: child,
    ),
  );
}

final _source = CatalogSource(
  id: 'source',
  name: 'Source',
  baseUri: Uri.parse('https://catalog.example'),
  type: CatalogSourceType.opds1,
  isBuiltIn: true,
  isEnabled: true,
  supportsSearch: true,
  supportsNavigation: true,
  supportsAcquisition: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

RemoteCatalogPublicationSummary
_mergedRemote() => RemoteCatalogPublicationSummary(
  remoteId: 'merged-remote',
  title:
      'A deliberately long downloaded title that still needs two bounded lines',
  authors: const ['A deliberately long downloaded author name'],
  language: 'en',
  accessHints: [_directDownload('merged-remote')],
);

RemoteCatalogPublicationSummary _remoteOnly() =>
    RemoteCatalogPublicationSummary(
      remoteId: 'remote-only',
      title: 'A deliberately long remote-only title with a missing cover',
      authors: const ['A deliberately long remote-only author name'],
      language: 'en',
      accessHints: [_directDownload('remote-only')],
    );

RemoteCatalogAccessHint _directDownload(String id) => RemoteCatalogAccessHint(
  type: RemoteCatalogAccessType.directDownload,
  uri: Uri.parse('https://catalog.example/$id.epub'),
  mediaType: 'application/epub+zip',
  isFullBook: true,
  isDrmFree: true,
);

LibraryBook _mergedBook() => _book(
  id: 'merged-local-id',
  title: _mergedRemote().title,
  author: _mergedRemote().authors.single,
  catalogSourceId: 'source',
  remotePublicationId: 'merged-remote',
);

LibraryBook _localOnlyBook() => _book(
  id: 'local-only-id',
  title:
      'A deliberately long local-only title that still needs two bounded lines',
  author: 'A deliberately long local-only author name',
);

LibraryBook _book({
  required String id,
  required String title,
  required String author,
  String? catalogSourceId,
  String? remotePublicationId,
}) => LibraryBook(
  id: id,
  title: title,
  sortTitle: title,
  author: author,
  description: null,
  filePath: 'C:/library/$id.epub',
  fileName: '$id.epub',
  fileExtension: 'epub',
  format: BookFormat.epub,
  mediaType: 'application/epub+zip',
  coverPath: null,
  language: 'en',
  publisher: null,
  publishedDate: null,
  isbn: null,
  pageCount: null,
  fileSizeBytes: 1,
  dateAdded: DateTime.utc(2026),
  lastOpenedAt: null,
  isFavorite: false,
  catalogSourceId: catalogSourceId,
  remotePublicationId: remotePublicationId,
);

class _CatalogRepository implements CatalogSourceRepository {
  @override
  Future<CatalogSource?> getById(String id) async => _source;

  @override
  Future<List<CatalogSource>> getAll() async => [_source];

  @override
  Stream<List<CatalogSource>> watchAll() => Stream.value([_source]);

  @override
  Future<void> ensureBuiltInSources() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Gateway implements RemoteCatalogGateway {
  _Gateway({this.paging = false});
  final bool paging;
  var searchCalls = 0;
  var rootCalls = 0;
  var pageCalls = 0;

  @override
  Future<RemoteCatalogPage> loadRoot(CatalogSource source) async {
    rootCalls++;
    return RemoteCatalogPage(
      sourceId: source.id,
      location: RemoteCatalogLocation.parse('https://catalog.example/root'),
      title: source.name,
      searchCapability: RemoteCatalogSearchCapability.directTemplate(
        RemoteCatalogLocation.parse(
          'https://catalog.example/search?q=%7BsearchTerms%7D',
        ),
      ),
    );
  }

  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) async {
    searchCalls++;
    return RemoteCatalogPage(
      sourceId: source.id,
      location: RemoteCatalogLocation.parse('https://catalog.example/search'),
      title: 'Results',
      nextPageLocation: paging
          ? RemoteCatalogLocation.parse('https://catalog.example/page/1')
          : null,
      publications: [_mergedRemote(), _remoteOnly()],
    );
  }

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) async {
    pageCalls++;
    return RemoteCatalogPage(
      sourceId: source.id,
      location: location,
      title: 'More',
      publications: [
        RemoteCatalogPublicationSummary(
          remoteId: 'more-$pageCalls',
          title: 'long more $pageCalls',
          authors: ['Author'],
          accessHints: [_directDownload('more-$pageCalls')],
        ),
      ],
      nextPageLocation: RemoteCatalogLocation.parse(
        'https://catalog.example/page/${pageCalls + 1}',
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LibraryRepository implements LibraryRepository {
  _LibraryRepository(this.books);

  final List<LibraryBook> books;

  @override
  Future<void> addBook(LibraryBook book) async {}

  @override
  Future<void> deleteBook(String id) async {}

  @override
  Future<LibraryBook?> findBookByFilePath(String filePath) async => null;

  @override
  Future<LibraryBook?> findBookByOriginalFilePath(
    String originalFilePath,
  ) async => null;

  @override
  Future<List<LibraryBook>> getAllBooks() async => books;

  @override
  Future<LibraryBook?> getBookById(String id) async =>
      books.where((book) => book.id == id).firstOrNull;

  @override
  Future<void> markBookOpened(String id, DateTime openedAt) async {}

  @override
  Future<void> setFavorite(String id, bool isFavorite) async {}

  @override
  Future<void> updateBook(LibraryBook book) async {}

  @override
  Stream<List<LibraryBook>> watchAllBooks() => Stream.value(books);

  @override
  Stream<List<LibraryBook>> watchFavoriteBooks() => Stream.value(
    books.where((book) => book.isFavorite).toList(growable: false),
  );

  @override
  Stream<List<LibraryBook>> watchUnsortedBooks() => watchAllBooks();
}

class _UpdatingLibraryRepository extends _LibraryRepository {
  _UpdatingLibraryRepository() : super(const []);

  final _updates = StreamController<List<LibraryBook>>.broadcast();

  void add(List<LibraryBook> books) => _updates.add(books);

  void dispose() => _updates.close();

  @override
  Stream<List<LibraryBook>> watchAllBooks() => _updates.stream;

  @override
  Stream<List<LibraryBook>> watchFavoriteBooks() => Stream.value(
    books.where((book) => book.isFavorite).toList(growable: false),
  );

  @override
  Stream<List<LibraryBook>> watchUnsortedBooks() => watchAllBooks();
}

class _LayoutMode extends LibraryViewModeNotifier {
  _LayoutMode(this.initial);
  final LibraryViewMode initial;
  @override
  LibraryViewMode build() {
    ready = Future.value();
    return initial;
  }

  @override
  Future<void> setMode(LibraryViewMode mode) async {
    state = mode;
  }
}

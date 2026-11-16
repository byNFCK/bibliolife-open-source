import 'package:bibliolife/features/library/application/providers/library_providers.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import '../../support/unified_book_list_assertions.dart';
import 'package:bibliolife/shared/presentation/widgets/app_book_list_tile.dart';
import 'package:bibliolife/app/theme/app_theme.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_browser_controller.dart';
import 'package:bibliolife/features/catalog_sources/presentation/widgets/remote_catalog_book_card.dart';
import 'package:bibliolife/features/catalog_sources/presentation/widgets/remote_catalog_book_tile.dart';
import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:bibliolife/features/library/data/repositories/drift_book_display_settings_repository.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_view_toggle.dart';
import 'package:bibliolife/features/settings/presentation/widgets/settings_body.dart';
import 'package:bibliolife/shared/models/book_cover_reference.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_image.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_render_profile.dart';
import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/core/database/database_provider.dart';
import 'package:drift/native.dart';
import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway_provider.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/catalog_browser_screen.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/catalog_sources_screen.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/remote_publication_details_screen.dart';
import 'package:bibliolife/features/connectivity/application/app_connectivity_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets(
    'default Grid keeps natural card geometry and responsive columns lazily',
    (tester) async {
      final h = await _layoutHarness(tester, root: _layoutPage(count: 500));
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final entry in [(400.0, 2), (700.0, 3), (1000.0, 4)]) {
        tester.view.physicalSize = Size(entry.$1, 900);
        await tester.pumpWidget(h.app());
        await tester.pumpAndSettle();
        final cards = find.byType(RemoteCatalogBookCard);
        expect(cards.evaluate().length, lessThan(30));
        final first = tester.getRect(
          find.byKey(const ValueKey('catalog-publication-pub-0')),
        );
        final next = tester.getRect(
          find.byKey(const ValueKey('catalog-publication-pub-1')),
        );
        expect(next.left - first.right, closeTo(16, .01));
        final expectedWidth = (entry.$1 - 32 - 16 * (entry.$2 - 1)) / entry.$2;
        expect(first.width, closeTo(expectedWidth, .01));
        final cover = tester.getSize(
          find.byKey(const Key('app-book-card')).first,
        );
        expect(cover.width / cover.height, closeTo(.65, .01));
        expect(find.text('0%'), findsNothing);
        expect(find.byKey(const Key('app-book-card-bottom-bar')), findsNothing);
        expect(find.byType(RemoteCatalogBookTile), findsNothing);
        expect(find.byType(GridView), findsNothing);
      }
      expect(h.gateway.calls, 1);
    },
  );

  testWidgets(
    'persisted List uses real remote models and keeps categories as rows',
    (tester) async {
      final h = await _layoutHarness(tester, saved: LibraryViewMode.list);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      expect(find.byType(RemoteCatalogBookTile), findsNWidgets(3));
      expectUnifiedBookList(tester);
      expect(find.byType(RemoteCatalogBookCard), findsNothing);
      expect(find.byIcon(Icons.folder_outlined), findsNWidgets(2));
      expect(find.text('Fiction'), findsOneWidget);
      expect(find.text('Science'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Fiction')).dy,
        lessThan(tester.getTopLeft(find.text('Science')).dy),
      );
      expect(await tester.runAsync(h.storage.load), 'list');
      final tile = tester.widget<RemoteCatalogBookTile>(
        find.byType(RemoteCatalogBookTile).first,
      );
      expect(tile.publication, same(h.gateway.root.publications.first));
      expect(tile.sourceId, 'source');
      expect(find.byIcon(Icons.favorite_border), findsNothing);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
    },
  );

  testWidgets(
    'reactive Grid and List do not refetch or replace controller/page',
    (tester) async {
      final h = await _layoutHarness(tester);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      final controller = h.controller;
      final page = h.state.page;
      for (final mode in [LibraryViewMode.list, LibraryViewMode.grid]) {
        await h.setMode(tester, mode);
        expect(h.controller, same(controller));
        expect(h.state.page, same(page));
        expect(h.gateway.calls, 1);
        expect(find.byIcon(Icons.folder_outlined), findsNWidgets(2));
        expect(
          mode == LibraryViewMode.list
              ? find.byType(RemoteCatalogBookTile)
              : find.byType(RemoteCatalogBookCard),
          findsWidgets,
        );
      }
    },
  );

  for (final route in ['/layout-settings', '/library-toggle']) {
    testWidgets('existing global control $route updates Browse', (
      tester,
    ) async {
      final h = await _layoutHarness(tester);
      await tester.pumpWidget(h.app());
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
      expect(find.byType(RemoteCatalogBookTile), findsWidgets);
      expect(h.gateway.calls, 1);
    });
  }

  for (final mode in LibraryViewMode.values) {
    testWidgets(
      'publication and source identities route once and return in $mode',
      (tester) async {
        final h = await _layoutHarness(tester, saved: mode);
        await tester.pumpWidget(h.app());
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Publication 1'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Publication 1'));
        await tester.pumpAndSettle();
        expect(find.text('Remote details:source:pub-1'), findsOneWidget);
        expect(h.requests, hasLength(1));
        expect(h.requests.single.sourceId, 'source');
        expect(
          h.requests.single.publication,
          same(h.gateway.root.publications[1]),
        );
        expect(h.requests.single.sourceName, 'Library');
        h.router.pop();
        await tester.pumpAndSettle();
        expect(h.state.page, same(h.gateway.root));
        expect(h.gateway.calls, 1);
        expect(h.container.read(libraryViewModeProvider), mode);
      },
    );

    testWidgets(
      'manual paging deduplicates and preserves logical page key in $mode',
      (tester) async {
        final root = _layoutPage(count: 2, next: _location('/page-2'));
        final h = await _layoutHarness(tester, saved: mode, root: root);
        h.gateway.pages[_location('/page-2')] = _page(
          location: _location('/page-2'),
          publications: [root.publications.last, _publication(2)],
        );
        await tester.pumpWidget(h.app());
        await tester.pumpAndSettle();
        final beforeKey = tester
            .widget<CustomScrollView>(find.byType(CustomScrollView))
            .key;
        await tester.scrollUntilVisible(
          find.text('Load more'),
          200,
          scrollable: _browserScrollable(),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Load more'));
        await tester.pumpAndSettle();
        expect(h.gateway.pageCalls, 1);
        expect(h.state.page!.publications.map((p) => p.remoteId), [
          'pub-0',
          'pub-1',
          'pub-2',
        ]);
        expect(h.state.page!.location, root.location);
        expect(
          tester.widget<CustomScrollView>(find.byType(CustomScrollView)).key,
          beforeKey,
        );
        expect(find.text('Load more'), findsNothing);
        await h.setMode(
          tester,
          mode == LibraryViewMode.grid
              ? LibraryViewMode.list
              : LibraryViewMode.grid,
        );
        expect(h.gateway.calls, 2);
        expect(h.state.page!.publications, hasLength(3));
      },
    );
  }

  testWidgets('semantic remote row activation navigates exactly once', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    final h = await _layoutHarness(tester, saved: LibraryViewMode.list);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    final tile = find.byKey(const ValueKey('catalog-publication-pub-0'));
    final node = tester.getSemantics(tile);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(h.requests, hasLength(1));
    expect(h.requests.single.publication.remoteId, 'pub-0');
    semantics.dispose();
  });

  testWidgets(
    'source/page/mode offsets restore independently and Details preserves scroll',
    (tester) async {
      final h = await _layoutHarness(tester, root: _layoutPage(count: 200));
      h.gateway.pages[_location('/fiction')] = _layoutPage(
        count: 150,
        location: _location('/fiction'),
        title: 'Fiction Feed',
      );
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      _browserPosition(tester).jumpTo(1400);
      await tester.pumpAndSettle();
      await h.setMode(tester, LibraryViewMode.list);
      expect(_browserPosition(tester).pixels, 0);
      _browserPosition(tester).jumpTo(700);
      await tester.pumpAndSettle();
      await h.setMode(tester, LibraryViewMode.grid);
      expect(_browserPosition(tester).pixels, closeTo(1400, 1));
      await h.controller.openNavigation(_location('/fiction'));
      await tester.pumpAndSettle();
      expect(_browserPosition(tester).pixels, 0);
      _browserPosition(tester).jumpTo(900);
      await tester.pumpAndSettle();
      final card = find.byType(RemoteCatalogBookCard).hitTestable().first;
      final id = tester
          .widget<RemoteCatalogBookCard>(card)
          .publication
          .remoteId;
      final offset = _browserPosition(tester).pixels;
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.text('Remote details:source:$id'), findsOneWidget);
      h.router.pop();
      await tester.pumpAndSettle();
      expect(_browserPosition(tester).pixels, closeTo(offset, 1));
      await tester.tap(find.byTooltip('Back in catalog'));
      await tester.pumpAndSettle();
      expect(h.state.page!.location, _location('/root'));
      expect(_browserPosition(tester).pixels, closeTo(1400, 1));
      await h.setMode(tester, LibraryViewMode.list);
      expect(_browserPosition(tester).pixels, closeTo(700, 1));
      expect(h.gateway.calls, 2);
      h.router.push('/online-libraries/another/browse');
      await tester.pumpAndSettle();
      expect(_browserPosition(tester).pixels, 0);
      expect(
        h.container.read(catalogBrowserControllerProvider('another')).sourceId,
        'another',
      );
      h.router.pop();
      await tester.pumpAndSettle();
      expect(_browserPosition(tester).pixels, closeTo(700, 1));
    },
  );

  testWidgets(
    'large List is lazy and refresh with fewer publications clamps saved offsets',
    (tester) async {
      final h = await _layoutHarness(tester, root: _layoutPage(count: 500));
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      _browserPosition(tester).jumpTo(3000);
      await tester.pumpAndSettle();
      await h.setMode(tester, LibraryViewMode.list);
      expect(
        find.byType(RemoteCatalogBookTile).evaluate().length,
        lessThan(30),
      );
      _browserPosition(tester).jumpTo(2500);
      await tester.pumpAndSettle();
      h.gateway.root = _layoutPage(count: 1);
      await h.controller.refresh();
      await tester.pumpAndSettle();
      await h.setMode(tester, LibraryViewMode.grid);
      final position = _browserPosition(tester);
      expect(
        position.pixels,
        inInclusiveRange(position.minScrollExtent, position.maxScrollExtent),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offline/retry/refresh states preserve controls and do not fetch on mode changes',
    (tester) async {
      final h = await _layoutHarness(tester);
      h.gateway.error = const RemoteCatalogException.accessDenied();
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      expect(find.text('Connectivity settings'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await h.setMode(tester, LibraryViewMode.list);
      expect(h.gateway.calls, 1);
      h.gateway.error = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(RemoteCatalogBookTile), findsWidgets);
      expect(h.gateway.calls, 2);
      await tester.tap(find.byTooltip('Refresh catalog'));
      await tester.pumpAndSettle();
      expect(h.gateway.pageCalls, 1);
    },
  );

  testWidgets(
    'remote row omits absent authors/status and keeps compact fallback without local actions',
    (tester) async {
      final publication = RemoteCatalogPublicationSummary(
        remoteId: 'missing',
        title: 'Missing metadata',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allBooksProvider.overrideWithValue(
              const AsyncData(<LibraryBook>[]),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: RemoteCatalogBookTile(
                publication: publication,
                sourceId: 'source',
                onOpen: () {},
              ),
            ),
          ),
        ),
      );
      expect(
        find.byKey(const Key('remote-book-cover-placeholder')),
        findsOneWidget,
      );
      expect(find.text('Unknown author'), findsNothing);
      final image = tester.widget<BookCoverImage>(find.byType(BookCoverImage));
      expect(image.cover, isA<MissingBookCover>());
      expect(image.profile, BookCoverRenderProfile.compactList);
      expect(image.remoteCache, isNull);
      final tile = tester.widget<AppBookListTile>(find.byType(AppBookListTile));
      expect(tile.metadata, isNull);
      expect(tile.actions.single, isA<AppBookListActionPlaceholder>());
      final size = tester.getSize(find.byKey(const Key('book-list-cover')));
      expect(size.width, 92);
      expect(size.height, 138);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(find.byIcon(Icons.favorite), findsNothing);
    },
  );

  testWidgets(
    'compact cover preserves source URL selection and caller-supplied status',
    (tester) async {
      final publication = RemoteCatalogPublicationSummary(
        remoteId: 'cover',
        title: 'Cover selection',
        authors: ['One', 'Two'],
        coverLocation: RemoteCatalogLocation.parse(
          'https://covers.openlibrary.org/b/id/123-S.jpg?default=false',
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allBooksProvider.overrideWithValue(
              const AsyncData(<LibraryBook>[]),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: RemoteCatalogBookTile(
                publication: publication,
                sourceId: 'builtin-open-library',
                onOpen: () {},
                status: const Text('Supplied status'),
              ),
            ),
          ),
        ),
      );
      final image = tester.widget<BookCoverImage>(find.byType(BookCoverImage));
      final expected = selectRemoteCoverForProfile(
        preferred: publication.coverLocation,
        candidates: publication.imageCandidates,
        sourceId: 'builtin-open-library',
        profile: BookCoverRenderProfile.searchGrid,
      )!;
      expect((image.cover as RemoteBookCover).uri, expected.uri);
      expect(image.profile.cacheWidth, 280);
      expect(image.profile.cacheHeight, 420);
      expect(find.text('One, Two'), findsOneWidget);
      expect(find.text('Supplied status'), findsOneWidget);
    },
  );

  for (final dark in [false, true]) {
    for (final mode in LibraryViewMode.values) {
      testWidgets('long metadata fits 320px and text2 in $mode, dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = await _layoutHarness(
          tester,
          saved: mode,
          root: _page(
            publications: [
              RemoteCatalogPublicationSummary(
                remoteId: 'long',
                title: 'An extremely long publication title with several words',
                authors: [
                  'A very long author name',
                  'Another exceptionally long author',
                ],
              ),
            ],
          ),
        );
        await tester.pumpWidget(h.app(dark: dark, textScale: 2));
        await tester.pumpAndSettle();
        expect(
          mode == LibraryViewMode.grid
              ? find.byType(RemoteCatalogBookCard)
              : find.byType(RemoteCatalogBookTile),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'browser book cards keep natural metadata height at phone scales',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final scale in [1.0, 1.5]) {
        final gateway = _Gateway(
          _page(
            publications: [
              RemoteCatalogPublicationSummary(
                remoteId: 'green-mummy-$scale',
                title: 'The Green Mummy',
                authors: const ['Hume, Fergus'],
                hasAcquisition: true,
              ),
            ],
          ),
        );
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: _browserApp(gateway),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('The Green Mummy'), findsOneWidget);
        expect(find.text('Hume, Fergus'), findsOneWidget);
        expect(find.text('Available from this catalog'), findsNothing);
        final card = tester.getSize(find.byKey(const Key('app-book-card')));
        expect(card.width / card.height, closeTo(.65, .01));
        expect(find.text('0%'), findsNothing);
        expect(find.byKey(const Key('app-book-card-bottom-bar')), findsNothing);
        expect(find.byTooltip('Add to favorites'), findsNothing);
      }
    },
  );

  testWidgets('browser renders accessible root with lazy cover widget', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final gateway = _Gateway(
      _page(
        navigation: [
          RemoteCatalogNavigationLink(
            title: 'Fiction',
            location: _location('/fiction'),
          ),
        ],
        publications: [
          RemoteCatalogPublicationSummary(
            remoteId: 'book',
            title: 'Readable Book',
            authors: ['A. Author'],
            summary: 'A summary',
            coverLocation: _location('/cover.jpg'),
            hasAcquisition: true,
          ),
        ],
        next: _location('/page-2'),
      ),
    )..pendingRoot = Completer<RemoteCatalogPage>();

    await tester.pumpWidget(_browserApp(gateway));
    await tester.pump();
    expect(find.bySemanticsLabel('Loading catalog'), findsOneWidget);
    gateway.pendingRoot!.complete(gateway.root);
    await tester.pump();

    expect(find.text('Root Feed'), findsOneWidget);
    expect(find.bySemanticsLabel('Open category Fiction'), findsOneWidget);
    expect(find.text('Readable Book'), findsOneWidget);
    expect(find.text('A. Author'), findsOneWidget);
    expect(find.text('Available from this catalog'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    expect(gateway.rootCalls, 1);
    semantics.dispose();
  });

  testWidgets(
    'semantic category activation requests once and remote back wins',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final gateway = _Gateway(
        _page(
          navigation: [
            RemoteCatalogNavigationLink(
              title: 'Fiction',
              location: _location('/fiction'),
            ),
          ],
        ),
      )..pages[_location('/fiction')] = _page(title: 'Fiction Feed');
      var parentVisible = true;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allBooksProvider.overrideWithValue(
              const AsyncData(<LibraryBook>[]),
            ),
            appDatabaseProvider.overrideWith((ref) {
              final database = AppDatabase(NativeDatabase.memory());
              ref.onDispose(database.close);
              return database;
            }),
            catalogSourceRepositoryProvider.overrideWithValue(
              _Repository(_source()),
            ),
            remoteCatalogGatewayProvider.overrideWithValue(gateway),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => StatefulBuilder(
                builder: (context, setState) => parentVisible
                    ? Scaffold(
                        body: FilledButton(
                          onPressed: () {
                            parentVisible = false;
                            Navigator.of(context)
                                .push<void>(
                                  MaterialPageRoute(
                                    builder: (_) => const CatalogBrowserScreen(
                                      sourceId: 'source',
                                    ),
                                  ),
                                )
                                .then(
                                  (_) => setState(() => parentVisible = true),
                                );
                          },
                          child: const Text('Open browser'),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open browser'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Open category Fiction'));
      await tester.pumpAndSettle();
      expect(find.text('Fiction Feed'), findsOneWidget);
      expect(gateway.pageCalls, 1);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Root Feed'), findsOneWidget);
      expect(find.text('Open browser'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Open browser'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('offline failure is announced and offers settings and retry', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final gateway = _Gateway(_page())
      ..error = const RemoteCatalogException.accessDenied();
    await tester.pumpWidget(_browserApp(gateway));
    await tester.pump();

    expect(
      find.bySemanticsLabel('Catalog unavailable while Offline'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Connectivity settings'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('publication semantic activation opens details once', (
    tester,
  ) async {
    final gateway = _Gateway(
      _page(
        publications: [
          RemoteCatalogPublicationSummary(
            remoteId: 'book',
            title: 'Readable Book',
            authors: const ['A. Author'],
            hasAcquisition: true,
          ),
        ],
      ),
    );
    final router = GoRouter(
      initialLocation: '/browser',
      routes: [
        GoRoute(
          path: '/browser',
          builder: (_, _) => const CatalogBrowserScreen(sourceId: 'source'),
        ),
        GoRoute(
          path: AppRoutes.publicationOnlineLibraryPath,
          name: AppRoutes.publicationOnlineLibraryName,
          builder: (_, state) => RemotePublicationDetailsScreen(
            request: state.extra! as RemotePublicationDetailsRequest,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allBooksProvider.overrideWithValue(const AsyncData(<LibraryBook>[])),
          appDatabaseProvider.overrideWith((ref) {
            final database = AppDatabase(NativeDatabase.memory());
            ref.onDispose(database.close);
            return database;
          }),
          catalogSourceRepositoryProvider.overrideWithValue(
            _Repository(_source()),
          ),
          remoteCatalogGatewayProvider.overrideWithValue(gateway),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Readable Book'));
    await tester.tap(find.text('Readable Book'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('book-details-title')), findsOneWidget);
    expect(gateway.rootCalls, 1);
  });

  testWidgets(
    'source rows expose enabled Browse only and render eagerly safe',
    (tester) async {
      final gateway = _Gateway(_page());
      final enabled = _source();
      final disabled = _source(id: 'disabled', enabled: false);
      final router = GoRouter(
        initialLocation: '/sources',
        routes: [
          GoRoute(
            path: '/sources',
            builder: (_, _) => const CatalogSourcesScreen(),
          ),
          GoRoute(
            path: AppRoutes.browseOnlineLibraryPath,
            name: AppRoutes.browseOnlineLibraryName,
            builder: (_, state) =>
                Text('Browsing ${state.pathParameters['sourceId']}'),
          ),
          GoRoute(
            path: AppRoutes.addOnlineLibraryPath,
            name: AppRoutes.addOnlineLibraryName,
            builder: (_, _) => const Text('Add'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allBooksProvider.overrideWithValue(
              const AsyncData(<LibraryBook>[]),
            ),
            appDatabaseProvider.overrideWith((ref) {
              final database = AppDatabase(NativeDatabase.memory());
              ref.onDispose(database.close);
              return database;
            }),
            catalogSourcesProvider.overrideWith(
              (ref) => Stream.value([enabled, disabled]),
            ),
            onlineAccessAllowedProvider.overrideWithValue(true),
            remoteCatalogGatewayProvider.overrideWithValue(gateway),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      expect(gateway.calls, 0);
      final enabledBrowse = find.bySemanticsLabel('Browse Library');
      final disabledBrowse = find.bySemanticsLabel('Browse Disabled');
      expect(enabledBrowse, findsOneWidget);
      expect(disabledBrowse, findsOneWidget);
      expect(
        tester
            .getSemantics(disabledBrowse)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
      );

      await tester.tap(enabledBrowse);
      await tester.pumpAndSettle();
      expect(find.text('Browsing source'), findsOneWidget);
      expect(gateway.calls, 0);
    },
  );
}

Widget _browserApp(_Gateway gateway) => ProviderScope(
  overrides: [
    allBooksProvider.overrideWithValue(const AsyncData(<LibraryBook>[])),
    appDatabaseProvider.overrideWith((ref) {
      final database = AppDatabase(NativeDatabase.memory());
      ref.onDispose(database.close);
      return database;
    }),
    catalogSourceRepositoryProvider.overrideWithValue(_Repository(_source())),
    remoteCatalogGatewayProvider.overrideWithValue(gateway),
  ],
  child: const MaterialApp(home: CatalogBrowserScreen(sourceId: 'source')),
);

CatalogSource _source({String id = 'source', bool enabled = true}) =>
    CatalogSource(
      id: id,
      name: id == 'source' ? 'Library' : 'Disabled',
      baseUri: Uri.parse('https://catalog.example/root'),
      type: CatalogSourceType.opds1,
      isBuiltIn: true,
      isEnabled: enabled,
      supportsSearch: false,
      supportsNavigation: true,
      supportsAcquisition: true,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

RemoteCatalogLocation _location(String path) =>
    RemoteCatalogLocation.parse('https://catalog.example$path');

RemoteCatalogPage _page({
  String title = 'Root Feed',
  RemoteCatalogLocation? location,
  List<RemoteCatalogNavigationLink> navigation = const [],
  List<RemoteCatalogPublicationSummary> publications = const [],
  RemoteCatalogLocation? next,
}) => RemoteCatalogPage(
  sourceId: 'source',
  location: location ?? _location('/root'),
  title: title,
  navigation: navigation,
  publications: publications,
  nextPageLocation: next,
);

class _Gateway implements RemoteCatalogGateway {
  _Gateway(this.root);
  RemoteCatalogPage root;
  final pages = <RemoteCatalogLocation, RemoteCatalogPage>{};
  Object? error;
  Completer<RemoteCatalogPage>? pendingRoot;
  int rootCalls = 0;
  int pageCalls = 0;
  int get calls => rootCalls + pageCalls;

  @override
  Future<RemoteCatalogPage> loadRoot(CatalogSource source) async {
    rootCalls++;
    if (error case final controlled?) throw controlled;
    if (pendingRoot case final controlled?) return controlled.future;
    return root;
  }

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) async {
    pageCalls++;
    if (error case final controlled?) throw controlled;
    return pages[location] ??
        (location == root.location ? root : throw StateError('Unknown page'));
  }

  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) => throw UnimplementedError();
}

class _Repository implements CatalogSourceRepository {
  _Repository(this.source);
  final CatalogSource source;
  @override
  Future<CatalogSource?> getById(String id) async => source;
  @override
  Future<List<CatalogSource>> getAll() async => [source];
  @override
  Stream<List<CatalogSource>> watchAll() => Stream.value([source]);
  @override
  Future<void> ensureBuiltInSources() async {}
  @override
  Future<CatalogSource> addCustomSource({
    required String name,
    required Uri baseUri,
  }) => throw UnimplementedError();
  @override
  Future<void> deleteCustomSource(String id) => throw UnimplementedError();
  @override
  Future<bool> normalizedUrlExists(Uri uri, {String? excludingSourceId}) =>
      throw UnimplementedError();
  @override
  Future<void> setEnabled({required String id, required bool enabled}) =>
      throw UnimplementedError();
  @override
  Future<void> updateCustomSource({
    required String id,
    required String name,
    required Uri baseUri,
  }) => throw UnimplementedError();
}

Finder _browserScrollable() => find
    .descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    )
    .first;
ScrollPosition _browserPosition(WidgetTester tester) =>
    tester.state<ScrollableState>(_browserScrollable()).position;
RemoteCatalogPublicationSummary _publication(int index) =>
    RemoteCatalogPublicationSummary(
      remoteId: 'pub-$index',
      title: 'Publication $index',
      authors: ['Author $index'],
    );
RemoteCatalogPage _layoutPage({
  int count = 3,
  RemoteCatalogLocation? location,
  String title = 'Root Feed',
  RemoteCatalogLocation? next,
}) => _page(
  title: title,
  location: location,
  navigation: [
    RemoteCatalogNavigationLink(
      title: 'Fiction',
      location: _location('/fiction'),
    ),
    RemoteCatalogNavigationLink(
      title: 'Science',
      location: _location('/science'),
    ),
  ],
  publications: List.generate(count, _publication),
  next: next,
);

Future<_LayoutHarness> _layoutHarness(
  WidgetTester tester, {
  LibraryViewMode saved = LibraryViewMode.grid,
  RemoteCatalogPage? root,
}) async {
  final database = AppDatabase(NativeDatabase.memory());
  final storage = DriftBookDisplaySettingsRepository(database);
  await tester.runAsync(() async {
    if (saved != LibraryViewMode.grid) await storage.save(saved.name);
  });
  final gateway = _Gateway(root ?? _layoutPage());
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      catalogSourceRepositoryProvider.overrideWithValue(
        _LayoutSourceRepository(),
      ),
      remoteCatalogGatewayProvider.overrideWithValue(gateway),
    ],
  );
  await tester.runAsync(() async {
    container.read(libraryViewModeProvider);
    await container.read(libraryViewModeProvider.notifier).ready;
  });
  final requests = <RemotePublicationDetailsRequest>[];
  final router = GoRouter(
    initialLocation: '/online-libraries/source/browse',
    routes: [
      GoRoute(
        path: AppRoutes.browseOnlineLibraryPath,
        builder: (_, state) =>
            CatalogBrowserScreen(sourceId: state.pathParameters['sourceId']!),
      ),
      GoRoute(
        path: AppRoutes.publicationOnlineLibraryPath,
        name: AppRoutes.publicationOnlineLibraryName,
        builder: (_, state) {
          final request = state.extra! as RemotePublicationDetailsRequest;
          requests.add(request);
          return Scaffold(
            body: Text(
              'Remote details:${state.pathParameters['sourceId']}:${request.publication.remoteId}',
            ),
          );
        },
      ),
      GoRoute(
        path: '/layout-settings',
        builder: (_, _) => const Scaffold(body: BookDisplayLayoutSettingTile()),
      ),
      GoRoute(
        path: '/library-toggle',
        builder: (_, _) => Scaffold(
          body: Consumer(
            builder: (_, ref, _) => LibraryViewToggle(
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
    await tester.runAsync(database.close);
  });
  return _LayoutHarness(container, gateway, storage, router, requests);
}

class _LayoutHarness {
  _LayoutHarness(
    this.container,
    this.gateway,
    this.storage,
    this.router,
    this.requests,
  );
  final ProviderContainer container;
  final _Gateway gateway;
  final DriftBookDisplaySettingsRepository storage;
  final GoRouter router;
  final List<RemotePublicationDetailsRequest> requests;
  CatalogBrowserController get controller =>
      container.read(catalogBrowserControllerProvider('source').notifier);
  CatalogBrowserState get state =>
      container.read(catalogBrowserControllerProvider('source'));
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

class _LayoutSourceRepository extends _Repository {
  _LayoutSourceRepository() : super(_source());
  @override
  Future<CatalogSource?> getById(String id) async => _source(id: id);
}

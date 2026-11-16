import '../../support/unified_book_list_assertions.dart';
import 'package:bibliolife/app/theme/app_theme.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_search_controller.dart';
import 'package:bibliolife/features/catalog_sources/presentation/widgets/remote_catalog_book_card.dart';
import 'package:bibliolife/features/catalog_sources/presentation/widgets/remote_catalog_book_tile.dart';
import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:bibliolife/features/library/data/repositories/drift_book_display_settings_repository.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_view_toggle.dart';
import 'package:bibliolife/features/settings/presentation/widgets/settings_body.dart';
import 'package:bibliolife/shared/presentation/widgets/app_book_list_tile.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_image.dart';
import 'package:bibliolife/shared/models/book_cover_reference.dart';
import 'package:flutter/rendering.dart' show SemanticsAction;
import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/core/database/database_provider.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'dart:async';

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
import 'package:bibliolife/features/catalog_sources/presentation/screens/catalog_search_screen.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/remote_publication_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets(
    'default Grid uses existing cards with natural adaptive and lazy rows',
    (tester) async {
      final h = await _layoutHarness(tester, count: 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(400, 900);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      expect(h.gateway.calls, 0);
      await _submit(tester, 'cats');
      for (final entry in [(400.0, 2), (700.0, 3), (1000.0, 4)]) {
        tester.view.physicalSize = Size(entry.$1, 900);
        await tester.pumpAndSettle();
        final first = tester.getRect(
          find.byKey(const ValueKey('catalog-search-publication-pub-0')),
        );
        final next = tester.getRect(
          find.byKey(const ValueKey('catalog-search-publication-pub-1')),
        );
        expect(
          first.width,
          closeTo((entry.$1 - 32 - 16 * (entry.$2 - 1)) / entry.$2, .01),
        );
        expect(next.left - first.right, closeTo(16, .01));
        expect(
          find.byType(RemoteCatalogBookCard).evaluate().length,
          lessThan(30),
        );
        expect(find.byType(RemoteCatalogBookTile), findsNothing);
        final cover = tester.getSize(
          find.byKey(const Key('app-book-card')).first,
        );
        expect(cover.width / cover.height, closeTo(.65, .01));
        expect(find.text('0%'), findsNothing);
        expect(find.byType(GridView), findsNothing);
      }
      expect(h.gateway.calls, 1);
    },
  );

  testWidgets('persisted List uses RemoteCatalogBookTile and AppBookListTile', (
    tester,
  ) async {
    final h = await _layoutHarness(tester, saved: LibraryViewMode.list);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    await _submit(tester, 'cats');
    expect(find.byType(RemoteCatalogBookTile), findsNWidgets(3));
    expect(find.byType(AppBookListTile), findsNWidgets(3));
    expectUnifiedBookList(tester);
    expect(find.byType(RemoteCatalogBookCard), findsNothing);
    expect(await tester.runAsync(h.storage.load), 'list');
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.byIcon(Icons.favorite_border), findsNothing);
  });

  testWidgets(
    'reactive layouts preserve text, focus, controllers, results and cursor without requests',
    (tester) async {
      final h = await _layoutHarness(tester, next: _location('/page-2'));
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      await _submit(tester, '  CATS  ');
      final bar = tester.element(find.byType(SearchBar));
      final focus = tester.widget<SearchBar>(find.byType(SearchBar)).focusNode!;
      final text = tester.widget<SearchBar>(find.byType(SearchBar)).controller!;
      final page = h.state.page;
      final controller = h.controller;
      final lookups = h.repository.lookups;
      expect(focus.hasFocus, isTrue);
      for (final mode in [LibraryViewMode.list, LibraryViewMode.grid]) {
        await h.setMode(tester, mode);
        expect(
          mode == LibraryViewMode.grid
              ? find.byType(RemoteCatalogBookCard)
              : find.byType(RemoteCatalogBookTile),
          findsWidgets,
        );
        expect(
          tester.element(find.byType(SearchBar, skipOffstage: false)),
          same(bar),
        );
        expect(
          tester.widget<SearchBar>(find.byType(SearchBar)).controller,
          same(text),
        );
        expect(text.text, '  CATS  ');
        expect(focus.hasFocus, isTrue);
        expect(h.controller, same(controller));
        expect(h.state.page, same(page));
        expect(h.state.query, 'CATS');
        expect(h.state.capability, same(h.capability));
        expect(h.state.page!.nextPageLocation, _location('/page-2'));
        expect(h.repository.lookups, lookups);
        expect(h.gateway.calls, 1);
        expect(h.gateway.pageCalls, 0);
      }
    },
  );

  testWidgets(
    'unfocused field and closed keyboard stay unchanged on layout switch',
    (tester) async {
      final h = await _layoutHarness(tester);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      await _submit(tester, 'cats');
      final focus = tester.widget<SearchBar>(find.byType(SearchBar)).focusNode!;
      focus.unfocus();
      await tester.pumpAndSettle();
      tester.testTextInput.hide();
      await h.setMode(tester, LibraryViewMode.list);
      expect(focus.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(h.gateway.calls, 1);
    },
  );

  for (final route in ['/layout-settings', '/library-toggle']) {
    testWidgets(
      'existing global control $route reacts without another search',
      (tester) async {
        final h = await _layoutHarness(tester);
        await tester.pumpWidget(h.app());
        await tester.pumpAndSettle();
        await _submit(tester, 'cats');
        final page = h.state.page;
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
        expect(h.state.page, same(page));
        expect(h.gateway.calls, 1);
        expect(
          tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
          'cats',
        );
      },
    );
  }

  for (final mode in LibraryViewMode.values) {
    testWidgets(
      'manual pagination preserves identity ordering and deduplication in $mode',
      (tester) async {
        final h = await _layoutHarness(
          tester,
          saved: mode,
          next: _location('/page-2'),
        );
        h.gateway.pages[_location('/page-2')] = _results(
          count: 2,
          first: 2,
          query: 'cats',
        );
        await tester.pumpWidget(h.app());
        await tester.pumpAndSettle();
        await _submit(tester, 'cats');
        final successful = h.state.lastSuccessfulQuery;
        await tester.scrollUntilVisible(
          find.text('Load more'),
          200,
          scrollable: _searchScrollable(),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Load more'));
        await tester.pumpAndSettle();
        expect(h.state.page!.publications.map((p) => p.remoteId), [
          'pub-0',
          'pub-1',
          'pub-2',
          'pub-3',
        ]);
        expect(h.state.lastSuccessfulQuery, successful);
        expect(h.gateway.pageCalls, 1);
        expect(find.text('Load more'), findsNothing);
        await h.setMode(
          tester,
          mode == LibraryViewMode.grid
              ? LibraryViewMode.list
              : LibraryViewMode.grid,
        );
        expect(h.gateway.calls, 1);
        expect(h.gateway.pageCalls, 1);
        expect(h.state.page!.publications, hasLength(4));
      },
    );

    testWidgets(
      'correct source/publication Details route and back preserve state in $mode',
      (tester) async {
        final h = await _layoutHarness(
          tester,
          saved: mode,
          next: _location('/page-2'),
        );
        await tester.pumpWidget(h.app());
        await tester.pumpAndSettle();
        await _submit(tester, 'cats');
        final page = h.state.page;
        await tester.ensureVisible(find.text('Result 1'));
        await tester.pumpAndSettle();
        final offset = _searchPosition(tester).pixels;
        await tester.tap(find.text('Result 1'));
        await tester.pumpAndSettle();
        expect(find.text('Details:source:pub-1'), findsOneWidget);
        expect(h.requests, hasLength(1));
        expect(h.requests.single.sourceId, 'source');
        expect(h.requests.single.sourceName, 'Library');
        expect(h.requests.single.publication, same(page!.publications[1]));
        h.router.pop();
        await tester.pumpAndSettle();
        expect(h.state.page, same(page));
        expect(h.state.page!.nextPageLocation, _location('/page-2'));
        expect(h.container.read(libraryViewModeProvider), mode);
        expect(_searchPosition(tester).pixels, closeTo(offset, 1));
        // Larger rows may lazily unmount the offscreen search header.
        // Verify the restored offset first, then reveal its retained query.
        _searchPosition(tester).jumpTo(0);
        await tester.pumpAndSettle();
        expect(
          tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
          'cats',
        );
        expect(h.gateway.calls, 1);
      },
    );
  }

  testWidgets(
    'pending initial search can change layout without another request or lost completion',
    (tester) async {
      final h = await _layoutHarness(tester);
      h.gateway.pendingSearch = Completer<RemoteCatalogPage>();
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(SearchBar), 'cats');
      final pending = h.controller.submit('cats');
      await tester.pump();
      final lookups = h.repository.lookups;
      await tester.runAsync(
        () => h.container
            .read(libraryViewModeProvider.notifier)
            .setMode(LibraryViewMode.list),
      );
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(h.gateway.calls, 1);
      expect(h.repository.lookups, lookups);
      h.gateway.pendingSearch!.complete(_results(query: 'cats'));
      await tester.pumpAndSettle();
      await pending;
      expect(find.byType(RemoteCatalogBookTile), findsWidgets);
      expect(h.gateway.calls, 1);
    },
  );

  testWidgets(
    'pending pagination retains cursor and appends once after mode change',
    (tester) async {
      final h = await _layoutHarness(tester, next: _location('/page-2'));
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      await _submit(tester, 'cats');
      h.gateway.pendingPage = Completer<RemoteCatalogPage>();
      final pending = h.controller.loadNextPage();
      await tester.pump();
      await h.setMode(tester, LibraryViewMode.list);
      expect(h.state.page!.nextPageLocation, _location('/page-2'));
      expect(h.gateway.pageCalls, 1);
      expect(h.gateway.calls, 1);
      expect(h.state.page!.publications, hasLength(3));
      h.gateway.pendingPage!.complete(
        _results(count: 2, first: 2, query: 'cats'),
      );
      await tester.pumpAndSettle();
      await pending;
      expect(h.state.page!.publications, hasLength(4));
      expect(h.gateway.pageCalls, 1);
    },
  );

  testWidgets(
    'pagination failure retries the same cursor and layout does not retry automatically',
    (tester) async {
      final h = await _layoutHarness(tester, next: _location('/page-2'));
      h.gateway.pageError = const RemoteCatalogException.accessDenied();
      h.gateway.pages[_location('/page-2')] = _results(
        count: 2,
        first: 2,
        query: 'cats',
      );
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      await _submit(tester, 'cats');
      await h.controller.loadNextPage();
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      await h.setMode(tester, LibraryViewMode.list);
      expect(h.gateway.pageCalls, 1);
      expect(h.state.page!.nextPageLocation, _location('/page-2'));
      h.gateway.pageError = null;
      await tester.ensureVisible(find.text('Retry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(h.gateway.pageCalls, 2);
      expect(h.gateway.requestedPages, [
        _location('/page-2'),
        _location('/page-2'),
      ]);
      expect(h.state.page!.publications, hasLength(4));
      expect(find.byType(RemoteCatalogBookTile), findsWidgets);
    },
  );

  testWidgets(
    'successful-query offsets are mode aware and new or repeated queries start fresh',
    (tester) async {
      final h = await _layoutHarness(tester, count: 200);
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      await _submit(tester, 'cats');
      final bar = tester.element(find.byType(SearchBar));
      _searchPosition(tester).jumpTo(1600);
      await tester.pumpAndSettle();
      await h.setMode(tester, LibraryViewMode.list);
      expect(_searchPosition(tester).pixels, 0);
      _searchPosition(tester).jumpTo(700);
      await tester.pumpAndSettle();
      await h.setMode(tester, LibraryViewMode.grid);
      expect(_searchPosition(tester).pixels, closeTo(1600, 1));
      await h.setMode(tester, LibraryViewMode.list);
      expect(_searchPosition(tester).pixels, closeTo(700, 1));
      expect(
        find.byType(RemoteCatalogBookTile).evaluate().length,
        lessThan(30),
      );
      expect(
        tester.element(find.byType(SearchBar, skipOffstage: false)),
        same(bar),
      );
      _searchPosition(tester).jumpTo(0);
      await tester.pumpAndSettle();
      await _submit(tester, 'dogs');
      expect(_searchPosition(tester).pixels, 0);
      await h.setMode(tester, LibraryViewMode.grid);
      expect(_searchPosition(tester).pixels, 0);
      await _submit(tester, 'cats');
      expect(_searchPosition(tester).pixels, 0);
      await h.setMode(tester, LibraryViewMode.list);
      expect(_searchPosition(tester).pixels, 0);
      expect(h.gateway.calls, 3);
    },
  );

  testWidgets('source offsets and Details back remain independent', (
    tester,
  ) async {
    final h = await _layoutHarness(tester, count: 200);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    await _submit(tester, 'cats');
    _searchPosition(tester).jumpTo(1300);
    await tester.pumpAndSettle();
    final card = find.byType(RemoteCatalogBookCard).hitTestable().first;
    final id = tester.widget<RemoteCatalogBookCard>(card).publication.remoteId;
    final offset = _searchPosition(tester).pixels;
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.text('Details:source:$id'), findsOneWidget);
    h.router.pop();
    await tester.pumpAndSettle();
    expect(_searchPosition(tester).pixels, closeTo(offset, 1));
    h.router.push('/online-libraries/other/search');
    await tester.pumpAndSettle();
    await _submit(tester, 'cats');
    expect(_searchPosition(tester).pixels, 0);
    expect(
      h.container.read(catalogSearchControllerProvider('other')).sourceId,
      'other',
    );
    h.router.pop();
    await tester.pumpAndSettle();
    expect(_searchPosition(tester).pixels, closeTo(offset, 1));
  });

  testWidgets('shorter refreshed results safely clamp saved offsets', (
    tester,
  ) async {
    final h = await _layoutHarness(tester, count: 200);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    await _submit(tester, 'cats');
    _searchPosition(tester).jumpTo(2500);
    await tester.pumpAndSettle();
    await h.setMode(tester, LibraryViewMode.list);
    h.gateway.results = [_publication(0)];
    await h.controller.submit('cats');
    await tester.pumpAndSettle();
    await h.setMode(tester, LibraryViewMode.grid);
    final position = _searchPosition(tester);
    expect(
      position.pixels,
      inInclusiveRange(position.minScrollExtent, position.maxScrollExtent),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Clear retains capability and does not execute another query', (
    tester,
  ) async {
    final h = await _layoutHarness(tester, saved: LibraryViewMode.list);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    await _submit(tester, 'cats');
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
      isEmpty,
    );
    expect(find.text('Enter a query and select Search.'), findsOneWidget);
    expect(h.state.page, isNull);
    expect(h.state.capability, same(h.capability));
    expect(h.gateway.calls, 1);
  });

  testWidgets(
    'missing cover and authors use existing shared List without local actions',
    (tester) async {
      final h = await _layoutHarness(tester, saved: LibraryViewMode.list);
      h.gateway.results = [
        RemoteCatalogPublicationSummary(
          remoteId: 'missing',
          title: 'Missing data',
        ),
      ];
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      await _submit(tester, 'cats');
      final tile = tester.widget<AppBookListTile>(find.byType(AppBookListTile));
      expect(tile.metadata, isNull);
      expect(tile.actions.single, isA<AppBookListActionPlaceholder>());
      expect(tile.status, isNull);
      expect(
        tester.widget<BookCoverImage>(find.byType(BookCoverImage)).cover,
        isA<MissingBookCover>(),
      );
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
    },
  );

  testWidgets('remote List semantics opens exactly once', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await _layoutHarness(tester, saved: LibraryViewMode.list);
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    await _submit(tester, 'cats');
    final node = tester.getSemantics(find.byType(RemoteCatalogBookTile).first);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(h.requests, hasLength(1));
    expect(h.requests.single.publication.remoteId, 'pub-0');
    semantics.dispose();
  });

  testWidgets(
    'unsupported and offline modes do not initialize or retry on layout change',
    (tester) async {
      final h = await _layoutHarness(
        tester,
        capability: const RemoteCatalogSearchCapability.unsupported(),
      );
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      final lookups = h.repository.lookups;
      await h.setMode(tester, LibraryViewMode.list);
      expect(
        find.text('Search is not available for this library.'),
        findsOneWidget,
      );
      expect(h.repository.lookups, lookups);
      expect(h.gateway.calls, 0);
    },
  );

  testWidgets('offline failure retries only on user action and retains query', (
    tester,
  ) async {
    final h = await _layoutHarness(tester);
    h.gateway.error = const RemoteCatalogException.accessDenied();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    await _submit(tester, 'cats');
    await h.setMode(tester, LibraryViewMode.list);
    expect(find.text('Connectivity settings'), findsOneWidget);
    expect(h.gateway.calls, 1);
    h.gateway.error = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(h.gateway.calls, 2);
    expect(find.byType(RemoteCatalogBookTile), findsWidgets);
    expect(
      tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
      'cats',
    );
  });

  for (final dark in [false, true]) {
    for (final mode in LibraryViewMode.values) {
      testWidgets('long metadata is safe at 320px text2 in $mode, dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = await _layoutHarness(tester, saved: mode);
        h.gateway.results = [
          RemoteCatalogPublicationSummary(
            remoteId: 'long',
            title: 'An exceptionally long book title with many words',
            authors: ['A very long author name', 'Another long name'],
          ),
        ];
        await tester.pumpWidget(h.app(dark: dark, textScale: 2));
        await tester.pumpAndSettle();
        await _submit(tester, 'cats');
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
    'search book cards keep natural metadata height at phone scales',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final scale in [1.0, 1.5]) {
        final gateway = _Gateway()
          ..result = RemoteCatalogPublicationSummary(
            remoteId: 'green-mummy-$scale',
            title: 'The Green Mummy',
            authors: const ['Hume, Fergus'],
            hasAcquisition: true,
          );
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: _app(gateway),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(SearchBar), 'green mummy');
        await tester.tap(find.byTooltip('Submit catalog search'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('The Green Mummy'), findsOneWidget);
        expect(find.text('Hume, Fergus'), findsOneWidget);
        expect(find.text('Available from this catalog'), findsNothing);
        final card = tester.getSize(find.byKey(const Key('app-book-card')));
        expect(card.width / card.height, closeTo(.65, .01));
        expect(find.text('0%'), findsNothing);
        expect(find.byTooltip('Add to favorites'), findsNothing);
      }
    },
  );

  testWidgets('opening and typing are eager-safe; semantic submit runs once', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final gateway = _Gateway();
    await tester.pumpWidget(_app(gateway));
    await tester.pump();

    expect(find.text('Enter a query and select Search.'), findsOneWidget);
    expect(gateway.calls, 0);
    await tester.enterText(find.byType(SearchBar), 'Unicode книга');
    await tester.pump();
    expect(gateway.calls, 0);

    await tester.tap(find.byTooltip('Submit catalog search'));
    await tester.pump();
    expect(gateway.calls, 1);
    expect(find.bySemanticsLabel('1 search results'), findsOneWidget);
    expect(find.text('Result Book'), findsOneWidget);
    expect(find.text('A. Author'), findsOneWidget);
    final cover = tester.widget<Image>(find.byType(Image));
    expect(cover.image, isA<ResizeImage>());
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('unsupported and Offline states are announced', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        _Gateway(),
        capability: const RemoteCatalogSearchCapability.unsupported(),
      ),
    );
    await tester.pump();
    expect(
      find.text('Search is not available for this library.'),
      findsOneWidget,
    );

    final gateway = _Gateway()
      ..error = const RemoteCatalogException.accessDenied();
    await tester.pumpWidget(_app(gateway));
    await tester.pump();
    await tester.enterText(find.byType(SearchBar), 'book');
    await tester.tap(find.byTooltip('Submit catalog search'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Search unavailable while Offline',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Connectivity settings'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
    'search publication activation opens details without new request',
    (tester) async {
      final gateway = _Gateway();
      final router = GoRouter(
        initialLocation: '/search-catalog',
        routes: [
          GoRoute(
            path: '/search-catalog',
            builder: (_, _) => CatalogSearchScreen(
              sourceId: 'source',
              capability: _capability(),
            ),
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
            appDatabaseProvider.overrideWith((ref) {
              final database = AppDatabase(
                DatabaseConnection(
                  NativeDatabase.memory(),
                  closeStreamsSynchronously: true,
                ),
              );
              ref.onDispose(database.close);
              return database;
            }),
            catalogSourceRepositoryProvider.overrideWithValue(_Repository()),
            remoteCatalogGatewayProvider.overrideWithValue(gateway),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(SearchBar), 'book');
      await tester.tap(find.byTooltip('Submit catalog search'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Result Book'));
      await tester.tap(find.text('Result Book'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('book-details-title')), findsOneWidget);
      expect(gateway.calls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

Widget _app(_Gateway gateway, {RemoteCatalogSearchCapability? capability}) =>
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        appDatabaseProvider.overrideWith((ref) {
          final database = AppDatabase(
            DatabaseConnection(
              NativeDatabase.memory(),
              closeStreamsSynchronously: true,
            ),
          );
          ref.onDispose(database.close);
          return database;
        }),
        catalogSourceRepositoryProvider.overrideWithValue(_Repository()),
        remoteCatalogGatewayProvider.overrideWithValue(gateway),
      ],
      child: MaterialApp(
        home: CatalogSearchScreen(
          sourceId: 'source',
          capability: capability ?? _capability(),
        ),
      ),
    );

RemoteCatalogSearchCapability _capability() =>
    RemoteCatalogSearchCapability.directTemplate(
      RemoteCatalogLocation.parse(
        'https://catalog.example/find?q=%7BsearchTerms%7D',
      ),
    );

CatalogSource _source({String id = 'source'}) => CatalogSource(
  id: id,
  name: 'Library',
  baseUri: Uri.parse('https://catalog.example/root'),
  type: CatalogSourceType.opds1,
  isBuiltIn: true,
  isEnabled: true,
  supportsSearch: true,
  supportsNavigation: true,
  supportsAcquisition: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _Gateway implements RemoteCatalogGateway {
  int calls = 0;
  Object? error;
  RemoteCatalogPublicationSummary? result;
  List<RemoteCatalogPublicationSummary>? results;
  RemoteCatalogLocation? next;
  final pages = <RemoteCatalogLocation, RemoteCatalogPage>{};
  int pageCalls = 0;
  final requestedPages = <RemoteCatalogLocation>[];
  Object? pageError;
  Completer<RemoteCatalogPage>? pendingSearch;
  Completer<RemoteCatalogPage>? pendingPage;
  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) async {
    calls++;
    if (error case final controlled?) throw controlled;
    if (pendingSearch case final pending?) return pending.future;
    return RemoteCatalogPage(
      sourceId: source.id,
      location: RemoteCatalogLocation.parse(
        'https://catalog.example/find?q=book',
      ),
      title: 'Results',
      nextPageLocation: next,
      publications:
          results ??
          [
            result ??
                RemoteCatalogPublicationSummary(
                  remoteId: 'book',
                  title: 'Result Book',
                  authors: ['A. Author'],
                  coverLocation: RemoteCatalogLocation.parse(
                    'https://catalog.example/cover.jpg',
                  ),
                  hasAcquisition: true,
                ),
          ],
    );
  }

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) async {
    pageCalls++;
    requestedPages.add(location);
    if (pageError case final controlled?) throw controlled;
    if (pendingPage case final pending?) return pending.future;
    return pages[location]!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository implements CatalogSourceRepository {
  int lookups = 0;
  @override
  Future<CatalogSource?> getById(String id) async {
    lookups++;
    return _source(id: id);
  }

  @override
  Future<List<CatalogSource>> getAll() async => [_source()];
  @override
  Stream<List<CatalogSource>> watchAll() => Stream.value([_source()]);
  @override
  Future<void> ensureBuiltInSources() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

RemoteCatalogLocation _location(String path) =>
    RemoteCatalogLocation.parse('https://catalog.example$path');
RemoteCatalogPublicationSummary _publication(int index) =>
    RemoteCatalogPublicationSummary(
      remoteId: 'pub-$index',
      title: 'Result $index',
      authors: ['Author $index'],
    );
RemoteCatalogPage _results({
  int count = 3,
  int first = 0,
  String query = 'cats',
  RemoteCatalogLocation? next,
}) => RemoteCatalogPage(
  sourceId: 'source',
  location: _location('/find?q=$query'),
  title: 'Results',
  publications: List.generate(count, (i) => _publication(first + i)),
  nextPageLocation: next,
);
Finder _searchScrollable() => find
    .descendant(
      of: find.byKey(const Key('catalog-search-scroll')),
      matching: find.byType(Scrollable),
    )
    .first;
ScrollPosition _searchPosition(WidgetTester tester) =>
    tester.state<ScrollableState>(_searchScrollable()).position;
Future<void> _submit(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(SearchBar), query);
  await tester.pump();
  await tester.tap(find.byTooltip('Submit catalog search'));
  await tester.pumpAndSettle();
}

Future<_LayoutHarness> _layoutHarness(
  WidgetTester tester, {
  LibraryViewMode saved = LibraryViewMode.grid,
  int count = 3,
  RemoteCatalogLocation? next,
  RemoteCatalogSearchCapability? capability,
}) async {
  final database = AppDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
  final storage = DriftBookDisplaySettingsRepository(database);
  await tester.runAsync(() async {
    if (saved != LibraryViewMode.grid) await storage.save(saved.name);
  });
  final gateway = _Gateway()
    ..results = List.generate(count, _publication)
    ..next = next;
  final repository = _Repository();
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      catalogSourceRepositoryProvider.overrideWithValue(repository),
      remoteCatalogGatewayProvider.overrideWithValue(gateway),
    ],
  );
  await tester.runAsync(() async {
    container.read(libraryViewModeProvider);
    await container.read(libraryViewModeProvider.notifier).ready;
  });
  final activeCapability = capability ?? _capability();
  final requests = <RemotePublicationDetailsRequest>[];
  final router = GoRouter(
    initialLocation: '/online-libraries/source/search',
    routes: [
      GoRoute(
        path: AppRoutes.searchOnlineLibraryPath,
        builder: (_, state) => CatalogSearchScreen(
          sourceId: state.pathParameters['sourceId']!,
          capability: activeCapability,
        ),
      ),
      GoRoute(
        path: AppRoutes.publicationOnlineLibraryPath,
        name: AppRoutes.publicationOnlineLibraryName,
        builder: (_, state) {
          final request = state.extra! as RemotePublicationDetailsRequest;
          requests.add(request);
          return Scaffold(
            body: Text(
              'Details:${state.pathParameters['sourceId']}:${request.publication.remoteId}',
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
  return _LayoutHarness(
    container,
    gateway,
    repository,
    storage,
    router,
    activeCapability,
    requests,
  );
}

class _LayoutHarness {
  _LayoutHarness(
    this.container,
    this.gateway,
    this.repository,
    this.storage,
    this.router,
    this.capability,
    this.requests,
  );
  final ProviderContainer container;
  final _Gateway gateway;
  final _Repository repository;
  final DriftBookDisplaySettingsRepository storage;
  final GoRouter router;
  final RemoteCatalogSearchCapability capability;
  final List<RemotePublicationDetailsRequest> requests;
  CatalogSearchController get controller =>
      container.read(catalogSearchControllerProvider('source').notifier);
  CatalogSearchState get state =>
      container.read(catalogSearchControllerProvider('source'));
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

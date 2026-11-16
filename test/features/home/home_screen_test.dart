import 'package:bibliolife/shared/presentation/widgets/app_context_menu.dart';
import 'package:bibliolife/features/library/application/providers/library_providers.dart';
import '../../support/unified_book_list_assertions.dart';
import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:bibliolife/shared/presentation/widgets/app_book_list_tile.dart';
import 'dart:async';
import 'dart:convert';

import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/app/theme/app_theme.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway_provider.dart';
import 'package:bibliolife/features/catalog_sources/data/http_opds_remote_catalog_transport.dart';
import 'package:bibliolife/features/catalog_sources/data/built_in_catalog_sources.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_acquisition.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_download_task.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/remote_publication_details_screen.dart';
import 'package:bibliolife/features/connectivity/application/app_connectivity_mode_provider.dart';
import 'package:bibliolife/features/home/application/providers/home_default_carousel_provider.dart';
import 'package:bibliolife/features/home/application/providers/online_home_sections_provider.dart';
import 'package:bibliolife/features/home/application/providers/home_online_tab_settings_provider.dart';
import 'package:bibliolife/features/home/application/providers/home_publication_page_cache.dart';
import 'package:bibliolife/features/home/application/providers/home_online_state_provider.dart';
import 'package:bibliolife/features/home/domain/models/home_online_book_state.dart';
import 'package:bibliolife/features/home/domain/models/online_home_section.dart';
import 'package:bibliolife/features/home/domain/models/remote_home_publication_identity.dart';
import 'package:bibliolife/features/home/domain/home_default_carousel_settings_repository.dart';
import 'package:bibliolife/features/home/presentation/screens/home_screen.dart';
import 'package:bibliolife/features/home/presentation/widgets/home_online_catalog_grid.dart';
import 'package:bibliolife/features/home/presentation/widgets/home_online_library_carousel.dart';
import 'package:bibliolife/features/home/presentation/widgets/home_local_book_carousel.dart';
import 'package:bibliolife/features/home/presentation/widgets/home_search_entry.dart';
import 'package:bibliolife/features/home/presentation/widgets/home_section_header.dart';
import 'package:bibliolife/features/library/application/providers/library_repository_provider.dart';
import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_providers.dart';
import 'package:bibliolife/features/reader/domain/models/reading_progress.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:bibliolife/shared/presentation/widgets/biblio_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      for (final opened in [false, true]) {
        testWidgets(
          'Phase33 Home local single reading status dark=$dark scale=$scale opened=$opened',
          (tester) async {
            await tester.binding.setSurfaceSize(const Size(320, 900));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final local = _book(
              id: 'imported',
              lastOpenedAt: opened
                  ? DateTime.now().subtract(const Duration(days: 3))
                  : null,
            );
            await tester.pumpWidget(
              _phase33Subject(
                local: local,
                phase: HomeOnlineBookPhase.inLibrary,
                dark: dark,
                scale: scale,
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.text(opened ? 'Opened 3 days ago' : 'Ready to read'),
              findsOneWidget,
            );
            expect(find.text('In library'), findsNothing);
            final bottom = find.byKey(const Key('book-list-bottom'));
            expect(
              find.descendant(of: bottom, matching: find.byType(Text)),
              findsOneWidget,
            );
            final tile = tester.widget<AppBookListTile>(
              find.byType(AppBookListTile),
            );
            expect(tile.status, isNull);
            expectUnifiedBookList(tester);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final local in [false, true]) {
    for (final entry in {
      HomeOnlineBookPhase.queued: 'Queued',
      HomeOnlineBookPhase.downloading: 'Downloading 50%',
      HomeOnlineBookPhase.importing: 'Importing',
      HomeOnlineBookPhase.failed: 'Retry',
      HomeOnlineBookPhase.readyToAdd: 'Ready to add',
    }.entries) {
      testWidgets(
        'Phase33 single operational status ${entry.key} local=$local',
        (tester) async {
          await tester.pumpWidget(
            _phase33Subject(
              local: local ? _book(id: 'imported') : null,
              phase: entry.key,
              metadata: const {'sale.saleability': 'FREE'},
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.text(entry.value), findsOneWidget);
          expect(find.text('In library'), findsNothing);
          expect(find.text('Ready to read'), findsNothing);
          expect(find.text('Read for free'), findsNothing);
          expect(find.byKey(const Key('book-list-status')), findsNothing);
          expect(
            find.descendant(
              of: find.byKey(const Key('book-list-bottom')),
              matching: find.byType(Text),
            ),
            findsOneWidget,
          );
          if (entry.key == HomeOnlineBookPhase.downloading) {
            expect(
              tester
                  .widget<CircularProgressIndicator>(
                    find.byType(CircularProgressIndicator),
                  )
                  .value,
              .5,
            );
          }
          expectUnifiedBookList(tester);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final entry in <Map<String, String>, String?>{
    const {'sale.saleability': 'FREE'}: 'Read for free',
    const {
      'sale.retailPrice.amount': '12.50',
      'sale.retailPrice.currencyCode': 'USD',
    }: 'Price: 12.50 USD',
    const {'sale.retailPrice.amount': '12.50'}: null,
    const {}: null,
  }.entries) {
    testWidgets(
      'Phase33 Home remote confirmed status ${entry.value ?? entry.key}',
      (tester) async {
        await tester.pumpWidget(
          _phase33Subject(
            metadata: entry.key,
            phase: HomeOnlineBookPhase.inLibrary,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('In library'), findsNothing);
        expect(find.text('Ready to read'), findsNothing);
        if (entry.value case final status?) {
          expect(find.text(status), findsOneWidget);
          expect(find.byKey(const Key('book-list-status')), findsOneWidget);
        } else {
          expect(find.byKey(const Key('book-list-bottom')), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Phase33 import completion replaces operation with local status',
    (tester) async {
      final local = _book(id: 'imported');
      final snapshot = ValueNotifier<HomeOnlineStateSnapshot>(
        _phase33Snapshot(phase: HomeOnlineBookPhase.importing),
      );
      addTearDown(snapshot.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder(
          valueListenable: snapshot,
          builder: (_, value, _) => _phase33Subject(snapshot: value),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Importing'), findsOneWidget);
      snapshot.value = _phase33Snapshot(
        phase: HomeOnlineBookPhase.inLibrary,
        local: local,
      );
      await tester.pumpAndSettle();
      expect(find.text('Ready to read'), findsOneWidget);
      expect(find.text('Importing'), findsNothing);
      expect(find.text('In library'), findsNothing);
      expect(find.byKey(const Key('book-list-status')), findsOneWidget);
      expectUnifiedBookList(tester);
    },
  );

  testWidgets('Phase33 Grid keeps legacy local availability indicator', (
    tester,
  ) async {
    await tester.pumpWidget(
      _phase33Subject(
        local: _book(id: 'imported'),
        phase: HomeOnlineBookPhase.inLibrary,
        mode: LibraryViewMode.grid,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('In library'), findsOneWidget);
    expect(find.text('Ready to read'), findsNothing);
    expect(find.byType(AppBookListTile), findsNothing);
  });

  testWidgets(
    'Phase33 List pending slot keeps reserved row without book status',
    (tester) async {
      await tester.pumpWidget(_phase33Subject(pending: true));
      await tester.pumpAndSettle();
      expect(find.byType(HomeOnlineReservedBookRow), findsOneWidget);
      expect(find.byKey(const Key('book-list-status')), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsNothing);
      expect(
        tester.getSize(find.byKey(const Key('book-list-cover'))),
        const Size(92, 138),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Home layouts keep slots, controller, offsets and avoid pagination reflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = _FakeOnlineController(
        AsyncData(
          _online(
            publications: List.generate(
              100,
              (i) => _publication('$i', 'Remote $i'),
            ),
            hasMore: true,
          ),
        ),
      );
      await tester.pumpWidget(
        _subject(
          books: [_book(id: 'local', lastOpenedAt: DateTime(2026))],
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      );
      final root = tester.state<ScrollableState>(_homeScrollable());
      root.position.jumpTo(1600);
      await tester.pumpAndSettle();
      final calls = controller.loadMoreCalls;
      await container
          .read(libraryViewModeProvider.notifier)
          .setMode(LibraryViewMode.list);
      await tester.pumpAndSettle();
      expect(tester.state<ScrollableState>(_homeScrollable()), same(root));
      expect(root.position.pixels, 0);
      expect(find.byType(AppBookListTile), findsWidgets);
      expectUnifiedBookList(tester);
      expect(controller.buildCalls, 1);
      expect(controller.loadMoreCalls, calls);
      root.position.jumpTo(900);
      await tester.pumpAndSettle();
      final listOffset = root.position.pixels;
      await container
          .read(libraryViewModeProvider.notifier)
          .setMode(LibraryViewMode.grid);
      await tester.pumpAndSettle();
      expect(root.position.pixels, closeTo(1600, 1));
      await container
          .read(libraryViewModeProvider.notifier)
          .setMode(LibraryViewMode.list);
      await tester.pumpAndSettle();
      expect(root.position.pixels, closeTo(listOffset, 1));
      expect(controller.buildCalls, 1);
      expect(controller.loadMoreCalls, calls);
      final tile = find.byType(AppBookListTile).hitTestable().first;
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.textContaining('Publication '), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester.state<ScrollableState>(_homeScrollable()).position.pixels,
        closeTo(listOffset, 1),
      );
      final carousel = find.byType(HomeLocalBookCarousel, skipOffstage: false);
      expect(carousel, findsOneWidget);
      final horizontal = find.descendant(
        of: carousel,
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
          skipOffstage: false,
        ),
        skipOffstage: false,
      );
      expect(horizontal, findsWidgets);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'Home List local mapping and status at 320px scale2 dark=$dark',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final local = _book(
          id: 'imported',
          catalogSourceId: homeCatalogSourceId,
          remotePublicationId: 'remote-1',
        );
        await tester.pumpWidget(
          _subject(
            books: [local],
            mode: LibraryViewMode.list,
            dark: dark,
            scale: 2,
            snapshot: HomeOnlineStateSnapshot(
              byPublication: {
                homeOnlineIdentity(
                  homeCatalogSourceId,
                  'remote-1',
                ): const HomeOnlineBookState(
                  phase: HomeOnlineBookPhase.inLibrary,
                ),
              },
              downloadsCount: 0,
              localBooksByPublication: {
                homeOnlineIdentity(homeCatalogSourceId, 'remote-1'): local,
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byType(AppBookListTile),
          300,
          scrollable: _homeScrollable(),
        );
        await tester.pumpAndSettle();
        expect(find.text('In library'), findsNothing);
        expect(find.text('Ready to read'), findsOneWidget);
        final menu = find.descendant(
          of: find.byType(AppBookListTile),
          matching: find.byType(AppContextMenuButton<String>),
        );
        expect(menu, findsOneWidget);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(find.text('Add to favorites'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(AppBookListTile));
        await tester.pumpAndSettle();
        expect(find.text('Local details imported'), findsOneWidget);
      },
    );
  }

  testWidgets('pending Home List slot fills in place with the same identity', (
    tester,
  ) async {
    final book = OnlineHomeBook(
      sourceId: homeCatalogSourceId,
      sourceName: 'Source',
      publication: _publication('loaded', 'Loaded'),
    );
    Widget app(OnlineHomeSlot slot) => ProviderScope(
      overrides: [
        allBooksProvider.overrideWithValue(const AsyncData(<LibraryBook>[])),
        homeOnlineStateProvider.overrideWithValue(
          const HomeOnlineStateSnapshot(byPublication: {}, downloadsCount: 0),
        ),
      ],
      child: MaterialApp(
        builder: (_, child) => Material(child: child),
        home: CustomScrollView(
          slivers: [
            HomeOnlineCatalogGrid(
              books: const [],
              slots: [slot],
              mode: LibraryViewMode.list,
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(
      app(const OnlineHomeSlot.pending(slotId: 42, sourceIndex: 0, attempt: 0)),
    );
    final slot = find.byKey(const ValueKey('home-online-slot-42'));
    final element = tester.element(slot);
    expect(find.byType(HomeOnlineReservedBookRow), findsOneWidget);
    await tester.pumpWidget(
      app(
        OnlineHomeSlot.loaded(
          slotId: 42,
          sourceIndex: 0,
          attempt: 0,
          book: book,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.element(slot), same(element));
    expect(find.byType(HomeOnlineReservedBookRow), findsNothing);
    expect(find.text('Loaded'), findsOneWidget);
    expect(find.byType(AppBookListTile), findsOneWidget);
  });

  testWidgets(
    'online Home cards keep natural metadata height at phone scales',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final book = OnlineHomeBook(
        sourceId: homeCatalogSourceId,
        sourceName: 'Project Gutenberg',
        publication: _publication(
          'green-mummy',
          'The Green Mummy',
          authors: const ['Hume, Fergus'],
        ),
      );
      for (final scale in [1.0, 1.5]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              homeOnlineStateProvider.overrideWithValue(
                const HomeOnlineStateSnapshot(
                  byPublication: {},
                  downloadsCount: 0,
                ),
              ),
            ],
            child: MaterialApp(
              theme: buildAppTheme(fallbackLightColorScheme),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: CustomScrollView(
                  slivers: [
                    HomeOnlineCatalogGrid(books: [book]),
                  ],
                ),
              ),
            ),
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

  test('canonical Home identity normalizes Gutenberg ID and URI variants', () {
    final variants = [
      _publication('123', 'Book'),
      _publication('ebooks/123', 'Book'),
      _publication('/ebooks/123', 'Book'),
      _publication('https://WWW.GUTENBERG.org/ebooks/123/', 'Book'),
      _publication('https://www.gutenberg.org/ebooks/123.opds#details', 'Book'),
      _publication('https://www.gutenberg.org/ebooks/123.images', 'Book'),
      _publication('https://www.gutenberg.org/ebooks/123.noimages', 'Book'),
      _publication('urn:gutenberg:123', 'Book'),
    ];

    expect(
      variants
          .map(
            (publication) => RemoteHomePublicationIdentity.canonical(
              sourceId: homeCatalogSourceId,
              publication: publication,
            ),
          )
          .toSet(),
      hasLength(1),
    );
  });

  test('canonical Home identity falls back to normalized details URI', () {
    final first = RemoteCatalogPublicationSummary(
      remoteId: '',
      title: 'Book',
      detailsLocation: RemoteCatalogLocation.parse(
        'https://EXAMPLE.test/books/one/#fragment',
      ),
    );
    final second = RemoteCatalogPublicationSummary(
      remoteId: '',
      title: 'Book',
      detailsLocation: RemoteCatalogLocation.parse(
        'https://example.test/books/one',
      ),
    );

    expect(
      RemoteHomePublicationIdentity.canonical(
        sourceId: 'source',
        publication: first,
      ),
      RemoteHomePublicationIdentity.canonical(
        sourceId: 'source',
        publication: second,
      ),
    );
  });

  test('online library carousel maps virtual pages cyclically', () {
    expect(HomeOnlineLibraryCarousel.libraryIndexForPage(1000000, 2), 0);
    expect(HomeOnlineLibraryCarousel.libraryIndexForPage(1000001, 2), 1);
    expect(HomeOnlineLibraryCarousel.libraryIndexForPage(1000002, 2), 0);
    expect(HomeOnlineLibraryCarousel.centeredPageFor(1, 3) % 3, 1);
    final nearStart = 4;
    final recentered = HomeOnlineLibraryCarousel.recenteredPageFor(
      nearStart,
      3,
    );
    expect(HomeOnlineLibraryCarousel.shouldRecenter(nearStart), isTrue);
    expect(
      HomeOnlineLibraryCarousel.libraryIndexForPage(recentered, 3),
      HomeOnlineLibraryCarousel.libraryIndexForPage(nearStart, 3),
    );
    expect(HomeOnlineLibraryCarousel.shouldRecenter(1000000), isFalse);
    expect(
      HomeOnlineLibraryCarousel.nearestPageForLibrary(
        libraryIndex: 0,
        currentPage: 1000002,
        libraryCount: 3,
      ),
      1000002,
    );
  });

  testWidgets('online library carousel has distinct zero and one states', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(fallbackLightColorScheme),
        home: const Scaffold(body: HomeOnlineLibraryCarousel.empty()),
      ),
    );
    expect(
      find.byKey(const Key('home-online-libraries-empty')),
      findsOneWidget,
    );

    final library = builtInCatalogSources.first;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(fallbackLightColorScheme),
        home: Scaffold(
          body: HomeOnlineLibraryCarousel(
            libraries: [library],
            selectedLibraryId: library.id,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('home-online-library-carousel')), findsNothing);
    expect(
      find.byKey(ValueKey('home-online-library-${library.id}')),
      findsOneWidget,
    );
  });

  testWidgets('selected library uses a compact text capsule only', (
    tester,
  ) async {
    final libraries = builtInCatalogSources.take(2).toList();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(fallbackLightColorScheme),
        home: Scaffold(
          body: HomeOnlineLibraryCarousel(
            libraries: libraries,
            selectedLibraryId: libraries.first.id,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final selected = find
        .byKey(ValueKey('home-online-library-${libraries.first.id}'))
        .first;
    final selectedText = find.text(libraries.first.name);
    expect(selected, findsOneWidget);
    expect(
      tester.getSize(selected).width - tester.getSize(selectedText).width,
      closeTo(28, 1),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('home-online-library-peek-right')),
        matching: find.byType(AnimatedContainer),
      ),
      findsNothing,
    );
  });

  testWidgets('cyclic carousel clips neighbors into isolated peek zones', (
    tester,
  ) async {
    final libraries = builtInCatalogSources.take(3).toList();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(fallbackLightColorScheme),
        home: Scaffold(
          body: HomeOnlineLibraryCarousel(
            libraries: libraries,
            selectedLibraryId: libraries.first.id,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final leftZone = tester.getRect(
      find.byKey(const Key('home-online-library-peek-left-zone')),
    );
    final rightZone = tester.getRect(
      find.byKey(const Key('home-online-library-peek-right-zone')),
    );
    final leftText = tester.getRect(
      find.byKey(const Key('home-online-library-peek-left-text')),
    );
    final rightText = tester.getRect(
      find.byKey(const Key('home-online-library-peek-right-text')),
    );
    final selectedRect = tester.getRect(
      find.byKey(ValueKey('home-online-library-${libraries.first.id}')).first,
    );

    expect(leftZone.width, HomeOnlineLibraryCarousel.peekZoneWidth);
    expect(rightZone.width, HomeOnlineLibraryCarousel.peekZoneWidth);
    expect(leftText.right, closeTo(leftZone.right, 0.1));
    expect(leftText.left, lessThan(leftZone.left));
    expect(rightText.left, closeTo(rightZone.left, 0.1));
    expect(rightText.right, greaterThan(rightZone.right));
    expect(leftZone.right, lessThan(selectedRect.left));
    expect(rightZone.left, greaterThan(selectedRect.right));
  });

  testWidgets('long library names remain bounded without overlapping', (
    tester,
  ) async {
    final libraries = builtInCatalogSources
        .take(3)
        .map(
          (library) => library.copyWith(
            name: 'An exceptionally long online library name ${library.id}',
          ),
        )
        .toList();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(fallbackLightColorScheme),
        home: Scaffold(
          body: HomeOnlineLibraryCarousel(
            libraries: libraries,
            selectedLibraryId: libraries.first.id,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final selected = tester.getRect(
      find.byKey(ValueKey('home-online-library-${libraries.first.id}')).first,
    );
    final left = tester.getRect(
      find.byKey(const Key('home-online-library-peek-left-zone')),
    );
    final right = tester.getRect(
      find.byKey(const Key('home-online-library-peek-right-zone')),
    );
    expect(left.right, lessThan(selected.left));
    expect(right.left, greaterThan(selected.right));
  });

  testWidgets('cyclic carousel continues in both directions', (tester) async {
    final libraries = builtInCatalogSources.take(3).toList();
    final selected = ValueNotifier(libraries.first.id);
    final selections = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(fallbackLightColorScheme),
        home: Scaffold(
          body: ValueListenableBuilder<String>(
            valueListenable: selected,
            builder: (context, selectedLibraryId, _) =>
                HomeOnlineLibraryCarousel(
                  libraries: libraries,
                  selectedLibraryId: selectedLibraryId,
                  onSelected: (id) {
                    if (id == selected.value) return;
                    selections.add(id);
                    selected.value = id;
                  },
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    selections.clear();

    final carousel = find.byKey(const Key('home-online-library-carousel'));
    final controller = tester
        .widget<PageView>(find.byType(PageView))
        .controller;
    expect(controller, isNotNull);
    final pageKeys = tester
        .widgetList<GestureDetector>(find.byType(GestureDetector))
        .map((widget) => widget.key)
        .whereType<ValueKey<String>>()
        .where((key) => key.value.startsWith('home-online-library-page-'))
        .map((key) => key.value)
        .toList();
    expect(pageKeys.toSet().length, pageKeys.length);
    for (var index = 0; index < 4; index++) {
      await tester.drag(carousel, const Offset(-700, 0));
      await tester.pumpAndSettle();
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller,
        same(controller),
      );
    }
    expect(selections, [
      libraries[1].id,
      libraries[2].id,
      libraries[0].id,
      libraries[1].id,
    ]);

    for (var index = 0; index < 3; index++) {
      await tester.drag(carousel, const Offset(700, 0));
      await tester.pumpAndSettle();
    }
    expect(selections.skip(4), [
      libraries[0].id,
      libraries[2].id,
      libraries[1].id,
    ]);
  });

  testWidgets(
    'neighbor tap animates one virtual page and interpolates capsules',
    (tester) async {
      final libraries = builtInCatalogSources.take(3).toList();
      final selected = ValueNotifier(libraries.first.id);
      final selections = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(fallbackLightColorScheme),
          home: Scaffold(
            body: ValueListenableBuilder<String>(
              valueListenable: selected,
              builder: (context, selectedLibraryId, _) =>
                  HomeOnlineLibraryCarousel(
                    libraries: libraries,
                    selectedLibraryId: selectedLibraryId,
                    onSelected: (id) {
                      if (id == selected.value) return;
                      selections.add(id);
                      selected.value = id;
                    },
                  ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pageView = tester.widget<PageView>(find.byType(PageView));
      final controller = pageView.controller!;
      final initialPage = controller.page!.round();
      await tester.tap(
        find
            .descendant(
              of: find.byKey(const Key('home-online-library-peek-right-zone')),
              matching: find.byType(GestureDetector),
            )
            .hitTestable(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));

      expect(controller.page, greaterThan(initialPage));
      expect(controller.page, lessThan(initialPage + 1));
      final outgoing = tester.widget<Opacity>(
        find
            .descendant(
              of: find.byKey(
                ValueKey('home-online-library-capsule-$initialPage'),
              ),
              matching: find.byType(Opacity),
            )
            .first,
      );
      final incoming = tester.widget<Opacity>(
        find
            .descendant(
              of: find.byKey(
                ValueKey('home-online-library-capsule-${initialPage + 1}'),
              ),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(outgoing.opacity, inExclusiveRange(0, 1));
      expect(incoming.opacity, inExclusiveRange(0, 1));

      await tester.pumpAndSettle();
      expect(controller.page, initialPage + 1);
      expect(selections, [libraries[1].id]);
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller,
        same(controller),
      );
    },
  );

  testWidgets('switching libraries preserves the Home scroll position', (
    tester,
  ) async {
    final libraries = builtInCatalogSources.take(2).toList();
    final first = _FakeOnlineController(AsyncData(_online()));
    final second = _FakeOnlineController(
      AsyncData([
        OnlineHomeSection(
          id: libraries[1].id,
          title: libraries[1].name,
          searchCapability: const RemoteCatalogSearchCapability.unsupported(),
          books: [
            OnlineHomeBook(
              sourceId: libraries[1].id,
              sourceName: libraries[1].name,
              publication: _publication('second', 'Second library book'),
            ),
          ],
        ),
      ]),
    );
    await tester.pumpWidget(
      _subject(
        books: [
          _book(id: 'local', lastOpenedAt: DateTime(2026), isFavorite: true),
        ],
        configuredLibraries: libraries,
        onlineControllers: {libraries.first.id: first, libraries[1].id: second},
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('home-online-library-tabs')),
      400,
      scrollable: _homeScrollable(),
    );
    final root = tester.element(find.byType(CustomScrollView));
    final scrollable = tester.state<ScrollableState>(_homeScrollable());
    final position = scrollable.position;
    final offset = position.pixels;

    await tester.tap(
      find.byKey(ValueKey('home-online-library-${libraries[1].id}')),
    );
    await tester.pumpAndSettle();

    expect(tester.element(find.byType(CustomScrollView)), same(root));
    expect(
      tester.state<ScrollableState>(_homeScrollable()).position,
      same(position),
    );
    expect(position.pixels, closeTo(offset, 0.1));
    expect(first.buildCalls, 1);
    expect(second.buildCalls, 1);
    expect(
      tester
          .widget<BiblioTabs<String>>(find.byType(BiblioTabs<String>))
          .selectedId,
      libraries[1].id,
    );
    expect(find.text('Second library book'), findsOneWidget);
  });

  testWidgets('all five supported Home tabs render in registry order', (
    tester,
  ) async {
    final controllers = {
      for (final source in builtInCatalogSources)
        source.id: _FakeOnlineController(
          AsyncData([
            OnlineHomeSection(
              id: source.id,
              title: source.name,
              books: const [],
              searchCapability:
                  const RemoteCatalogSearchCapability.unsupported(),
            ),
          ]),
        ),
    };
    await tester.pumpWidget(
      _subject(
        books: const [],
        configuredLibraries: builtInCatalogSources,
        onlineControllers: controllers,
      ),
    );
    await tester.pump();
    await tester.pump();

    for (final source in builtInCatalogSources) {
      expect(
        find.byKey(ValueKey('home-online-library-${source.id}')),
        findsOneWidget,
      );
    }
    expect(controllers[builtInCatalogSources.first.id]!.buildCalls, 1);
    for (final source in builtInCatalogSources.skip(1)) {
      expect(controllers[source.id]!.buildCalls, 0);
    }
  });

  testWidgets('Home visibility hides only the selected provider tab', (
    tester,
  ) async {
    final hidden = builtInCatalogSources.first;
    final controllers = {
      for (final source in builtInCatalogSources)
        source.id: _FakeOnlineController(const AsyncData([])),
    };
    await tester.pumpWidget(
      _subject(
        books: const [],
        configuredLibraries: builtInCatalogSources,
        onlineControllers: controllers,
        homeVisibility: {hidden.id: false},
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(ValueKey('home-online-library-${hidden.id}')),
      findsNothing,
    );
    for (final source in builtInCatalogSources.skip(1)) {
      expect(
        find.byKey(ValueKey('home-online-library-${source.id}')),
        findsOneWidget,
      );
    }
  });

  testWidgets('Home source changes keep selection by ID and use its fallback', (
    tester,
  ) async {
    final sources = builtInCatalogSources.take(3).toList();
    final visibility = StreamController<Map<String, bool>>();
    addTearDown(visibility.close);
    await tester.pumpWidget(
      _subject(
        books: const [],
        configuredLibraries: sources,
        visibilityChanges: visibility.stream,
        onlineControllers: {
          for (final source in sources)
            source.id: _FakeOnlineController(const AsyncData([])),
        },
      ),
    );
    await tester.pumpAndSettle();

    BiblioTabs<String> tabs() => tester.widget(find.byType(BiblioTabs<String>));
    expect(tabs().selectedId, sources.first.id);
    await tester.tap(
      find.byKey(ValueKey('home-online-library-${sources[1].id}')),
    );
    await tester.pumpAndSettle();
    expect(tabs().selectedId, sources[1].id);

    visibility.add({sources.first.id: false});
    await tester.pumpAndSettle();
    expect(tabs().items.map((item) => item.id), [sources[1].id, sources[2].id]);
    expect(tabs().selectedId, sources[1].id);

    visibility.add({sources.first.id: false, sources[1].id: false});
    await tester.pumpAndSettle();
    expect(tabs().items.single.id, sources[2].id);
    expect(tabs().selectedId, sources[2].id);
  });

  test(
    'an unrelated online-card state update does not notify another card',
    () {
      const firstIdentity = 'source\u0000first';
      const secondIdentity = 'source\u0000second';
      final state =
          NotifierProvider<_MutableHomeOnlineSnapshot, HomeOnlineStateSnapshot>(
            _MutableHomeOnlineSnapshot.new,
          );
      final container = ProviderContainer(
        overrides: [
          homeOnlineStateProvider.overrideWith((ref) => ref.watch(state)),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(state.notifier)
          .set(
            const HomeOnlineStateSnapshot(
              byPublication: {
                firstIdentity: HomeOnlineBookState(
                  phase: HomeOnlineBookPhase.downloading,
                  downloadedBytes: 10,
                  totalBytes: 100,
                ),
                secondIdentity: HomeOnlineBookState(
                  phase: HomeOnlineBookPhase.queued,
                ),
              },
              downloadsCount: 2,
            ),
          );

      var notifications = 0;
      final subscription = container.listen<HomeOnlineBookState>(
        homeOnlineStateProvider.select(
          (snapshot) =>
              snapshot.byPublication[firstIdentity] ??
              const HomeOnlineBookState.idle(),
        ),
        (_, _) => notifications += 1,
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      container
          .read(state.notifier)
          .set(
            const HomeOnlineStateSnapshot(
              byPublication: {
                firstIdentity: HomeOnlineBookState(
                  phase: HomeOnlineBookPhase.downloading,
                  downloadedBytes: 10,
                  totalBytes: 100,
                ),
                secondIdentity: HomeOnlineBookState(
                  phase: HomeOnlineBookPhase.downloading,
                  downloadedBytes: 20,
                  totalBytes: 100,
                ),
              },
              downloadsCount: 2,
            ),
          );

      expect(notifications, 1);
    },
  );

  testWidgets('online Home card uses linked local cover without feed rebuild', (
    tester,
  ) async {
    final controller = _FakeOnlineController(AsyncData(_online()));
    final localBook = _book(
      id: 'local-remote-1',
      catalogSourceId: homeCatalogSourceId,
      remotePublicationId: 'remote-1',
      coverPath: 'C:\\covers\\remote-1.png',
    );
    final snapshot = buildHomeOnlineStateSnapshot(
      tasks: [_task(RemoteDownloadTaskState.imported)],
      books: [localBook],
    );
    await tester.pumpWidget(
      _subject(books: [localBook], controller: controller, snapshot: snapshot),
    );
    await tester.pump();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1800));
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('${localBook.id}-${localBook.coverPath}')),
      findsOneWidget,
    );
    expect(
      snapshot
          .localBooksByPublication[homeOnlineIdentity(
            homeCatalogSourceId,
            'remote-1',
          )]
          ?.id,
      localBook.id,
    );
    expect(controller.buildCalls, 1);
  });

  testWidgets('local carousel viewport matches its tallest visible book card', (
    tester,
  ) async {
    final book = _book(
      id: 'tight-local',
      title: 'A local title that uses both allowed lines in the card',
      author: 'An author name that also uses both allowed lines',
      lastOpenedAt: DateTime(2026),
    );
    await tester.pumpWidget(_subject(books: [book], online: _online()));
    await tester.pumpAndSettle();

    final viewport = find.byKey(
      const PageStorageKey('carousel-Recently opened'),
    );
    final card = find.byKey(const ValueKey('home-book-tight-local'));
    expect(viewport, findsOneWidget);
    expect(card, findsOneWidget);
    expect(
      tester.getSize(viewport).height,
      closeTo(tester.getSize(card).height, 1),
    );
  });

  testWidgets('Home has required order and hides empty local sections', (
    tester,
  ) async {
    await tester.pumpWidget(_subject(books: [], online: _online()));
    await tester.pumpAndSettle();

    expect(find.text('Search books'), findsOneWidget);
    expect(find.text('Recently opened'), findsNothing);
    expect(find.text('Favorites'), findsNothing);
    expect(find.text('Online libraries'), findsOneWidget);
    expect(find.text('Explore online'), findsNothing);
    expect(find.text('Free books from Project Gutenberg'), findsNothing);
    expect(find.text('See all'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Search books')).dy,
      lessThan(tester.getTopLeft(find.text('Online libraries')).dy),
    );
  });

  testWidgets('shared headers and Search alignment use the Home contract', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _subject(
        books: [
          _book(id: 'recent', isFavorite: true, lastOpenedAt: DateTime(2026)),
        ],
        online: _online(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const Key('home-search-action'))).width,
      lessThanOrEqualTo(560),
    );
    expect(
      tester.getCenter(find.byKey(const Key('home-search-action'))).dx,
      closeTo(600, 8),
    );
    await tester.scrollUntilVisible(
      find.text('Online libraries'),
      400,
      scrollable: _homeScrollable(),
    );
    expect(find.byType(HomeSectionHeader), findsNWidgets(2));
  });

  testWidgets('online cards expose concise authoritative states', (
    tester,
  ) async {
    final cases = <HomeOnlineBookState, String?>{
      const HomeOnlineBookState.idle(): null,
      const HomeOnlineBookState(phase: HomeOnlineBookPhase.queued): 'Queued',
      const HomeOnlineBookState(
        phase: HomeOnlineBookPhase.downloading,
        downloadedBytes: 50,
        totalBytes: 100,
      ): 'Downloading 50%',
      const HomeOnlineBookState(
        phase: HomeOnlineBookPhase.downloading,
        downloadedBytes: 50,
      ): 'Downloading',
      const HomeOnlineBookState(phase: HomeOnlineBookPhase.readyToAdd):
          'Ready to add',
      const HomeOnlineBookState(phase: HomeOnlineBookPhase.importing):
          'Importing',
      const HomeOnlineBookState(phase: HomeOnlineBookPhase.inLibrary):
          'In library',
      const HomeOnlineBookState(phase: HomeOnlineBookPhase.failed): 'Retry',
    };
    for (final entry in cases.entries) {
      await tester.pumpWidget(
        _subject(
          books: [],
          online: _online(),
          snapshot: HomeOnlineStateSnapshot(
            byPublication: {
              homeOnlineIdentity(homeCatalogSourceId, 'remote-1'): entry.key,
            },
            downloadsCount: 0,
          ),
        ),
      );
      await tester.pump();
      if (entry.value case final label?) {
        expect(find.text(label), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('Remote One')), findsOneWidget);
        expect(find.textContaining('completedTemporary'), findsNothing);
      } else {
        expect(find.text('Queued'), findsNothing);
      }
    }
  });

  testWidgets('healthy automatic pagination hides manual More', (tester) async {
    final initial = _online(
      publications: [_publication('first', 'First Book')],
      hasMore: true,
    );
    final next = _online(
      publications: [
        _publication('first', 'First Book'),
        _publication('second', 'Second Book'),
      ],
    );
    final controller = _FakeOnlineController(
      AsyncData(initial),
      next: AsyncData(next),
    );
    await tester.pumpWidget(_subject(books: const [], controller: controller));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-online-more')), findsNothing);
    expect(find.text('First Book'), findsOneWidget);

    await controller.loadMore();
    await tester.pumpAndSettle();

    expect(controller.loadMoreCalls, 1);
    expect(find.text('First Book'), findsOneWidget);
    expect(find.text('Second Book'), findsOneWidget);
    expect(find.byKey(const Key('home-online-more')), findsNothing);
  });

  testWidgets('near-end crossing triggers one bounded automatic load', (
    tester,
  ) async {
    final publications = [
      for (var index = 1; index <= 12; index++)
        _publication('auto-$index', 'Auto Book $index'),
    ];
    final controller = _FakeOnlineController(
      AsyncData(_online(publications: publications, hasMore: true)),
      next: AsyncData(_online(publications: publications)),
    );
    await tester.pumpWidget(_subject(books: const [], controller: controller));
    await tester.pump();

    await tester.drag(_homeScrollable(), const Offset(0, -1800));
    await tester.pumpAndSettle();
    expect(controller.loadMoreCalls, 1);

    await tester.drag(_homeScrollable(), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(controller.loadMoreCalls, 1);
  });

  testWidgets(
    'remaining at exact bottom does not auto-chain pagination requests',
    (tester) async {
      List<RemoteCatalogPublicationSummary> publications(int count) => [
        for (var index = 1; index <= count; index++)
          _publication('chain-$index', 'Chain Book $index'),
      ];
      final controller = _FakeOnlineController(
        AsyncData(_online(publications: publications(12), hasMore: true)),
        nextStates: [
          AsyncData(_online(publications: publications(16), hasMore: true)),
          AsyncData(_online(publications: publications(20))),
        ],
      );
      await tester.pumpWidget(
        _subject(books: const [], controller: controller),
      );
      await tester.pump();

      await tester.drag(_homeScrollable(), const Offset(0, -10000));
      await tester.pumpAndSettle();

      expect(controller.loadMoreCalls, 1);
      expect(controller.state.requireValue.first.books, hasLength(16));
    },
  );

  testWidgets(
    'one near-end demand fires only once until leaving the threshold',
    (tester) async {
      List<RemoteCatalogPublicationSummary> publications(int count) => [
        for (var index = 1; index <= count; index++)
          _publication('bounded-$index', 'Bounded Book $index'),
      ];
      final controller = _FakeOnlineController(
        AsyncData(_online(publications: publications(12), hasMore: true)),
        nextStates: [
          AsyncData(_online(publications: publications(16), hasMore: true)),
          AsyncData(_online(publications: publications(20), hasMore: true)),
          AsyncData(_online(publications: publications(24), hasMore: true)),
          AsyncData(_online(publications: publications(28), hasMore: true)),
        ],
      );
      await tester.pumpWidget(
        _subject(books: const [], controller: controller),
      );
      await tester.pump();

      await tester.drag(_homeScrollable(), const Offset(0, -10000));
      await tester.pumpAndSettle();

      expect(controller.loadMoreCalls, 1);
      expect(controller.state.requireValue.first.books, hasLength(16));
    },
  );

  testWidgets('online header has no downloads action', (tester) async {
    await tester.pumpWidget(
      _subject(
        books: [],
        online: _online(),
        snapshot: const HomeOnlineStateSnapshot(
          byPublication: {},
          downloadsCount: 3,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Downloads, 3 pending'), findsNothing);
    expect(find.byKey(const Key('home-downloads-action')), findsNothing);
  });

  test(
    'state mapping follows local deletion and excludes terminal history',
    () {
      final identity = homeOnlineIdentity(homeCatalogSourceId, 'remote-1');
      final local = _book(
        id: 'local',
        catalogSourceId: homeCatalogSourceId,
        remotePublicationId: 'remote-1',
      );
      expect(
        buildHomeOnlineStateSnapshot(
          tasks: [_task(RemoteDownloadTaskState.imported)],
          books: [local],
        ).byPublication[identity]!.phase,
        HomeOnlineBookPhase.inLibrary,
      );
      expect(
        buildHomeOnlineStateSnapshot(
          tasks: [_task(RemoteDownloadTaskState.deleted)],
          books: const [],
        ).byPublication[identity],
        isNull,
      );
      expect(
        buildHomeOnlineStateSnapshot(
          tasks: [_task(RemoteDownloadTaskState.imported)],
          books: const [],
        ).byPublication[identity],
        isNull,
      );
      expect(
        buildHomeOnlineStateSnapshot(
          tasks: [_task(RemoteDownloadTaskState.duplicate)],
          books: const [],
        ).byPublication[identity],
        isNull,
      );
      expect(
        buildHomeOnlineStateSnapshot(
          tasks: [
            _task(RemoteDownloadTaskState.queued, id: 'queued'),
            _task(RemoteDownloadTaskState.completedTemporary, id: 'ready'),
            _task(RemoteDownloadTaskState.imported, id: 'history'),
            _task(RemoteDownloadTaskState.failed, id: 'failed'),
          ],
          books: const [],
        ).downloadsCount,
        2,
      );
    },
  );

  testWidgets('selected local carousel filters data and horizontally scrolls', (
    tester,
  ) async {
    final newer = _book(id: 'newer', lastOpenedAt: DateTime(2026, 7, 24));
    final older = _book(id: 'older', lastOpenedAt: DateTime(2026, 7, 20));
    final favorite = _book(id: 'favorite', isFavorite: true);
    final plain = _book(id: 'plain');

    await tester.pumpWidget(
      _subject(books: [older, plain, favorite, newer], online: _online()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recently opened'), findsOneWidget);
    expect(find.text('Favorites'), findsNothing);
    expect(find.text('Book newer'), findsOneWidget);
    expect(find.text('Book older'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Book newer')).dx,
      lessThan(tester.getTopLeft(find.text('Book older')).dx),
    );
    expect(find.text('Book favorite'), findsNothing);
    expect(find.text('Book plain'), findsNothing);
    expect(find.byType(HomeLocalBookCarousel), findsOneWidget);
    expect(
      find.byKey(const PageStorageKey('carousel-Favorites')),
      findsNothing,
    );

    final recentList = find.byKey(
      const PageStorageKey('carousel-Recently opened'),
    );
    expect(recentList, findsOneWidget);
    await tester.drag(recentList, const Offset(-250, 0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Scrollable>(
        find.descendant(of: recentList, matching: find.byType(Scrollable)),
      ),
      isNotNull,
    );

    await tester.scrollUntilVisible(
      find.text('Search books'),
      400,
      scrollable: _homeScrollable(),
    );
    expect(find.text('Search books'), findsOneWidget);
  });

  testWidgets('default Home carousel preference selects one local section', (
    tester,
  ) async {
    final recentBook = _book(
      id: 'default-recent',
      lastOpenedAt: DateTime(2026, 7, 24),
    );
    final favoriteBook = _book(id: 'default-favorite', isFavorite: true);

    for (final preference in [
      HomeDefaultCarousel.recentlyOpened,
      HomeDefaultCarousel.favorites,
    ]) {
      await tester.pumpWidget(
        _subject(
          books: [recentBook, favoriteBook],
          online: _online(),
          providerScopeKey: ValueKey(preference),
          homeDefaultCarouselRepository:
              _MemoryHomeDefaultCarouselSettingsRepository(preference),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        ProviderScope.containerOf(
          tester.element(find.byType(HomeScreen)),
          listen: false,
        ).read(defaultHomeCarouselProvider),
        AsyncData(preference),
      );

      if (preference == HomeDefaultCarousel.favorites) {
        expect(find.text('Favorites'), findsOneWidget);
        expect(find.text('Recently opened'), findsNothing);
        expect(find.text('Book default-favorite'), findsOneWidget);
        expect(find.text('Book default-recent'), findsNothing);
        expect(
          find.byKey(const PageStorageKey('carousel-Favorites')),
          findsOneWidget,
        );
        expect(
          find.byKey(const PageStorageKey('carousel-Recently opened')),
          findsNothing,
        );
      } else {
        expect(find.text('Recently opened'), findsOneWidget);
        expect(find.text('Favorites'), findsNothing);
        expect(find.text('Book default-recent'), findsOneWidget);
        expect(find.text('Book default-favorite'), findsNothing);
        expect(
          find.byKey(const PageStorageKey('carousel-Recently opened')),
          findsOneWidget,
        );
        expect(
          find.byKey(const PageStorageKey('carousel-Favorites')),
          findsNothing,
        );
      }
      expect(find.byType(HomeLocalBookCarousel), findsOneWidget);
      expect(
        find.text('Online libraries', skipOffstage: false),
        findsOneWidget,
      );
    }
  });

  testWidgets('empty selected carousel does not fall back to the other one', (
    tester,
  ) async {
    final recentBook = _book(
      id: 'only-recent',
      lastOpenedAt: DateTime(2026, 7, 24),
    );
    await tester.pumpWidget(
      _subject(
        books: [recentBook],
        online: _online(),
        providerScopeKey: const ValueKey('empty-favorites'),
        homeDefaultCarouselRepository:
            _MemoryHomeDefaultCarouselSettingsRepository(
              HomeDefaultCarousel.favorites,
            ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Favorites'), findsNothing);
    expect(find.text('Recently opened'), findsNothing);
    expect(find.byType(HomeLocalBookCarousel), findsNothing);
    expect(find.text('Book only-recent'), findsNothing);
    expect(find.text('Online libraries', skipOffstage: false), findsOneWidget);
  });

  testWidgets('changing the preference reactively replaces the local section', (
    tester,
  ) async {
    final repository = _MemoryHomeDefaultCarouselSettingsRepository();
    await tester.pumpWidget(
      _subject(
        books: [
          _book(id: 'reactive-recent', lastOpenedAt: DateTime(2026, 7, 24)),
          _book(id: 'reactive-favorite', isFavorite: true),
        ],
        online: _online(),
        providerScopeKey: const ValueKey('reactive-home-carousel'),
        homeDefaultCarouselRepository: repository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recently opened'), findsOneWidget);
    expect(find.text('Favorites'), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
      listen: false,
    );
    await container
        .read(defaultHomeCarouselProvider.notifier)
        .setDefault(HomeDefaultCarousel.favorites);
    await tester.pumpAndSettle();

    expect(find.text('Recently opened'), findsNothing);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.byType(HomeLocalBookCarousel), findsOneWidget);
    expect(
      find.byKey(const PageStorageKey('carousel-Recently opened')),
      findsNothing,
    );
    expect(
      find.byKey(const PageStorageKey('carousel-Favorites')),
      findsOneWidget,
    );
  });

  testWidgets('Search, local, remote, and See all use existing routes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(
        books: [_book(id: 'local', lastOpenedAt: DateTime(2026))],
        online: _online(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('home-search-action')));
    await tester.pumpAndSettle();
    expect(find.text('Catalog search destination'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-book-local')).first);
    await tester.pumpAndSettle();
    expect(find.text('Local details local'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.drag(_homeScrollable(), const Offset(0, -2000));
    await tester.pump();
    await tester.tap(find.text('Remote One'));
    await tester.pumpAndSettle();
    expect(find.text('Publication remote-1'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-online-see-all')), findsNothing);
  });

  testWidgets('two Home cards retain distinct publication route identities', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _subject(
        books: [],
        online: _online(
          publications: [
            _publication('remote-1', 'Remote One'),
            _publication('remote-2', 'Remote Two'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final id in ['remote-1', 'remote-2']) {
      final title = id == 'remote-1' ? 'Remote One' : 'Remote Two';
      await tester.scrollUntilVisible(
        find.text(title),
        400,
        scrollable: _homeScrollable(),
      );
      final card = find.byKey(
        ValueKey(
          'home-online-${RemoteHomePublicationIdentity.canonical(sourceId: homeCatalogSourceId, publication: _publication(id, title))}',
        ),
      );
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.text('Publication $id'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
    'imported online publication opens the canonical local details route',
    (tester) async {
      final imported = _book(
        id: 'imported',
        catalogSourceId: homeCatalogSourceId,
        remotePublicationId: 'remote-1',
      );
      await tester.pumpWidget(
        _subject(
          books: [imported],
          online: _online(),
          snapshot: HomeOnlineStateSnapshot(
            byPublication: {
              homeOnlineIdentity(
                homeCatalogSourceId,
                'remote-1',
              ): const HomeOnlineBookState(
                phase: HomeOnlineBookPhase.inLibrary,
              ),
            },
            downloadsCount: 0,
            localBooksByPublication: {
              homeOnlineIdentity(homeCatalogSourceId, 'remote-1'): imported,
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(_homeScrollable(), const Offset(0, -2000));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Book imported'));
      await tester.pumpAndSettle();

      expect(find.text('Local details imported'), findsOneWidget);
      expect(find.text('Publication remote-1'), findsNothing);
    },
  );

  testWidgets('back navigation preserves horizontal and vertical positions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(
        books: [
          for (var index = 0; index < 6; index++)
            _book(
              id: 'local-$index',
              lastOpenedAt: DateTime(2026, 1, 10 - index),
            ),
        ],
        online: _online(
          publications: [
            for (var index = 0; index < 8; index++)
              _publication('remote-$index', 'Remote $index'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final recentList = find.byKey(
      const PageStorageKey('carousel-Recently opened'),
    );
    final recentScrollable = find.descendant(
      of: recentList,
      matching: find.byType(Scrollable),
    );
    await tester.drag(recentList, const Offset(-300, 0));
    await tester.pumpAndSettle();
    final horizontalBefore = tester
        .state<ScrollableState>(recentScrollable)
        .position
        .pixels;
    await tester.tap(find.text('Book local-2'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(recentScrollable).position.pixels,
      horizontalBefore,
    );

    await tester.scrollUntilVisible(
      find.text('Remote 0'),
      500,
      scrollable: _homeScrollable(),
    );
    final verticalBefore = tester
        .state<ScrollableState>(_homeScrollable())
        .position
        .pixels;
    await tester.tap(find.text('Remote 0'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(_homeScrollable()).position.pixels,
      verticalBefore,
    );
  });

  testWidgets('online grid is two columns and preserves feed order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _subject(
        books: [],
        online: _online(
          publications: [
            _publication('remote-1', 'Remote One'),
            _publication('remote-2', 'Remote Two'),
            _publication('remote-3', 'Remote Three', authors: const []),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
    expect(
      tester.getTopLeft(find.text('Remote One')).dy,
      tester.getTopLeft(find.text('Remote Two')).dy,
    );
    expect(
      tester.getTopLeft(find.text('Remote One')).dx,
      lessThan(tester.getTopLeft(find.text('Remote Two')).dx),
    );
    expect(find.text('Unknown author'), findsOneWidget);
  });

  testWidgets('online grid lazily builds a 150-card catalog', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _subject(
        books: [],
        online: _online(
          publications: [
            for (var index = 0; index < 150; index++)
              _publication('remote-$index', 'Performance Remote $index'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Performance Remote 0'), findsOneWidget);
    expect(find.text('Performance Remote 149'), findsNothing);
    expect(
      find.textContaining('Performance Remote').evaluate().length,
      lessThan(40),
    );

    await tester.scrollUntilVisible(
      find.text('Performance Remote 149'),
      1200,
      scrollable: _homeScrollable(),
    );
    expect(find.text('Performance Remote 149'), findsOneWidget);
    expect(find.text('Performance Remote 0'), findsNothing);
  });

  testWidgets('loading and failure stay local; Retry activates once', (
    tester,
  ) async {
    final controller = _FakeOnlineController(const AsyncLoading());
    await tester.pumpWidget(
      _subject(
        books: [_book(id: 'local', lastOpenedAt: DateTime(2026))],
        controller: controller,
      ),
    );
    await tester.pump();

    expect(find.text('Book local'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Project Gutenberg'),
      400,
      scrollable: _homeScrollable(),
    );
    await tester.drag(_homeScrollable(), const Offset(0, -250));
    await tester.pump();
    await tester.pump();
    expect(find.bySemanticsLabel('Loading online books'), findsOneWidget);
    expect(find.byType(HomeOnlineReservedBookCard), findsNothing);

    controller.state = AsyncError(StateError('hidden'), StackTrace.current);
    await tester.pump();
    expect(find.text('Book local'), findsWidgets);
    expect(find.text('Could not load online books.'), findsOneWidget);
    expect(find.textContaining('StateError'), findsNothing);
    await tester.tap(find.byKey(const Key('home-online-retry')));
    expect(controller.retryCalls, 1);
  });

  testWidgets(
    'partial online data renders the slot grid and keeps compact progress',
    (tester) async {
      await tester.pumpWidget(
        _subject(books: const [], online: _online(isInitialResolving: true)),
      );
      await tester.pump();

      expect(find.bySemanticsLabel('Loading online books'), findsNothing);
      expect(find.byType(HomeOnlineCatalogGrid), findsOneWidget);
      expect(find.text('Remote One'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byType(CircularProgressIndicator),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('home-online-more')), findsNothing);
    },
  );

  testWidgets('initial pending slots render placeholders instead of skeleton', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(
        books: const [],
        online: [
          OnlineHomeSection(
            id: homeCatalogSourceId,
            title: 'Project Gutenberg',
            books: const [],
            searchCapability: const RemoteCatalogSearchCapability.unsupported(),
            hasMore: true,
            isInitialResolving: true,
            slots: const [
              OnlineHomeSlot.pending(slotId: 0, sourceIndex: 0, attempt: 0),
              OnlineHomeSlot.pending(slotId: 1, sourceIndex: 1, attempt: 0),
              OnlineHomeSlot.pending(slotId: 2, sourceIndex: 2, attempt: 0),
              OnlineHomeSlot.pending(slotId: 3, sourceIndex: 3, attempt: 0),
            ],
          ),
        ],
      ),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byType(HomeOnlineReservedBookCard).first,
      400,
      scrollable: _homeScrollable(),
    );
    expect(find.byType(HomeOnlineReservedBookCard), findsWidgets);
    expect(find.byType(HomeOnlineCatalogGrid), findsOneWidget);
    expect(find.bySemanticsLabel('Loading online books'), findsNothing);
  });

  testWidgets(
    'two-column grid keeps a placeholder in the earlier pending slot',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final left = OnlineHomeBook(
        sourceId: homeCatalogSourceId,
        sourceName: 'Project Gutenberg',
        publication: _publication('left', 'Left Book'),
      );
      final right = OnlineHomeBook(
        sourceId: homeCatalogSourceId,
        sourceName: 'Project Gutenberg',
        publication: _publication('right', 'Right Book'),
      );
      Widget grid(OnlineHomeSlot first) => ProviderScope(
        overrides: [
          allBooksProvider.overrideWithValue(const AsyncData(<LibraryBook>[])),
          homeOnlineStateProvider.overrideWithValue(
            const HomeOnlineStateSnapshot(byPublication: {}, downloadsCount: 0),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(fallbackLightColorScheme),
          home: CustomScrollView(
            slivers: [
              HomeOnlineCatalogGrid(
                books: const [],
                slots: [
                  first,
                  OnlineHomeSlot.loaded(
                    slotId: 1,
                    sourceIndex: 1,
                    attempt: 0,
                    book: right,
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      await tester.pumpWidget(
        grid(
          const OnlineHomeSlot.pending(slotId: 0, sourceIndex: 0, attempt: 0),
        ),
      );
      final leftSlot = find.byKey(const ValueKey('home-online-slot-0'));
      final rightSlot = find.byKey(const ValueKey('home-online-slot-1'));
      final rightPosition = tester.getTopLeft(rightSlot);
      expect(tester.getSize(leftSlot).isEmpty, isFalse);
      expect(tester.getSize(rightSlot).isEmpty, isFalse);
      expect(
        find.descendant(
          of: leftSlot,
          matching: find.byType(HomeOnlineReservedBookCard),
        ),
        findsOneWidget,
      );
      expect(find.text('Right Book'), findsOneWidget);

      await tester.pumpWidget(
        grid(
          const OnlineHomeSlot.pending(slotId: 0, sourceIndex: 4, attempt: 1),
        ),
      );
      expect(
        find.descendant(
          of: leftSlot,
          matching: find.byType(HomeOnlineReservedBookCard),
        ),
        findsOneWidget,
      );
      expect(tester.getTopLeft(rightSlot), rightPosition);

      await tester.pumpWidget(
        grid(
          OnlineHomeSlot.loaded(
            slotId: 0,
            sourceIndex: 4,
            attempt: 1,
            book: left,
          ),
        ),
      );
      expect(find.text('Left Book'), findsOneWidget);
      expect(tester.getTopLeft(rightSlot), rightPosition);
    },
  );

  testWidgets(
    'reserved slot matches card footprint and has no book semantics',
    (tester) async {
      final book = OnlineHomeBook(
        sourceId: homeCatalogSourceId,
        sourceName: 'Project Gutenberg',
        publication: _publication('slot-loaded', 'Loaded Slot'),
      );
      await tester.pumpWidget(
        _subject(
          books: const [],
          online: [
            OnlineHomeSection(
              id: homeCatalogSourceId,
              title: 'Project Gutenberg',
              books: [book],
              searchCapability:
                  const RemoteCatalogSearchCapability.unsupported(),
              slots: [
                const OnlineHomeSlot.pending(
                  slotId: 10,
                  sourceIndex: 10,
                  attempt: 0,
                ),
                OnlineHomeSlot.loaded(
                  slotId: 11,
                  sourceIndex: 11,
                  attempt: 0,
                  book: book,
                ),
              ],
              isInitialResolving: true,
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-online-slot-10')),
        500,
        scrollable: _homeScrollable(),
      );

      final pending = find.byKey(const ValueKey('home-online-slot-10'));
      final loaded = find.byKey(const ValueKey('home-online-slot-11'));
      expect(tester.getSize(pending), tester.getSize(loaded));
      expect(find.byType(HomeOnlineReservedBookCard), findsOneWidget);
      expect(
        find.descendant(
          of: pending,
          matching: find.byKey(const Key('app-book-card-placeholder')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: pending, matching: find.byType(InkWell)),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel(RegExp('Open Loaded Slot, Remote Author')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('pending|loading', caseSensitive: false)),
        findsNothing,
      );
    },
  );

  testWidgets('loaded data replaces the same reserved slot key', (
    tester,
  ) async {
    final book = OnlineHomeBook(
      sourceId: homeCatalogSourceId,
      sourceName: 'Project Gutenberg',
      publication: _publication('same-slot', 'Same Slot'),
    );
    Widget grid(OnlineHomeSlot slot) => ProviderScope(
      overrides: [
        allBooksProvider.overrideWithValue(const AsyncData(<LibraryBook>[])),
        homeOnlineStateProvider.overrideWithValue(
          const HomeOnlineStateSnapshot(byPublication: {}, downloadsCount: 0),
        ),
      ],
      child: MaterialApp(
        theme: buildAppTheme(fallbackLightColorScheme),
        home: CustomScrollView(
          slivers: [
            HomeOnlineCatalogGrid(books: const [], slots: [slot]),
          ],
        ),
      ),
    );

    await tester.pumpWidget(
      grid(
        const OnlineHomeSlot.pending(slotId: 12, sourceIndex: 12, attempt: 0),
      ),
    );
    final slotFinder = find.byKey(const ValueKey('home-online-slot-12'));
    final pendingElement = tester.element(slotFinder);
    final pendingSize = tester.getSize(slotFinder);

    await tester.pumpWidget(
      grid(
        OnlineHomeSlot.loaded(
          slotId: 12,
          sourceIndex: 12,
          attempt: 0,
          book: book,
        ),
      ),
    );

    expect(tester.element(slotFinder), same(pendingElement));
    expect(tester.getSize(slotFinder), pendingSize);
    expect(find.text('Same Slot'), findsOneWidget);
    expect(find.byType(HomeOnlineReservedBookCard), findsNothing);
  });

  testWidgets(
    'reserved card uses the shared cover panel color in light and dark themes',
    (tester) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(
              ColorScheme.fromSeed(
                seedColor: Colors.indigo,
                brightness: brightness,
              ),
            ),
            home: const Scaffold(
              body: SizedBox(
                width: 180,
                height: 290,
                child: HomeOnlineReservedBookCard(),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final placeholder = find.byKey(const Key('app-book-card-placeholder'));
        expect(placeholder, findsOneWidget);
        final coverFinder = find.descendant(
          of: placeholder,
          matching: find.byType(ColoredBox),
        );
        final colorScheme = Theme.of(tester.element(placeholder)).colorScheme;
        final background = Theme.of(
          tester.element(placeholder),
        ).scaffoldBackgroundColor;
        final coverColors = tester
            .widgetList<ColoredBox>(coverFinder)
            .map((cover) => cover.color);
        expect(coverColors, contains(colorScheme.secondaryContainer));
        expect(coverColors, isNot(contains(background)));
      }
    },
  );

  testWidgets('incremental append retains Home-local widgets and existing card', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final firstPublication = _publication('stable-1', 'Stable One');
    final controller = _FakeOnlineController(
      AsyncData(
        _online(publications: [firstPublication], isInitialResolving: true),
      ),
      next: AsyncData(
        _online(
          publications: [
            firstPublication,
            _publication('stable-2', 'Stable Two'),
          ],
          isInitialResolving: true,
        ),
      ),
    );
    await tester.pumpWidget(
      _subject(
        books: [
          _book(
            id: 'local-stable',
            isFavorite: true,
            lastOpenedAt: DateTime(2026),
          ),
        ],
        controller: controller,
      ),
    );
    await tester.pump();

    final search = tester.element(find.byType(HomeSearchEntry));
    final carousel = tester.element(find.byType(HomeLocalBookCarousel));
    final cardKey = ValueKey(
      'home-online-${RemoteHomePublicationIdentity.canonical(sourceId: homeCatalogSourceId, publication: firstPublication)}',
    );
    final cardElement = tester.element(find.byKey(cardKey));

    await controller.loadMore();
    await tester.pump();

    expect(tester.element(find.byType(HomeSearchEntry)), same(search));
    expect(tester.element(find.byType(HomeLocalBookCarousel)), same(carousel));
    expect(tester.element(find.byKey(cardKey)), same(cardElement));
    expect(find.text('Stable Two'), findsOneWidget);
  });

  testWidgets('Offline makes online area compact and local cards functional', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(
        books: [
          _book(id: 'local', lastOpenedAt: DateTime(2026), isFavorite: true),
        ],
        onlineAllowed: false,
        online: _online(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Book local'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Go online to explore free books'),
      400,
      scrollable: _homeScrollable(),
    );
    expect(find.text('Go online to explore free books'), findsOneWidget);
    expect(find.byType(HomeOnlineCatalogGrid), findsNothing);
    expect(find.byKey(const Key('home-online-see-all')), findsNothing);
    await tester.drag(_homeScrollable(), const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-book-local')).first);
    await tester.pumpAndSettle();
    expect(find.text('Local details local'), findsOneWidget);
  });

  testWidgets('rebuild does not recreate or refetch retained online state', (
    tester,
  ) async {
    final controller = _FakeOnlineController(AsyncData(_online()));
    await tester.pumpWidget(_subject(books: [], controller: controller));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_subject(books: [], controller: controller));
    await tester.pumpAndSettle();

    expect(controller.buildCalls, 1);
  });

  testWidgets('book cards and headings expose concise semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _subject(
        books: [
          _book(id: 'local', lastOpenedAt: DateTime(2026), isFavorite: true),
        ],
        online: _online(),
      ),
    );
    await tester.pumpAndSettle();

    final headers = tester.widgetList<Semantics>(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.header == true,
      ),
    );
    expect(headers, isNotEmpty);
    await tester.scrollUntilVisible(
      find.bySemanticsLabel(RegExp('Search books')),
      400,
      scrollable: _homeScrollable(),
    );
    expect(find.bySemanticsLabel(RegExp('Search books')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.bySemanticsLabel(RegExp('Open Remote One, Remote Author')),
      400,
      scrollable: _homeScrollable(),
    );
    expect(
      find.bySemanticsLabel(RegExp('Open Remote One, Remote Author')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  for (final scenario in [
    (size: const Size(320, 700), scale: 1.0, name: 'narrow screen'),
    (size: const Size(400, 800), scale: 1.5, name: 'text scale 1.5'),
  ]) {
    testWidgets('${scenario.name} has no overflow or vertical nesting error', (
      tester,
    ) async {
      tester.view.physicalSize = scenario.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: scenario.size,
            textScaler: TextScaler.linear(scenario.scale),
          ),
          child: _subject(
            books: [
              _book(
                id: 'long',
                title: 'A very long localized book title that remains readable',
                author: 'An equally long author name',
                lastOpenedAt: DateTime(2026),
                isFavorite: true,
              ),
            ],
            online: _online(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
    });
  }

  test(
    'production controller loads once, bounds feed, and retries once',
    () async {
      final gateway = _Gateway(
        RemoteCatalogPage(
          sourceId: homeCatalogSourceId,
          location: RemoteCatalogLocation.parse('https://example.test/root'),
          title: 'Root',
          publications: List.generate(
            15,
            (index) => _publication('p$index', 'Book $index'),
          ),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          onlineAccessAllowedProvider.overrideWithValue(true),
          catalogSourceRepositoryProvider.overrideWithValue(
            _CatalogRepository(builtInCatalogSources.first),
          ),
          remoteCatalogGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        onlineHomeSectionsProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      final first = await _waitForOnlineData(container);
      expect(first.single.books, hasLength(12));
      expect(gateway.rootCalls, 1);
      expect(gateway.searchCalls, 0);
      container.read(onlineHomeSectionsProvider);
      expect(gateway.rootCalls, 1);
      await container.read(onlineHomeSectionsProvider.notifier).retry();
      expect(gateway.rootCalls, 2);
    },
  );

  test(
    'production provider and gateway/parser resolve navigation-only Gutenberg root',
    () async {
      final client = _FixtureHttpClient();
      final container = ProviderContainer(
        overrides: [
          onlineAccessAllowedProvider.overrideWithValue(true),
          catalogSourceRepositoryProvider.overrideWithValue(
            _CatalogRepository(builtInCatalogSources.first),
          ),
          remoteCatalogTransportProvider.overrideWithValue(
            HttpOpdsRemoteCatalogTransport(client: client),
          ),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        onlineHomeSectionsProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      final sections = await _waitForOnlineData(container);
      final books = sections.single.books;
      expect(books, hasLength(6));
      expect(books.map((book) => book.title), [
        for (var index = 1; index <= 6; index++) 'Fixture Book $index',
      ]);
      expect(books.any((book) => book.title == 'Project Gutenberg'), isFalse);
      expect(client.requests, 7);
    },
  );

  test(
    'bounded parallel resolver emits partial cards in source order and caches pages',
    () async {
      final gateway = _ConcurrentGateway();
      final container = ProviderContainer(
        overrides: [
          onlineAccessAllowedProvider.overrideWithValue(true),
          catalogSourceRepositoryProvider.overrideWithValue(
            _CatalogRepository(builtInCatalogSources.first),
          ),
          remoteCatalogGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);
      final observedCounts = <int>[];
      final subscription = container.listen(onlineHomeSectionsProvider, (
        _,
        next,
      ) {
        final section = next.asData?.value.firstOrNull;
        if (section != null && section.books.isNotEmpty) {
          observedCounts.add(section.books.length);
        }
      });
      addTearDown(subscription.close);

      final first = await _waitForBookCount(container, 1);
      expect(first.isInitialResolving, isTrue);
      expect(
        gateway.maxActive,
        OnlineHomeSectionsController.subsectionConcurrency,
      );
      expect(gateway.maxActive, greaterThan(1));

      final settled = (await _waitForOnlineSettled(container)).single;
      expect(settled.books, hasLength(12));
      expect(settled.books.map((book) => book.title), [
        for (var index = 1; index <= 12; index++) 'Concurrent Book $index',
      ]);
      final distinctCounts = [
        for (var index = 0; index < observedCounts.length; index++)
          if (index == 0 || observedCounts[index] != observedCounts[index - 1])
            observedCounts[index],
      ];
      expect(distinctCounts, containsAllInOrder([1, 2, 3, 4]));
      expect(distinctCounts.last, 12);
      expect(distinctCounts.take(4), [1, 2, 3, 4]);
      expect(
        distinctCounts.indexed
            .skip(1)
            .every((entry) => entry.$2 > distinctCounts[entry.$1 - 1]),
        isTrue,
      );
      final pageCalls = gateway.pageCalls;

      await container.read(onlineHomeSectionsProvider.notifier).retry();
      expect(gateway.pageCalls, pageCalls);
      expect(container.read(homePublicationPageCacheProvider).hits, 12);
    },
  );

  test('later stable slot fills while earlier slot remains pending', () async {
    final gateway = _OutOfOrderSlotGateway();
    final container = ProviderContainer(
      overrides: [
        onlineAccessAllowedProvider.overrideWithValue(true),
        catalogSourceRepositoryProvider.overrideWithValue(
          _CatalogRepository(builtInCatalogSources.first),
        ),
        remoteCatalogGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      onlineHomeSectionsProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);

    OnlineHomeSection? partial;
    for (var attempt = 0; attempt < 100; attempt++) {
      final section = container
          .read(onlineHomeSectionsProvider)
          .asData
          ?.value
          .firstOrNull;
      if (section != null &&
          section.slots.length == 4 &&
          section.slots[0].isPending &&
          section.slots[1].book?.title == 'Slot Book 2') {
        partial = section;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(partial, isNotNull);
    expect(partial!.slots.where((slot) => slot.isPending), isNotEmpty);
    expect(gateway.maxActive, 4);

    final settled = (await _waitForOnlineSettled(container)).single;
    expect(settled.slots, hasLength(4));
    expect(settled.slots.map((slot) => slot.book?.title), [
      'Slot Book 1',
      'Slot Book 2',
      'Slot Book 3',
      'Slot Book 4',
    ]);
    expect(settled.slots.map((slot) => slot.slotId), [0, 1, 2, 3]);
  });

  test(
    'initial pending slots are published before the root transport completes',
    () async {
      final gateway = _PendingRootGateway();
      final container = ProviderContainer(
        overrides: [
          onlineAccessAllowedProvider.overrideWithValue(true),
          catalogSourceRepositoryProvider.overrideWithValue(
            _CatalogRepository(builtInCatalogSources.first),
          ),
          remoteCatalogGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        onlineHomeSectionsProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      await gateway.rootStarted.future;
      final pending = await _waitForPendingSlots(container, 4);

      expect(gateway.rootCompleted, isFalse);
      expect(pending.isInitialResolving, isTrue);
      expect(pending.books, isEmpty);
      expect(pending.slots.map((slot) => slot.slotId), [0, 1, 2, 3]);
    },
  );

  test(
    'automatic pagination appends pending slots before pages complete',
    () async {
      final gateway = _PaginationPendingGateway();
      final container = ProviderContainer(
        overrides: [
          onlineAccessAllowedProvider.overrideWithValue(true),
          catalogSourceRepositoryProvider.overrideWithValue(
            _CatalogRepository(builtInCatalogSources.first),
          ),
          remoteCatalogGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        onlineHomeSectionsProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      final initial = (await _waitForOnlineSettled(container)).single;
      expect(initial.slots, hasLength(12));

      final loadMore = container
          .read(onlineHomeSectionsProvider.notifier)
          .loadMore();
      await gateway.allPagesStarted.future;
      final pending = await _waitForPendingSlots(container, 4);
      expect(pending.slots, hasLength(16));
      expect(pending.slots.take(12).every((slot) => !slot.isPending), isTrue);

      gateway.completePage(1);
      final partial = await _waitForLoadedSlotCount(container, 13);
      expect(partial.slots[12].book?.title, 'Page Book 1');
      expect(partial.slots.skip(13).every((slot) => slot.isPending), isTrue);

      gateway.completePage(2);
      gateway.completePage(3);
      gateway.completePage(4);
      await loadMore;
    },
  );

  test('transient root HTTP 504 retries once before success', () async {
    final gateway = _RootRetryGateway();
    final container = ProviderContainer(
      overrides: [
        onlineAccessAllowedProvider.overrideWithValue(true),
        catalogSourceRepositoryProvider.overrideWithValue(
          _CatalogRepository(builtInCatalogSources.first),
        ),
        remoteCatalogGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      onlineHomeSectionsProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);

    final sections = await _waitForOnlineData(container);
    expect(sections.single.books, hasLength(1));
    expect(gateway.rootCalls, 2);
  });

  test(
    'production initial load skips one failed subsection and keeps real cards',
    () async {
      final client = _FixtureHttpClient(failingIndexes: {1});
      final container = ProviderContainer(
        overrides: [
          onlineAccessAllowedProvider.overrideWithValue(true),
          catalogSourceRepositoryProvider.overrideWithValue(
            _CatalogRepository(builtInCatalogSources.first),
          ),
          remoteCatalogTransportProvider.overrideWithValue(
            HttpOpdsRemoteCatalogTransport(client: client),
          ),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        onlineHomeSectionsProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      final section = (await _waitForOnlineData(container)).single;
      final books = section.books;
      expect(books, hasLength(5));
      expect(books.map((book) => book.title), [
        'Fixture Book 5',
        'Fixture Book 2',
        'Fixture Book 3',
        'Fixture Book 4',
        'Fixture Book 6',
      ]);
      expect(section.slots.where((slot) => slot.isPending), isEmpty);
    },
  );

  test(
    'production initial load reports typed failure when every subsection fails',
    () async {
      final client = _FixtureHttpClient(
        failingIndexes: {for (var index = 1; index <= 6; index++) index},
      );
      final container = ProviderContainer(
        overrides: [
          onlineAccessAllowedProvider.overrideWithValue(true),
          catalogSourceRepositoryProvider.overrideWithValue(
            _CatalogRepository(builtInCatalogSources.first),
          ),
          remoteCatalogTransportProvider.overrideWithValue(
            HttpOpdsRemoteCatalogTransport(client: client),
          ),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        onlineHomeSectionsProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      final error = await _waitForOnlineError(container);
      expect(
        error,
        isA<RemoteCatalogException>().having(
          (value) => value.failure,
          'failure',
          RemoteCatalogFailure.httpStatus,
        ),
      );
    },
  );

  test(
    'production More appends a bounded identity-deduplicated batch',
    () async {
      final publications = [
        for (var index = 1; index <= 12; index++)
          _publication('id-$index', 'Book $index'),
        _publication('id-1', 'Repeated first identity'),
        _publication('id-13', 'Book 1'),
      ];
      final gateway = _Gateway(
        RemoteCatalogPage(
          sourceId: homeCatalogSourceId,
          location: RemoteCatalogLocation.parse('https://example.test/root'),
          title: 'Root',
          publications: publications,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          onlineAccessAllowedProvider.overrideWithValue(true),
          catalogSourceRepositoryProvider.overrideWithValue(
            _CatalogRepository(builtInCatalogSources.first),
          ),
          remoteCatalogGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        onlineHomeSectionsProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      final initial = await _waitForOnlineData(container);
      expect(initial.single.books, hasLength(12));
      expect(initial.single.hasMore, isTrue);

      await Future.wait([
        container.read(onlineHomeSectionsProvider.notifier).loadMore(),
        container.read(onlineHomeSectionsProvider.notifier).loadMore(),
      ]);
      final loaded = container
          .read(onlineHomeSectionsProvider)
          .requireValue
          .single;

      expect(loaded.books, hasLength(13));
      expect(loaded.books.last.id, 'id-13');
      expect(loaded.books.last.title, 'Book 1');
      expect(loaded.hasMore, isFalse);
      expect(gateway.rootCalls, 1);
    },
  );

  test(
    'production continuation supports five More activations across root next',
    () async {
      final gateway = _MultiPageGateway();
      final container = ProviderContainer(
        overrides: [
          onlineAccessAllowedProvider.overrideWithValue(true),
          catalogSourceRepositoryProvider.overrideWithValue(
            _CatalogRepository(builtInCatalogSources.first),
          ),
          remoteCatalogGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        onlineHomeSectionsProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      var section = (await _waitForOnlineData(container)).single;
      final counts = <int>[section.books.length];
      for (var activation = 0; activation < 6; activation++) {
        expect(section.hasMore, isTrue);
        await container.read(onlineHomeSectionsProvider.notifier).loadMore();
        section = container
            .read(onlineHomeSectionsProvider)
            .requireValue
            .single;
        counts.add(section.books.length);
      }

      expect(counts, [12, 16, 20, 24, 28, 32, 36]);
      expect(section.hasMore, isTrue);
      expect(section.books.map((book) => book.id).toSet(), hasLength(36));
      expect(
        section.books.where((book) => book.title == 'Shared title'),
        hasLength(2),
      );
      expect(gateway.rootPageLoads, 0);
      expect(gateway.optionalMalformedLoads, 1);
      expect(gateway.emptyLoads, 1);
    },
  );

  test('recoverable continuation failure retries the same cursor', () async {
    final gateway = _MultiPageGateway(failOnceAt: 20);
    final container = ProviderContainer(
      overrides: [
        onlineAccessAllowedProvider.overrideWithValue(true),
        catalogSourceRepositoryProvider.overrideWithValue(
          _CatalogRepository(builtInCatalogSources.first),
        ),
        remoteCatalogGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      onlineHomeSectionsProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);

    var section = (await _waitForOnlineData(container)).single;
    await container.read(onlineHomeSectionsProvider.notifier).loadMore();
    section = container.read(onlineHomeSectionsProvider).requireValue.single;
    expect(section.books, hasLength(16));
    await container.read(onlineHomeSectionsProvider.notifier).loadMore();
    section = container.read(onlineHomeSectionsProvider).requireValue.single;
    expect(section.books, hasLength(16));
    expect(section.loadMoreFailed, isTrue);
    expect(section.isLoadingMore, isFalse);
    expect(section.hasMore, isTrue);

    await container.read(onlineHomeSectionsProvider.notifier).loadMore();
    section = container.read(onlineHomeSectionsProvider).requireValue.single;
    expect(section.books, hasLength(20));
    expect(section.loadMoreFailed, isFalse);
    expect(gateway.failedLoads, 1);
  });

  test('production controller performs zero gateway calls Offline', () async {
    final gateway = _Gateway(_page());
    final container = ProviderContainer(
      overrides: [
        onlineAccessAllowedProvider.overrideWithValue(false),
        catalogSourceRepositoryProvider.overrideWithValue(
          _CatalogRepository(builtInCatalogSources.first),
        ),
        remoteCatalogGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(onlineHomeSectionsProvider),
      const AsyncData<List<OnlineHomeSection>>([]),
    );
    await Future<void>.delayed(Duration.zero);
    expect(gateway.rootCalls, 0);
  });
}

Finder _homeScrollable() => find
    .descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    )
    .first;

Widget _subject({
  required List<LibraryBook> books,
  List<OnlineHomeSection>? online,
  _FakeOnlineController? controller,
  bool onlineAllowed = true,
  HomeOnlineStateSnapshot snapshot = const HomeOnlineStateSnapshot(
    byPublication: {},
    downloadsCount: 0,
  ),
  List<CatalogSource>? configuredLibraries,
  Map<String, _FakeOnlineController>? onlineControllers,
  Map<String, bool> homeVisibility = const {},
  Stream<Map<String, bool>>? visibilityChanges,
  HomeDefaultCarouselSettingsRepository? homeDefaultCarouselRepository,
  Key? providerScopeKey,
  LibraryViewMode mode = LibraryViewMode.grid,
  bool dark = false,
  double scale = 1,
}) {
  final onlineController =
      controller ?? _FakeOnlineController(AsyncData(online ?? _online()));
  final controllers = {
    homeCatalogSourceId: onlineController,
    ...?onlineControllers,
  };
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: AppRoutes.downloadsPath,
        name: AppRoutes.downloadsName,
        builder: (_, _) => const Text('Downloads destination'),
      ),
      GoRoute(
        path: AppRoutes.bookDetailsPath,
        name: AppRoutes.bookDetailsName,
        builder: (_, state) =>
            Text('Local details ${state.pathParameters['bookId']}'),
      ),
      GoRoute(
        path: AppRoutes.searchOnlineLibraryPath,
        name: AppRoutes.searchOnlineLibraryName,
        builder: (_, _) => const Text('Catalog search destination'),
      ),
      GoRoute(
        path: AppRoutes.browseOnlineLibraryPath,
        name: AppRoutes.browseOnlineLibraryName,
        builder: (_, _) => const Text('Catalog browse destination'),
      ),
      GoRoute(
        path: AppRoutes.publicationOnlineLibraryPath,
        name: AppRoutes.publicationOnlineLibraryName,
        builder: (_, state) {
          final request = state.extra! as RemotePublicationDetailsRequest;
          return Text('Publication ${request.publication.remoteId}');
        },
      ),
    ],
  );
  return ProviderScope(
    key: providerScopeKey,
    overrides: [
      libraryViewModeProvider.overrideWith(() => _LayoutMode(mode)),
      libraryRepositoryProvider.overrideWithValue(_LibraryRepository(books)),
      allReadingProgressProvider.overrideWith(
        (ref) => Stream.value(<ReadingProgress>[]),
      ),
      onlineAccessAllowedProvider.overrideWithValue(onlineAllowed),
      for (final entry in controllers.entries)
        onlineHomeSectionsForLibraryProvider(
          entry.key,
        ).overrideWith(() => entry.value),
      catalogSourcesProvider.overrideWith(
        (ref) => Stream.value(
          configuredLibraries ??
              [
                builtInCatalogSources.firstWhere(
                  (source) => source.id == homeCatalogSourceId,
                ),
              ],
        ),
      ),
      homeOnlineTabVisibilityProvider.overrideWith(
        (ref) => visibilityChanges ?? Stream.value(homeVisibility),
      ),
      homeDefaultCarouselSettingsRepositoryProvider.overrideWithValue(
        homeDefaultCarouselRepository ??
            _MemoryHomeDefaultCarouselSettingsRepository(),
      ),
      homeOnlineStateProvider.overrideWithValue(snapshot),
    ],
    child: MaterialApp.router(
      theme: buildAppTheme(
        dark ? fallbackDarkColorScheme : fallbackLightColorScheme,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      routerConfig: router,
    ),
  );
}

class _MemoryHomeDefaultCarouselSettingsRepository
    implements HomeDefaultCarouselSettingsRepository {
  _MemoryHomeDefaultCarouselSettingsRepository([
    this.value = HomeDefaultCarousel.recentlyOpened,
  ]);

  HomeDefaultCarousel value;

  @override
  Future<HomeDefaultCarousel> load() async => value;

  @override
  Future<void> save(HomeDefaultCarousel carousel) async => value = carousel;
}

List<OnlineHomeSection> _online({
  List<RemoteCatalogPublicationSummary>? publications,
  bool hasMore = false,
  bool isInitialResolving = false,
}) => [
  OnlineHomeSection(
    id: homeCatalogSourceId,
    title: 'Project Gutenberg',
    searchCapability: RemoteCatalogSearchCapability.directTemplate(
      RemoteCatalogLocation.parse(
        'https://example.test/search?q={searchTerms}',
      ),
    ),
    books: (publications ?? [_publication('remote-1', 'Remote One')])
        .map(
          (publication) => OnlineHomeBook(
            sourceId: homeCatalogSourceId,
            sourceName: 'Project Gutenberg',
            publication: publication,
          ),
        )
        .toList(),
    hasMore: hasMore,
    isInitialResolving: isInitialResolving,
  ),
];

RemoteCatalogPublicationSummary _publication(
  String id,
  String title, {
  List<String> authors = const ['Remote Author'],
}) => RemoteCatalogPublicationSummary(
  remoteId: id,
  title: title,
  authors: authors,
  acquisitions: [
    RemoteAcquisition(
      relation: 'http://opds-spec.org/acquisition',
      href: 'https://example.test/$id.epub',
      mediaType: 'application/epub+zip',
    ),
  ],
);

RemoteCatalogPage _page() => RemoteCatalogPage(
  sourceId: homeCatalogSourceId,
  location: RemoteCatalogLocation.parse('https://example.test/root'),
  title: 'Root',
  publications: [_publication('remote-1', 'Remote One')],
);

Future<List<OnlineHomeSection>> _waitForOnlineData(
  ProviderContainer container,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final value = container.read(onlineHomeSectionsProvider);
    if (value case AsyncData(
      :final value,
    ) when value.isNotEmpty && !value.first.isInitialResolving) {
      return value;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Online Home data did not load');
}

Future<Object> _waitForOnlineError(ProviderContainer container) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final value = container.read(onlineHomeSectionsProvider);
    if (value case AsyncError(:final error)) return error;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Online Home error did not load');
}

Future<OnlineHomeSection> _waitForBookCount(
  ProviderContainer container,
  int count,
) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    final section = container
        .read(onlineHomeSectionsProvider)
        .asData
        ?.value
        .firstOrNull;
    if (section != null && section.books.length >= count) return section;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Online Home did not reach $count books');
}

Future<OnlineHomeSection> _waitForPendingSlots(
  ProviderContainer container,
  int count,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final section = container
        .read(onlineHomeSectionsProvider)
        .asData
        ?.value
        .firstOrNull;
    if (section != null &&
        section.slots.where((slot) => slot.isPending).length == count) {
      return section;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Online Home did not publish $count pending slots');
}

Future<OnlineHomeSection> _waitForLoadedSlotCount(
  ProviderContainer container,
  int count,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final section = container
        .read(onlineHomeSectionsProvider)
        .asData
        ?.value
        .firstOrNull;
    if (section != null &&
        section.slots.where((slot) => !slot.isPending).length == count) {
      return section;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Online Home did not reach $count loaded slots');
}

Future<List<OnlineHomeSection>> _waitForOnlineSettled(
  ProviderContainer container,
) async {
  for (var attempt = 0; attempt < 300; attempt++) {
    final sections = container.read(onlineHomeSectionsProvider).asData?.value;
    if (sections != null &&
        sections.isNotEmpty &&
        !sections.first.isInitialResolving) {
      return sections;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Online Home did not settle');
}

class _FakeOnlineController extends OnlineHomeSectionsController {
  _FakeOnlineController(this.initial, {this.next, this.nextStates = const []});

  final AsyncValue<List<OnlineHomeSection>> initial;
  final AsyncValue<List<OnlineHomeSection>>? next;
  final List<AsyncValue<List<OnlineHomeSection>>> nextStates;
  var buildCalls = 0;
  var retryCalls = 0;
  var loadMoreCalls = 0;
  var _nextStateIndex = 0;

  @override
  AsyncValue<List<OnlineHomeSection>> build() {
    buildCalls++;
    return initial;
  }

  @override
  Future<void> retry() async {
    retryCalls++;
  }

  @override
  Future<void> loadMore() async {
    loadMoreCalls++;
    if (_nextStateIndex < nextStates.length) {
      state = nextStates[_nextStateIndex++];
    } else if (next != null) {
      state = next!;
    }
  }
}

class _Gateway implements RemoteCatalogGateway {
  _Gateway(this.page);

  final RemoteCatalogPage page;
  var rootCalls = 0;
  var searchCalls = 0;

  @override
  Future<RemoteCatalogPage> loadRoot(CatalogSource source) async {
    rootCalls++;
    return page;
  }

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) async => page;

  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) async {
    searchCalls++;
    return page;
  }
}

class _OutOfOrderSlotGateway implements RemoteCatalogGateway {
  var active = 0;
  var maxActive = 0;

  @override
  Future<RemoteCatalogPage> loadRoot(CatalogSource source) async =>
      RemoteCatalogPage(
        sourceId: source.id,
        location: RemoteCatalogLocation.parse('https://example.test/root'),
        title: 'Root',
        navigation: [
          for (var index = 1; index <= 4; index++)
            RemoteCatalogNavigationLink(
              title: 'Slot $index',
              location: RemoteCatalogLocation.parse(
                'https://example.test/slot-$index',
              ),
            ),
        ],
      );

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) async {
    active++;
    maxActive = maxActive < active ? active : maxActive;
    final index = int.parse(location.uri.path.split('-').last);
    try {
      await Future<void>.delayed(
        Duration(milliseconds: index == 1 ? 90 : index * 8),
      );
      return RemoteCatalogPage(
        sourceId: source.id,
        location: location,
        title: 'Slot $index',
        publications: [_publication('$index', 'Slot Book $index')],
      );
    } finally {
      active--;
    }
  }

  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) async => throw UnimplementedError();
}

class _ConcurrentGateway implements RemoteCatalogGateway {
  var active = 0;
  var maxActive = 0;
  var pageCalls = 0;

  @override
  Future<RemoteCatalogPage> loadRoot(CatalogSource source) async =>
      RemoteCatalogPage(
        sourceId: source.id,
        location: RemoteCatalogLocation.parse('https://example.test/root'),
        title: 'Root',
        navigation: [
          for (var index = 1; index <= 25; index++)
            RemoteCatalogNavigationLink(
              title: 'Navigation $index',
              location: RemoteCatalogLocation.parse(
                'https://example.test/concurrent-$index',
              ),
            ),
        ],
      );

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) async {
    pageCalls++;
    active++;
    maxActive = maxActive < active ? active : maxActive;
    final index = int.parse(location.uri.path.split('-').last);
    try {
      await Future<void>.delayed(
        Duration(
          milliseconds: index <= 4
              ? index * 20
              : index <= 8
              ? (9 - index) * 15
              : 70,
        ),
      );
      return RemoteCatalogPage(
        sourceId: source.id,
        location: location,
        title: 'Concurrent $index',
        publications: [_publication('$index', 'Concurrent Book $index')],
      );
    } finally {
      active--;
    }
  }

  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) async => throw UnimplementedError();
}

class _PendingRootGateway implements RemoteCatalogGateway {
  final rootStarted = Completer<void>();
  final _root = Completer<RemoteCatalogPage>();

  bool get rootCompleted => _root.isCompleted;

  @override
  Future<RemoteCatalogPage> loadRoot(CatalogSource source) {
    if (!rootStarted.isCompleted) rootStarted.complete();
    return _root.future;
  }

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) => throw UnimplementedError();

  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) => throw UnimplementedError();
}

class _PaginationPendingGateway implements RemoteCatalogGateway {
  _PaginationPendingGateway()
    : _pages = {
        for (var index = 1; index <= 4; index++)
          index: Completer<RemoteCatalogPage>(),
      };

  final Map<int, Completer<RemoteCatalogPage>> _pages;
  final allPagesStarted = Completer<void>();
  var _startedPages = 0;

  @override
  Future<RemoteCatalogPage> loadRoot(CatalogSource source) async =>
      RemoteCatalogPage(
        sourceId: source.id,
        location: RemoteCatalogLocation.parse('https://example.test/root'),
        title: 'Root',
        publications: [
          for (var index = 1; index <= 12; index++)
            _publication('$index', 'Initial Book $index'),
        ],
        navigation: [
          for (var index = 1; index <= 4; index++)
            RemoteCatalogNavigationLink(
              title: 'Page $index',
              location: RemoteCatalogLocation.parse(
                'https://example.test/page-$index',
              ),
            ),
        ],
      );

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) {
    final index = int.parse(location.uri.path.split('-').last);
    _startedPages++;
    if (_startedPages == 4 && !allPagesStarted.isCompleted) {
      allPagesStarted.complete();
    }
    return _pages[index]!.future;
  }

  void completePage(int index) => _pages[index]!.complete(
    RemoteCatalogPage(
      sourceId: homeCatalogSourceId,
      location: RemoteCatalogLocation.parse('https://example.test/page-$index'),
      title: 'Page $index',
      publications: [_publication('page-$index', 'Page Book $index')],
    ),
  );

  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) => throw UnimplementedError();
}

class _RootRetryGateway implements RemoteCatalogGateway {
  var rootCalls = 0;

  @override
  Future<RemoteCatalogPage> loadRoot(CatalogSource source) async {
    rootCalls++;
    if (rootCalls == 1) {
      throw const RemoteCatalogException.httpStatus(
        'Remote catalog returned HTTP 504.',
      );
    }
    return RemoteCatalogPage(
      sourceId: source.id,
      location: RemoteCatalogLocation.parse('https://example.test/root'),
      title: 'Root',
      publications: [_publication('root-retry', 'Root Retry Book')],
    );
  }

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) async => throw UnimplementedError();

  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) async => throw UnimplementedError();
}

class _MultiPageGateway implements RemoteCatalogGateway {
  _MultiPageGateway({this.failOnceAt});

  final int? failOnceAt;
  var rootPageLoads = 0;
  var optionalMalformedLoads = 0;
  var emptyLoads = 0;
  var failedLoads = 0;

  @override
  Future<RemoteCatalogPage> loadRoot(CatalogSource source) async =>
      _navigationPage(
        1,
        40,
        next: '/root-2',
        publications: [_publication('1', 'Book 1')],
      );

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) async {
    if (location.uri.path == '/root-2') {
      rootPageLoads++;
      return _navigationPage(41, 80);
    }
    final match = RegExp(r'/nav-(\d+)$').firstMatch(location.uri.path);
    final index = int.parse(match!.group(1)!);
    if (index == failOnceAt && failedLoads == 0) {
      failedLoads++;
      throw const RemoteCatalogException.transport();
    }
    if (index == 14) {
      emptyLoads++;
      return _publicationPage(index, const []);
    }
    if (index == 15) {
      optionalMalformedLoads++;
      throw const RemoteCatalogException.malformedCatalogResponse();
    }
    final id = index == 13 ? 'https://www.gutenberg.org/ebooks/1/' : '$index';
    final title = index == 16 || index == 17 ? 'Shared title' : 'Book $index';
    return _publicationPage(index, [_publication(id, title)]);
  }

  RemoteCatalogPage _navigationPage(
    int first,
    int last, {
    String? next,
    List<RemoteCatalogPublicationSummary> publications = const [],
  }) => RemoteCatalogPage(
    sourceId: homeCatalogSourceId,
    location: RemoteCatalogLocation.parse(
      first == 1 ? 'https://example.test/root' : 'https://example.test/root-2',
    ),
    title: 'Root',
    publications: publications,
    navigation: [
      for (var index = first; index <= last; index++)
        RemoteCatalogNavigationLink(
          title: 'Navigation $index',
          location: RemoteCatalogLocation.parse(
            'https://example.test/nav-$index',
          ),
        ),
    ],
    nextPageLocation: next == null
        ? null
        : RemoteCatalogLocation.parse('https://example.test$next'),
  );

  RemoteCatalogPage _publicationPage(
    int index,
    List<RemoteCatalogPublicationSummary> publications,
  ) => RemoteCatalogPage(
    sourceId: homeCatalogSourceId,
    location: RemoteCatalogLocation.parse('https://example.test/nav-$index'),
    title: 'Book $index',
    publications: publications,
  );

  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) async => throw UnimplementedError();
}

class _FixtureHttpClient implements HttpCatalogClient {
  _FixtureHttpClient({this.failingIndexes = const {}});

  final Set<int> failingIndexes;
  var requests = 0;

  @override
  Future<HttpCatalogResponse> get({
    required RemoteCatalogLocation location,
    required Map<String, String> headers,
    required Duration timeout,
    required int maximumResponseBytes,
    required int maximumRedirects,
  }) async {
    requests++;
    final match = RegExp(r'/book-(\d+)\.opds$').firstMatch(location.uri.path);
    final index = match == null ? null : int.parse(match.group(1)!);
    if (index != null && failingIndexes.contains(index)) {
      return HttpCatalogResponse(
        statusCode: 504,
        bodyBytes: const [],
        effectiveLocation: location,
        contentType: 'text/html',
      );
    }
    final body = match == null
        ? _navigationFixture()
        : _publicationFixture(index!);
    return HttpCatalogResponse(
      statusCode: 200,
      bodyBytes: utf8.encode(body),
      effectiveLocation: location,
      contentType: 'application/atom+xml',
    );
  }
}

String _navigationFixture() =>
    '''
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>https://www.gutenberg.org/ebooks/search.opds/</id>
  <title>All Books</title>
  ${[for (var index = 1; index <= 6; index++) '<entry><id>nav-$index</id><title>Navigation $index</title>'
          '<link rel="subsection" type="application/atom+xml" '
          'href="/book-$index.opds"/></entry>'].join()}
</feed>
''';

String _publicationFixture(int index) =>
    '''
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>https://www.gutenberg.org/book-$index.opds</id>
  <title>Fixture Book $index</title>
  <entry>
    <id>urn:gutenberg:$index</id>
    <title>Fixture Book $index</title>
    <author><name>Fixture Author $index</name></author>
    <link rel="http://opds-spec.org/acquisition"
      type="application/epub+zip"
      href="/ebooks/$index.epub"/>
  </entry>
</feed>
''';

class _CatalogRepository implements CatalogSourceRepository {
  _CatalogRepository(this.source);

  final CatalogSource source;

  @override
  Future<CatalogSource?> getById(String id) async =>
      id == source.id ? source : null;

  @override
  Stream<List<CatalogSource>> watchAll() => Stream.value([source]);

  @override
  Future<List<CatalogSource>> getAll() async => [source];

  @override
  Future<void> ensureBuiltInSources() async {}

  @override
  Future<CatalogSource> addCustomSource({
    required String name,
    required Uri baseUri,
  }) async => source;

  @override
  Future<void> updateCustomSource({
    required String id,
    required String name,
    required Uri baseUri,
  }) async {}

  @override
  Future<void> setEnabled({required String id, required bool enabled}) async {}

  @override
  Future<void> deleteCustomSource(String id) async {}

  @override
  Future<bool> normalizedUrlExists(
    Uri uri, {
    String? excludingSourceId,
  }) async => false;
}

LibraryBook _book({
  required String id,
  String? title,
  String? author = 'Author',
  DateTime? lastOpenedAt,
  bool isFavorite = false,
  String? catalogSourceId,
  String? remotePublicationId,
  String? coverPath,
}) => LibraryBook(
  id: id,
  title: title ?? 'Book $id',
  sortTitle: null,
  author: author,
  description: null,
  filePath: '/books/$id.epub',
  fileName: '$id.epub',
  fileExtension: 'epub',
  format: BookFormat.epub,
  mediaType: null,
  coverPath: coverPath,
  language: null,
  publisher: null,
  publishedDate: null,
  isbn: null,
  pageCount: null,
  fileSizeBytes: 1,
  dateAdded: DateTime(2026),
  lastOpenedAt: lastOpenedAt,
  isFavorite: isFavorite,
  catalogSourceId: catalogSourceId,
  remotePublicationId: remotePublicationId,
);

RemoteDownloadTask _task(RemoteDownloadTaskState state, {String id = 'task'}) =>
    RemoteDownloadTask(
      id: id,
      sourceId: homeCatalogSourceId,
      publicationRemoteId: 'remote-1',
      title: 'Remote One',
      authors: const ['Remote Author'],
      acquisitionUri: 'https://example.test/remote-1.epub',
      suggestedFilename: 'remote-1.epub',
      state: state,
      downloadedBytes: 0,
      retryCount: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

class _MutableHomeOnlineSnapshot extends Notifier<HomeOnlineStateSnapshot> {
  @override
  HomeOnlineStateSnapshot build() =>
      const HomeOnlineStateSnapshot(byPublication: {}, downloadsCount: 0);

  void set(HomeOnlineStateSnapshot value) => state = value;
}

class _LibraryRepository implements LibraryRepository {
  _LibraryRepository(this.books);

  final List<LibraryBook> books;

  @override
  Stream<List<LibraryBook>> watchAllBooks() => Stream.value(books);

  @override
  Stream<List<LibraryBook>> watchFavoriteBooks() => Stream.value(
    books.where((book) => book.isFavorite).toList(growable: false),
  );

  @override
  Stream<List<LibraryBook>> watchUnsortedBooks() => watchAllBooks();

  @override
  Future<List<LibraryBook>> getAllBooks() async => books;

  @override
  Future<LibraryBook?> getBookById(String id) async =>
      books.where((book) => book.id == id).firstOrNull;

  @override
  Future<LibraryBook?> findBookByFilePath(String filePath) async => null;

  @override
  Future<LibraryBook?> findBookByOriginalFilePath(
    String originalFilePath,
  ) async => null;

  @override
  Future<void> addBook(LibraryBook book) async {}

  @override
  Future<void> updateBook(LibraryBook book) async {}

  @override
  Future<void> deleteBook(String id) async {}

  @override
  Future<void> setFavorite(String id, bool isFavorite) async {}

  @override
  Future<void> markBookOpened(String id, DateTime openedAt) async {}
}

class _LayoutMode extends LibraryViewModeNotifier {
  _LayoutMode([this.initial = LibraryViewMode.grid]);
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

// Isolated Home composition: all state is supplied; a presentation rebuild
// cannot start a catalog fetch or the download/import pipeline.
HomeOnlineStateSnapshot _phase33Snapshot({
  HomeOnlineBookPhase phase = HomeOnlineBookPhase.idle,
  LibraryBook? local,
}) => HomeOnlineStateSnapshot(
  byPublication: {
    homeOnlineIdentity(homeCatalogSourceId, 'remote-1'): HomeOnlineBookState(
      phase: phase,
      downloadedBytes: 50,
      totalBytes: 100,
    ),
  },
  downloadsCount: 0,
  localBooksByPublication: {
    homeOnlineIdentity(homeCatalogSourceId, 'remote-1'): ?local,
  },
);

Widget _phase33Subject({
  LibraryBook? local,
  HomeOnlineBookPhase phase = HomeOnlineBookPhase.idle,
  HomeOnlineStateSnapshot? snapshot,
  Map<String, String> metadata = const {},
  LibraryViewMode mode = LibraryViewMode.list,
  bool dark = false,
  double scale = 1,
  bool pending = false,
}) => ProviderScope(
  overrides: [
    homeOnlineStateProvider.overrideWithValue(
      snapshot ?? _phase33Snapshot(phase: phase, local: local),
    ),
    allBooksProvider.overrideWithValue(AsyncData([?local])),
    readingProgressProvider.overrideWith((ref, bookId) => Stream.value(null)),
    onlineHomeSectionsForLibraryProvider(homeCatalogSourceId).overrideWith(
      () =>
          throw StateError('List presentation must not request catalog pages'),
    ),
  ],
  child: MaterialApp(
    theme: buildAppTheme(
      dark ? fallbackDarkColorScheme : fallbackLightColorScheme,
    ),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: CustomScrollView(
            slivers: [
              HomeOnlineCatalogGrid(
                mode: mode,
                slots: pending
                    ? [
                        OnlineHomeSlot.pending(
                          slotId: 0,
                          sourceIndex: 0,
                          attempt: 0,
                        ),
                      ]
                    : const [],
                books: [
                  OnlineHomeBook(
                    sourceId: homeCatalogSourceId,
                    sourceName: 'Project Gutenberg',
                    publication: RemoteCatalogPublicationSummary(
                      remoteId: 'remote-1',
                      title: 'Remote One',
                      authors: const ['Author'],
                      accessMetadata: metadata,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

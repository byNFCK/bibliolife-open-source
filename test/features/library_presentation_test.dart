import 'package:bibliolife/features/collections/domain/models/collection_summary.dart';
import '../support/unified_book_list_assertions.dart';
import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/settings/presentation/widgets/settings_body.dart';
import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:drift/native.dart';
import 'dart:ui' as ui;

import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/app/router/app_shell.dart';
import 'package:bibliolife/features/search/presentation/screens/search_screen.dart';
import 'package:bibliolife/features/home/presentation/screens/home_screen.dart';
import 'package:bibliolife/features/home/application/providers/home_online_state_provider.dart';
import 'package:bibliolife/features/home/application/providers/home_online_tab_settings_provider.dart';
import 'package:bibliolife/features/home/application/providers/home_default_carousel_provider.dart';
import 'package:bibliolife/features/home/domain/models/home_online_book_state.dart';
import 'package:bibliolife/features/connectivity/application/app_connectivity_mode_provider.dart';
import 'package:bibliolife/features/library/application/providers/library_repository_provider.dart';
import 'package:bibliolife/features/library/application/providers/library_section_provider.dart';
import 'package:bibliolife/features/library/domain/library_section_settings_repository.dart';
import 'package:bibliolife/features/collections/application/providers/collection_repository_provider.dart';
import 'package:bibliolife/features/collections/domain/models/library_collection.dart';
import 'package:bibliolife/features/collections/domain/repositories/collection_repository.dart';
import 'package:bibliolife/features/collections/presentation/widgets/collection_card.dart';
import 'package:bibliolife/features/collections/presentation/screens/collections_screen.dart';
import 'package:bibliolife/app/theme/app_theme.dart';
import 'package:bibliolife/features/import/application/providers/import_repository_provider.dart';
import 'package:bibliolife/features/import/domain/entities/import_result.dart';
import 'package:bibliolife/features/import/domain/repositories/import_repository.dart';
import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';
import 'package:bibliolife/features/library/presentation/screens/library_screen.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_header.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_providers.dart';
import 'package:bibliolife/features/reader/domain/models/reading_progress.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:bibliolife/shared/presentation/widgets/biblio_tabs.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_image.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_render_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  LibrarySection? selectedTab(WidgetTester tester) => tester
      .widget<BiblioTabs<LibrarySection>>(
        find.byType(BiblioTabs<LibrarySection>).hitTestable().first,
      )
      .selectedId;

  Widget buildSubject(
    Widget child,
    LibraryRepository repository, {
    ImportRepository? importRepository,
    ThemeData? theme,
    GoRouter? router,
    TextScaler? textScaler,
    ProviderContainer? container,
    LibrarySection defaultSection = LibrarySection.allBooks,
    LibrarySectionSettingsRepository? settingsRepository,
  }) {
    final app = router == null
        ? MaterialApp(
            theme: theme ?? lightTheme,
            home: child,
            builder: textScaler == null
                ? null
                : (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: textScaler),
                    child: child!,
                  ),
          )
        : MaterialApp.router(theme: theme ?? lightTheme, routerConfig: router);
    if (container != null) {
      return UncontrolledProviderScope(container: container, child: app);
    }
    return ProviderScope(
      key: child.key,
      overrides: _libraryOverrides(
        repository,
        importRepository: importRepository,
        defaultSection: defaultSection,
        settingsRepository: settingsRepository,
      ),
      child: app,
    );
  }

  Finder verticalScrollable() => find
      .descendant(
        of: find.byType(PageView),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      )
      .hitTestable();

  RenderLibraryHeaderBackdrop tabsBackdrop(WidgetTester tester) =>
      tester
              .renderObject<RenderSliverOverlapAbsorber>(
                find.byType(SliverOverlapAbsorber),
              )
              .child!
          as RenderLibraryHeaderBackdrop;

  Rect backdropRect(WidgetTester tester) {
    final backdrop = tabsBackdrop(tester);
    return MatrixUtils.transformRect(
      backdrop.getTransformTo(null),
      backdrop.gradientBounds,
    );
  }

  testWidgets(
    'Library search and Create collection open their existing routes',
    (tester) async {
      final router = GoRouter(
        initialLocation: AppRoutes.libraryPath,
        routes: [
          GoRoute(
            path: AppRoutes.libraryPath,
            builder: (_, _) => const LibraryScreen(),
          ),
          GoRoute(
            path: AppRoutes.searchPath,
            name: AppRoutes.searchName,
            builder: (_, _) => const SearchScreen(),
          ),
          GoRoute(
            path: AppRoutes.createCollectionPath,
            name: AppRoutes.createCollectionName,
            builder: (_, _) => const Scaffold(body: Text('Collection editor')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        buildSubject(
          const LibraryScreen(),
          _FakeRepository([_book(id: 'book-1')]),
          router: router,
        ),
      );
      await tester.pumpAndSettle();

      final search = find.text('Search books').hitTestable();
      await tester.tapAt(tester.getCenter(search) - const Offset(25, 0));
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'unmatched');
      await tester.pumpAndSettle();
      expect(find.text('No matching books'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Collection').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Create collection').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Collection editor'), findsOneWidget);
    },
  );

  testWidgets(
    'Library swipes only content and keeps one stationary header and nav bar',
    (tester) async {
      final router = GoRouter(
        initialLocation: AppRoutes.libraryPath,
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (_, _, shell) => AppShell(navigationShell: shell),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: AppRoutes.homePath,
                    builder: (_, _) => const SizedBox(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: AppRoutes.libraryPath,
                    builder: (_, _) => const LibraryScreen(),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: AppRoutes.profilePath,
                    builder: (_, _) => const SizedBox(),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        buildSubject(
          const LibraryScreen(),
          _FakeRepository([
            _book(id: 'favorite', isFavorite: true),
            _book(id: 'ordinary'),
          ]),
          router: router,
        ),
      );
      await tester.pumpAndSettle();

      final page = find.byType(PageView);
      final controller = tester.widget<PageView>(page).controller!;
      final sharedControls = [
        find.byKey(const Key('library-search')),
        find.byKey(const Key('library-section-tab-bar')),
        find.byKey(const Key('navigation-island-surface')),
      ];
      final add = find.byIcon(Icons.add);
      final toggle = find.byTooltip('Show list view');
      final originalRects = [
        ...sharedControls,
        add,
        toggle,
      ].map(tester.getRect).toList();
      final sharedElements = sharedControls.map(tester.element).toList();
      final originalBackdrop = backdropRect(tester);

      void expectStationary({bool showToggle = true}) {
        expect(backdropRect(tester), originalBackdrop);
        final controls = [...sharedControls, add, if (showToggle) toggle];
        for (var index = 0; index < controls.length; index++) {
          expect(controls[index], findsOneWidget);
          final current = tester.getRect(controls[index]);
          final original = originalRects[index];
          expect(current.left, closeTo(original.left, 0.1));
          expect(current.right, closeTo(original.right, 0.1));
          expect(current.top, closeTo(original.top, 0.1));
        }
        for (var index = 0; index < sharedControls.length; index++) {
          expect(
            tester.element(sharedControls[index]),
            same(sharedElements[index]),
          );
        }
        expect(find.text('Search books'), findsOneWidget);
        expect(find.byType(BiblioTabs<LibrarySection>), findsOneWidget);
        expect(find.byType(FloatingNavigationIsland), findsOneWidget);
      }

      Future<TestGesture> beginSwipe() async {
        final bounds = tester.getRect(page);
        final drag = await tester.startGesture(
          Offset(bounds.left + 100, bounds.center.dy),
        );
        await drag.moveBy(const Offset(30, 0));
        await drag.moveBy(const Offset(300, 0));
        await tester.pump();
        return drag;
      }

      expectStationary();
      final booksToFollow = await beginSwipe();
      expect(controller.page, inExclusiveRange(1.5, 2));
      expectStationary();
      final ordinary = find.text('Book ordinary');
      expect(ordinary, findsOneWidget);
      final outgoingLeft = tester.getTopLeft(ordinary).dx;
      await booksToFollow.moveBy(const Offset(250, 0));
      await tester.pump();
      expect(controller.page, inExclusiveRange(1, 1.5));
      expect(tester.getTopLeft(ordinary).dx, greaterThan(outgoingLeft));
      expect(selectedTab(tester), LibrarySection.follow);
      expectStationary();
      await booksToFollow.up();
      await tester.pumpAndSettle();
      expect(controller.page, 1);
      expectStationary();
      expect(ordinary, findsNothing);

      final followToCollections = await beginSwipe();
      expect(controller.page, inExclusiveRange(0.5, 1));
      expectStationary();
      await followToCollections.moveBy(const Offset(250, 0));
      await tester.pump();
      expect(controller.page, inExclusiveRange(0, 0.5));
      expectStationary(showToggle: false);
      expect(toggle, findsNothing);
      expect(selectedTab(tester), LibrarySection.collection);
      await followToCollections.up();
      await tester.pumpAndSettle();
      expect(controller.page, 0);
      expectStationary(showToggle: false);
      expect(find.byTooltip('Create collection'), findsOneWidget);
    },
  );

  testWidgets(
    'Library floats search, pins tabs, and preserves tab scroll positions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        buildSubject(
          const LibraryScreen(),
          _FakeRepository(
            List.generate(30, (i) => _book(id: 'book-$i', isFavorite: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tabs = find
          .byKey(const Key('library-section-tab-bar'))
          .hitTestable();
      final search = find.text('Search books').hitTestable();
      final firstBook = find.byKey(const ValueKey('library-book-card-book-0'));
      expect(search, findsOneWidget);
      expect(
        tester.getTopLeft(firstBook).dy - tester.getBottomLeft(tabs).dy,
        inInclusiveRange(12, 16),
      );

      Future<void> scroll(double dy) async {
        await tester.timedDrag(
          verticalScrollable(),
          Offset(0, dy),
          const Duration(milliseconds: 500),
        );
        await tester.pumpAndSettle();
      }

      ScrollPosition position() =>
          tester.state<ScrollableState>(verticalScrollable()).position;
      await scroll(-500);
      expect(search, findsNothing);
      expect(find.byTooltip('Add').hitTestable(), findsNothing);
      expect(tabs, findsOneWidget);
      expect(tester.getTopLeft(tabs).dy, closeTo(12, 1));

      final allBooksOffset = position().pixels;
      final viewport = tester.getRect(verticalScrollable());
      final swipe = await tester.startGesture(
        Offset(viewport.left + 60, viewport.center.dy),
      );
      await swipe.moveBy(const Offset(30, 0));
      await swipe.moveBy(const Offset(140, 0));
      await tester.pump();
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        inExclusiveRange(1.5, 2),
      );
      expect(
        find.byType(BiblioTabs<LibrarySection>, skipOffstage: false),
        findsOneWidget,
      );
      expect(search, findsNothing);
      expect(tester.getTopLeft(tabs).dy, closeTo(12, 1));
      await swipe.moveBy(const Offset(110, 0));
      await swipe.up();
      await tester.pumpAndSettle();
      expect(selectedTab(tester), LibrarySection.follow);
      expect(position().pixels, 0);
      expect(search, findsNothing);
      await scroll(120);
      expect(search, findsOneWidget);
      expect(position().pixels, 0);
      await scroll(-320);
      final followOffset = position().pixels;
      expect(followOffset, greaterThan(100));

      // Reveal the last tab in the shared strip without moving the page.
      await tester.drag(tabs, const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(selectedTab(tester), LibrarySection.follow);
      expect(position().pixels, followOffset);
      expect(tester.getTopLeft(tabs).dy, closeTo(12, 1));
      final allBooksTab = find
          .byKey(const Key('library-tab-all-books'))
          .hitTestable();
      expect(allBooksTab, findsOneWidget);
      await tester.tap(allBooksTab);
      await tester.pumpAndSettle();
      expect(position().pixels, allBooksOffset);
      await scroll(120);
      expect(position().pixels, greaterThan(100));
      expect(search, findsOneWidget);
      expect(tabs, findsOneWidget);
      expect(
        tester.getBottomLeft(search).dy,
        lessThan(tester.getTopLeft(tabs).dy),
      );

      await tester.tap(find.text('Follow').hitTestable());
      await tester.pumpAndSettle();
      expect(position().pixels, followOffset);
      expect(search, findsOneWidget);

      await tester.tap(find.byTooltip('Show list view').hitTestable());
      await tester.pumpAndSettle();
      expect(position().pixels, 0);
      await tester.tap(find.byTooltip('Show grid view').hitTestable());
      await tester.pumpAndSettle();
      expect(position().pixels, followOffset);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Pinned tabs retain their 12 dp gap and blend the gradient over scrolling covers',
    (tester) async {
      const boundaryKey = Key('library-paint-boundary');
      const statusBarHeight = 24.0;
      final statusBar = FakeViewPadding(
        top: statusBarHeight * tester.view.devicePixelRatio,
      );
      tester.view.padding = statusBar;
      tester.view.viewPadding = statusBar;
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await tester.pumpWidget(
        buildSubject(
          const RepaintBoundary(key: boundaryKey, child: LibraryScreen()),
          _FakeRepository(
            List.generate(12, (index) => _book(id: 'book-$index')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tabs = find.byType(BiblioTabs<LibrarySection>);
      expect(tabs, findsOneWidget);
      final capsule = find.descendant(
        of: tabs,
        matching: find.byWidgetPredicate(
          (widget) => widget is Material && widget.shape is StadiumBorder,
        ),
      );
      final book = find.byKey(const ValueKey('library-book-card-book-0'));
      final search = find.byKey(const Key('library-search'));
      final expandedSearch = tester.getRect(search);
      final expandedCapsule = tester.getRect(capsule);
      expect(expandedSearch.top, statusBarHeight + 16);
      expect(expandedCapsule.top - expandedSearch.bottom, 16);
      expect(tester.getTopLeft(book).dy - expandedCapsule.bottom, 16);
      final expandedBackdrop = backdropRect(tester);
      expect(expandedBackdrop.top, statusBarHeight);
      expect(expandedBackdrop.bottom, expandedCapsule.bottom);
      final outer = tester
          .state<NestedScrollViewState>(find.byType(NestedScrollView))
          .outerController;
      for (final offset in [20.0, 40.0, 60.0, 40.0, 20.0, 0.0]) {
        outer.jumpTo(offset);
        await tester.pump();
        expect(backdropRect(tester).top, statusBarHeight);
        expect(backdropRect(tester).bottom, tester.getRect(capsule).bottom);
        expect(backdropRect(tester).height, expandedBackdrop.height - offset);
      }

      tester.state<ScrollableState>(verticalScrollable()).position.jumpTo(100);
      await tester.pumpAndSettle();

      expect(search.hitTestable(), findsNothing);
      final capsuleRect = tester.getRect(capsule);
      expect(capsuleRect.top - statusBarHeight, closeTo(12, 0.1));
      expect(capsuleRect.height, expandedCapsule.height);

      final cover = find.descendant(
        of: book,
        matching: find.byKey(const Key('app-book-card-cover')),
      );
      final coverRect = tester.getRect(cover);
      final above = Offset(coverRect.center.dx, statusBarHeight + 6);
      final beside = Offset(coverRect.center.dx, capsuleRect.center.dy);
      final below = Offset(coverRect.center.dx, capsuleRect.bottom + 8);
      final fadeTail = Offset(coverRect.center.dx, capsuleRect.bottom + 40);
      final beyondFade = Offset(coverRect.center.dx, capsuleRect.bottom + 52);
      expect(beside.dx, lessThan(capsuleRect.left));
      final samplePoints = [above, beside, below, fadeTail, beyondFade];
      expect(samplePoints.every(coverRect.contains), isTrue);

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byWidgetPredicate(
          (widget) => widget is RepaintBoundary && widget.key == boundaryKey,
        ),
      );
      final pixels = await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          return samplePoints.map((point) {
            final offset =
                (point.dy.floor() * image.width + point.dx.floor()) * 4;
            return Color.fromARGB(
              bytes.getUint8(offset + 3),
              bytes.getUint8(offset),
              bytes.getUint8(offset + 1),
              bytes.getUint8(offset + 2),
            );
          }).toList();
        } finally {
          image.dispose();
        }
      });
      final bounds = backdropRect(tester);
      expect(bounds.top, statusBarHeight);
      expect(bounds.bottom, capsuleRect.bottom);
      final surface = lightTheme.scaffoldBackgroundColor;
      final coverColor = lightTheme.colorScheme.secondaryContainer;
      for (final (index, pixel) in pixels!.indexed) {
        final y = samplePoints[index].dy.floor() + 0.5;
        final fraction = (y - bounds.top) / bounds.height;
        final alpha = switch (fraction) {
          < 1 => 1 - fraction * fraction * (3 - 2 * fraction),
          _ => 0.0,
        };
        final expected = Color.alphaBlend(
          surface.withValues(alpha: alpha),
          coverColor,
        );
        expect(pixel.r, closeTo(expected.r, 0.01));
        expect(pixel.g, closeTo(expected.g, 0.01));
        expect(pixel.b, closeTo(expected.b, 0.01));
      }

      final bookRender = tester.renderObject(book);
      for (final point in samplePoints) {
        expect(
          tester.hitTestOnBinding(point).path.map((entry) => entry.target),
          contains(bookRender),
        );
      }
      await tester.tap(
        find.byKey(const Key('library-tab-follow')).hitTestable(),
      );
      await tester.pumpAndSettle();
      expect(selectedTab(tester), LibrarySection.follow);
    },
  );

  testWidgets(
    'Header pixels stay seamless across search and tabs while collapsing',
    (tester) async {
      const boundaryKey = Key('header-seam-pixels');
      const contentColor = Color(0xFFE04090);
      await tester.binding.setSurfaceSize(const Size(400, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final theme in [darkTheme, lightTheme]) {
        await tester.pumpWidget(
          buildSubject(
            RepaintBoundary(
              key: boundaryKey,
              child: Scaffold(
                body: NestedScrollView(
                  key: ValueKey(theme.brightness),
                  floatHeaderSlivers: true,
                  headerSliverBuilder: (context, _) => LibraryHeader.slivers(
                    initialSection: LibrarySection.allBooks,
                    overlapHandle:
                        NestedScrollView.sliverOverlapAbsorberHandleFor(
                          context,
                        ),
                  ),
                  body: Builder(
                    builder: (context) => CustomScrollView(
                      key: const Key('seam-scroll'),
                      slivers: [
                        SliverOverlapInjector(
                          handle:
                              NestedScrollView.sliverOverlapAbsorberHandleFor(
                                context,
                              ),
                        ),
                        const SliverToBoxAdapter(
                          child: SizedBox(
                            height: 1800,
                            child: ColoredBox(color: contentColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _FakeRepository([]),
            theme: theme,
          ),
        );
        await tester.pumpAndSettle();
        final inner = find.descendant(
          of: find.byKey(const Key('seam-scroll')),
          matching: find.byType(Scrollable),
        );
        tester.state<ScrollableState>(inner).position.jumpTo(300);
        await tester.pumpAndSettle();
        final pinned = tabsBackdrop(tester);
        final renderers = find.byElementPredicate(
          (element) =>
              element is RenderObjectElement &&
              element.renderObject is RenderLibraryHeaderBackdrop,
          skipOffstage: false,
        );
        expect(renderers, findsNWidgets(2));
        final search = tester.renderObject<RenderLibraryHeaderBackdrop>(
          renderers.first,
        );
        expect(search.isPinned, isFalse);
        expect(pinned.isPinned, isTrue);
        final outer = tester
            .state<NestedScrollViewState>(find.byType(NestedScrollView))
            .outerController;
        final collapsedOffset = outer.offset;
        final states = <double>[];

        // Reveal the search row while content stays behind the pinned tabs.
        for (final reveal in [0.0, 20.0, 20.0, 60.0]) {
          if (reveal > 0) {
            await tester.timedDrag(
              inner,
              Offset(0, reveal),
              const Duration(milliseconds: 400),
            );
            await tester.pumpAndSettle();
          }
          states.add(outer.offset);
          final bounds = backdropRect(tester);
          final searchBounds = MatrixUtils.transformRect(
            search.getTransformTo(null),
            search.gradientBounds,
          );
          expect(searchBounds, bounds);
          expect(search.gradient, pinned.gradient);
          final seam = MatrixUtils.transformPoint(
            pinned.getTransformTo(null),
            Offset.zero,
          ).dy;
          final fadeHeight = bounds.bottom - seam;
          final points = [
            if (seam >= 1) Offset(1, seam - 0.5),
            Offset(1, seam + 0.5),
            Offset(1, seam + fadeHeight * 0.25),
            Offset(1, seam + fadeHeight * 0.5),
            Offset(1, bounds.bottom - 0.5),
            Offset(1, bounds.bottom + 0.5),
          ];
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is RepaintBoundary && widget.key == boundaryKey,
            ),
          );
          final pixels = await tester.runAsync(() async {
            final image = await boundary.toImage();
            try {
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              return points.map((point) {
                final index =
                    (point.dy.floor() * image.width + point.dx.floor()) * 4;
                return Color.fromARGB(
                  bytes.getUint8(index + 3),
                  bytes.getUint8(index),
                  bytes.getUint8(index + 1),
                  bytes.getUint8(index + 2),
                );
              }).toList();
            } finally {
              image.dispose();
            }
          });
          for (var i = 0; i < points.length; i++) {
            final y = points[i].dy.floor() + 0.5;
            final t = ((y - seam) / fadeHeight).clamp(0.0, 1.0);
            final alpha = 1 - t * t * (3 - 2 * t);
            final expected = Color.alphaBlend(
              theme.scaffoldBackgroundColor.withValues(alpha: alpha),
              contentColor,
            );
            expect(pixels![i].r, closeTo(expected.r, 0.01));
            expect(pixels[i].g, closeTo(expected.g, 0.01));
            expect(pixels[i].b, closeTo(expected.b, 0.01));
          }
          if (seam >= 1) {
            // A contrasting cover begins here, but the pixels on either side
            // still meet at the page color instead of forming a dark panel.
            expect(pixels![0].r, closeTo(pixels[1].r, 1 / 255));
            expect(pixels[0].g, closeTo(pixels[1].g, 1 / 255));
            expect(pixels[0].b, closeTo(pixels[1].b, 1 / 255));
          }
        }
        expect(states.first, collapsedOffset);
        expect(states[1], inExclusiveRange(0, collapsedOffset));
        expect(states.last, 0);
      }
    },
  );

  testWidgets('Collection scroll collapses and reveals the shared search row', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 260));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      buildSubject(
        const LibraryScreen(),
        _FakeRepository([]),
        defaultSection: LibrarySection.collection,
      ),
    );
    await tester.pumpAndSettle();
    final search = find.byKey(const Key('library-search')).hitTestable();
    final tabs = find.byKey(const Key('library-section-tab-bar')).hitTestable();
    expect(search, findsOneWidget);

    await tester.drag(verticalScrollable(), const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(search, findsNothing);
    expect(tester.getTopLeft(tabs).dy, closeTo(12, 1));

    final card = find.byType(CollectionCard).first;
    final tabsRect = tester.getRect(tabs);
    final gapPoint = Offset(tabsRect.center.dx, tabsRect.bottom + 8);
    expect(tester.getRect(card).contains(gapPoint), isTrue);
    expect(
      tester.hitTestOnBinding(gapPoint).path.map((entry) => entry.target),
      contains(tester.renderObject(card)),
    );

    await tester.drag(verticalScrollable(), const Offset(0, 150));
    await tester.pumpAndSettle();
    expect(search, findsOneWidget);
    expect(tester.getTopLeft(tabs).dy, greaterThan(0));
    expect(selectedTab(tester), LibrarySection.collection);
  });

  testWidgets('Library shows loading state', (tester) async {
    await tester.pumpWidget(
      buildSubject(const LibraryScreen(), _LoadingRepository()),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('Library shows empty state', (tester) async {
    await tester.pumpWidget(
      buildSubject(const LibraryScreen(), _FakeRepository([])),
    );
    await tester.pump();

    expect(find.text('No books in your library'), findsOneWidget);
  });

  testWidgets(
    'Profile choice and actual Library rendering synchronize both ways',
    (tester) async {
      await tester.pumpWidget(
        buildSubject(
          const Scaffold(
            body: Column(
              children: [
                BookDisplayLayoutSettingTile(),
                Expanded(child: LibraryScreen()),
              ],
            ),
          ),
          _FakeRepository([_book(id: 'shared-layout-book')]),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('book-display-option-list')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Show grid view'), findsOneWidget);
      expect(find.byType(SliverList), findsWidgets);
      expect(
        tester
            .widget<BiblioTabs<LibraryViewMode>>(
              find.byType(BiblioTabs<LibraryViewMode>),
            )
            .selectedId,
        LibraryViewMode.list,
      );
      final context = tester.element(find.byType(LibraryScreen));
      final container = ProviderScope.containerOf(context);
      expect(container.read(libraryViewModeProvider), LibraryViewMode.list);
      await tester.tap(find.byTooltip('Show grid view'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BiblioTabs<LibraryViewMode>>(
              find.byType(BiblioTabs<LibraryViewMode>),
            )
            .selectedId,
        LibraryViewMode.grid,
      );
      expect(find.byType(SliverGrid), findsWidgets);
      expect(
        await container.read(bookDisplaySettingsRepositoryProvider).load(),
        'grid',
      );
    },
  );

  testWidgets('Follow and All books share the same clean List canvas', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(
        const LibraryScreen(),
        _FakeRepository([_book(id: 'unified', isFavorite: true)]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show list view'));
    await tester.pumpAndSettle();
    expectUnifiedBookList(tester);
    await tester.tap(find.text('Follow').hitTestable());
    await tester.pumpAndSettle();
    expectUnifiedBookList(tester);
    await tester.tap(find.text('All books').hitTestable());
    await tester.pumpAndSettle();
    expectUnifiedBookList(tester);
  });

  testWidgets('Library grid displays books and toggles to list mode', (
    tester,
  ) async {
    final repository = _FakeRepository([_book(id: 'book-1')]);
    await tester.pumpWidget(buildSubject(const LibraryScreen(), repository));
    await tester.pump();

    expect(find.text('Book book-1'), findsOneWidget);
    expect(find.byType(SliverGrid), findsOneWidget);
    expect(
      find.byKey(const ValueKey('library-book-card-book-1')),
      findsOneWidget,
    );
    expect(
      tester.widget<BookCoverImage>(find.byType(BookCoverImage)).profile,
      BookCoverRenderProfile.localLibraryGrid,
    );

    await tester.tap(find.byTooltip('Show list view'));
    await tester.pump();

    expect(find.byType(SliverList), findsOneWidget);
    expect(find.text('Book book-1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('library-book-tile-book-1')),
      findsOneWidget,
    );
    expect(
      tester.widget<BookCoverImage>(find.byType(BookCoverImage)).profile,
      BookCoverRenderProfile.localLibraryList,
    );
  });

  testWidgets(
    'All books shows the complete local dataset in grid and list modes',
    (tester) async {
      final allBooks = [
        _book(id: 'book-a'),
        _book(id: 'book-b'),
        _book(id: 'book-c'),
        _book(id: 'book-d'),
        _book(id: 'book-e'),
      ];
      final repository = _FakeRepository(allBooks);
      await tester.pumpWidget(buildSubject(const LibraryScreen(), repository));
      await tester.pumpAndSettle();

      for (final id in ['book-a', 'book-b', 'book-c', 'book-d', 'book-e']) {
        final book = find.text('Book $id');
        await tester.scrollUntilVisible(
          book,
          500,
          scrollable: verticalScrollable(),
        );
        expect(book, findsOneWidget);
      }

      tester
          .state<NestedScrollViewState>(find.byType(NestedScrollView))
          .outerController
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show list view').hitTestable());
      await tester.pumpAndSettle();
      for (final id in ['book-a', 'book-b', 'book-c', 'book-d', 'book-e']) {
        final book = find.text('Book $id');
        await tester.scrollUntilVisible(
          book,
          500,
          scrollable: verticalScrollable(),
        );
        expect(book, findsOneWidget);
      }
    },
  );

  testWidgets('Library header keeps Add and exposes the three sections', (
    tester,
  ) async {
    final imports = _FakeImportRepository();
    await tester.pumpWidget(
      buildSubject(
        const LibraryScreen(),
        _FakeRepository([_book(id: 'book-1')]),
        importRepository: imports,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.text('Add'), findsNothing);
    expect(find.byTooltip('Add'), findsOneWidget);
    expect(find.byTooltip('Show list view'), findsOneWidget);
    expect(find.byTooltip('Collections'), findsNothing);
    expect(find.text('Search books').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Search filters'), findsNothing);
    expect(find.byIcon(Icons.filter_alt_outlined), findsNothing);
    expect(find.byIcon(Icons.filter_list), findsNothing);
    expect(find.text('Collection'), findsOneWidget);
    expect(find.text('Follow'), findsOneWidget);
    expect(find.text('All books'), findsOneWidget);

    await tester.tap(find.byTooltip('Add'));
    await tester.pump();
    expect(imports.calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Library defaults to All books and scopes the view toggle', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(
        const LibraryScreen(),
        _FakeRepository([
          _book(id: 'favorite', isFavorite: true),
          _book(id: 'ordinary'),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Book favorite'), findsOneWidget);
    expect(find.text('Book ordinary'), findsOneWidget);
    expect(selectedTab(tester), LibrarySection.allBooks);
    expect(find.byTooltip('Show list view'), findsOneWidget);

    await tester.tap(find.text('Collection'));
    await tester.pumpAndSettle();
    expect(find.byType(CollectionCard), findsWidgets);
    expect(find.byTooltip('Create collection'), findsOneWidget);
    expect(find.byTooltip('Show list view'), findsNothing);

    await tester.tap(find.text('Follow'));
    await tester.pumpAndSettle();
    expect(find.text('Book favorite'), findsOneWidget);
    expect(find.text('Book ordinary'), findsNothing);
    expect(find.byTooltip('Show list view'), findsOneWidget);
  });

  testWidgets('Library initializes all sections from the configured default', (
    tester,
  ) async {
    for (final entry in {
      LibrarySection.collection: 0,
      LibrarySection.follow: 1,
      LibrarySection.allBooks: 2,
    }.entries) {
      await tester.pumpWidget(
        buildSubject(
          LibraryScreen(key: ValueKey('library-default-${entry.key.name}')),
          _FakeRepository([
            _book(id: 'favorite', isFavorite: true),
            _book(id: 'ordinary'),
          ]),
          defaultSection: entry.key,
        ),
      );
      await tester.pumpAndSettle();

      expect(selectedTab(tester), entry.key);
      expect(
        tester
            .widget<PageView>(find.byType(PageView))
            .controller!
            .page!
            .round(),
        entry.value,
      );
      if (entry.key == LibrarySection.collection) {
        expect(find.byTooltip('Create collection'), findsOneWidget);
        expect(find.byTooltip('Show list view'), findsNothing);
      } else {
        expect(find.byTooltip('Add'), findsOneWidget);
        expect(find.byTooltip('Show list view'), findsOneWidget);
      }
    }
  });

  testWidgets('Library navigation does not overwrite the persisted default', (
    tester,
  ) async {
    final settings = _MemoryLibrarySectionSettingsRepository(
      LibrarySection.collection,
    );
    final container = ProviderContainer(
      overrides: _libraryOverrides(
        _FakeRepository([_book(id: 'book-1')]),
        settingsRepository: settings,
      ),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      buildSubject(
        const LibraryScreen(),
        _FakeRepository([_book(id: 'book-1')]),
        container: container,
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(librarySectionProvider), LibrarySection.collection);
    expect(
      container.read(defaultLibrarySectionProvider).asData?.value,
      LibrarySection.collection,
    );

    await tester.tap(find.text('All books'));
    await tester.pumpAndSettle();
    expect(container.read(librarySectionProvider), LibrarySection.allBooks);
    expect(settings.section, LibrarySection.collection);
    expect(
      container.read(defaultLibrarySectionProvider).asData?.value,
      LibrarySection.collection,
    );

    await tester.tap(find.byTooltip('Show list view'));
    await tester.pump();
    expect(container.read(librarySectionProvider), LibrarySection.allBooks);
    expect(
      tester.widget<PageView>(find.byType(PageView)).controller!.page!.round(),
      2,
    );
  });

  testWidgets(
    'Library keeps the PageView subtree stable across section changes',
    (tester) async {
      await tester.pumpWidget(
        buildSubject(
          const LibraryScreen(),
          _FakeRepository([_book(id: 'book-1')]),
        ),
      );
      await tester.pumpAndSettle();

      final pageView = tester.widget<PageView>(find.byType(PageView));
      final allBooksState = tester.state<State>(
        find.byKey(const ValueKey('library-all-books-page')),
      );

      await tester.tap(find.text('Follow'));
      await tester.pumpAndSettle();

      final switchedPageView = tester.widget<PageView>(find.byType(PageView));
      expect(identical(switchedPageView, pageView), isTrue);
      final followState = tester.state<State>(
        find.byKey(const ValueKey('library-follow-page')),
      );

      await tester.tap(find.text('All books'));
      await tester.pumpAndSettle();
      expect(
        identical(
          tester.state<State>(
            find.byKey(const ValueKey('library-all-books-page')),
          ),
          allBooksState,
        ),
        isTrue,
      );

      await tester.tap(find.text('Follow'));
      await tester.pumpAndSettle();
      expect(
        identical(
          tester.state<State>(
            find.byKey(const ValueKey('library-follow-page')),
          ),
          followState,
        ),
        isTrue,
      );

      await tester.tap(find.byTooltip('Show list view'));
      await tester.pump();
      expect(
        identical(tester.widget<PageView>(find.byType(PageView)), pageView),
        isTrue,
      );
    },
  );

  testWidgets(
    'Library swipes between sections and keeps tabs and state aligned',
    (tester) async {
      final container = ProviderContainer(
        overrides: _libraryOverrides(
          _FakeRepository([
            _book(id: 'favorite', isFavorite: true),
            _book(id: 'ordinary'),
          ]),
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        buildSubject(
          const LibraryScreen(),
          _FakeRepository([
            _book(id: 'favorite', isFavorite: true),
            _book(id: 'ordinary'),
          ]),
          container: container,
        ),
      );
      await tester.pumpAndSettle();

      final pageView = find.byType(PageView);
      expect(container.read(librarySectionProvider), LibrarySection.allBooks);
      expect(tester.widget<PageView>(pageView).controller!.page!.round(), 2);

      await tester.drag(pageView, const Offset(500, 0));
      await tester.pumpAndSettle();
      expect(container.read(librarySectionProvider), LibrarySection.follow);
      expect(selectedTab(tester), LibrarySection.follow);
      expect(find.text('Book favorite'), findsOneWidget);
      expect(find.text('Book ordinary'), findsNothing);

      await tester.drag(pageView, const Offset(500, 0));
      await tester.pumpAndSettle();
      expect(container.read(librarySectionProvider), LibrarySection.collection);
      expect(selectedTab(tester), LibrarySection.collection);
      expect(find.byType(CollectionCard), findsWidgets);
      expect(find.byTooltip('Create collection'), findsOneWidget);
      expect(find.byTooltip('Show list view'), findsNothing);

      await tester.drag(pageView, const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(container.read(librarySectionProvider), LibrarySection.follow);
      expect(find.byTooltip('Show list view'), findsOneWidget);

      await tester.drag(pageView, const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(container.read(librarySectionProvider), LibrarySection.allBooks);
      expect(selectedTab(tester), LibrarySection.allBooks);
      expect(find.text('Book ordinary'), findsOneWidget);

      await tester.tap(find.text('Collection'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.widget<PageView>(pageView).controller!.page!.round(), 1);
      expect(selectedTab(tester), LibrarySection.collection);
      await tester.pumpAndSettle();
      expect(tester.widget<PageView>(pageView).controller!.page!.round(), 0);
      expect(selectedTab(tester), LibrarySection.collection);

      await tester.tap(find.text('Follow'));
      await tester.pumpAndSettle();
      expect(container.read(librarySectionProvider), LibrarySection.follow);
      expect(tester.widget<PageView>(pageView).controller!.page!.round(), 1);
    },
  );

  testWidgets('Library swipes stay on the first and last section', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(
        const LibraryScreen(),
        _FakeRepository([_book(id: 'book-1')]),
      ),
    );
    await tester.pumpAndSettle();

    final pageView = find.byType(PageView);
    await tester.drag(pageView, const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<PageView>(pageView).controller!.page!.round(), 2);

    await tester.tap(find.text('Collection'));
    await tester.pumpAndSettle();
    await tester.drag(pageView, const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<PageView>(pageView).controller!.page!.round(), 0);
    expect(find.byType(CollectionCard), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Library vertical scrolling does not change the selected page', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(
        const LibraryScreen(),
        _FakeRepository(List.generate(20, (index) => _book(id: 'book-$index'))),
      ),
    );
    await tester.pumpAndSettle();

    final pageView = find.byType(PageView);
    final grid = verticalScrollable();
    expect(grid, findsOneWidget);
    await tester.drag(grid, const Offset(0, -800));
    await tester.pumpAndSettle();

    expect(tester.widget<PageView>(pageView).controller!.page!.round(), 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('standalone CollectionsScreen reuses the extracted body', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(const CollectionsScreen(), _FakeRepository([])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Collections'), findsOneWidget);
    expect(find.byType(CollectionCard), findsWidgets);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets(
    'Library header fits narrow phones with large text in both themes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final theme in [lightTheme, darkTheme]) {
        await tester.pumpWidget(
          buildSubject(
            const LibraryScreen(),
            _FakeRepository([_book(id: 'book-1')]),
            theme: theme,
            textScaler: TextScaler.linear(2),
          ),
        );
        await tester.pumpAndSettle();

        final gradient = tabsBackdrop(tester).gradient;
        final surface = theme.scaffoldBackgroundColor;
        expect(gradient.begin, Alignment.topCenter);
        expect(gradient.end, Alignment.bottomCenter);
        expect(gradient.colors.first, surface);
        expect(gradient.colors.last, surface.withValues(alpha: 0));
        expect(
          gradient.colors.every(
            (color) => color.withValues(alpha: 1) == surface,
          ),
          isTrue,
        );
        final capsule = find.descendant(
          of: find.byType(BiblioTabs<LibrarySection>),
          matching: find.byWidgetPredicate(
            (widget) => widget is Material && widget.shape is StadiumBorder,
          ),
        );
        expect(backdropRect(tester).bottom, tester.getRect(capsule).bottom);

        expect(find.text('Collection'), findsOneWidget);
        expect(find.text('Follow'), findsOneWidget);
        expect(find.text('All books'), findsOneWidget);
        expect(find.text('Search books').hitTestable(), findsOneWidget);
        expect(find.byTooltip('Add').hitTestable(), findsOneWidget);
        expect(find.byTooltip('Show list view').hitTestable(), findsOneWidget);
        expect(
          tester.getBottomLeft(find.text('Author')).dy,
          lessThanOrEqualTo(
            tester
                .getBottomLeft(
                  find.byKey(const ValueKey('library-book-card-book-1')),
                )
                .dy,
          ),
        );
        expect(tester.takeException(), isNull);
        final outer = tester
            .state<NestedScrollViewState>(find.byType(NestedScrollView))
            .outerController;
        outer.jumpTo(outer.position.maxScrollExtent);
        await tester.pump();
        expect(backdropRect(tester).top, 0);
        expect(tester.getRect(capsule).top, 12);
        expect(backdropRect(tester).bottom, tester.getRect(capsule).bottom);
        outer.jumpTo(0);
        await tester.pump();
      }
    },
  );

  testWidgets('Library error state exposes retry action', (tester) async {
    final repository = _ErrorRepository();
    await tester.pumpWidget(buildSubject(const LibraryScreen(), repository));
    await tester.pump();

    expect(find.text('We could not load your library.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(repository.watchCalls, greaterThanOrEqualTo(2));
  });

  testWidgets('Favorite action invokes the repository flow', (tester) async {
    final repository = _FakeRepository([_book(id: 'book-1')]);
    await tester.pumpWidget(buildSubject(const LibraryScreen(), repository));
    await tester.pump();

    await tester.tap(find.byTooltip('Add to favorites'));
    await tester.pump();

    expect(repository.favoriteRequests, [('book-1', true)]);
  });

  testWidgets('Home uses the configured recently opened carousel', (
    tester,
  ) async {
    final repository = _FakeRepository([
      _book(
        id: 'favorite',
        isFavorite: true,
        lastOpenedAt: DateTime(2026, 1, 2),
      ),
      _book(id: 'unopened'),
    ]);
    await tester.pumpWidget(buildSubject(const HomeScreen(), repository));
    await tester.pump();

    expect(find.text('Recently opened'), findsOneWidget);
    expect(find.text('Favorites'), findsNothing);
    expect(find.text('Book favorite'), findsOneWidget);
  });
}

dynamic _libraryOverrides(
  LibraryRepository repository, {
  ImportRepository? importRepository,
  LibrarySection defaultSection = LibrarySection.allBooks,
  LibrarySectionSettingsRepository? settingsRepository,
}) {
  final overrides = [
    appDatabaseProvider.overrideWith((ref) {
      final database = AppDatabase(NativeDatabase.memory());
      ref.onDispose(database.close);
      return database;
    }),
    libraryRepositoryProvider.overrideWithValue(repository),
    collectionRepositoryProvider.overrideWithValue(_FakeCollectionRepository()),
    importRepositoryProvider.overrideWithValue(
      importRepository ?? _FakeImportRepository(),
    ),
    allReadingProgressProvider.overrideWith(
      (ref) => Stream.value(<ReadingProgress>[]),
    ),
    readingProgressProvider.overrideWith((ref, bookId) => Stream.value(null)),
    onlineAccessAllowedProvider.overrideWithValue(false),
    homeOnlineStateProvider.overrideWithValue(
      const HomeOnlineStateSnapshot(byPublication: {}, downloadsCount: 0),
    ),
    visibleHomeCatalogSourcesProvider.overrideWithValue(const []),
    defaultHomeCarouselProvider.overrideWith(
      _FixedDefaultHomeCarouselNotifier.new,
    ),
  ];
  if (settingsRepository != null) {
    overrides.add(
      librarySectionSettingsRepositoryProvider.overrideWithValue(
        settingsRepository,
      ),
    );
  } else {
    overrides.add(
      defaultLibrarySectionProvider.overrideWith(
        () => _FixedDefaultLibrarySectionNotifier(defaultSection),
      ),
    );
  }
  return overrides;
}

class _FixedDefaultLibrarySectionNotifier
    extends DefaultLibrarySectionNotifier {
  _FixedDefaultLibrarySectionNotifier(this._section);

  final LibrarySection _section;

  @override
  LibrarySection build() => _section;
}

class _FixedDefaultHomeCarouselNotifier extends DefaultHomeCarouselNotifier {
  @override
  HomeDefaultCarousel build() => HomeDefaultCarousel.recentlyOpened;
}

class _MemoryLibrarySectionSettingsRepository
    implements LibrarySectionSettingsRepository {
  _MemoryLibrarySectionSettingsRepository([
    this.section = LibrarySection.allBooks,
  ]);

  LibrarySection section;

  @override
  Future<LibrarySection> load() async => section;

  @override
  Future<void> save(LibrarySection next) async => section = next;
}

LibraryBook _book({
  required String id,
  bool isFavorite = false,
  DateTime? lastOpenedAt,
}) {
  return LibraryBook(
    id: id,
    title: 'Book $id',
    sortTitle: null,
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
    dateAdded: DateTime(2026, 1, 1),
    lastOpenedAt: lastOpenedAt,
    isFavorite: isFavorite,
  );
}

class _LoadingRepository implements LibraryRepository {
  @override
  Stream<List<LibraryBook>> watchAllBooks() => const Stream.empty();

  @override
  Stream<List<LibraryBook>> watchFavoriteBooks() => watchAllBooks();

  @override
  Stream<List<LibraryBook>> watchUnsortedBooks() => watchAllBooks();

  @override
  Future<List<LibraryBook>> getAllBooks() async => [];

  @override
  Future<LibraryBook?> getBookById(String id) async => null;

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

class _FakeImportRepository implements ImportRepository {
  var calls = 0;

  @override
  Future<ImportResult> importFile() async {
    calls++;
    return const ImportCancelled();
  }

  @override
  Future<void> removeImportedFile(LibraryBook book) async {}
}

class _ErrorRepository extends _LoadingRepository {
  var watchCalls = 0;

  @override
  Stream<List<LibraryBook>> watchAllBooks() {
    watchCalls++;
    return Stream.error(StateError('test error'));
  }

  @override
  Stream<List<LibraryBook>> watchFavoriteBooks() => watchAllBooks();

  @override
  Stream<List<LibraryBook>> watchUnsortedBooks() => watchAllBooks();
}

class _FakeRepository implements LibraryRepository {
  _FakeRepository(this._books);

  final List<LibraryBook> _books;
  final List<(String, bool)> favoriteRequests = [];

  @override
  Stream<List<LibraryBook>> watchAllBooks() => Stream.value(_books);

  @override
  Stream<List<LibraryBook>> watchFavoriteBooks() => Stream.value(
    _books.where((book) => book.isFavorite).toList(growable: false),
  );

  @override
  Stream<List<LibraryBook>> watchUnsortedBooks() => Stream.value(_books);

  @override
  Future<List<LibraryBook>> getAllBooks() async => _books;

  @override
  Future<LibraryBook?> getBookById(String id) async {
    for (final book in _books) {
      if (book.id == id) return book;
    }
    return null;
  }

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
  Future<void> setFavorite(String id, bool isFavorite) async {
    favoriteRequests.add((id, isFavorite));
  }

  @override
  Future<void> markBookOpened(String id, DateTime openedAt) async {}
}

class _FakeCollectionRepository implements CollectionRepository {
  _FakeCollectionRepository()
    : summaries = [
        CollectionSummary(
          collection: LibraryCollection(
            id: 'collection-1',
            name: 'Reading',
            normalizedName: 'reading',
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
            sortOrder: null,
          ),
          bookCount: 0,
          recentBooks: const [],
        ),
      ];

  final List<CollectionSummary> summaries;

  @override
  Stream<List<CollectionSummary>> watchSummaries() => Stream.value(summaries);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

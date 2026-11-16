import 'package:bibliolife/shared/presentation/widgets/app_modal_sheet_scaffold.dart';
import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/app/router/app_shell.dart';
import 'package:bibliolife/features/collections/application/providers/collection_providers.dart';
import 'package:bibliolife/features/collections/domain/models/library_collection.dart';
import 'package:bibliolife/features/collections/domain/models/system_collection.dart';
import 'package:bibliolife/features/collections/presentation/widgets/collection_selector_sheet.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_list.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_providers.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

LibraryBook _book() => LibraryBook(
  id: 'b',
  title: 'Book',
  sortTitle: null,
  author: null,
  description: null,
  filePath: '/missing/b.epub',
  fileName: 'b.epub',
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
  isFavorite: false,
);
LibraryCollection _collection(String id, String name) => LibraryCollection(
  id: id,
  name: name,
  normalizedName: id,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  sortOrder: null,
);

void main() {
  testWidgets('shared single-action footer still defaults to Cancel', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppModalSheetSingleActionFooter()),
      ),
    );
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Apply'), findsNothing);
  });
  testWidgets(
    'Library list collection sheet covers shell navigation and preserves route',
    (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final items = systemCollectionNames.entries
          .map((e) => _collection(e.key, e.value))
          .toList();
      final router = GoRouter(
        initialLocation: AppRoutes.libraryPath,
        routes: [
          GoRoute(
            path: AppRoutes.createCollectionPath,
            name: AppRoutes.createCollectionName,
            builder: (_, state) => Scaffold(
              body: Text('Create:${(state.extra as Set<String>).single}'),
            ),
          ),
          StatefulShellRoute.indexedStack(
            builder: (_, _, shell) => AppShell(navigationShell: shell),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: AppRoutes.homePath,
                    builder: (_, _) =>
                        const Scaffold(body: Text('Home branch')),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: AppRoutes.libraryPath,
                    builder: (_, _) => Scaffold(
                      body: CustomScrollView(
                        slivers: [
                          LibraryList(books: [_book()]),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: AppRoutes.profilePath,
                    builder: (_, _) =>
                        const Scaffold(body: Text('Profile branch')),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          allCollectionsProvider.overrideWith((ref) => Stream.value(items)),
          collectionsForBookProvider.overrideWith(
            (ref, id) => Stream.value([]),
          ),
          readingProgressProvider.overrideWith((ref, id) => Stream.value(null)),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> openSheet() async {
        await tester.tap(find.byTooltip('More options for Book'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add to collection'));
        await tester.pumpAndSettle();
      }

      await openSheet();
      final sheetContext = tester.element(find.byType(CollectionSelectorSheet));
      expect(
        Navigator.of(sheetContext),
        same(Navigator.of(sheetContext, rootNavigator: true)),
      );
      final nav = find.byKey(const Key('navigation-island-surface'));
      final navPoint = tester.getCenter(nav);
      final hit = tester
          .hitTestOnBinding(navPoint)
          .path
          .map((entry) => entry.target);
      expect(hit, isNot(contains(tester.renderObject(nav))));
      await tester.tapAt(navPoint);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        AppRoutes.libraryPath,
      );
      if (find.byType(CollectionSelectorSheet).evaluate().isNotEmpty) {
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
      }
      expect(find.byType(LibraryList), findsOneWidget);
      await openSheet();
      expect(find.text('Apply'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.byType(CollectionSelectorSheet), findsNothing);
      expect(
        router.routeInformationProvider.value.uri.path,
        AppRoutes.libraryPath,
      );
      await openSheet();
      await tester.ensureVisible(
        find.byKey(const Key('create-collection-from-selector')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('create-collection-from-selector')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Create:b'), findsOneWidget);
      expect(find.byType(CollectionSelectorSheet), findsNothing);
      router.pop();
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        AppRoutes.libraryPath,
      );
      expect(find.byType(LibraryList), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      router.dispose();
    },
  );
}

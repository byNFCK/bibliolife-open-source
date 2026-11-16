import 'package:go_router/go_router.dart';
import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/features/collections/presentation/screens/collection_editor_screen.dart';
import 'package:bibliolife/features/collections/presentation/system_collection_colors.dart';
import 'package:bibliolife/features/collections/domain/models/collection_summary.dart';
import 'package:bibliolife/features/collections/presentation/widgets/collection_card.dart';
import 'dart:async';
import 'package:bibliolife/features/collections/application/providers/collection_providers.dart';
import 'package:bibliolife/features/collections/application/providers/collection_repository_provider.dart';
import 'package:bibliolife/features/collections/domain/models/library_collection.dart';
import 'package:bibliolife/features/collections/domain/models/system_collection.dart';
import 'package:bibliolife/features/collections/domain/repositories/collection_repository.dart';
import 'package:bibliolife/features/collections/presentation/screens/collection_details_screen.dart';
import 'package:bibliolife/features/collections/presentation/widgets/collection_selector_sheet.dart';
import 'package:bibliolife/features/library/application/providers/library_providers.dart';
import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_providers.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Mode extends LibraryViewModeNotifier {
  _Mode(this.mode);
  final LibraryViewMode mode;
  @override
  LibraryViewMode build() => mode;
}

class _Repo implements CollectionRepository {
  final memberships = <String, Set<String>>{};
  @override
  Future<void> addBook(String id, String book) async =>
      memberships.putIfAbsent(id, () => {}).add(book);
  @override
  Future<void> removeBook(String id, String book) async {
    memberships[id]?.remove(book);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

LibraryCollection _collection(String id, String name) => LibraryCollection(
  id: id,
  name: name,
  normalizedName: id,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  sortOrder: null,
);
LibraryBook _book() => LibraryBook(
  id: 'b',
  title: 'Book',
  sortTitle: null,
  author: null,
  description: null,
  filePath: '/b.epub',
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

void main() {
  for (final entry in systemCollectionNames.entries) {
    testWidgets('${entry.value} menu opens the shared editor', (tester) async {
      final collection = _collection(entry.key, entry.value);
      final container = ProviderContainer(
        overrides: [
          collectionByIdProvider.overrideWith((ref, id) async => collection),
          booksInCollectionProvider.overrideWith((ref, id) => Stream.value([])),
          allBooksProvider.overrideWith((ref) => Stream.value([])),
          libraryViewModeProvider.overrideWith(
            () => _Mode(LibraryViewMode.grid),
          ),
        ],
      );
      final router = GoRouter(
        initialLocation: '/collections/${entry.key}',
        routes: [
          GoRoute(
            path: AppRoutes.collectionDetailsPath,
            builder: (_, state) => CollectionDetailsScreen(
              collectionId: state.pathParameters['collectionId']!,
            ),
          ),
          GoRoute(
            path: AppRoutes.editCollectionPath,
            name: AppRoutes.editCollectionName,
            builder: (_, state) => CollectionEditorScreen(
              collectionId: state.pathParameters['collectionId']!,
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collection-details-overflow')));
      await tester.pumpAndSettle();
      expect(find.text('Delete collection'), findsNothing);
      await tester.tap(find.text('Edit collection'));
      await tester.pumpAndSettle();
      expect(find.byType(CollectionEditorScreen), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('collection-editor-name')))
            .readOnly,
        isTrue,
      );
      expect(
        find.byKey(const Key('collection-editor-description')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      container.dispose();
    });
  }
  for (final brightness in Brightness.values) {
    testWidgets(
      'system hues apply to cards, details and picker in ${brightness.name}',
      (tester) async {
        final base = ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.purple,
            brightness: brightness,
          ),
        );
        final items = [
          ...systemCollectionNames.entries.map(
            (e) => _collection(e.key, e.value),
          ),
          _collection('user', 'Reading'),
        ];
        final repo = _Repo();
        final container = ProviderContainer(
          overrides: [
            collectionRepositoryProvider.overrideWithValue(repo),
            allCollectionsProvider.overrideWith((ref) => Stream.value(items)),
            collectionsForBookProvider.overrideWith(
              (ref, id) => Stream.value(items),
            ),
            collectionByIdProvider.overrideWith(
              (ref, id) async => items.firstWhere((c) => c.id == id),
            ),
            booksInCollectionProvider.overrideWith(
              (ref, id) => Stream.value([]),
            ),
            libraryViewModeProvider.overrideWith(
              () => _Mode(LibraryViewMode.grid),
            ),
            allBooksProvider.overrideWith((ref) => Stream.value([_book()])),
          ],
        );
        for (final item in items) {
          await tester.pumpWidget(
            MaterialApp(
              theme: base,
              home: Scaffold(
                body: CollectionCard(
                  summary: CollectionSummary(
                    collection: item,
                    bookCount: 1,
                    recentBooks: const [],
                  ),
                  onTap: () {},
                ),
              ),
            ),
          );
          final theme = Theme.of(
            tester.element(find.byKey(const Key('collection-card-icon-badge'))),
          );
          final expected =
              systemCollectionColorScheme(item.id, brightness) ??
              base.colorScheme;
          expect(theme.colorScheme.primary, expected.primary);
          final count = tester.widget<Text>(find.text('1 book'));
          expect(count.style?.color, expected.primary);
          final chevron = tester.widget<Icon>(
            find.byIcon(Icons.chevron_right_rounded),
          );
          expect(chevron.color, expected.primary);
          final a = expected.primary.computeLuminance();
          final b = expected.onPrimary.computeLuminance();
          final ratio =
              (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
          expect(ratio, greaterThanOrEqualTo(4.5));
          final badge = tester.widget<DecoratedBox>(
            find.byKey(const Key('collection-card-icon-badge')),
          );
          expect(
            (badge.decoration as BoxDecoration).color,
            expected.primaryContainer,
          );
          final hue = HSLColor.fromColor(expected.primary).hue;
          if (item.id == systemFinishedId) {
            expect(hue, inInclusiveRange(80, 170));
          }
          if (item.id == systemReadingId) {
            expect(hue, inInclusiveRange(180, 270));
          }
          if (item.id == systemToReadId) {
            expect(hue, inInclusiveRange(10, 80));
          }
        }
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: base,
              home: const Scaffold(body: CollectionSelectorSheet(bookId: 'b')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final item in items) {
          final tile = tester.widget<CheckboxListTile>(
            find.byKey(ValueKey('collection-membership-${item.id}')),
          );
          final expected = systemCollectionColorScheme(item.id, brightness);
          expect(tile.activeColor, expected?.primary);
          expect(tile.checkColor, expected?.onPrimary);
          final title = tile.title! as Text;
          expect(title.style?.color, expected?.primary);
        }
        for (final item in items.take(3)) {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: base,
                home: CollectionDetailsScreen(collectionId: item.id),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final expected = systemCollectionColorScheme(item.id, brightness)!;
          final headerTheme = Theme.of(
            tester.element(find.byKey(const Key('collection-details-cover'))),
          );
          expect(headerTheme.colorScheme.primary, expected.primary);
          final overflow = find.byKey(const Key('collection-details-overflow'));
          expect(overflow, findsOneWidget);
          await tester.tap(overflow);
          await tester.pumpAndSettle();
          expect(find.text('Edit collection'), findsOneWidget);
          expect(find.text('Delete collection'), findsNothing);
          await tester.tap(overflow);
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      },
    );
  }
  testWidgets('existing picker offers system and same-named user collection', (
    tester,
  ) async {
    final repo = _Repo();
    final items = [
      ...systemCollectionNames.entries.map((e) => _collection(e.key, e.value)),
      _collection('user', 'Reading'),
    ];
    final container = ProviderContainer(
      overrides: [
        collectionRepositoryProvider.overrideWithValue(repo),
        allCollectionsProvider.overrideWith((ref) => Stream.value(items)),
        collectionsForBookProvider.overrideWith((ref, id) => Stream.value([])),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: CollectionSelectorSheet(bookId: 'b')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final id in [...systemCollectionNames.keys, 'user']) {
      expect(find.byKey(ValueKey('collection-membership-$id')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('collection-membership-$id')));
      await tester.pumpAndSettle();
      expect(repo.memberships[id], contains('b'));
    }
    expect(find.text('Reading'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
  for (final mode in LibraryViewMode.values) {
    testWidgets('system details ${mode.name} can add books', (tester) async {
      final repo = _Repo();
      final book = _book();
      final contents = StreamController<List<LibraryBook>>.broadcast(
        sync: true,
      );
      final container = ProviderContainer(
        overrides: [
          collectionRepositoryProvider.overrideWithValue(repo),
          collectionByIdProvider.overrideWith(
            (ref, id) async => _collection(id, 'Reading'),
          ),
          booksInCollectionProvider.overrideWith((ref, id) => contents.stream),
          allBooksProvider.overrideWith((ref) => Stream.value([book])),
          readingProgressProvider.overrideWith((ref, id) => Stream.value(null)),
          libraryViewModeProvider.overrideWith(() => _Mode(mode)),
        ],
      );
      final subscription = container.listen(
        booksInCollectionProvider(systemReadingId),
        (_, _) {},
      );
      contents.add([]);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: CollectionDetailsScreen(collectionId: systemReadingId),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('collection-details-overflow')),
        findsOneWidget,
      );
      await tester.drag(
        find.byKey(const Key('collection-details-scroll')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('collection-details-add-books')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('collection-details-add-books')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collection-book-option-b')));
      await tester.tap(find.byKey(const Key('collection-book-selector-done')));
      await tester.pumpAndSettle();
      expect(repo.memberships[systemReadingId], contains('b'));
      contents.add([book]);
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const Key('collection-details-scroll')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(Key('collection-details-book-${mode.name}')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      subscription.close();
      container.dispose();
      await contents.close();
    });
  }
}

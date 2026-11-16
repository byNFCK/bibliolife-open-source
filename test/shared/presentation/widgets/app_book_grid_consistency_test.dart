import 'package:bibliolife/shared/presentation/presenters/book_reading_progress_availability.dart';
import 'package:bibliolife/features/library/application/providers/library_providers.dart';
import 'dart:convert';
import 'dart:io';

import 'package:bibliolife/app/theme/app_theme.dart';
import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/presentation/widgets/remote_catalog_book_card.dart';
import 'package:bibliolife/features/catalog_sources/presentation/widgets/remote_catalog_publication_sliver.dart';
import 'package:bibliolife/features/home/domain/models/online_home_section.dart';
import 'package:bibliolife/features/home/presentation/widgets/home_online_catalog_grid.dart';
import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_book_card.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_grid.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixture =
    'test/shared/presentation/widgets/fixtures/book_grid_geometry.json';
const _title = 'A long book title for shared geometry verification';
const _author = 'An author with a lengthy name';

void main() {
  testWidgets('approved local and remote Grid geometry and typography', (
    tester,
  ) async {
    final measurements = <String, Object?>{};
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final dark in [false, true]) {
      for (final configuration in [(320.0, 2.0), (400.0, 1.0)]) {
        await tester.binding.setSurfaceSize(Size(configuration.$1, 1000));
        final width = (configuration.$1 - 48) / 2;
        Map<String, Object?>? local;
        for (final remote in [false, true]) {
          await tester.pumpWidget(
            _app(
              dark: dark,
              scale: configuration.$2,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: remote
                      ? RemoteCatalogBookCard(
                          publication: _publication('remote'),
                          onOpen: () {},
                          status: const Text('Available', key: Key('status')),
                        )
                      : LibraryBookCard(
                          book: _book,
                          progressPercent: 0,
                          onOpen: (_) {},
                        ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final cardFinder = find.byKey(const Key('app-book-card'));
          final origin = tester.getTopLeft(cardFinder);
          List<double> rect(Finder finder) {
            final value = tester.getRect(finder).shift(-origin);
            return [
              value.left,
              value.top,
              value.width,
              value.height,
            ].map((n) => double.parse(n.toStringAsFixed(4))).toList();
          }

          Map<String, Object?> text(Finder finder) {
            final widget = tester.widget<Text>(finder);
            return {
              'rect': rect(finder),
              'size': widget.style?.fontSize,
              'height': widget.style?.height,
              'weight': widget.style?.fontWeight?.value,
              'color': widget.style?.color?.toARGB32(),
              'lines': widget.maxLines,
              'overflow': widget.overflow?.name,
            };
          }

          final card = tester.widget<Card>(cardFinder);
          final shape = card.shape! as RoundedRectangleBorder;
          final common = <String, Object?>{
            'cover': rect(cardFinder),
            if (!remote)
              'bar': rect(find.byKey(const Key('app-book-card-bottom-bar'))),
            'title': text(find.text(_title)),
            'author': text(find.text(_author)),
            'radius': shape.borderRadius.resolve(TextDirection.ltr).topLeft.x,
            'margin': card.margin.toString(),
            'color': card.color?.toARGB32(),
          };
          final coverSize = tester.getSize(cardFinder);
          expect(coverSize.width / coverSize.height, closeTo(0.65, .0001));
          expect(shape.borderRadius.resolve(TextDirection.ltr).topLeft.x, 24);
          expect(
            tester.getTopLeft(find.text(_title)).dy -
                tester.getBottomLeft(cardFinder).dy,
            8,
          );
          if (remote) {
            expect(
              find.byKey(const Key('app-book-card-bottom-bar')),
              findsNothing,
            );
            expect(common, Map.of(local!)..remove('bar'));
            expect(
              tester.getTopLeft(find.byKey(const Key('status'))).dy -
                  tester.getBottomLeft(find.text(_author)).dy,
              4,
            );
            expect(find.byTooltip('Add to favorites'), findsNothing);
          } else {
            local = common;
            expect(find.byTooltip('Add to favorites'), findsOneWidget);
          }
          measurements['$dark-${configuration.$1}-${configuration.$2}-$remote'] =
              common;
        }
      }
    }
    if (const bool.fromEnvironment('UPDATE_BOOK_GRID_BASELINE')) {
      File(_fixture).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(measurements),
      );
    } else {
      final expected =
          jsonDecode(File(_fixture).readAsStringSync()) as Map<String, dynamic>;
      for (final entry in expected.entries) {
        if (entry.key.endsWith('-true')) (entry.value as Map).remove('bar');
      }
      expect(measurements, expected);
    }
  });

  testWidgets('Home Online honors the shared gap without changing its slots', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        gap: 22,
        child: const CustomScrollView(
          slivers: [
            HomeOnlineCatalogGrid(
              books: [],
              slots: [
                OnlineHomeSlot.pending(slotId: 0, sourceIndex: 0, attempt: 0),
                OnlineHomeSlot.pending(slotId: 1, sourceIndex: 1, attempt: 0),
                OnlineHomeSlot.pending(slotId: 2, sourceIndex: 2, attempt: 0),
              ],
            ),
          ],
        ),
      ),
    );
    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.mainAxisSpacing, 22);
    expect(delegate.crossAxisSpacing, 22);
    expect(grid.delegate.estimatedChildCount, 3);
    expect(find.byType(HomeOnlineReservedBookCard), findsNWidgets(3));
    final first = tester.getRect(
      find.byKey(const ValueKey('home-online-slot-0')),
    );
    final second = tester.getRect(
      find.byKey(const ValueKey('home-online-slot-1')),
    );
    expect(second.left - first.right, closeTo(22, .001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Library and remote grids honor the same theme gap', (
    tester,
  ) async {
    for (final gap in [16.0, 22.0]) {
      await tester.pumpWidget(
        _app(
          gap: gap,
          child: CustomScrollView(
            slivers: [
              const LibraryGrid(books: [], width: 800),
              RemoteCatalogPublicationSliver(
                publications: List.generate(6, (i) => _publication('$i')),
                onOpen: (_) {},
                sourceId: 'source',
                mode: LibraryViewMode.grid,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final delegate =
          tester.widget<SliverGrid>(find.byType(SliverGrid)).gridDelegate
              as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.mainAxisSpacing, gap);
      expect(delegate.crossAxisSpacing, gap);
      final first = tester.getRect(
        find.byKey(const ValueKey('catalog-publication-0')),
      );
      final second = tester.getRect(
        find.byKey(const ValueKey('catalog-publication-1')),
      );
      final nextRow = tester.getRect(
        find.byKey(const ValueKey('catalog-publication-3')),
      );
      expect(second.left - first.right, closeTo(gap, .001));
      expect(nextRow.top - first.bottom, closeTo(gap, .001));
      expect(tester.takeException(), isNull);
    }
  });
}

Widget _app({
  required Widget child,
  bool dark = false,
  double scale = 1,
  double gap = 16,
}) {
  final theme = buildAppTheme(
    dark ? fallbackDarkColorScheme : fallbackLightColorScheme,
  );
  return ProviderScope(
    overrides: [
      localBookFileAvailableProvider.overrideWith((ref, source) => true),
      allBooksProvider.overrideWithValue(const AsyncData(<LibraryBook>[])),
    ],
    child: MaterialApp(
      theme: theme.copyWith(
        extensions: [AppThemeTokens.standard().copyWith(bookCardGridGap: gap)],
      ),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: child),
      ),
    ),
  );
}

RemoteCatalogPublicationSummary _publication(String id) =>
    RemoteCatalogPublicationSummary(
      remoteId: id,
      title: _title,
      authors: [_author],
    );

final _book = LibraryBook(
  id: 'local',
  title: _title,
  sortTitle: null,
  author: _author,
  description: null,
  filePath: '/unused.epub',
  fileName: 'unused.epub',
  fileExtension: 'epub',
  format: BookFormat.epub,
  mediaType: null,
  coverPath: null,
  language: null,
  publisher: null,
  publishedDate: null,
  isbn: null,
  pageCount: null,
  fileSizeBytes: 0,
  dateAdded: DateTime(2026),
  lastOpenedAt: null,
  isFavorite: false,
);

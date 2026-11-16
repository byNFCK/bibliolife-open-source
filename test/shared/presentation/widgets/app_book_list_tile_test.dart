import 'dart:async';
import 'package:bibliolife/features/book_details/application/providers/book_file_export_service_provider.dart';
import 'package:bibliolife/features/book_details/application/services/book_file_export_service.dart';
import 'package:bibliolife/shared/presentation/widgets/app_context_menu.dart';
import 'package:bibliolife/features/library/application/providers/library_providers.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_providers.dart';
import 'package:bibliolife/shared/presentation/widgets/app_book_list_tile.dart';
import 'dart:convert';
import 'dart:io';

import 'package:bibliolife/app/theme/app_theme.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/presentation/widgets/remote_catalog_book_cover.dart';
import 'package:bibliolife/features/catalog_sources/presentation/widgets/remote_catalog_book_tile.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_book_card.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_book_tile.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _title =
    'A long book title that must keep its approved overflow behavior';
const _metadata = 'An author with a lengthy name';
const _status = 'Caller supplied status';
const _baselinePath =
    'test/shared/presentation/widgets/fixtures/book_list_tile_phase32_geometry.json';

void main() {
  testWidgets(
    'both adapters supply data and business actions to the same visual shell',
    (tester) async {
      for (final kind in [
        'local',
        'collection',
        'remote',
        'missing-author',
        'status',
      ]) {
        await tester.pumpWidget(_subject(kind, dark: false, scale: 1));
        await tester.pumpAndSettle();
        final shared = tester.widget<AppBookListTile>(
          find.byType(AppBookListTile),
        );
        expect(shared.title, _title);
        final local = kind == 'local' || kind == 'collection';
        expect(
          shared.cover,
          local ? isA<LibraryBookCover>() : isA<RemoteCatalogBookCover>(),
        );
        expect(shared.actions.length, 1);
        expect(shared.metadata, kind == 'missing-author' ? null : _metadata);
        expect(shared.status == null, kind != 'status');
        expect(find.text('0%'), findsNothing);
        expect(find.textContaining('EPUB'), findsNothing);
        if (local) expect(find.textContaining('Opened'), findsOneWidget);
        expect(find.text('Read for free'), findsNothing);
        expect(
          find.byType(AppContextMenuButton<String>),
          local ? findsOneWidget : findsNothing,
        );
      }
    },
  );

  testWidgets(
    'one row open action and isolated action slot preserve semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var opens = 0;
      var favorites = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppBookListTile(
              title: _title,
              metadata: _metadata,
              cover: Semantics(
                label: 'Cover of $_title',
                child: const ColoredBox(color: Colors.grey),
              ),
              onOpen: () => opens++,
              actions: [
                IconButton(
                  tooltip: 'Favorite action',
                  onPressed: () => favorites++,
                  icon: const Icon(Icons.favorite_border),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Cover of $_title'), findsNothing);
      await tester.tap(find.byTooltip('Favorite action'));
      await tester.pumpAndSettle();
      expect(favorites, 1);
      expect(opens, 0);
      await tester.tap(find.text(_title));
      expect(opens, 1);
      final node = tester.getSemantics(find.byType(AppBookListTile));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      expect(opens, 2);
      semantics.dispose();
    },
  );

  testWidgets(
    'local favorite labels and disabled Delete configuration remain intact',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_subject('collection', dark: false, scale: 1));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AppContextMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Add to favorites'), findsOneWidget);
      for (final label in [
        'Add to collection',
        'Edit book',
        'Save book file',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(
        tester
            .getSemantics(find.text('Add to favorites'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(find.text('Delete'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.pumpWidget(_subject('local', dark: false, scale: 1));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AppContextMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Delete book?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'six actions remain reachable on a small screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _subject('local', dark: false, scale: 2, includeOpenAction: true),
      );
      await tester.tap(find.byTooltip('More options for $_title'));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Refresh'), findsNothing);
      expect(find.byType(MenuItemButton), findsNWidgets(6));
      final scrollable = find.descendant(
        of: find.byType(MenuAnchor),
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsWidgets);
      await tester.scrollUntilVisible(
        find.text('Delete'),
        100,
        scrollable: scrollable.last,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.text('Delete')).bottom,
        lessThanOrEqualTo(320),
      );
      final delete = tester.widget<MenuItemButton>(
        find.ancestor(
          of: find.text('Delete'),
          matching: find.byType(MenuItemButton),
        ),
      );
      expect(delete.onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stale file checks cannot enable export for the changed book', (
    tester,
  ) async {
    final service = _DelayedExportService();
    Widget subject(String path) => _subject(
      'local',
      dark: false,
      scale: 1,
      book: _book(path: path),
      exportService: service,
    );
    await tester.pumpWidget(subject('/old.epub'));
    await tester.tap(find.byTooltip('More options for $_title'));
    await tester.pump();
    expect(service.pending.length, 1);
    await tester.tap(find.byTooltip('More options for $_title'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(subject('/new.epub'));
    await tester.tap(find.byTooltip('More options for $_title'));
    await tester.pump();
    expect(service.pending.length, 2);
    service.pending[1].complete(null);
    await tester.pump();
    service.pending[0].complete(
      const BookFileExportSource(
        path: '/old.epub',
        fileName: 'old.epub',
        mimeType: 'application/epub+zip',
        sizeBytes: 1,
      ),
    );
    await tester.pumpAndSettle();
    final item = tester.widget<MenuItemButton>(
      find.ancestor(
        of: find.text('Save book file'),
        matching: find.byType(MenuItemButton),
      ),
    );
    expect(item.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'adapter layout and typography match the universal Phase 3.2 baseline',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final actual = <String, Object?>{};
      for (final dark in [false, true]) {
        for (final size in [(400.0, 1.0), (320.0, 2.0)]) {
          tester.view.physicalSize = Size(size.$1, 900);
          for (final kind in [
            'local',
            'collection',
            'remote',
            'missing-author',
            'status',
          ]) {
            final local = kind == 'local' || kind == 'collection';
            await tester.pumpWidget(_subject(kind, dark: dark, scale: size.$2));
            await tester.pumpAndSettle();
            expect(find.byType(AppBookListTile), findsOneWidget);
            final tileFinder = find.byType(AppBookListTile);
            final tile = tester.widget<AppBookListTile>(tileFinder);
            final origin = tester.getTopLeft(tileFinder);
            List<double> rect(Finder finder) {
              final box = tester.getRect(finder).shift(-origin);
              return [
                box.left,
                box.top,
                box.width,
                box.height,
              ].map((n) => double.parse(n.toStringAsFixed(4))).toList();
            }

            Map<String, Object?> text(String label) {
              final finder = find.text(label);
              final widget = tester.widget<Text>(finder);
              final style = tester
                  .renderObject<RenderParagraph>(finder)
                  .text
                  .style!;
              return {
                'rect': rect(finder),
                'fontSize': style.fontSize,
                'height': style.height,
                'weight': style.fontWeight?.value,
                'color': style.color?.toARGB32(),
                'maxLines': widget.maxLines,
                'overflow': widget.overflow?.name,
              };
            }

            actual['$kind/dark=$dark/width=${size.$1}/scale=${size.$2}'] = {
              'row': rect(tileFinder),
              'cover': rect(
                local
                    ? find.byType(LibraryBookCover)
                    : find.byType(RemoteCatalogBookCover),
              ),
              'title': text(_title),
              'metadata': kind == 'missing-author' ? null : text(_metadata),
              'status': kind == 'status' ? text(_status) : null,
              'actions': tile.actions.isEmpty
                  ? null
                  : rect(find.byKey(const Key('book-list-actions'))),
              'bottom': tile.status == null && tile.bookStatus == null
                  ? null
                  : rect(find.byKey(const Key('book-list-bottom'))),
            };
            expect(tester.takeException(), isNull);
          }
        }
      }
      const update = bool.fromEnvironment('UPDATE_BOOK_LIST_PHASE32_BASELINE');
      if (update) {
        await tester.runAsync(() async {
          final file = File(_baselinePath);
          await file.parent.create(recursive: true);
          await file.writeAsString(
            const JsonEncoder.withIndent('  ').convert(actual),
          );
        });
      } else {
        final baseline = jsonDecode(File(_baselinePath).readAsStringSync());
        expect(actual, baseline);
      }
    },
  );
}

Widget _subject(
  String kind, {
  required bool dark,
  required double scale,
  bool includeOpenAction = false,
  LibraryBook? book,
  BookFileExportService? exportService,
}) {
  final local = kind == 'local' || kind == 'collection';
  return ProviderScope(
    overrides: [
      if (exportService != null)
        bookFileExportServiceProvider.overrideWithValue(exportService),
      allBooksProvider.overrideWithValue(const AsyncData(<LibraryBook>[])),
      readingProgressProvider.overrideWith((ref, _) => Stream.value(null)),
    ],
    child: MaterialApp(
      theme: dark ? darkTheme : lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: local
              ? LibraryBookTile(
                  book: book ?? _book(),
                  includeOpenAction: includeOpenAction,
                  allowDeleteBook: kind != 'collection',
                )
              : RemoteCatalogBookTile(
                  publication: RemoteCatalogPublicationSummary(
                    remoteId: 'remote-id',
                    title: _title,
                    authors: kind == 'missing-author' ? [] : [_metadata],
                  ),
                  sourceId: 'source',
                  onOpen: () {},
                  status: kind == 'status' ? const Text(_status) : null,
                ),
        ),
      ),
    ),
  );
}

LibraryBook _book({String path = '/unused/shared-list-test.epub'}) =>
    LibraryBook(
      id: 'local-id',
      title: _title,
      sortTitle: _title,
      author: _metadata,
      description: null,
      filePath: path,
      fileName: 'test.epub',
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
      lastOpenedAt: DateTime(2026, 1, 2),
      isFavorite: false,
    );

class _DelayedExportService extends BookFileExportService {
  _DelayedExportService() : super(_UnusedSaver());
  final pending = <Completer<BookFileExportSource?>>[];
  @override
  Future<BookFileExportSource?> resolveSource(LibraryBook book) {
    final completer = Completer<BookFileExportSource?>();
    pending.add(completer);
    return completer.future;
  }
}

class _UnusedSaver implements BookFileSaver {
  @override
  Future<BookFileSaveOutcome> save({
    required String sourcePath,
    required String fileName,
    required String mimeType,
    required int sizeBytes,
  }) async => BookFileSaveOutcome.failed;
}

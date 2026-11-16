import 'dart:io';

import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/presentation/widgets/remote_catalog_book_card.dart';
import 'package:bibliolife/features/catalog_sources/presentation/widgets/remote_catalog_book_tile.dart';
import 'package:bibliolife/features/library/application/providers/library_providers.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_book_card.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_book_tile.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_providers.dart';
import 'package:bibliolife/features/reader/domain/models/reading_progress.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:bibliolife/shared/presentation/presenters/book_reading_progress_availability.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File file;
  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'book-progress-visibility-',
    );
    file = File('${directory.path}/book.epub')..writeAsBytesSync([1, 2]);
  });
  tearDown(() => directory.deleteSync(recursive: true));

  for (final list in [false, true]) {
    for (final phase in [
      'not downloaded',
      'downloading',
      'failed',
      'cancelled',
      'metadata only',
      'temporary download completed',
    ]) {
      testWidgets(
        '$phase has no reading overlay in ${list ? 'List' : 'Grid'}',
        (tester) async {
          final status = phase == 'downloading'
              ? const LinearProgressIndicator(
                  key: Key('download-progress'),
                  value: .5,
                )
              : Text(phase);
          await _show(
            tester,
            list
                ? RemoteCatalogBookTile(
                    publication: _publication,
                    sourceId: 'source',
                    onOpen: () {},
                    status: status,
                  )
                : SizedBox(
                    width: 160,
                    child: RemoteCatalogBookCard(
                      publication: _publication,
                      sourceId: 'source',
                      onOpen: () {},
                      status: status,
                    ),
                  ),
          );
          expect(
            find.byKey(const Key('app-book-card-bottom-bar')),
            findsNothing,
          );
          expect(
            find.byKey(const Key('app-book-card-panel-background')),
            findsNothing,
          );
          expect(find.byKey(const Key('book-list-progress')), findsNothing);
          expect(find.text('0%'), findsNothing);
          expect(find.byType(BackdropFilter), findsNothing);
          if (phase == 'downloading') {
            expect(find.byKey(const Key('download-progress')), findsOneWidget);
          }
          final cover = tester.getSize(
            find.byKey(Key(list ? 'book-list-cover' : 'app-book-card-cover')),
          );
          expect(
            cover,
            list ? const Size(92, 138) : const Size(160, 160 / .65),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final percent in [0, 50]) {
      testWidgets(
        'readable local book at $percent% retains ${list ? 'List' : 'Grid'} overlay',
        (tester) async {
          final book = _book(file.path);
          await _show(
            tester,
            list
                ? LibraryBookTile(book: book, onOpen: () {})
                : SizedBox(
                    width: 160,
                    child: LibraryBookCard(
                      book: book,
                      progressPercent: percent,
                      onOpen: (_) {},
                    ),
                  ),
            percent: percent,
          );
          expect(find.text('$percent%'), findsOneWidget);
          expect(
            find.byKey(
              Key(list ? 'book-list-progress' : 'app-book-card-bottom-bar'),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'local file without reading history retains 0% in ${list ? 'List' : 'Grid'}',
      (tester) async {
        final book = _book(file.path);
        await _show(
          tester,
          list
              ? LibraryBookTile(book: book, onOpen: () {})
              : SizedBox(
                  width: 160,
                  child: LibraryBookCard(book: book, onOpen: (_) {}),
                ),
          hasHistory: false,
        );
        expect(find.text('0%'), findsOneWidget);
      },
    );

    testWidgets(
      'missing local file hides ${list ? 'List' : 'Grid'} overlay and retains actions',
      (tester) async {
        final book = _book('${directory.path}/missing.epub');
        await _show(
          tester,
          list
              ? LibraryBookTile(book: book, onOpen: () {})
              : SizedBox(
                  width: 160,
                  child: LibraryBookCard(
                    book: book,
                    progressPercent: 50,
                    onOpen: (_) {},
                  ),
                ),
          percent: 50,
        );
        expect(find.text('50%'), findsNothing);
        expect(
          find.byKey(
            Key(list ? 'book-list-progress' : 'app-book-card-bottom-bar'),
          ),
          findsNothing,
        );
        expect(find.byType(BackdropFilter), findsNothing);
        expect(
          list
              ? find.byIcon(Icons.more_vert)
              : find.byTooltip('Add to favorites'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'imported exact catalog identity exposes actual progress in ${list ? 'List' : 'Grid'}',
      (tester) async {
        final book = _book(file.path);
        await _show(
          tester,
          list
              ? RemoteCatalogBookTile(
                  publication: _publication,
                  sourceId: 'source',
                  onOpen: () {},
                )
              : SizedBox(
                  width: 160,
                  child: RemoteCatalogBookCard(
                    publication: _publication,
                    sourceId: 'source',
                    onOpen: () {},
                  ),
                ),
          books: [book],
          percent: 50,
        );
        expect(find.text('50%'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('returning to the app rechecks a removed local file', (
    tester,
  ) async {
    await _show(
      tester,
      SizedBox(
        width: 160,
        child: LibraryBookCard(
          book: _book(file.path),
          progressPercent: 50,
          onOpen: (_) {},
        ),
      ),
    );
    expect(find.text('50%'), findsOneWidget);
    file.deleteSync();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('50%'), findsNothing);
    expect(find.byKey(const Key('app-book-card-bottom-bar')), findsNothing);
  });

  test(
    'availability rejects invalid file references without metadata parsing',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      for (final source in <LocalBookFile>[
        (path: '', format: BookFormat.epub, size: 2),
        (path: file.path, format: BookFormat.unknown, size: 2),
        (path: file.path, format: BookFormat.pdf, size: 2),
        (path: file.path, format: BookFormat.epub, size: 0),
        (path: file.path, format: BookFormat.epub, size: 3),
        (path: directory.path, format: BookFormat.epub, size: 2),
      ]) {
        expect(
          await container.read(localBookFileAvailableProvider(source).future),
          isFalse,
        );
      }
      expect(
        await container.read(
          localBookFileAvailableProvider((
            path: file.path,
            format: BookFormat.epub,
            size: 2,
          )).future,
        ),
        isTrue,
      );
    },
  );
}

Future<void> _show(
  WidgetTester tester,
  Widget child, {
  List<LibraryBook> books = const [],
  int percent = 0,
  bool hasHistory = true,
}) async {
  tester.view.physicalSize = const Size(320, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        allBooksProvider.overrideWithValue(AsyncData(books)),
        readingProgressProvider.overrideWith(
          (ref, id) => Stream.value(
            !hasHistory
                ? null
                : ReadingProgress(
                    bookId: id,
                    locatorJson: null,
                    progression: percent / 100,
                    currentChapterTitle: null,
                    currentPage: null,
                    totalPages: null,
                    updatedAt: DateTime(2026),
                  ),
          ),
        ),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  // Drain the real stat/open/close callbacks between fake-clock frames.
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

final _publication = RemoteCatalogPublicationSummary(
  remoteId: 'remote',
  title: 'Book',
  authors: const ['Author'],
);
LibraryBook _book(String path) => LibraryBook(
  id: 'local',
  title: 'Book',
  sortTitle: 'Book',
  author: 'Author',
  description: null,
  filePath: path,
  fileName: 'book.epub',
  fileExtension: 'epub',
  format: BookFormat.epub,
  mediaType: 'application/epub+zip',
  coverPath: null,
  language: null,
  publisher: null,
  publishedDate: null,
  isbn: null,
  pageCount: null,
  fileSizeBytes: 2,
  dateAdded: DateTime(2026),
  lastOpenedAt: null,
  isFavorite: false,
  catalogSourceId: 'source',
  remotePublicationId: 'remote',
);

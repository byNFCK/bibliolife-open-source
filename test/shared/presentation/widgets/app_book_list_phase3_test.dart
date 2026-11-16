import 'package:bibliolife/shared/presentation/presenters/book_reading_progress_availability.dart';
import 'package:bibliolife/shared/presentation/presenters/book_list_status_presenter.dart';
import 'package:bibliolife/features/library/application/providers/library_providers.dart';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:bibliolife/app/theme/app_theme.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/presentation/widgets/remote_catalog_book_tile.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_book_card.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_book_tile.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_providers.dart';
import 'package:bibliolife/features/reader/domain/models/reading_progress.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:bibliolife/shared/presentation/widgets/app_book_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _title = 'Відьмак Геральт. Меч призначення. Частина 2';
const _author = 'Анджей Сапковський';

void main() {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Phase 3 geometry at 320dp scale=$scale dark=$dark', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(320, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(_app(_row(), dark: dark, scale: scale));
        await tester.pumpAndSettle();
        final cover = tester.getRect(find.byKey(const Key('book-list-cover')));
        final title = tester.getRect(find.byKey(const Key('book-list-title')));
        final action = tester.getRect(
          find.byKey(const Key('book-list-actions')),
        );
        final bottom = tester.getRect(
          find.byKey(const Key('book-list-bottom')),
        );
        expect(cover.size, const Size(92, 138));
        expect(cover.left, 16);
        expect(cover.top, 12);
        expect(title.left - cover.right, 16);
        expect(title.top, cover.top);
        final visibleIcon = tester.getRect(find.byIcon(Icons.more_vert));
        expect(
          visibleIcon.center.dy,
          closeTo(title.top + 18 * 1.2 * scale / 2, 2),
        );
        expect(action.top, greaterThanOrEqualTo(0));
        expect(action.right, 304);
        expect(action.size, const Size(48, 48));
        expect(bottom.left, title.left);
        expect(bottom.bottom, greaterThanOrEqualTo(cover.bottom));
        final text = tester.widget<Text>(
          find.byKey(const Key('book-list-title')),
        );
        expect(text.maxLines, 2);
        expect(text.style!.fontSize, 18);
        expect(text.style!.fontWeight, FontWeight.w600);
        expect(
          tester
              .widget<Text>(find.byKey(const Key('book-list-author')))
              .maxLines,
          2,
        );
        expect(
          tester
              .widget<ClipRRect>(find.byKey(const Key('book-list-cover')))
              .borderRadius,
          BorderRadius.circular(12),
        );
        final progress = tester.getRect(
          find.byKey(const Key('book-list-progress')),
        );
        expect(progress.width, cover.width);
        expect(progress.bottom, cover.bottom);
        expect(progress.height, greaterThanOrEqualTo(28));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('all action variants reserve identical cover and text geometry', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Rect? title;
    Rect? author;
    Rect? cover;
    for (final action in <Widget?>[
      null,
      PopupMenuButton<String>(
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'existing', child: Text('Existing action')),
        ],
      ),
      IconButton(onPressed: () {}, icon: const Icon(Icons.favorite_border)),
      Checkbox(value: false, onChanged: (_) {}),
      IconButton(onPressed: () {}, icon: const Icon(Icons.close)),
    ]) {
      await tester.pumpWidget(
        _app(
          AppBookListTile(
            title: _title,
            metadata: _author,
            cover: const ColoredBox(color: Colors.grey),
            onOpen: () {},
            actions: [?action],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final currentTitle = tester.getRect(
        find.byKey(const Key('book-list-title')),
      );
      final currentAuthor = tester.getRect(
        find.byKey(const Key('book-list-author')),
      );
      final currentCover = tester.getRect(
        find.byKey(const Key('book-list-cover')),
      );
      expect(
        tester.getSize(find.byKey(const Key('book-list-actions'))),
        const Size(48, 48),
      );
      if (title != null) {
        expect(currentTitle, title);
        expect(currentAuthor, author);
        expect(currentCover, cover);
      }
      title = currentTitle;
      author = currentAuthor;
      cover = currentCover;
      expect(find.byKey(const Key('book-list-bottom')), findsNothing);
    }
  });

  testWidgets(
    'local file shows current progression and defaults to 0 without history',
    (tester) async {
      final updates = Stream<ReadingProgress?>.fromIterable([
        null,
        _progress(.53),
      ]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localBookFileAvailableProvider.overrideWith((ref, _) async => true),
            readingProgressProvider.overrideWith((ref, id) {
              expect(id, 'local');
              return updates;
            }),
          ],
          child: _material(LibraryBookTile(book: _book, onOpen: () {})),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('53%'), findsOneWidget);
      expect(find.byKey(const Key('book-list-progress')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      for (final value in [null, 0.0, .25, 1.0]) {
        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey(value),
            overrides: [
              localBookFileAvailableProvider.overrideWith(
                (ref, _) async => true,
              ),
              readingProgressProvider.overrideWith(
                (ref, _) =>
                    Stream.value(value == null ? null : _progress(value)),
              ),
            ],
            child: _material(LibraryBookTile(book: _book, onOpen: () {})),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('book-list-progress')), findsOneWidget);
        if (value != null) {
          expect(find.text('${(value * 100).round()}%'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'remote has no fake footer, preserves actual bottom status and missing author',
    (tester) async {
      await tester.pumpWidget(
        _app(
          RemoteCatalogBookTile(
            publication: RemoteCatalogPublicationSummary(
              remoteId: 'remote',
              title: _title,
            ),
            status: const Text('Existing availability'),
            onOpen: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('book-list-progress')), findsNothing);
      expect(find.byKey(const Key('book-list-author')), findsNothing);
      expect(find.text('Unknown author'), findsNothing);
      expect(find.text('Existing availability'), findsOneWidget);
      expect(find.byKey(const Key('book-list-actions')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('book-list-actions'))),
        const Size(48, 48),
      );
      expect(find.byType(PopupMenuButton<String>), findsNothing);
    },
  );

  testWidgets(
    'cover footer opens once while checkbox and Remove remain independent',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var opens = 0;
      var selections = 0;
      var removes = 0;
      await tester.pumpWidget(
        _app(
          AppBookListTile(
            title: _title,
            metadata: _author,
            cover: const ColoredBox(color: Colors.grey),
            progressPercent: 53,
            onOpen: () => opens++,
            actions: [
              Checkbox(
                value: true,
                semanticLabel: 'Selected book',
                onChanged: (_) => selections++,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp('Reading progress 53%')),
        findsOneWidget,
      );
      await tester.tap(find.text('53%'));
      await tester.pumpAndSettle();
      expect(opens, 1);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(selections, 1);
      expect(opens, 1);
      await tester.pumpWidget(
        _app(
          AppBookListTile(
            title: _title,
            cover: const ColoredBox(color: Colors.grey),
            onOpen: null,
            actions: [
              IconButton(
                tooltip: 'Remove from draft',
                onPressed: () => removes++,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(_title));
      expect(opens, 1);
      await tester.tap(find.byTooltip('Remove from draft'));
      expect(removes, 1);
      semantics.dispose();
    },
  );

  testWidgets('export representative Phase 3 rendered boards when requested', (
    tester,
  ) async {
    if (!const bool.fromEnvironment('EXPORT_PHASE3_VISUALS')) return;
    const fontDirectory = String.fromEnvironment('PHASE3_FONT_DIR');
    await tester.runAsync(() async {
      final loader = FontLoader('Phase3Roboto');
      for (final name in [
        'roboto-regular.ttf',
        'roboto-medium.ttf',
        'roboto-bold.ttf',
      ]) {
        loader.addFont(
          File('$fontDirectory/$name').readAsBytes().then(ByteData.sublistView),
        );
      }
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(
            '$fontDirectory/materialicons-regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        );
      await icons.load();
    });
    await tester.binding.setSurfaceSize(const Size(400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        final rows = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _row(withStatus: false),
            RemoteCatalogBookTile(
              publication: RemoteCatalogPublicationSummary(
                remoteId: 'remote',
                title: _title,
                authors: [_author],
                accessMetadata: const {'sale.saleability': 'FREE'},
              ),
              onOpen: () {},
            ),
            AppBookListTile(
              title: _title,
              metadata: _author,
              bookStatus: BookListStatusPresenter.local(_book),
              cover: LibraryBookCover(book: _book),
              onOpen: () {},
              actions: [Checkbox(value: false, onChanged: (_) {})],
            ),
            AppBookListTile(
              title: _title,
              metadata: _author,
              bookStatus: BookListStatusPresenter.local(_book),
              cover: LibraryBookCover(book: _book),
              onOpen: () {},
              actions: [Checkbox(value: true, onChanged: (_) {})],
            ),
            AppBookListTile(
              title: _title,
              metadata: _author,
              bookStatus: BookListStatusPresenter.local(_book),
              cover: LibraryBookCover(book: _book),
              onOpen: null,
              actions: [
                IconButton(
                  tooltip: 'Remove from draft',
                  onPressed: () {},
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ],
        );
        final theme = buildAppTheme(
          dark ? fallbackDarkColorScheme : fallbackLightColorScheme,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              allBooksProvider.overrideWithValue(
                const AsyncData(<LibraryBook>[]),
              ),
            ],
            child: MaterialApp(
              theme: theme.copyWith(
                textTheme: theme.textTheme.apply(fontFamily: 'Phase3Roboto'),
              ),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: RepaintBoundary(
                      key: const Key('capture'),
                      child: ColoredBox(
                        color: theme.scaffoldBackgroundColor,
                        child: rows,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ImageByteFormat.png);
          final directory = Directory(
            const String.fromEnvironment('PHASE3_VISUAL_DIR'),
          );
          await directory.create(recursive: true);
          await File(
            '${directory.path}/list-dark-$dark-scale-$scale.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
  });
}

Widget _row({bool withStatus = true}) => AppBookListTile(
  title: _title,
  metadata: _author,
  bookStatus: BookListStatusPresenter.local(_book),
  cover: LibraryBookCover(book: _book),
  onOpen: () {},
  progressPercent: 53,
  status: withStatus ? const Text('In library') : null,
  actions: [
    PopupMenuButton<String>(
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'existing', child: Text('Existing action')),
      ],
    ),
  ],
);

Widget _app(Widget child, {bool dark = true, double scale = 1}) =>
    ProviderScope(
      overrides: [
        allBooksProvider.overrideWithValue(const AsyncData(<LibraryBook>[])),
      ],
      child: MaterialApp(
        theme: buildAppTheme(
          dark ? fallbackDarkColorScheme : fallbackLightColorScheme,
        ),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Align(alignment: Alignment.topLeft, child: child),
          ),
        ),
      ),
    );
Widget _material(Widget child) => MaterialApp(
  home: Scaffold(
    body: Align(alignment: Alignment.topLeft, child: child),
  ),
);
ReadingProgress _progress(double value) => ReadingProgress(
  bookId: 'local',
  locatorJson: null,
  progression: value,
  currentChapterTitle: null,
  currentPage: null,
  totalPages: null,
  updatedAt: DateTime(2026),
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
  fileSizeBytes: 1,
  dateAdded: DateTime(2026),
  lastOpenedAt: null,
  isFavorite: false,
);

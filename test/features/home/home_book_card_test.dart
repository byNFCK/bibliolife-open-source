import 'package:bibliolife/shared/presentation/presenters/book_reading_progress_availability.dart';
import 'dart:async';

import 'package:bibliolife/app/theme/app_theme.dart';
import 'package:bibliolife/features/home/domain/models/book_reading_progress.dart';
import 'package:bibliolife/features/home/presentation/widgets/home_book_card.dart';
import 'package:bibliolife/features/library/application/providers/library_repository_provider.dart';
import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:bibliolife/shared/presentation/widgets/app_book_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reading progress clamps to presentation range', () {
    expect(BookReadingProgress.fromProgression(-0.2).percent, 0);
    expect(BookReadingProgress.fromProgression(0.456).percent, 46);
    final completed = BookReadingProgress.fromProgression(1.4);
    expect(completed.percent, 100);
    expect(completed.isCompleted, isTrue);
  });

  testWidgets('card has cover and bottom bar with progress and favorite', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(
        book: _book(id: 'one', isFavorite: true),
        progress: BookReadingProgress.fromProgression(0.42),
      ),
    );

    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    expect(find.text('Author'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.byKey(const Key('app-book-card-cover')), findsOneWidget);
    expect(find.byKey(const Key('app-book-card-bottom-bar')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Reading progress 42%',
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Remove from favorites'), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('progress is always formatted and safely clamped', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(
        book: _book(id: 'zero'),
        progress: BookReadingProgress.fromProgression(0),
      ),
    );

    expect(find.text('0%'), findsOneWidget);

    await tester.pumpWidget(
      _subject(
        book: _book(id: 'partial'),
        progress: const BookReadingProgress(
          percent: 15,
          hasStarted: true,
          isCompleted: false,
        ),
      ),
    );
    expect(find.text('15%'), findsOneWidget);

    await tester.pumpWidget(
      _subject(
        book: _book(id: 'complete'),
        progress: const BookReadingProgress(
          percent: 150,
          hasStarted: true,
          isCompleted: true,
        ),
      ),
    );
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('favorite bar uses three equal flexible gaps', (tester) async {
    await tester.pumpWidget(
      _subject(
        book: _book(id: 'balanced'),
        progress: BookReadingProgress.fromProgression(.42),
      ),
    );

    final barFinder = find.byKey(const Key('app-book-card-bottom-bar'));
    expect(
      find.descendant(of: barFinder, matching: find.byType(BackdropFilter)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(const Key('app-book-card-panel-background')),
          )
          .color
          .a,
      closeTo(0.8, 0.001),
    );
    final rowFinder = find.descendant(
      of: barFinder,
      matching: find.byType(Row),
    );
    final gaps = find.descendant(
      of: rowFinder,
      matching: find.byType(Expanded),
    );
    expect(gaps, findsNWidgets(3));
    for (final gap in gaps.evaluate()) {
      expect((gap.widget as Expanded).flex, 1);
    }
    final barSize = tester.getSize(barFinder);
    expect(barSize.height, 40);
    final targetFinder = find
        .ancestor(
          of: find.byTooltip('Add to favorites'),
          matching: find.byType(IconButton),
        )
        .first;
    expect(tester.getSize(targetFinder), const Size(48, 48));
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Add to favorites'),
              matching: find.byType(IconButton),
            ),
          )
          .iconSize,
      20,
    );
    expect(
      (tester.getCenter(find.text('42%')).dy - tester.getCenter(barFinder).dy)
          .abs(),
      lessThan(1),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(fallbackLightColorScheme),
        home: Center(
          child: SizedBox(
            width: 164,
            height: 405,
            child: AppBookCard(
              title: 'Remote',
              author: 'Author',
              cover: const ColoredBox(color: Colors.grey),
              onOpen: () {},
              progressPercent: 0,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Add to favorites'), findsNothing);
    expect(find.text('0%'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('app-book-card-bottom-bar'))).height,
      40,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('card tap reports the correct book id', (tester) async {
    String? openedId;
    await tester.pumpWidget(
      _subject(
        book: _book(id: 'target'),
        onOpen: (id) => openedId = id,
      ),
    );

    await tester.tap(find.byKey(const Key('app-book-card-cover')));
    expect(openedId, 'target');
  });

  testWidgets('title, author, and metadata gap open the same card route', (
    tester,
  ) async {
    var openCalls = 0;
    await tester.pumpWidget(
      _subject(
        book: _book(id: 'metadata'),
        onOpen: (_) => openCalls++,
      ),
    );

    await tester.tap(find.text('Book metadata'));
    expect(openCalls, 1);
    await tester.tap(find.text('Author'));
    expect(openCalls, 2);
    final card = tester.getRect(find.byKey(const Key('app-book-card')));
    final title = tester.getRect(find.text('Book metadata'));
    await tester.tapAt(
      Offset(card.center.dx, card.bottom + (title.top - card.bottom) / 2),
    );
    expect(openCalls, 3);
    final itemFinder = find.ancestor(
      of: find.byKey(const Key('app-book-card')),
      matching: find.byType(GestureDetector),
    );
    final itemRect = tester.getRect(itemFinder.first);
    final authorRect = tester.getRect(find.text('Author'));
    expect(itemRect.bottom, lessThanOrEqualTo(authorRect.bottom + 1));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Material && widget.type == MaterialType.transparency,
      ),
      findsNothing,
    );
    expect(
      tester.widget<GestureDetector>(itemFinder.first).behavior,
      HitTestBehavior.opaque,
    );
    await tester.tapAt(Offset(itemRect.center.dx, itemRect.bottom + 24));
    expect(openCalls, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'favorite tap does not open the book and uses the existing flow',
    (tester) async {
      final repository = _PendingFavoriteRepository(completed: true);
      var openCalls = 0;
      await tester.pumpWidget(
        _subject(
          book: _book(id: 'favorite-action'),
          repository: repository,
          onOpen: (_) => openCalls++,
        ),
      );

      await tester.tap(find.byTooltip('Add to favorites'));
      await tester.pump();

      expect(repository.favoriteCalls, 1);
      expect(openCalls, 0);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    },
  );

  testWidgets('duplicate favorite taps are guarded while mutation is pending', (
    tester,
  ) async {
    final repository = _PendingFavoriteRepository();
    await tester.pumpWidget(
      _subject(
        book: _book(id: 'favorite'),
        repository: repository,
      ),
    );

    final favorite = find.byTooltip('Add to favorites');
    await tester.tap(favorite);
    await tester.pump();
    await tester.tap(favorite, warnIfMissed: false);
    await tester.pump();

    expect(repository.favoriteCalls, 1);
    repository.completer.complete();
    await tester.pump();
  });

  testWidgets('real cover uses an image and long text is ellipsized', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(
        book: _book(
          id: 'covered',
          coverPath: 'C:\\test-covers\\covered.png',
          title: 'A very long book title that cannot fit on one line',
          author: 'A very long author name that must be constrained',
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    final title = tester.widget<Text>(
      find.text('A very long book title that cannot fit on one line'),
    );
    final author = tester.widget<Text>(
      find.text('A very long author name that must be constrained'),
    );
    expect(title.maxLines, 2);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(author.maxLines, 1);
    expect(author.overflow, TextOverflow.ellipsis);
  });

  testWidgets('narrow card with enlarged text has no layout overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(
        book: _book(
          id: 'narrow',
          title: 'A title long enough to use both permitted lines',
          author: 'A long author name',
        ),
        textScaleFactor: 1.5,
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('book card shapes keep rounded corners without an outline', (
    tester,
  ) async {
    for (final scheme in [fallbackLightColorScheme, fallbackDarkColorScheme]) {
      await tester.pumpWidget(
        _subject(
          book: _book(id: scheme.brightness.name),
          colorScheme: scheme,
        ),
      );

      final shape =
          tester.widget<Card>(find.byKey(const Key('app-book-card'))).shape!
              as RoundedRectangleBorder;
      expect(shape.side.style, BorderStyle.none);
      expect(shape.borderRadius, BorderRadius.circular(24));
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(fallbackDarkColorScheme),
        home: const Scaffold(
          body: SizedBox(
            width: 180,
            height: 290,
            child: AppBookCardPlaceholder(),
          ),
        ),
      ),
    );
    final placeholderShape =
        tester
                .widget<Card>(
                  find.byKey(const Key('app-book-card-placeholder')),
                )
                .shape!
            as RoundedRectangleBorder;
    expect(placeholderShape.side.style, BorderStyle.none);
    expect(placeholderShape.borderRadius, BorderRadius.circular(24));
  });

  testWidgets('card resolves light and dark semantic surface colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      _subject(
        book: _book(id: 'light'),
        colorScheme: fallbackLightColorScheme,
      ),
    );
    expect(
      tester.widget<Card>(find.byType(Card)).color,
      fallbackLightColorScheme.surfaceContainerLow,
    );
    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(const Key('app-book-card-panel-background')),
          )
          .color,
      fallbackLightColorScheme.surfaceContainerHigh.withValues(alpha: 0.8),
    );

    await tester.pumpWidget(
      _subject(
        book: _book(id: 'dark'),
        colorScheme: fallbackDarkColorScheme,
      ),
    );
    expect(
      tester.widget<Card>(find.byType(Card)).color,
      fallbackDarkColorScheme.surfaceContainerLow,
    );
  });
}

Widget _subject({
  required LibraryBook book,
  BookReadingProgress? progress,
  ValueChanged<String>? onOpen,
  LibraryRepository? repository,
  double textScaleFactor = 1,
  ColorScheme? colorScheme,
}) {
  return ProviderScope(
    overrides: [
      localBookFileAvailableProvider.overrideWith((ref, source) => true),
      libraryRepositoryProvider.overrideWithValue(
        repository ?? _PendingFavoriteRepository(completed: true),
      ),
    ],
    child: MaterialApp(
      key: ValueKey(colorScheme?.brightness),
      theme: buildAppTheme(colorScheme ?? fallbackLightColorScheme),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScaleFactor)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 164,
              height: 405,
              child: HomeBookCard(
                book: book,
                progress: progress,
                onOpen: onOpen ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

LibraryBook _book({
  required String id,
  String? title,
  String? author = 'Author',
  String? coverPath,
  bool isFavorite = false,
}) {
  return LibraryBook(
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
    dateAdded: DateTime(2026, 1, 1),
    lastOpenedAt: null,
    isFavorite: isFavorite,
  );
}

class _PendingFavoriteRepository implements LibraryRepository {
  _PendingFavoriteRepository({bool completed = false}) {
    if (completed) completer.complete();
  }

  final completer = Completer<void>();
  var favoriteCalls = 0;

  @override
  Future<void> setFavorite(String id, bool isFavorite) {
    favoriteCalls++;
    return completer.future;
  }

  @override
  Stream<List<LibraryBook>> watchAllBooks() => Stream.value([]);

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
  Future<void> markBookOpened(String id, DateTime openedAt) async {}
}

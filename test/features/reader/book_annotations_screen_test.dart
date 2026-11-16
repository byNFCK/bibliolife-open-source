import 'dart:async';

import 'package:bibliolife/features/library/application/providers/library_repository_provider.dart';
import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';
import 'package:bibliolife/features/reader/application/providers/reader_annotation_repository_provider.dart';
import 'package:bibliolife/features/reader/domain/models/reader_annotation.dart';
import 'package:bibliolife/features/reader/domain/repositories/reader_annotation_repository.dart';
import 'package:bibliolife/features/reader/presentation/screens/book_annotations_screen.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows loading, empty and error states', (tester) async {
    final loading = _Repository(StreamController<List<ReaderAnnotation>>());
    await _pump(tester, loading);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    loading.emissions.add(const []);
    await tester.pump();
    expect(find.text('No annotations yet'), findsOneWidget);
    expect(
      find.text('Highlights you create in this book will appear here.'),
      findsOneWidget,
    );

    final failed = _Repository(
      StreamController<List<ReaderAnnotation>>()..addError(StateError('nope')),
    );
    await _pump(tester, failed);
    await tester.pump();
    expect(find.text('Could not load annotations.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('nope'), findsNothing);
  });

  testWidgets('renders newest first and ID ascending for equal timestamps', (
    tester,
  ) async {
    final repository = _Repository(StreamController<List<ReaderAnnotation>>());
    await _pump(tester, repository);
    repository.emissions.add([
      _annotation('z', text: 'equal z', createdAt: DateTime(2026, 1, 2)),
      _annotation('old', text: 'old', createdAt: DateTime(2026, 1, 1)),
      _annotation('a', text: 'equal a', createdAt: DateTime(2026, 1, 2)),
    ]);
    await tester.pump();

    final cards = tester.widgetList<BookAnnotationListTile>(
      find.byType(BookAnnotationListTile),
    );
    expect(cards.map((card) => card.annotation.id), ['a', 'z', 'old']);
    expect(find.byType(Material), findsWidgets);
    expect(find.byType(Ink), findsNWidgets(3));
    expect(find.byType(InkWell), findsWidgets);
  });

  for (final value in const {
    ReaderAnnotationColor.yellow: 'Yellow highlight',
    ReaderAnnotationColor.green: 'Green highlight',
    ReaderAnnotationColor.blue: 'Blue highlight',
    ReaderAnnotationColor.pink: 'Pink highlight',
  }.entries) {
    testWidgets('renders accessible ${value.key.storageValue} indicator', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: AnnotationColorIndicator(color: value.key)),
      );
      expect(find.bySemanticsLabel(value.value), findsOneWidget);
    });
  }

  testWidgets('unsupported color uses an accessible neutral fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AnnotationColorIndicator(color: ReaderAnnotationColor.purple),
      ),
    );
    expect(
      find.bySemanticsLabel('Highlight color unavailable'),
      findsOneWidget,
    );
  });

  testWidgets('normalizes display whitespace, limits lines and handles blank', (
    tester,
  ) async {
    final repository = _Repository(StreamController<List<ReaderAnnotation>>());
    await _pump(tester, repository);
    repository.emissions.add([
      _annotation('text', text: '  Unicode\n  текст\t remains  '),
      _annotation('blank', text: ' \n\t '),
    ]);
    await tester.pump();

    expect(find.text('Unicode текст remains'), findsOneWidget);
    expect(find.text('Highlighted passage'), findsOneWidget);
    final excerpt = tester.widget<Text>(find.text('Unicode текст remains'));
    expect(excerpt.maxLines, 4);
    expect(excerpt.overflow, TextOverflow.ellipsis);
  });

  testWidgets('delete is immediate, exact and guarded while pending', (
    tester,
  ) async {
    final repository = _Repository(StreamController<List<ReaderAnnotation>>());
    final pending = Completer<bool>();
    repository.pendingDelete = pending;
    await _pump(tester, repository);
    repository.emissions.add([_annotation('one'), _annotation('two')]);
    await tester.pump();

    final deleteButtons = find.byTooltip('Delete highlight');
    expect(deleteButtons, findsNWidgets(2));
    await tester.tap(deleteButtons.first);
    await tester.pump();
    expect(repository.deletedIds, ['one']);
    expect(find.byTooltip('Delete highlight'), findsOneWidget);
    pending.complete(true);
    await tester.pump();
  });

  testWidgets('failed delete leaves row and enables retry', (tester) async {
    final repository = _Repository(StreamController<List<ReaderAnnotation>>())
      ..deleteError = StateError('failed');
    await _pump(tester, repository);
    repository.emissions.add([_annotation('one', text: 'keep me')]);
    await tester.pump();

    await tester.tap(find.byTooltip('Delete highlight'));
    await tester.pump();
    expect(find.text('keep me'), findsOneWidget);
    expect(find.byTooltip('Delete highlight'), findsOneWidget);

    repository.deleteError = null;
    await tester.tap(find.byTooltip('Delete highlight'));
    await tester.pump();
    expect(repository.deletedIds, ['one', 'one']);
  });

  testWidgets('provider emissions remove and recolor rows reactively', (
    tester,
  ) async {
    final repository = _Repository(StreamController<List<ReaderAnnotation>>());
    await _pump(tester, repository);
    repository.emissions.add([
      _annotation('one', color: ReaderAnnotationColor.green),
    ]);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.text('selected'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AnnotationColorIndicator &&
            widget.color == ReaderAnnotationColor.green,
      ),
      findsOneWidget,
    );

    repository.emissions.add([
      _annotation('one', color: ReaderAnnotationColor.pink),
    ]);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AnnotationColorIndicator &&
            widget.color == ReaderAnnotationColor.pink,
      ),
      findsOneWidget,
    );

    repository.emissions.add(const []);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.text('No annotations yet'), findsOneWidget);
  });

  testWidgets('malformed locator reports controlled error', (tester) async {
    final repository = _Repository(StreamController<List<ReaderAnnotation>>());
    await _pump(tester, repository);
    repository.emissions.add([_annotation('one', locatorJson: '{bad')]);
    await tester.pump();
    await tester.tap(find.byType(BookAnnotationListTile));
    await tester.pump();
    expect(
      find.text('Could not open this highlight location.'),
      findsOneWidget,
    );
  });

  testWidgets('location metadata and date render together', (tester) async {
    final repository = _Repository(StreamController<List<ReaderAnnotation>>());
    await _pump(tester, repository);
    repository.emissions.add([
      _annotation(
        'one',
        locatorJson:
            '{"href":"chapter.xhtml","locations":{"position":42,"totalProgression":0.8}}',
      ),
    ]);
    await tester.pump();

    expect(find.textContaining('80% · '), findsOneWidget);
  });

  testWidgets(
    'malformed locator keeps the row and narrow layout does not overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository(
        StreamController<List<ReaderAnnotation>>(),
      );
      await _pump(tester, repository);
      repository.emissions.add([
        _annotation(
          'one',
          text: 'A long highlighted passage that must remain visible',
          locatorJson: '{bad',
        ),
      ]);
      await tester.pump();

      expect(find.textContaining('A long highlighted passage'), findsOneWidget);
      expect(find.textContaining('Page'), findsNothing);
      expect(find.byTooltip('Delete highlight'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pump(WidgetTester tester, _Repository repository) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        readerAnnotationRepositoryProvider.overrideWithValue(repository),
        libraryRepositoryProvider.overrideWithValue(_LibraryRepository()),
      ],
      child: const MaterialApp(
        home: Scaffold(body: BookAnnotationsScreen(bookId: 'book')),
      ),
    ),
  );
  await tester.pump();
}

ReaderAnnotation _annotation(
  String id, {
  String text = 'selected',
  String locatorJson = '{"href":"chapter.xhtml"}',
  ReaderAnnotationColor color = ReaderAnnotationColor.yellow,
  DateTime? createdAt,
}) => ReaderAnnotation(
  id: id,
  bookId: 'book',
  locatorJson: locatorJson,
  locationKey: 'location-$id',
  selectedText: text,
  color: color,
  href: 'chapter.xhtml',
  createdAt: createdAt ?? DateTime(2026),
  updatedAt: createdAt ?? DateTime(2026),
);

class _Repository implements ReaderAnnotationRepository {
  _Repository(this.emissions);

  final StreamController<List<ReaderAnnotation>> emissions;
  final deletedIds = <String>[];
  Completer<bool>? pendingDelete;
  Object? deleteError;

  @override
  Stream<List<ReaderAnnotation>> watchForBook(String bookId) =>
      emissions.stream;

  @override
  Future<bool> deleteById(String id) async {
    deletedIds.add(id);
    final error = deleteError;
    if (error != null) throw error;
    final pending = pendingDelete;
    pendingDelete = null;
    return pending?.future ?? true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LibraryRepository implements LibraryRepository {
  @override
  Stream<List<LibraryBook>> watchAllBooks() => Stream.value(const []);

  @override
  Stream<List<LibraryBook>> watchFavoriteBooks() => watchAllBooks();

  @override
  Stream<List<LibraryBook>> watchUnsortedBooks() => watchAllBooks();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

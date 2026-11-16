import 'package:bibliolife/features/reader/application/services/reader_annotation_draft_factory.dart';
import 'package:bibliolife/features/reader/domain/models/reader_annotation.dart';
import 'package:bibliolife/features/reader/domain/value_objects/annotation_location_key.dart';
import 'package:bibliolife_readium/bibliolife_readium.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final instant = DateTime.utc(2026, 7, 23, 18, 30);

  ReaderAnnotationDraftFactory factory({String id = 'annotation-id'}) =>
      ReaderAnnotationDraftFactory(idGenerator: () => id, clock: () => instant);

  ReaderSelectionPlatformEvent selection({
    String locatorJson =
        '{"href":"chapter.xhtml","locations":{"fragments":["#one","#two","#two"]}}',
    String selectedText = 'Привіт 😀',
    String? textBefore = 'Before',
    String? textAfter = 'After',
    String href = 'chapter.xhtml',
    double? progression = .25,
    double? totalProgression = .75,
  }) => ReaderSelectionPlatformEvent(
    locatorJson: locatorJson,
    selectedText: selectedText,
    textBefore: textBefore,
    textAfter: textAfter,
    href: href,
    progression: progression,
    totalProgression: totalProgression,
  );

  test('creates a complete draft with exact selection values', () {
    final source = selection();
    final draft = factory().create(
      bookId: 'book-id',
      selection: source,
      style: ReaderAnnotationStyle.underline,
      color: ReaderAnnotationColor.purple,
      note: '  A note  ',
    );

    expect(draft.id, 'annotation-id');
    expect(draft.bookId, 'book-id');
    expect(draft.locatorJson, source.locatorJson);
    expect(
      draft.locationKey,
      AnnotationLocationKey.build(
        bookId: 'book-id',
        href: source.href,
        fragments: ['#one', '#two', '#two'],
        progression: .25,
        selectedText: 'Привіт 😀',
      ),
    );
    expect(draft.selectedText, 'Привіт 😀');
    expect(draft.textBefore, 'Before');
    expect(draft.textAfter, 'After');
    expect(draft.note, 'A note');
    expect(draft.style, ReaderAnnotationStyle.underline);
    expect(draft.color, ReaderAnnotationColor.purple);
    expect(draft.href, source.href);
    expect(draft.progression, .25);
    expect(draft.totalProgression, .75);
    expect(draft.createdAt, instant);
    expect(draft.updatedAt, instant);
  });

  test(
    'location key uses ordered and repeated fragments with null progression',
    () {
      final source = selection(
        locatorJson:
            '{"locations":{"fragments":["#first","#second","#first"]}}',
        selectedText: '漢字 😀',
        progression: null,
      );
      final draft = factory().create(
        bookId: 'book',
        selection: source,
        style: ReaderAnnotationStyle.highlight,
        color: ReaderAnnotationColor.blue,
      );

      expect(
        draft.locationKey,
        AnnotationLocationKey.build(
          bookId: 'book',
          href: source.href,
          fragments: ['#first', '#second', '#first'],
          progression: null,
          selectedText: '漢字 😀',
        ),
      );
    },
  );

  test('location key retains zero progression', () {
    final source = selection(progression: 0);
    final draft = factory().create(
      bookId: 'book',
      selection: source,
      style: ReaderAnnotationStyle.highlight,
      color: ReaderAnnotationColor.yellow,
    );

    expect(
      draft.locationKey,
      AnnotationLocationKey.build(
        bookId: 'book',
        href: source.href,
        fragments: ['#one', '#two', '#two'],
        progression: 0,
        selectedText: source.selectedText,
      ),
    );
  });

  test('accepts a Readium locator with no fragments', () {
    final source = selection(locatorJson: '{"locations":{}}');
    final draft = factory().create(
      bookId: 'book',
      selection: source,
      style: ReaderAnnotationStyle.highlight,
      color: ReaderAnnotationColor.green,
    );

    expect(
      draft.locationKey,
      AnnotationLocationKey.build(
        bookId: 'book',
        href: source.href,
        fragments: const [],
        progression: source.progression,
        selectedText: source.selectedText,
      ),
    );
  });

  test('location key uses a single Readium fragment', () {
    final source = selection(
      locatorJson: '{"locations":{"fragments":["#single"]}}',
    );
    final draft = factory().create(
      bookId: 'book',
      selection: source,
      style: ReaderAnnotationStyle.highlight,
      color: ReaderAnnotationColor.green,
    );

    expect(
      draft.locationKey,
      AnnotationLocationKey.build(
        bookId: 'book',
        href: source.href,
        fragments: ['#single'],
        progression: source.progression,
        selectedText: source.selectedText,
      ),
    );
  });

  test('rejects malformed or structurally invalid locator JSON', () {
    for (final locatorJson in [
      'not json',
      '{}',
      '{"locations":{"fragments":[1]}}',
    ]) {
      expect(
        () => factory().create(
          bookId: 'book',
          selection: selection(locatorJson: locatorJson),
          style: ReaderAnnotationStyle.highlight,
          color: ReaderAnnotationColor.yellow,
        ),
        throwsFormatException,
      );
    }
  });

  test('normalizes creation notes without changing selection context', () {
    for (final entry in <String?, String?>{
      null: null,
      '': null,
      ' \t\n ': null,
      '  first\n  second  ': 'first\n  second',
      '  first   second  ': 'first   second',
    }.entries) {
      final draft = factory().create(
        bookId: 'book',
        selection: selection(textBefore: '  context  ', textAfter: '\nnext\n'),
        style: ReaderAnnotationStyle.highlight,
        color: ReaderAnnotationColor.pink,
        note: entry.key,
      );
      expect(draft.note, entry.value);
      expect(draft.textBefore, '  context  ');
      expect(draft.textAfter, '\nnext\n');
    }
  });

  test(
    'rejects invalid required values and manually constructed progression',
    () {
      final valid = selection();
      for (final bookId in ['', ' ']) {
        expect(
          () => factory().create(
            bookId: bookId,
            selection: valid,
            style: ReaderAnnotationStyle.highlight,
            color: ReaderAnnotationColor.yellow,
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => factory(id: ' ').create(
          bookId: 'book',
          selection: valid,
          style: ReaderAnnotationStyle.highlight,
          color: ReaderAnnotationColor.yellow,
        ),
        throwsArgumentError,
      );
      expect(
        () => factory().create(
          bookId: 'book',
          selection: selection(selectedText: ' '),
          style: ReaderAnnotationStyle.highlight,
          color: ReaderAnnotationColor.yellow,
        ),
        throwsArgumentError,
      );
      expect(
        () => factory().create(
          bookId: 'book',
          selection: selection(href: ' '),
          style: ReaderAnnotationStyle.highlight,
          color: ReaderAnnotationColor.yellow,
        ),
        throwsArgumentError,
      );
      expect(
        () => factory().create(
          bookId: 'book',
          selection: selection(progression: double.nan),
          style: ReaderAnnotationStyle.highlight,
          color: ReaderAnnotationColor.yellow,
        ),
        throwsArgumentError,
      );
      expect(
        () => factory().create(
          bookId: 'book',
          selection: selection(totalProgression: double.infinity),
          style: ReaderAnnotationStyle.highlight,
          color: ReaderAnnotationColor.yellow,
        ),
        throwsArgumentError,
      );
    },
  );
}

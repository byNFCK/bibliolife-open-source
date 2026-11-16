import 'dart:async';

import 'package:bibliolife/core/database/app_database.dart' as db;
import 'package:bibliolife/features/reader/data/repositories/drift_reader_annotation_repository.dart';
import 'package:bibliolife/features/reader/domain/models/reader_annotation.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late db.AppDatabase database;
  late DriftReaderAnnotationRepository repository;

  setUp(() async {
    database = db.AppDatabase(NativeDatabase.memory());
    await database.customStatement('PRAGMA foreign_keys = ON');
    repository = DriftReaderAnnotationRepository(database);
    for (final id in ['a', 'b']) {
      await database.booksDao.insertBook(
        db.BooksCompanion.insert(
          id: id,
          title: id,
          filePath: '/$id',
          fileName: id,
          fileExtension: 'epub',
          fileSizeBytes: 1,
          dateAdded: DateTime(2026),
        ),
      );
    }
  });

  tearDown(() => database.close());

  Future<void> add(String id, String book, String key, {double? total}) =>
      database
          .into(database.readerAnnotations)
          .insert(
            db.ReaderAnnotationsCompanion.insert(
              id: id,
              bookId: book,
              locatorJson: '{"id":"$id"}',
              locationKey: key,
              selectedText: id,
              href: 'c',
              totalProgression: Value(total),
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          );

  ReaderAnnotation model({
    String id = 'insert',
    String book = 'a',
    String key = 'insert-key',
    double? progression = .2,
    double? total = .4,
  }) => ReaderAnnotation(
    id: id,
    bookId: book,
    locatorJson: '{"unicode":"Привіт 😀"}',
    locationKey: key,
    selectedText: 'Привіт 😀',
    href: 'c',
    progression: progression,
    totalProgression: total,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026, 1, 2),
  );

  test('list filters and preserves exact locator data', () async {
    expect(await repository.listForBook('a'), isEmpty);
    await add('x', 'a', 'key');
    await add('y', 'b', 'key');
    final rows = await repository.listForBook('a');
    expect(rows.single.locatorJson, '{"id":"x"}');
    expect(rows.single.locationKey, 'key');
  });

  test(
    'skips a malformed legacy row without hiding valid annotations',
    () async {
      await add('valid', 'a', 'valid-key');
      await database
          .into(database.readerAnnotations)
          .insert(
            db.ReaderAnnotationsCompanion.insert(
              id: 'malformed',
              bookId: 'a',
              locatorJson: '{"id":"malformed"}',
              locationKey: 'malformed-key',
              selectedText: 'malformed',
              href: 'c',
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ).copyWith(style: const Value('legacy-unknown-style')),
          );

      expect((await repository.listForBook('a')).map((item) => item.id), [
        'valid',
      ]);
      expect(
        (await repository.watchForBook('a').first).map((item) => item.id),
        ['valid'],
      );
    },
  );

  test('get methods find exact rows and missing returns null', () async {
    await add('x', 'a', 'key');
    expect((await repository.getById('x'))?.id, 'x');
    expect(await repository.getById('missing'), isNull);
    expect(
      (await repository.getByLocation(bookId: 'a', locationKey: 'key'))?.id,
      'x',
    );
    expect(
      await repository.getByLocation(bookId: 'b', locationKey: 'key'),
      isNull,
    );
  });

  test('ordering and validation are deterministic', () async {
    await add('z', 'a', 'z', total: .2);
    await add('a', 'a', 'a', total: .2);
    await add('n', 'a', 'n');
    expect((await repository.listForBook('a')).map((e) => e.id), [
      'a',
      'z',
      'n',
    ]);
    expect(() => repository.listForBook(' '), throwsArgumentError);
    expect(() => repository.getById(' '), throwsArgumentError);
    expect(
      () => repository.getByLocation(bookId: 'a', locationKey: ' '),
      throwsArgumentError,
    );
  });

  test('insert stores and returns exact annotation', () async {
    final item = model();
    final stored = await repository.insert(item);
    expect(stored, await repository.getById(item.id));
    expect(
      (await repository.getByLocation(
        bookId: 'a',
        locationKey: 'insert-key',
      ))?.locatorJson,
      item.locatorJson,
    );
    expect(
      await database.select(database.readerAnnotations).get(),
      hasLength(1),
    );
  });

  test('insert validates required values and progressions', () async {
    for (final item in [
      model(id: ' '),
      model(book: ' '),
      model(key: ' '),
      model(progression: -.1),
      model(progression: 1.1),
      model(progression: double.nan),
      model(total: -.1),
      model(total: 1.1),
      model(total: double.infinity),
    ]) {
      expect(() => repository.insert(item), throwsArgumentError);
    }
  });

  test('insert remains strict for conflicts', () async {
    await repository.insert(model());
    await expectLater(repository.insert(model()), throwsA(isA<Exception>()));
    expect(
      await database.select(database.readerAnnotations).get(),
      hasLength(1),
    );
    await expectLater(
      repository.insert(model(id: 'other')),
      throwsA(isA<Exception>()),
    );
    await repository.insert(model(id: 'book-b', book: 'b'));
    expect(
      await database.select(database.readerAnnotations).get(),
      hasLength(2),
    );
  });

  test('upsert inserts an absent logical row', () async {
    final item = model(id: 'upsert', key: 'upsert-key');
    final stored = await repository.upsert(item);
    expect(stored, await repository.getById('upsert'));
    expect(
      stored,
      await repository.getByLocation(bookId: 'a', locationKey: 'upsert-key'),
    );
    expect(stored.createdAt, item.createdAt);
    expect(stored.updatedAt, item.updatedAt);
    expect(
      await database.select(database.readerAnnotations).get(),
      hasLength(1),
    );

    for (final note in <String?>['', '   ', '  untrimmed  ']) {
      final inserted = await repository.upsert(
        ReaderAnnotation(
          id: 'upsert-$note',
          bookId: 'a',
          locatorJson: '{}',
          locationKey: 'upsert-$note',
          selectedText: 'text',
          note: note,
          href: 'c',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
      expect(inserted.note, note);
    }
  });

  test(
    'upsert preserves canonical identity and overwrites mutable fields',
    () async {
      final original = model(id: 'original', key: 'same');
      await repository.insert(original);
      final incoming = ReaderAnnotation(
        id: 'other',
        bookId: 'a',
        locatorJson: '{"changed":true}',
        locationKey: 'same',
        selectedText: 'changed',
        textBefore: 'before',
        textAfter: 'after',
        note: 'note',
        style: ReaderAnnotationStyle.underline,
        color: ReaderAnnotationColor.purple,
        href: 'other',
        progression: .9,
        totalProgression: .9,
        createdAt: DateTime(2000),
        updatedAt: DateTime(2030),
      );

      final result = await repository.upsert(incoming);

      expect(result.id, original.id);
      expect(result.bookId, original.bookId);
      expect(result.locationKey, original.locationKey);
      expect(result.createdAt, original.createdAt);
      expect(result.locatorJson, incoming.locatorJson);
      expect(result.selectedText, incoming.selectedText);
      expect(result.textBefore, incoming.textBefore);
      expect(result.textAfter, incoming.textAfter);
      expect(result.note, incoming.note);
      expect(result.style, incoming.style);
      expect(result.color, incoming.color);
      expect(result.href, incoming.href);
      expect(result.progression, incoming.progression);
      expect(result.totalProgression, incoming.totalProgression);
      expect(result.updatedAt, incoming.updatedAt);
      expect(
        result,
        await repository.getByLocation(bookId: 'a', locationKey: 'same'),
      );
      expect(result, await repository.getById('original'));
      expect(await repository.getById('other'), isNull);
      expect(
        await database.select(database.readerAnnotations).get(),
        hasLength(1),
      );
      expect(() => repository.upsert(model(key: ' ')), throwsArgumentError);
    },
  );

  test('upsert applies the existing-row note policy', () async {
    final original = ReaderAnnotation(
      id: 'original',
      bookId: 'a',
      locatorJson: '{}',
      locationKey: 'note',
      selectedText: 'text',
      note: 'old',
      href: 'c',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await repository.insert(original);

    for (final expectation in <(String?, String?)>[
      (null, 'old'),
      ('', null),
      ('   ', null),
      ('  new note  ', 'new note'),
      ('  first line\nsecond line  ', 'first line\nsecond line'),
      ('  first  middle   last  ', 'first  middle   last'),
    ]) {
      final result = await repository.upsert(
        ReaderAnnotation(
          id: 'incoming-${expectation.$1}',
          bookId: 'a',
          locatorJson: '{}',
          locationKey: 'note',
          selectedText: 'text',
          note: expectation.$1,
          href: 'c',
          createdAt: DateTime(2000),
          updatedAt: DateTime(2030),
        ),
      );
      expect(result.note, expectation.$2);
      expect(result.id, 'original');
    }
  });

  test(
    'upsert recovers a logical unique conflict and updates the canonical row',
    () async {
      final canonical = ReaderAnnotation(
        id: 'canonical',
        bookId: 'a',
        locatorJson: '{"old":true}',
        locationKey: 'race',
        selectedText: 'old',
        textBefore: 'old before',
        textAfter: 'old after',
        note: 'old note',
        href: 'old',
        progression: .1,
        totalProgression: .1,
        createdAt: DateTime(2020),
        updatedAt: DateTime(2020),
      );
      final incoming = ReaderAnnotation(
        id: 'incoming',
        bookId: 'a',
        locatorJson: '{"new":true}',
        locationKey: 'race',
        selectedText: 'new',
        textBefore: 'new before',
        textAfter: 'new after',
        note: null,
        style: ReaderAnnotationStyle.underline,
        color: ReaderAnnotationColor.purple,
        href: 'new',
        progression: .9,
        totalProgression: .9,
        createdAt: DateTime(2030),
        updatedAt: DateTime(2030),
      );
      final recoveringRepository = DriftReaderAnnotationRepository(
        database,
        beforeUpsertInsert: () => database
            .into(database.readerAnnotations)
            .insert(
              db.ReaderAnnotationsCompanion.insert(
                id: canonical.id,
                bookId: canonical.bookId,
                locatorJson: canonical.locatorJson,
                locationKey: canonical.locationKey,
                selectedText: canonical.selectedText,
                textBefore: Value(canonical.textBefore),
                textAfter: Value(canonical.textAfter),
                note: Value(canonical.note),
                href: canonical.href,
                progression: Value(canonical.progression),
                totalProgression: Value(canonical.totalProgression),
                createdAt: canonical.createdAt,
                updatedAt: canonical.updatedAt,
              ),
            ),
      );

      final result = await recoveringRepository.upsert(incoming);

      expect(result.id, canonical.id);
      expect(result.createdAt, canonical.createdAt);
      expect(result.locatorJson, incoming.locatorJson);
      expect(result.selectedText, incoming.selectedText);
      expect(result.textBefore, incoming.textBefore);
      expect(result.textAfter, incoming.textAfter);
      expect(result.note, canonical.note);
      expect(result.style, incoming.style);
      expect(result.color, incoming.color);
      expect(result.href, incoming.href);
      expect(result.progression, incoming.progression);
      expect(result.totalProgression, incoming.totalProgression);
      expect(result.updatedAt, incoming.updatedAt);
      expect(
        result,
        await recoveringRepository.getByLocation(
          bookId: 'a',
          locationKey: 'race',
        ),
      );
      expect(
        await database.select(database.readerAnnotations).get(),
        hasLength(1),
      );
    },
  );

  test('upsert propagates an unrelated primary-key conflict', () async {
    final unrelated = model(id: 'shared-id', key: 'unrelated');
    await repository.insert(unrelated);

    await expectLater(
      repository.upsert(model(id: 'shared-id', key: 'requested')),
      throwsA(isA<SqliteException>()),
    );

    expect(
      await repository.getByLocation(bookId: 'a', locationKey: 'requested'),
      isNull,
    );
    expect(await repository.getById('shared-id'), unrelated);
  });

  test('updateNote normalizes note and preserves every other field', () async {
    final original = ReaderAnnotation(
      id: 'note-update',
      bookId: 'a',
      locatorJson: '{"locator":"exact"}',
      locationKey: 'note-update',
      selectedText: 'selected',
      textBefore: 'before',
      textAfter: 'after',
      note: 'old',
      style: ReaderAnnotationStyle.underline,
      color: ReaderAnnotationColor.blue,
      href: 'chapter',
      progression: .2,
      totalProgression: .3,
      createdAt: DateTime(2020),
      updatedAt: DateTime(2021),
    );
    await repository.insert(original);
    final updatedAt = DateTime(2030);

    final result = await repository.updateNote(
      id: original.id,
      note: '  first line\nsecond   line  ',
      updatedAt: updatedAt,
    );

    final expected = ReaderAnnotation(
      id: original.id,
      bookId: original.bookId,
      locatorJson: original.locatorJson,
      locationKey: original.locationKey,
      selectedText: original.selectedText,
      textBefore: original.textBefore,
      textAfter: original.textAfter,
      note: 'first line\nsecond   line',
      style: original.style,
      color: original.color,
      href: original.href,
      progression: original.progression,
      totalProgression: original.totalProgression,
      createdAt: original.createdAt,
      updatedAt: updatedAt,
    );
    expect(result, expected);
    expect(result, await repository.getById(original.id));
  });

  test('updateNote clears null and blank notes', () async {
    for (final entry in <(String, String?)>[
      ('null', null),
      ('empty', ''),
      ('whitespace', '   '),
    ]) {
      final annotation = ReaderAnnotation(
        id: 'clear-${entry.$1}',
        bookId: 'a',
        locatorJson: '{}',
        locationKey: 'clear-${entry.$1}',
        selectedText: 'text',
        note: 'old',
        href: 'c',
        createdAt: DateTime(2020),
        updatedAt: DateTime(2020),
      );
      await repository.insert(annotation);
      final result = await repository.updateNote(
        id: annotation.id,
        note: entry.$2,
        updatedAt: DateTime(2030),
      );
      expect(result.note, isNull);
      expect(result.updatedAt, DateTime(2030));
      expect(result.createdAt, annotation.createdAt);
    }
  });

  test('updateNote validates IDs and reports missing rows', () async {
    final existing = model(id: 'existing', key: 'existing');
    await repository.insert(existing);

    for (final id in ['', '   ']) {
      await expectLater(
        repository.updateNote(id: id, note: 'note', updatedAt: DateTime(2030)),
        throwsArgumentError,
      );
    }
    await expectLater(
      repository.updateNote(
        id: 'missing',
        note: 'note',
        updatedAt: DateTime(2030),
      ),
      throwsA(
        predicate<Object>(
          (error) =>
              error is StateError &&
              error.message == 'Reader annotation not found',
        ),
      ),
    );
    expect(await repository.getById(existing.id), existing);
    expect(
      await database.select(database.readerAnnotations).get(),
      hasLength(1),
    );
  });

  test('updateStyleAndColor updates style only', () async {
    final original = ReaderAnnotation(
      id: 'style-only',
      bookId: 'a',
      locatorJson: '{"locator":"exact"}',
      locationKey: 'style-only',
      selectedText: 'selected',
      textBefore: 'before',
      textAfter: 'after',
      note: 'note',
      style: ReaderAnnotationStyle.highlight,
      color: ReaderAnnotationColor.green,
      href: 'chapter',
      progression: .2,
      totalProgression: .3,
      createdAt: DateTime(2020),
      updatedAt: DateTime(2021),
    );
    await repository.insert(original);
    final updatedAt = DateTime(2030);

    final result = await repository.updateStyleAndColor(
      id: original.id,
      style: ReaderAnnotationStyle.underline,
      updatedAt: updatedAt,
    );

    final expected = ReaderAnnotation(
      id: original.id,
      bookId: original.bookId,
      locatorJson: original.locatorJson,
      locationKey: original.locationKey,
      selectedText: original.selectedText,
      textBefore: original.textBefore,
      textAfter: original.textAfter,
      note: original.note,
      style: ReaderAnnotationStyle.underline,
      color: original.color,
      href: original.href,
      progression: original.progression,
      totalProgression: original.totalProgression,
      createdAt: original.createdAt,
      updatedAt: updatedAt,
    );
    expect(result, expected);
    expect(result, await repository.getById(original.id));
  });

  test('updateStyleAndColor updates color only', () async {
    final original = model(id: 'color-only', key: 'color-only');
    await repository.insert(original);

    final result = await repository.updateStyleAndColor(
      id: original.id,
      color: ReaderAnnotationColor.pink,
      updatedAt: DateTime(2030),
    );

    expect(result.style, original.style);
    expect(result.color, ReaderAnnotationColor.pink);
    expect(result.updatedAt, DateTime(2030));
    expect(result.createdAt, original.createdAt);
    expect(result.note, original.note);
  });

  test(
    'updateStyleAndColor updates both values without creating a row',
    () async {
      final original = model(id: 'both', key: 'both');
      await repository.insert(original);

      final result = await repository.updateStyleAndColor(
        id: original.id,
        style: ReaderAnnotationStyle.underline,
        color: ReaderAnnotationColor.purple,
        updatedAt: DateTime(2030),
      );

      expect(result.id, original.id);
      expect(result.style, ReaderAnnotationStyle.underline);
      expect(result.color, ReaderAnnotationColor.purple);
      expect(
        await database.select(database.readerAnnotations).get(),
        hasLength(1),
      );
    },
  );

  test(
    'updateStyleAndColor validates arguments and reports missing rows',
    () async {
      final existing = model(id: 'existing', key: 'existing');
      await repository.insert(existing);

      for (final id in ['', '   ']) {
        await expectLater(
          repository.updateStyleAndColor(
            id: id,
            style: ReaderAnnotationStyle.underline,
            updatedAt: DateTime(2030),
          ),
          throwsArgumentError,
        );
      }
      await expectLater(
        repository.updateStyleAndColor(
          id: existing.id,
          updatedAt: DateTime(2030),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.updateStyleAndColor(
          id: 'missing',
          style: ReaderAnnotationStyle.underline,
          updatedAt: DateTime(2030),
        ),
        throwsA(
          predicate<Object>(
            (error) =>
                error is StateError &&
                error.message == 'Reader annotation not found',
          ),
        ),
      );
      expect(await repository.getById(existing.id), existing);
      expect(
        await database.select(database.readerAnnotations).get(),
        hasLength(1),
      );
    },
  );

  test('deleteById removes only the exact row', () async {
    await repository.insert(model(id: 'delete', key: 'delete'));
    await repository.insert(model(id: 'remaining', key: 'remaining'));

    expect(await repository.deleteById('delete'), isTrue);
    expect(await repository.getById('delete'), isNull);
    expect(await repository.deleteById('delete'), isFalse);
    expect((await repository.getById('remaining'))?.id, 'remaining');
    for (final id in ['', '   ']) {
      await expectLater(repository.deleteById(id), throwsArgumentError);
    }
  });

  test('deleteByLocation removes only the exact logical row', () async {
    await repository.insert(model(id: 'a-row', key: 'shared'));
    await repository.insert(model(id: 'b-row', book: 'b', key: 'shared'));

    expect(
      await repository.deleteByLocation(bookId: 'a', locationKey: 'shared'),
      isTrue,
    );
    expect(
      await repository.deleteByLocation(bookId: 'a', locationKey: 'shared'),
      isFalse,
    );
    expect(
      await repository.deleteByLocation(bookId: 'a', locationKey: 'missing'),
      isFalse,
    );
    expect(
      await repository.deleteByLocation(bookId: 'b', locationKey: 'missing'),
      isFalse,
    );
    expect((await repository.getById('b-row'))?.id, 'b-row');
    for (final bookId in ['', '   ']) {
      await expectLater(
        repository.deleteByLocation(bookId: bookId, locationKey: 'shared'),
        throwsArgumentError,
      );
    }
    for (final locationKey in ['', '   ']) {
      await expectLater(
        repository.deleteByLocation(bookId: 'b', locationKey: locationKey),
        throwsArgumentError,
      );
    }
  });

  test('deleteAllForBook removes only that book annotations', () async {
    await repository.insert(model(id: 'a-one', key: 'a-one'));
    await repository.insert(model(id: 'a-two', key: 'a-two'));
    await repository.insert(model(id: 'b-one', book: 'b', key: 'b-one'));

    expect(await repository.deleteAllForBook('a'), 2);
    expect(await repository.listForBook('a'), isEmpty);
    expect((await repository.getById('b-one'))?.id, 'b-one');
    expect(await repository.deleteAllForBook('a'), 0);
    for (final bookId in ['', '   ']) {
      await expectLater(
        repository.deleteAllForBook(bookId),
        throwsArgumentError,
      );
    }
  });

  test('watchForBook emits after deleteById', () async {
    await repository.insert(model(id: 'watched', key: 'watched'));
    final events = StreamIterator(repository.watchForBook('a'));

    expect(await events.moveNext(), isTrue);
    expect(events.current.map((annotation) => annotation.id), ['watched']);
    expect(await repository.deleteById('watched'), isTrue);
    expect(await events.moveNext(), isTrue);
    expect(events.current, isEmpty);
    await events.cancel();
  });
}

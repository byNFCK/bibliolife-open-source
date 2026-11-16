import 'dart:async';

import 'package:bibliolife/core/database/app_database.dart' as db;
import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/reader/application/providers/reader_annotation_providers.dart';
import 'package:bibliolife/features/reader/application/providers/reader_annotation_repository_provider.dart';
import 'package:bibliolife/features/reader/domain/models/reader_annotation.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late db.AppDatabase database;
  late ProviderContainer container;

  setUp(() async {
    database = db.AppDatabase(NativeDatabase.memory());
    await database.customStatement('PRAGMA foreign_keys = ON');
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
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  ReaderAnnotation annotation({
    required String id,
    required String bookId,
    required String locationKey,
    double? totalProgression,
  }) => ReaderAnnotation(
    id: id,
    bookId: bookId,
    locatorJson: '{"id":"$id"}',
    locationKey: locationKey,
    selectedText: id,
    href: 'chapter',
    totalProgression: totalProgression,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  test('readerAnnotationsForBookProvider emits initial empty data', () async {
    final provider = readerAnnotationsForBookProvider('a');
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    expect(await container.read(provider.future), isEmpty);
  });

  test(
    'readerAnnotationsForBookProvider filters and preserves ordering',
    () async {
      final repository = container.read(readerAnnotationRepositoryProvider);
      await repository.insert(
        annotation(
          id: 'later',
          bookId: 'a',
          locationKey: 'later',
          totalProgression: .8,
        ),
      );
      await repository.insert(
        annotation(
          id: 'earlier',
          bookId: 'a',
          locationKey: 'earlier',
          totalProgression: .2,
        ),
      );
      await repository.insert(
        annotation(
          id: 'other-book',
          bookId: 'b',
          locationKey: 'other-book',
          totalProgression: .1,
        ),
      );
      final provider = readerAnnotationsForBookProvider('a');
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      expect((await container.read(provider.future)).map((item) => item.id), [
        'earlier',
        'later',
      ]);
    },
  );

  test('readerAnnotationsForBookProvider emits repository mutations', () async {
    final provider = readerAnnotationsForBookProvider('a');
    Completer<List<ReaderAnnotation>>? nextData;
    final subscription = container.listen<AsyncValue<List<ReaderAnnotation>>>(
      provider,
      (_, next) {
        final value = next.value;
        if (value != null && nextData != null && !nextData.isCompleted) {
          nextData.complete(value);
        }
      },
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    expect(await container.read(provider.future), isEmpty);
    final repository = container.read(readerAnnotationRepositoryProvider);

    nextData = Completer<List<ReaderAnnotation>>();
    await repository.insert(
      annotation(id: 'live', bookId: 'a', locationKey: 'live'),
    );
    expect((await nextData.future).single.id, 'live');

    nextData = Completer<List<ReaderAnnotation>>();
    await repository.updateNote(
      id: 'live',
      note: '  updated  ',
      updatedAt: DateTime(2030),
    );
    expect((await nextData.future).single.note, 'updated');

    nextData = Completer<List<ReaderAnnotation>>();
    await repository.deleteById('live');
    expect(await nextData.future, isEmpty);
  });

  test(
    'readerAnnotationsForBookProvider surfaces invalid book IDs as errors',
    () async {
      final provider = readerAnnotationsForBookProvider('   ');
      final error = Completer<Object>();
      final subscription = container.listen(provider, (_, next) {
        if (next.hasError && !error.isCompleted) {
          error.complete(next.error!);
        }
      }, fireImmediately: true);
      addTearDown(subscription.close);

      expect(await error.future, isA<ArgumentError>());
    },
  );

  test(
    'sorted provider uses newest-first then ID as stable tie-breaker',
    () async {
      final repository = container.read(readerAnnotationRepositoryProvider);
      ReaderAnnotation value(String id, DateTime createdAt) => ReaderAnnotation(
        id: id,
        bookId: 'a',
        locatorJson: '{"id":"$id"}',
        locationKey: id,
        selectedText: id,
        href: 'chapter',
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      await repository.insert(value('z', DateTime(2026, 2)));
      await repository.insert(value('old', DateTime(2026, 1)));
      await repository.insert(value('a', DateTime(2026, 2)));

      final provider = sortedReaderAnnotationsForBookProvider('a');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(readerAnnotationsForBookProvider('a').future);
      expect(container.read(provider).requireValue.map((item) => item.id), [
        'a',
        'z',
        'old',
      ]);
    },
  );
}

import 'dart:async';

import 'package:bibliolife/core/database/app_database.dart' as db;
import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/reader/application/controllers/reader_annotation_mutation_controller.dart';
import 'package:bibliolife/features/reader/application/providers/reader_annotation_providers.dart';
import 'package:bibliolife/features/reader/application/providers/reader_annotation_repository_provider.dart';
import 'package:bibliolife/features/reader/domain/models/reader_annotation.dart';
import 'package:bibliolife/features/reader/domain/repositories/reader_annotation_repository.dart';
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
    String bookId = 'a',
    required String locationKey,
    String selectedText = 'selected',
    String? note,
  }) => ReaderAnnotation(
    id: id,
    bookId: bookId,
    locatorJson: '{"id":"$id"}',
    locationKey: locationKey,
    selectedText: selectedText,
    note: note,
    href: 'chapter',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  test(
    'controller delegates writes and the read-only stream reflects them',
    () async {
      final provider = readerAnnotationsForBookProvider('a');
      Completer<List<ReaderAnnotation>>? nextData;
      bool Function(List<ReaderAnnotation>)? matches;
      final subscription = container.listen<AsyncValue<List<ReaderAnnotation>>>(
        provider,
        (_, next) {
          final value = next.value;
          if (value != null &&
              nextData != null &&
              matches != null &&
              matches(value) &&
              !nextData.isCompleted) {
            nextData.complete(value);
          }
        },
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      expect(await container.read(provider.future), isEmpty);
      final controller = container.read(
        readerAnnotationMutationControllerProvider.notifier,
      );

      nextData = Completer<List<ReaderAnnotation>>();
      matches = (items) => items.singleOrNull?.id == 'canonical';
      final inserted = await controller.insert(
        annotation(id: 'canonical', locationKey: 'location', note: 'old'),
      );
      expect(inserted.id, 'canonical');
      expect((await nextData.future).single.id, 'canonical');

      nextData = Completer<List<ReaderAnnotation>>();
      matches = (items) => items.singleOrNull?.selectedText == 'upserted';
      final upserted = await controller.upsert(
        annotation(
          id: 'incoming',
          locationKey: 'location',
          selectedText: 'upserted',
        ),
      );
      expect(upserted.id, 'canonical');
      expect((await nextData.future).single.id, 'canonical');

      nextData = Completer<List<ReaderAnnotation>>();
      matches = (items) => items.singleOrNull?.note == 'updated';
      final noted = await controller.updateNote(
        id: 'canonical',
        note: '  updated  ',
        updatedAt: DateTime(2030),
      );
      expect(noted.note, 'updated');
      expect((await nextData.future).single.note, 'updated');

      final styled = await controller.updateStyleAndColor(
        id: 'canonical',
        style: ReaderAnnotationStyle.underline,
        updatedAt: DateTime(2031),
      );
      expect(styled.style, ReaderAnnotationStyle.underline);
    },
  );

  test('controller forwards delete results', () async {
    final controller = container.read(
      readerAnnotationMutationControllerProvider.notifier,
    );
    await controller.insert(annotation(id: 'first', locationKey: 'first'));
    await controller.insert(annotation(id: 'second', locationKey: 'second'));
    await controller.insert(
      annotation(id: 'other', bookId: 'b', locationKey: 'other'),
    );

    expect(await controller.deleteById('first'), isTrue);
    expect(
      await controller.deleteByLocation(bookId: 'a', locationKey: 'second'),
      isTrue,
    );
    expect(await controller.deleteAllForBook('a'), 0);
    expect(await controller.deleteAllForBook('b'), 1);
  });

  test(
    'controller preserves repository errors and enters AsyncError',
    () async {
      final controller = container.read(
        readerAnnotationMutationControllerProvider.notifier,
      );

      await expectLater(controller.deleteById(' '), throwsArgumentError);
      final invalidState = container.read(
        readerAnnotationMutationControllerProvider,
      );
      expect(invalidState, isA<AsyncError<void>>());
      expect((invalidState as AsyncError<void>).error, isA<ArgumentError>());

      await expectLater(
        controller.updateNote(
          id: 'missing',
          note: 'note',
          updatedAt: DateTime(2030),
        ),
        throwsA(isA<StateError>()),
      );
      final missingState = container.read(
        readerAnnotationMutationControllerProvider,
      );
      expect(missingState, isA<AsyncError<void>>());
      expect((missingState as AsyncError<void>).error, isA<StateError>());
    },
  );

  test('controller exposes idle, loading, success, and error states', () async {
    final repository = _ControlledRepository();
    final localContainer = ProviderContainer(
      overrides: [
        readerAnnotationRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(localContainer.dispose);
    final controller = localContainer.read(
      readerAnnotationMutationControllerProvider.notifier,
    );
    expect(
      localContainer.read(readerAnnotationMutationControllerProvider),
      isA<AsyncData<void>>(),
    );

    repository.nextInsert = Completer<ReaderAnnotation>();
    final successfulInsert = controller.insert(
      annotation(id: 'controlled', locationKey: 'controlled'),
    );
    expect(
      localContainer.read(readerAnnotationMutationControllerProvider),
      isA<AsyncLoading<void>>(),
    );
    repository.nextInsert!.complete(
      annotation(id: 'controlled', locationKey: 'controlled'),
    );
    await successfulInsert;
    expect(
      localContainer.read(readerAnnotationMutationControllerProvider),
      isA<AsyncData<void>>(),
    );

    repository.nextInsert = Completer<ReaderAnnotation>();
    final failingInsert = controller.insert(
      annotation(id: 'failing', locationKey: 'failing'),
    );
    repository.nextInsert!.completeError(ArgumentError('invalid'));
    await expectLater(failingInsert, throwsArgumentError);
    final state = localContainer.read(
      readerAnnotationMutationControllerProvider,
    );
    expect(state, isA<AsyncError<void>>());
    expect((state as AsyncError<void>).error, isA<ArgumentError>());
  });
}

class _ControlledRepository implements ReaderAnnotationRepository {
  Completer<ReaderAnnotation>? nextInsert;

  @override
  Future<ReaderAnnotation> insert(ReaderAnnotation annotation) =>
      nextInsert?.future ?? Future.value(annotation);

  @override
  Future<ReaderAnnotation> upsert(ReaderAnnotation annotation) =>
      Future.value(annotation);

  @override
  Future<ReaderAnnotation> updateNote({
    required String id,
    required String? note,
    required DateTime updatedAt,
  }) => Future.error(UnimplementedError());

  @override
  Future<ReaderAnnotation> updateStyleAndColor({
    required String id,
    ReaderAnnotationStyle? style,
    ReaderAnnotationColor? color,
    required DateTime updatedAt,
  }) => Future.error(UnimplementedError());

  @override
  Future<bool> deleteById(String id) => Future.error(UnimplementedError());

  @override
  Future<bool> deleteByLocation({
    required String bookId,
    required String locationKey,
  }) => Future.error(UnimplementedError());

  @override
  Future<int> deleteAllForBook(String bookId) =>
      Future.error(UnimplementedError());

  @override
  Future<ReaderAnnotation?> getById(String id) => Future.value(null);

  @override
  Future<ReaderAnnotation?> getByLocation({
    required String bookId,
    required String locationKey,
  }) => Future.value(null);

  @override
  Future<List<ReaderAnnotation>> listForBook(String bookId) => Future.value([]);

  @override
  Stream<List<ReaderAnnotation>> watchForBook(String bookId) =>
      Stream.value([]);
}

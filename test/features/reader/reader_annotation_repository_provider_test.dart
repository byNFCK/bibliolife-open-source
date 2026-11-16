import 'package:bibliolife/core/database/app_database.dart' as db;
import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/reader/application/providers/reader_annotation_repository_provider.dart';
import 'package:bibliolife/features/reader/data/repositories/drift_reader_annotation_repository.dart';
import 'package:bibliolife/features/reader/domain/models/reader_annotation.dart';
import 'package:bibliolife/features/reader/domain/repositories/reader_annotation_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reader annotation repository uses the overridden AppDatabase',
    () async {
      final database = db.AppDatabase(NativeDatabase.memory());
      await database.customStatement('PRAGMA foreign_keys = ON');
      await database.booksDao.insertBook(
        db.BooksCompanion.insert(
          id: 'book',
          title: 'book',
          filePath: '/book',
          fileName: 'book',
          fileExtension: 'epub',
          fileSizeBytes: 1,
          dateAdded: DateTime(2026),
        ),
      );
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      final repository = container.read(readerAnnotationRepositoryProvider);
      expect(repository, isA<ReaderAnnotationRepository>());
      expect(repository, isA<DriftReaderAnnotationRepository>());

      await repository.insert(
        ReaderAnnotation(
          id: 'annotation',
          bookId: 'book',
          locatorJson: '{"id":"annotation"}',
          locationKey: 'location',
          selectedText: 'selected',
          href: 'chapter',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );

      expect(
        await database.select(database.readerAnnotations).get(),
        hasLength(1),
      );
    },
  );
}

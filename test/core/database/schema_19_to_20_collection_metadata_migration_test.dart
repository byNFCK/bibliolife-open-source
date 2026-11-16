import 'dart:io';

import 'package:bibliolife/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'v19 migration adds collection metadata without losing memberships',
    () async {
      final directory = await Directory.systemTemp.createTemp('bibliolife_v19');
      final file = File(
        '${directory.path}${Platform.pathSeparator}bibliolife.db',
      );
      final old = AppDatabase(NativeDatabase(file));
      final now = DateTime(2026, 8, 11);
      await old.booksDao.insertBook(
        BooksCompanion.insert(
          id: 'book-1',
          title: 'Book',
          filePath: '/books/book.epub',
          fileName: 'book.epub',
          fileExtension: 'epub',
          fileSizeBytes: 1,
          dateAdded: now,
        ),
      );
      await old.collectionsDao.insertCollection(
        CollectionsCompanion.insert(
          id: 'collection-1',
          name: 'Saved',
          normalizedName: 'saved',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await old.collectionsDao.addMembership(
        BookCollectionEntriesCompanion.insert(
          collectionId: 'collection-1',
          bookId: 'book-1',
          addedAt: now,
        ),
      );
      await old.customStatement(
        'ALTER TABLE collections DROP COLUMN description',
      );
      await old.customStatement(
        'ALTER TABLE collections DROP COLUMN custom_cover_path',
      );
      await old.customStatement('PRAGMA user_version = 19');
      await old.close();

      final migrated = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await migrated.close();
        await directory.delete(recursive: true);
      });

      expect(migrated.schemaVersion, 23);
      final collection = await migrated.collectionsDao.getCollectionById(
        'collection-1',
      );
      expect(collection?.description, isNull);
      expect(collection?.customCoverPath, isNull);
      expect(
        await migrated.collectionsDao.containsMembership(
          'collection-1',
          'book-1',
        ),
        isTrue,
      );
    },
  );
}

import 'dart:io';
import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/collections/data/repositories/drift_collection_repository.dart';
import 'package:bibliolife/features/collections/domain/models/system_collection.dart';
import 'package:bibliolife/features/reader/data/repositories/drift_reading_progress_repository.dart';
import 'package:bibliolife/features/reader/domain/models/reading_progress.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> insertBook(AppDatabase db) => db.customStatement(
  "INSERT INTO books (id,title,file_path,file_name,file_extension,file_size_bytes,date_added,is_favorite,source,catalog_source_id,remote_publication_id) VALUES ('b','Book','/b.epub','b.epub','epub',10,1,1,'local','catalog','publication')",
);

void main() {
  test(
    'manual membership is independent and protected collections are ordered',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await insertBook(db);
      final repo = DriftCollectionRepository(db.collectionsDao);
      final all = await repo.watchAll().first;
      expect(all.map((c) => c.id), systemCollectionNames.keys);
      final user = await repo.create('Reading');
      expect(user.id, isNot(systemReadingId));
      expect((await repo.watchAll().first).map((c) => c.id), [
        ...systemCollectionNames.keys,
        user.id,
      ]);
      await repo.addBook(user.id, 'b');
      for (final id in systemCollectionNames.keys) {
        await repo.addBook(id, 'b');
      }
      for (final id in systemCollectionNames.keys) {
        expect(await repo.containsBook(id, 'b'), isTrue);
      }
      var summaries = await repo.watchSummaries().first;
      expect(summaries.map((s) => s.bookCount), [1, 1, 1, 1]);
      final changedCounts = repo.watchSummaries().firstWhere(
        (items) => items.length == 4 && items[1].bookCount == 0,
      );
      await repo.removeBook(systemReadingId, 'b');
      expect((await changedCounts).map((s) => s.bookCount), [1, 0, 1, 1]);
      expect(await repo.containsBook(systemReadingId, 'b'), isFalse);
      expect(await repo.containsBook(systemFinishedId, 'b'), isTrue);
      expect(await repo.containsBook(user.id, 'b'), isTrue);
      summaries = await repo.watchSummaries().first;
      expect(summaries.map((s) => s.bookCount), [1, 0, 1, 1]);
      await expectLater(
        repo.rename(systemReadingId, 'Changed'),
        throwsA(anything),
      );
      await expectLater(repo.delete(systemReadingId), throwsA(anything));
      await expectLater(
        repo.saveEditor(
          collectionId: systemReadingId,
          name: 'Changed',
          description: null,
          customCoverPath: null,
          selectedBookIds: {},
        ),
        throwsA(anything),
      );
      await repo.rename(user.id, 'Other');
      await repo.delete(user.id);
      expect(await repo.getById(user.id), isNull);
      final reader = DriftReadingProgressRepository(db.readingProgressDao);
      await reader.save(
        ReadingProgress(
          bookId: 'b',
          locatorJson: '{}',
          progression: 1,
          currentChapterTitle: null,
          currentPage: 20,
          totalPages: 20,
          updatedAt: DateTime(2026),
        ),
      );
      expect(await repo.containsBook(systemFinishedId, 'b'), isTrue);
      expect(await repo.containsBook(systemReadingId, 'b'), isFalse);
      expect((await reader.getForBook('b'))!.progression, 1);
    },
  );

  test(
    'system editor persists cover, description and membership without changing identity',
    () async {
      final dir = await Directory.systemTemp.createTemp('system_edit');
      final file = File('${dir.path}/library.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      await insertBook(db);
      await db.customStatement(
        "INSERT INTO books (id,title,file_path,file_name,file_extension,file_size_bytes,date_added) VALUES ('c','Other','/c.epub','c.epub','epub',10,1)",
      );
      var repo = DriftCollectionRepository(db.collectionsDao);
      final user = await repo.create('Reading');
      await repo.addBook(user.id, 'b');
      final before = (await repo.getById(systemReadingId))!;
      await repo.addBook(systemReadingId, 'b');
      final saved = await repo.saveEditor(
        collectionId: systemReadingId,
        name: before.name,
        description: 'Personal notes',
        customCoverPath: '/covers/reading.png',
        selectedBookIds: {'c'},
      );
      expect(saved.id, systemReadingId);
      expect(saved.normalizedName, before.normalizedName);
      expect(saved.name, before.name);
      expect(await repo.containsBook(systemReadingId, 'b'), isFalse);
      expect(await repo.containsBook(systemReadingId, 'c'), isTrue);
      expect(await repo.containsBook(user.id, 'b'), isTrue);
      await expectLater(
        repo.saveEditor(
          collectionId: systemReadingId,
          name: 'Changed',
          description: 'Bad',
          customCoverPath: null,
          selectedBookIds: {},
        ),
        throwsA(anything),
      );
      await expectLater(
        repo.saveEditor(
          collectionId: systemReadingId,
          name: before.name,
          description: 'Bad',
          customCoverPath: null,
          selectedBookIds: {'missing'},
        ),
        throwsA(anything),
      );
      await expectLater(repo.delete(systemReadingId), throwsA(anything));
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      repo = DriftCollectionRepository(db.collectionsDao);
      final after = (await repo.getById(systemReadingId))!;
      expect(
        [
          after.name,
          after.normalizedName,
          after.description,
          after.customCoverPath,
        ],
        [
          before.name,
          before.normalizedName,
          'Personal notes',
          '/covers/reading.png',
        ],
      );
      expect(await repo.containsBook(systemReadingId, 'c'), isTrue);
      expect(await repo.containsBook(user.id, 'b'), isTrue);
      await db.close();
      await dir.delete(recursive: true);
    },
  );

  for (final version in [21, 22]) {
    test(
      'schema $version migrates and preserves user data without converting statuses',
      () async {
        final dir = await Directory.systemTemp.createTemp('simple_collections');
        final file = File('${dir.path}/db.sqlite');
        var db = AppDatabase(NativeDatabase(file));
        await insertBook(db);
        await db.customStatement(
          "DELETE FROM collections WHERE id LIKE 'system-%'",
        );
        await db.customStatement(
          "INSERT INTO collections (id,name,normalized_name,created_at,updated_at) VALUES ('u','Reading','reading',1,1)",
        );
        // Deliberate collision with the first internal key must not rename the user row.
        await db.customStatement(
          "INSERT INTO collections (id,name,normalized_name,created_at,updated_at) VALUES ('collision','Collision',?,1,1)",
          ['\u0000system-finished'],
        );
        await db.customStatement(
          "INSERT INTO book_collection_entries (book_id,collection_id,added_at) VALUES ('b','u',1)",
        );
        await db.customStatement(
          "INSERT INTO reading_progress_entries (book_id,locator_json,progression,updated_at) VALUES ('b','{}',0.5,1)",
        );
        await db.customStatement(
          "INSERT INTO bookmarks (id,book_id,locator_json,created_at,updated_at) VALUES ('m','b','{}',1,1)",
        );
        await db.customStatement(
          "INSERT INTO reader_annotations (id,book_id,locator_json,location_key,selected_text,href,created_at,updated_at) VALUES ('a','b','{}','key','text','chapter',1,1)",
        );
        if (version == 22) {
          await db.customStatement(
            'CREATE TABLE reading_status_entries (book_id TEXT PRIMARY KEY, status TEXT NOT NULL, updated_at_micros INTEGER NOT NULL)',
          );
          await db.customStatement(
            "INSERT INTO reading_status_entries VALUES ('b','finished',1)",
          );
        }
        await db.customStatement('PRAGMA user_version = $version');
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        final repo = DriftCollectionRepository(db.collectionsDao);
        final all = await repo.watchAll().first;
        expect(all.take(3).map((c) => c.id), systemCollectionNames.keys);
        expect(all.where((c) => c.name == 'Reading'), hasLength(2));
        expect((await repo.getById('collision'))!.name, 'Collision');
        expect(await repo.containsBook('u', 'b'), isTrue);
        for (final id in systemCollectionNames.keys) {
          expect(await repo.containsBook(id, 'b'), isFalse);
        }
        final book = (await db.booksDao.getBookById('b'))!;
        expect(
          [
            book.isFavorite,
            book.source,
            book.catalogSourceId,
            book.remotePublicationId,
          ],
          [true, 'local', 'catalog', 'publication'],
        );
        expect(
          (await db.readingProgressDao.getProgressForBook('b'))!.progression,
          .5,
        );
        expect((await db.select(db.bookmarks).getSingle()).locatorJson, '{}');
        expect(
          (await db.select(db.readerAnnotations).getSingle()).selectedText,
          'text',
        );
        expect(
          await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE name='reading_status_entries'",
              )
              .get(),
          isEmpty,
        );
        await repo.addBook(systemReadingId, 'b');
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        final reopened = DriftCollectionRepository(db.collectionsDao);
        expect(
          (await reopened.watchAll().first).where(
            (c) => isSystemCollection(c.id),
          ),
          hasLength(3),
        );
        expect(await reopened.containsBook(systemReadingId, 'b'), isTrue);
        await db.close();
        await dir.delete(recursive: true);
      },
    );
  }
}

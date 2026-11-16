import 'dart:async';

import 'package:bibliolife/core/database/app_database.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.customStatement('PRAGMA foreign_keys = ON');
  });

  tearDown(() => database.close());

  test(
    'fresh schema 23 has collection metadata, cache settings, Home tabs, library defaults, cover provenance and indexed downloads',
    () async {
      expect(database.schemaVersion, 23);
      final bookColumns = await database
          .customSelect('PRAGMA table_info(books)')
          .get();
      expect(
        bookColumns.map((row) => row.read<String>('name')),
        contains('toc_json'),
      );
      expect(
        bookColumns.map((row) => row.read<String>('name')),
        contains('cover_provenance'),
      );
      expect(
        await database.select(database.remoteDownloadTasks).get(),
        isEmpty,
      );
      expect(
        (await database.remoteCacheSettingsDao.load())?.maximumBytes,
        1280 * 1024 * 1024,
      );
      expect(
        await database.select(database.homeOnlineTabSettingsEntries).get(),
        isEmpty,
      );
      expect(
        await database.select(database.librarySectionSettingsEntries).get(),
        isEmpty,
      );
      expect(
        await database
            .select(database.homeDefaultCarouselSettingsEntries)
            .get(),
        isEmpty,
      );
      final indexes = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' "
            "AND name='remote_download_tasks_state_updated_at'",
          )
          .get();
      expect(
        indexes.single.read<String>('name'),
        'remote_download_tasks_state_updated_at',
      );
    },
  );

  BooksCompanion book({
    required String id,
    required String filePath,
    required DateTime dateAdded,
    DateTime? lastOpenedAt,
    String fileExtension = 'epub',
  }) {
    return BooksCompanion.insert(
      id: id,
      title: 'Book $id',
      filePath: filePath,
      fileName: '$id.$fileExtension',
      fileExtension: fileExtension,
      fileSizeBytes: 1024,
      dateAdded: dateAdded,
      lastOpenedAt: Value(lastOpenedAt),
    );
  }

  test('inserts and reads a book', () async {
    final addedAt = DateTime(2026, 1, 1);
    await database.booksDao.insertBook(
      book(id: 'book-1', filePath: '/books/one.epub', dateAdded: addedAt),
    );

    final savedBook = await database.booksDao.getBookById('book-1');

    expect(savedBook, isNotNull);
    expect(savedBook!.filePath, '/books/one.epub');
  });

  test('rejects duplicate file paths', () async {
    final addedAt = DateTime(2026, 1, 1);
    await database.booksDao.insertBook(
      book(id: 'book-1', filePath: '/books/one.epub', dateAdded: addedAt),
    );

    await expectLater(
      database.booksDao.insertBook(
        book(id: 'book-2', filePath: '/books/one.epub', dateAdded: addedAt),
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('updates favorite status', () async {
    await database.booksDao.insertBook(
      book(
        id: 'book-1',
        filePath: '/books/one.epub',
        dateAdded: DateTime(2026, 1, 1),
      ),
    );

    await database.booksDao.setFavorite('book-1', true);

    expect((await database.booksDao.getBookById('book-1'))!.isFavorite, isTrue);
  });

  test('orders opened books first, then by date added', () async {
    await database.booksDao.insertBook(
      book(
        id: 'older-opened',
        filePath: '/books/older.epub',
        dateAdded: DateTime(2026, 1, 1),
        lastOpenedAt: DateTime(2026, 1, 2),
      ),
    );
    await database.booksDao.insertBook(
      book(
        id: 'newer-opened',
        filePath: '/books/newer.epub',
        dateAdded: DateTime(2026, 1, 1),
        lastOpenedAt: DateTime(2026, 1, 3),
      ),
    );
    await database.booksDao.insertBook(
      book(
        id: 'not-opened',
        filePath: '/books/unopened.epub',
        dateAdded: DateTime(2026, 1, 4),
      ),
    );

    final books = await database.booksDao.getAllBooks();

    expect(books.map((book) => book.id), [
      'newer-opened',
      'older-opened',
      'not-opened',
    ]);
  });

  test('zero-membership query reacts to membership changes', () async {
    final books = [
      book(
        id: 'book-a',
        filePath: '/books/a.epub',
        fileExtension: 'epub',
        dateAdded: DateTime(2026, 1, 1),
      ),
      book(
        id: 'book-b',
        filePath: '/books/b.pdf',
        fileExtension: 'pdf',
        dateAdded: DateTime(2026, 1, 2),
      ),
      book(
        id: 'book-c',
        filePath: '/books/c.txt',
        fileExtension: 'txt',
        dateAdded: DateTime(2026, 1, 3),
      ),
      book(
        id: 'book-d',
        filePath: '/books/d.fb2',
        fileExtension: 'fb2',
        dateAdded: DateTime(2026, 1, 4),
      ),
      book(
        id: 'book-e',
        filePath: '/books/e.cbz',
        fileExtension: 'cbz',
        dateAdded: DateTime(2026, 1, 5),
      ),
    ];
    for (final value in books) {
      await database.booksDao.insertBook(value);
    }
    for (final id in ['collection-1', 'collection-2']) {
      await database.collectionsDao.insertCollection(
        CollectionsCompanion.insert(
          id: id,
          name: id,
          normalizedName: id,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
    }
    await database.collectionsDao.addMembership(
      BookCollectionEntriesCompanion.insert(
        bookId: 'book-b',
        collectionId: 'collection-1',
        addedAt: DateTime(2026),
      ),
    );
    for (final collectionId in ['collection-1', 'collection-2']) {
      await database.collectionsDao.addMembership(
        BookCollectionEntriesCompanion.insert(
          bookId: 'book-d',
          collectionId: collectionId,
          addedAt: DateTime(2026),
        ),
      );
    }

    final allIds = (await database.booksDao.getAllBooks())
        .map((value) => value.id)
        .toSet();
    final zeroMembershipIds =
        (await database.booksDao.watchUnsortedBooks().first)
            .map((value) => value.id)
            .toSet();
    expect(allIds, {'book-a', 'book-b', 'book-c', 'book-d', 'book-e'});
    expect(zeroMembershipIds, {'book-a', 'book-c', 'book-e'});

    final iterator = StreamIterator(
      database.booksDao.watchUnsortedBooks().map(
        (values) => values.map((value) => value.id).toSet(),
      ),
    );
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current, {'book-a', 'book-c', 'book-e'});

    await database.collectionsDao.addMembership(
      BookCollectionEntriesCompanion.insert(
        bookId: 'book-a',
        collectionId: 'collection-1',
        addedAt: DateTime(2026),
      ),
    );
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current, {'book-c', 'book-e'});

    await database.collectionsDao.addMembership(
      BookCollectionEntriesCompanion.insert(
        bookId: 'book-a',
        collectionId: 'collection-2',
        addedAt: DateTime(2026),
      ),
    );
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current, {'book-c', 'book-e'});

    await database.collectionsDao.removeMembership('collection-1', 'book-a');
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current, {'book-c', 'book-e'});

    await database.collectionsDao.removeMembership('collection-2', 'book-a');
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current, {'book-a', 'book-c', 'book-e'});
    await iterator.cancel();

    await database.collectionsDao.addMembership(
      BookCollectionEntriesCompanion.insert(
        bookId: 'book-a',
        collectionId: 'collection-1',
        addedAt: DateTime(2026),
      ),
    );
    final afterCollectionDelete = database.booksDao
        .watchUnsortedBooks()
        .firstWhere((values) => values.any((value) => value.id == 'book-a'));
    await database.collectionsDao.deleteCollection('collection-1');
    expect(
      (await afterCollectionDelete).map((value) => value.id),
      contains('book-a'),
    );
  });

  test(
    'zero-membership query reacts to new unassigned books and deletion',
    () async {
      final iterator = StreamIterator(
        database.booksDao.watchUnsortedBooks().map(
          (values) => values.map((value) => value.id).toList(),
        ),
      );
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current, isEmpty);

      await database.booksDao.insertBook(
        book(
          id: 'new-book',
          filePath: '/books/new-book.pdf',
          fileExtension: 'pdf',
          dateAdded: DateTime(2026),
        ),
      );
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current, ['new-book']);

      await database.booksDao.deleteBookById('new-book');
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current, isEmpty);
      await iterator.cancel();
    },
  );

  test('upserts reading progress', () async {
    await database.booksDao.insertBook(
      book(
        id: 'book-1',
        filePath: '/books/one.epub',
        dateAdded: DateTime(2026, 1, 1),
      ),
    );
    await database.readingProgressDao.upsertProgress(
      ReadingProgressEntriesCompanion.insert(
        bookId: 'book-1',
        progression: const Value(0.25),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    await database.readingProgressDao.upsertProgress(
      ReadingProgressEntriesCompanion.insert(
        bookId: 'book-1',
        progression: const Value(0.75),
        updatedAt: DateTime(2026, 1, 2),
      ),
    );

    expect(
      (await database.readingProgressDao.getProgressForBook(
        'book-1',
      ))!.progression,
      0.75,
    );
  });

  test('deleting a book cascades its reading progress', () async {
    await database.booksDao.insertBook(
      book(
        id: 'book-1',
        filePath: '/books/one.epub',
        dateAdded: DateTime(2026, 1, 1),
      ),
    );
    await database.readingProgressDao.upsertProgress(
      ReadingProgressEntriesCompanion.insert(
        bookId: 'book-1',
        updatedAt: DateTime(2026, 1, 1),
      ),
    );

    await database.booksDao.deleteBookById('book-1');

    expect(
      await database.readingProgressDao.getProgressForBook('book-1'),
      isNull,
    );
  });

  test(
    'enforces collection membership uniqueness and cascades it on delete',
    () async {
      await database.booksDao.insertBook(
        book(
          id: 'book-1',
          filePath: '/books/one.epub',
          dateAdded: DateTime(2026),
        ),
      );
      await database.collectionsDao.insertCollection(
        CollectionsCompanion.insert(
          id: 'collection-1',
          name: 'Unread',
          normalizedName: 'unread',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
      final membership = BookCollectionEntriesCompanion.insert(
        bookId: 'book-1',
        collectionId: 'collection-1',
        addedAt: DateTime(2026),
      );
      await database.collectionsDao.addMembership(membership);
      await database.collectionsDao.addMembership(membership);
      expect(
        await database.collectionsDao.containsMembership(
          'collection-1',
          'book-1',
        ),
        isTrue,
      );

      await database.collectionsDao.deleteCollection('collection-1');
      expect(
        await database.collectionsDao.containsMembership(
          'collection-1',
          'book-1',
        ),
        isFalse,
      );
      expect(await database.booksDao.getBookById('book-1'), isNotNull);
    },
  );
}

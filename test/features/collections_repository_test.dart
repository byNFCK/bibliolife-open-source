import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/collections/data/repositories/drift_collection_repository.dart';
import 'package:bibliolife/features/collections/domain/repositories/collection_repository.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftCollectionRepository repository;
  var nextId = 0;
  final clock = DateTime(2026, 7, 22, 10);
  var now = DateTime(2026, 7, 22, 10);

  setUp(() async {
    now = clock;
    database = AppDatabase(NativeDatabase.memory());
    await database.customStatement('PRAGMA foreign_keys = ON');
    repository = DriftCollectionRepository(
      database.collectionsDao,
      idGenerator: () => 'collection-${++nextId}',
      clock: () => now,
    );
    await database.booksDao.insertBook(
      BooksCompanion.insert(
        id: 'book-1',
        title: 'A book',
        filePath: '/books/a.epub',
        fileName: 'a.epub',
        fileExtension: 'epub',
        fileSizeBytes: 1,
        dateAdded: clock,
      ),
    );
  });

  tearDown(() => database.close());

  test(
    'creates normalized collections and rejects blank or duplicate names',
    () async {
      final collection = await repository.create('  Українська   література ');

      expect(collection.id, 'collection-1');
      expect(collection.name, 'Українська література');
      expect(collection.normalizedName, 'українська література');
      expect(collection.createdAt, clock);
      expect(repository.create('   '), throwsA(isA<InvalidCollectionName>()));
      expect(
        repository.create('УКРАЇНСЬКА ЛІТЕРАТУРА'),
        throwsA(isA<DuplicateCollectionName>()),
      );
    },
  );

  test(
    'renames, accepts equivalent own names, and reports missing collections',
    () async {
      final collection = await repository.create(' AI ');
      final renamed = await repository.rename(
        collection.id,
        '  Artificial   Intelligence ',
      );

      expect(renamed.name, 'Artificial Intelligence');
      expect(
        (await repository.rename(
          collection.id,
          'ARTIFICIAL intelligence',
        )).name,
        'ARTIFICIAL intelligence',
      );
      expect(
        repository.rename('missing', 'Anything'),
        throwsA(isA<CollectionNotFound>()),
      );
      await repository.create('Other');
      expect(
        repository.rename(collection.id, ' OTHER '),
        throwsA(isA<DuplicateCollectionName>()),
      );
    },
  );

  test('membership is idempotent and streams books and collections', () async {
    final collection = await repository.create('Unread');
    await repository.addBook(collection.id, 'book-1');
    await repository.addBook(collection.id, 'book-1');

    expect(await repository.containsBook(collection.id, 'book-1'), isTrue);
    expect(
      (await repository.watchForBook('book-1').first).single.id,
      collection.id,
    );
    expect(
      (await repository.watchBooks(collection.id).first).single.id,
      'book-1',
    );

    await repository.removeBook(collection.id, 'book-1');
    await repository.removeBook(collection.id, 'book-1');
    expect(await repository.containsBook(collection.id, 'book-1'), isFalse);
  });

  test(
    'editor save persists metadata and diffs memberships without resetting addedAt',
    () async {
      for (final id in ['book-2', 'book-3']) {
        await database.booksDao.insertBook(
          BooksCompanion.insert(
            id: id,
            title: id,
            filePath: '/books/$id.epub',
            fileName: '$id.epub',
            fileExtension: 'epub',
            fileSizeBytes: 1,
            dateAdded: clock,
          ),
        );
      }
      final collection = await repository.saveEditor(
        name: '  Reading  ',
        description: 'First line\nSecond line',
        customCoverPath: '/collections/covers/cover.png',
        selectedBookIds: {'book-1', 'book-2'},
      );
      final originalBookTwoAddedAt = (await (database.select(
        database.bookCollectionEntries,
      )..where((row) => row.bookId.equals('book-2'))).getSingle()).addedAt;
      now = clock.add(const Duration(hours: 1));

      final updated = await repository.saveEditor(
        collectionId: collection.id,
        name: 'Reading updated',
        description: 'Updated',
        customCoverPath: null,
        selectedBookIds: {'book-2', 'book-3'},
      );

      expect(updated.name, 'Reading updated');
      expect(updated.description, 'Updated');
      expect(updated.customCoverPath, isNull);
      expect(await repository.containsBook(collection.id, 'book-1'), isFalse);
      expect(await repository.containsBook(collection.id, 'book-2'), isTrue);
      expect(await repository.containsBook(collection.id, 'book-3'), isTrue);
      final bookTwoMembership = await (database.select(
        database.bookCollectionEntries,
      )..where((row) => row.bookId.equals('book-2'))).getSingle();
      final bookThreeMembership = await (database.select(
        database.bookCollectionEntries,
      )..where((row) => row.bookId.equals('book-3'))).getSingle();
      expect(bookTwoMembership.addedAt, originalBookTwoAddedAt);
      expect(bookThreeMembership.addedAt, now);
    },
  );

  test('rejects missing collection and book when adding membership', () async {
    final collection = await repository.create('Unread');
    expect(
      repository.addBook('missing', 'book-1'),
      throwsA(isA<CollectionNotFound>()),
    );
    expect(
      repository.addBook(collection.id, 'missing'),
      throwsA(isA<CollectionBookNotFound>()),
    );
  });

  test(
    'collection and book deletion cascade memberships without deleting the other record',
    () async {
      final collection = await repository.create('Unread');
      await repository.addBook(collection.id, 'book-1');
      await repository.delete(collection.id);
      expect(await repository.containsBook(collection.id, 'book-1'), isFalse);
      expect(await database.booksDao.getBookById('book-1'), isNotNull);

      final second = await repository.create('Second');
      await repository.addBook(second.id, 'book-1');
      await database.booksDao.deleteBookById('book-1');
      expect(await repository.containsBook(second.id, 'book-1'), isFalse);
    },
  );

  test('orders collections by sort order, then normalized name', () async {
    await database.collectionsDao.insertCollection(
      CollectionsCompanion.insert(
        id: 'c-null',
        name: 'Zulu',
        normalizedName: 'zulu',
        createdAt: clock,
        updatedAt: clock,
      ),
    );
    await database.collectionsDao.insertCollection(
      CollectionsCompanion.insert(
        id: 'c-two',
        name: 'Beta',
        normalizedName: 'beta',
        createdAt: clock,
        updatedAt: clock,
        sortOrder: const Value(2),
      ),
    );
    await database.collectionsDao.insertCollection(
      CollectionsCompanion.insert(
        id: 'c-one',
        name: 'Alpha',
        normalizedName: 'alpha',
        createdAt: clock,
        updatedAt: clock,
        sortOrder: const Value(1),
      ),
    );

    expect((await repository.watchAll().first).map((item) => item.id), [
      'system-finished',
      'system-reading',
      'system-to-read',
      'c-one',
      'c-two',
      'c-null',
    ]);
  });

  test(
    'summaries use membership recency and limit cover previews to three',
    () async {
      final empty = await repository.create('Empty');
      final collection = await repository.create('Recent');
      for (var index = 2; index <= 5; index++) {
        await database.booksDao.insertBook(
          BooksCompanion.insert(
            id: 'book-$index',
            title: 'Book $index',
            filePath: '/books/$index.epub',
            fileName: '$index.epub',
            fileExtension: 'epub',
            fileSizeBytes: index,
            dateAdded: clock.add(Duration(minutes: index)),
            coverPath: Value(index == 5 ? null : '/covers/$index.jpg'),
          ),
        );
        await database.collectionsDao.addMembership(
          BookCollectionEntriesCompanion.insert(
            collectionId: collection.id,
            bookId: 'book-$index',
            addedAt: clock.add(Duration(minutes: index)),
          ),
        );
      }

      final summaries = await repository.watchSummaries().first;
      final emptySummary = summaries.singleWhere(
        (item) => item.collection.id == empty.id,
      );
      final recent = summaries.singleWhere(
        (item) => item.collection.id == collection.id,
      );

      expect(emptySummary.bookCount, 0);
      expect(emptySummary.recentBooks, isEmpty);
      expect(recent.bookCount, 4);
      expect(recent.recentBooks.map((book) => book.id), [
        'book-5',
        'book-4',
        'book-3',
      ]);
      expect(recent.recentBooks.first.coverPath, equals(null));
    },
  );
}

import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/bookmarks/data/repositories/drift_bookmark_repository.dart';
import 'package:bibliolife/features/bookmarks/domain/models/bookmark_metadata_update.dart';
import 'package:bibliolife/features/bookmarks/domain/models/bookmark_location_key.dart';
import 'package:bibliolife/features/bookmarks/domain/repositories/bookmark_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftBookmarkRepository repository;
  var nextId = 0;
  var tick = 0;
  final start = DateTime(2026, 7, 22, 10);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.customStatement('PRAGMA foreign_keys = ON');
    await database.booksDao.insertBook(
      BooksCompanion.insert(
        id: 'book',
        title: 'Book',
        filePath: '/book.epub',
        fileName: 'book.epub',
        fileExtension: 'epub',
        fileSizeBytes: 1,
        dateAdded: start,
      ),
    );
    repository = DriftBookmarkRepository(
      database.bookmarksDao,
      idGenerator: () => 'bookmark-${++nextId}',
      clock: () => start.add(Duration(seconds: tick++)),
    );
  });
  tearDown(() => database.close());

  test('validates locator and progression', () async {
    expect(
      repository.createBookmark(bookId: 'book', locatorJson: ' '),
      throwsA(isA<InvalidBookmarkLocator>()),
    );
    expect(
      repository.createBookmark(bookId: 'book', locatorJson: '[]'),
      throwsA(isA<InvalidBookmarkLocator>()),
    );
    expect(
      repository.createBookmark(
        bookId: 'book',
        locatorJson: '{"href":"one"}',
        progression: double.nan,
      ),
      throwsA(isA<InvalidBookmarkProgression>()),
    );
    expect(
      repository.createBookmark(
        bookId: 'book',
        locatorJson: '{"href":"two"}',
        progression: 1.1,
      ),
      throwsA(isA<InvalidBookmarkProgression>()),
    );
  });

  test(
    'creates normalizes and updates metadata without changing location',
    () async {
      final bookmark = await repository.createBookmark(
        bookId: ' book ',
        locatorJson: ' {"href":"x"} ',
        href: ' ',
        chapterTitle: ' ',
        title: ' title ',
        note: ' first\n note ',
      );
      expect(bookmark.locatorJson, '{"href":"x"}');
      expect(bookmark.href, isNull);
      expect(bookmark.title, 'title');
      expect(bookmark.createdAt, bookmark.updatedAt);
      final updated = await repository.updateBookmarkMetadata(
        bookmarkId: bookmark.id,
        update: const BookmarkMetadataUpdate(
          title: Changed(null),
          note: Changed(' next '),
        ),
      );
      expect(updated.title, isNull);
      expect(updated.note, 'next');
      expect(updated.locatorJson, bookmark.locatorJson);
      expect(updated.createdAt, bookmark.createdAt);
      expect(updated.updatedAt, isNot(bookmark.updatedAt));
    },
  );

  test(
    'orders non-null progression first and cascades with book deletion',
    () async {
      await repository.createBookmark(
        bookId: 'book',
        locatorJson: '{"href":"three"}',
        progression: null,
      );
      await repository.createBookmark(
        bookId: 'book',
        locatorJson: '{}',
        progression: .5,
      );
      await repository.createBookmark(
        bookId: 'book',
        locatorJson: '{}',
        progression: .2,
      );
      expect(
        (await repository.watchBookmarksForBook('book').first).map(
          (b) => b.progression,
        ),
        [.2, .5, null],
      );
      await database.booksDao.deleteBookById('book');
      expect(await repository.countBookmarksForBook('book'), 0);
    },
  );

  test('missing book and idempotent delete follow contract', () async {
    expect(
      repository.createBookmark(bookId: 'missing', locatorJson: '{}'),
      throwsA(isA<MissingBookmarkBook>()),
    );
    await repository.deleteBookmark('missing');
    expect(
      repository.updateBookmarkMetadata(
        bookmarkId: 'missing',
        update: const BookmarkMetadataUpdate(),
      ),
      throwsA(isA<MissingBookmark>()),
    );
  });

  test('deduplicates and removes all legacy matches at a canonical position', () async {
    final first = await repository.createBookmark(bookId: 'book', locatorJson: '{"href":"chapter#a"}', position: 4);
    final repeated = await repository.createBookmark(bookId: 'book', locatorJson: '{ "href": "other" }', position: 4);
    expect(repeated.id, first.id);
    expect(await repository.isBookmarked(BookmarkLocationKey.fromValues(bookId: 'book', locatorJson: '{"href":"anything"}', position: 4)!), isTrue);
    await repository.removeBookmarksAt(BookmarkLocationKey.fromValues(bookId: 'book', locatorJson: '{"href":"anything"}', position: 4)!);
    expect(await repository.countBookmarksForBook('book'), 0);
  });
}

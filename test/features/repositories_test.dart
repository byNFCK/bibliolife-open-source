import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/library/data/repositories/drift_library_repository.dart';
import 'package:bibliolife/features/reader/data/repositories/drift_reading_progress_repository.dart';
import 'package:bibliolife/features/reader/domain/models/reading_progress.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftLibraryRepository libraryRepository;
  late DriftReadingProgressRepository readingProgressRepository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.customStatement('PRAGMA foreign_keys = ON');
    libraryRepository = DriftLibraryRepository(database.booksDao);
    readingProgressRepository = DriftReadingProgressRepository(
      database.readingProgressDao,
    );
  });

  tearDown(() => database.close());

  LibraryBook book({
    String id = 'book-1',
    String title = 'Original title',
    String author = 'Author',
    String description = 'Description',
    String publisher = 'Publisher',
    String filePath = '/books/one.epub',
    DateTime? lastOpenedAt,
  }) {
    return LibraryBook(
      id: id,
      title: title,
      sortTitle: 'Original sort title',
      author: author,
      description: description,
      filePath: filePath,
      fileName: 'one.epub',
      fileExtension: 'epub',
      format: BookFormat.epub,
      mediaType: 'application/epub+zip',
      coverPath: '/covers/one.jpg',
      language: 'en',
      publisher: publisher,
      publishedDate: '2026',
      isbn: '9780000000001',
      pageCount: 100,
      fileSizeBytes: 1024,
      dateAdded: DateTime(2026, 1, 1),
      lastOpenedAt: lastOpenedAt,
      isFavorite: false,
    );
  }

  test('watchAllBooks emits mapped domain books', () async {
    final emittedBooks = libraryRepository.watchAllBooks().firstWhere(
      (books) => books.length == 1,
    );

    await libraryRepository.addBook(book());

    expect((await emittedBooks).single.title, 'Original title');
  });

  test(
    'watchAllBooks includes books regardless of collection membership',
    () async {
      final allBooks = libraryRepository.watchAllBooks().firstWhere(
        (books) => books.length == 3,
      );
      for (final id in ['book-a', 'book-b', 'book-c']) {
        await libraryRepository.addBook(
          book(id: id, filePath: '/books/$id.epub'),
        );
      }
      expect(
        (await allBooks).map((item) => item.id),
        containsAll(['book-a', 'book-b', 'book-c']),
      );

      for (final id in ['collection-a', 'collection-b']) {
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
          collectionId: 'collection-a',
          addedAt: DateTime(2026),
        ),
      );
      for (final collectionId in ['collection-a', 'collection-b']) {
        await database.collectionsDao.addMembership(
          BookCollectionEntriesCompanion.insert(
            bookId: 'book-c',
            collectionId: collectionId,
            addedAt: DateTime(2026),
          ),
        );
      }

      expect(
        (await libraryRepository.getAllBooks()).map((item) => item.id),
        containsAll(['book-a', 'book-b', 'book-c']),
      );

      await database.collectionsDao.removeMembership('collection-a', 'book-c');
      await database.collectionsDao.deleteCollection('collection-b');
      expect(
        (await libraryRepository.getAllBooks()).map((item) => item.id),
        containsAll(['book-a', 'book-b', 'book-c']),
      );

      await libraryRepository.setFavorite('book-a', true);
      expect(
        (await libraryRepository.getAllBooks()).map((item) => item.id),
        containsAll(['book-a', 'book-b', 'book-c']),
      );

      final afterBookDelete = libraryRepository.watchAllBooks().firstWhere(
        (books) => books.length == 2,
      );
      await libraryRepository.deleteBook('book-c');
      expect(
        (await afterBookDelete).map((item) => item.id),
        containsAll(['book-a', 'book-b']),
      );
    },
  );

  test('addBook inserts and getBookById returns a domain model', () async {
    await libraryRepository.addBook(book());

    final savedBook = await libraryRepository.getBookById('book-1');

    expect(savedBook, isNotNull);
    expect(savedBook!.format, BookFormat.epub);
  });

  test(
    'Drift preserves Unicode metadata without a charset conversion',
    () async {
      const title = '\u041a\u043d\u0438\u0433\u0430 \uD83D\uDE80';
      const author =
          '\u0410\u0432\u0442\u043e\u0440 \u0645\u0631\u062d\u0628\u0627';
      const description =
          '\u4f60\u597d \u2014 \u0457\u0436\u0430\u043a \uD83E\uDDEA';
      const publisher = '\u00c9ditions \u0490\u0440\u0443\u043d\u0442';
      await libraryRepository.addBook(
        book(
          title: title,
          author: author,
          description: description,
          publisher: publisher,
        ),
      );

      final saved = await libraryRepository.getBookById('book-1');

      expect(saved?.title, title);
      expect(saved?.author, author);
      expect(saved?.description, description);
      expect(saved?.publisher, publisher);
    },
  );

  test('updateBook preserves all persisted metadata', () async {
    await libraryRepository.addBook(book());
    await libraryRepository.updateBook(book(title: 'Updated title'));

    final updatedBook = await libraryRepository.getBookById('book-1');

    expect(updatedBook!.title, 'Updated title');
    expect(updatedBook.description, 'Description');
    expect(updatedBook.publisher, 'Publisher');
    expect(updatedBook.isbn, '9780000000001');
  });

  test('setFavorite and markBookOpened update persisted values', () async {
    final openedAt = DateTime(2026, 1, 2);
    await libraryRepository.addBook(book());

    await libraryRepository.setFavorite('book-1', true);
    await libraryRepository.markBookOpened('book-1', openedAt);

    final updatedBook = await libraryRepository.getBookById('book-1');
    expect(updatedBook!.isFavorite, isTrue);
    expect(updatedBook.lastOpenedAt, openedAt);
  });

  test(
    'watchFavoriteBooks uses the persisted favorite query and ordering',
    () async {
      await libraryRepository.addBook(
        book(id: 'older', filePath: '/books/older.epub'),
      );
      await libraryRepository.addBook(
        book(id: 'newer', filePath: '/books/newer.epub'),
      );
      await libraryRepository.setFavorite('older', true);
      await libraryRepository.setFavorite('newer', true);
      await libraryRepository.markBookOpened('older', DateTime(2026, 1, 2));
      await libraryRepository.markBookOpened('newer', DateTime(2026, 1, 3));

      final favorites = await libraryRepository.watchFavoriteBooks().firstWhere(
        (books) => books.length == 2,
      );

      expect(favorites.map((item) => item.id), ['newer', 'older']);
    },
  );

  test('watchUnsortedBooks reacts to zero and multiple memberships', () async {
    await libraryRepository.addBook(
      book(id: 'book-1', filePath: '/books/book-1.epub'),
    );
    await libraryRepository.addBook(
      book(id: 'book-2', filePath: '/books/book-2.epub'),
    );
    await database.collectionsDao.insertCollection(
      CollectionsCompanion.insert(
        id: 'collection-a',
        name: 'A',
        normalizedName: 'a',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    await database.collectionsDao.insertCollection(
      CollectionsCompanion.insert(
        id: 'collection-b',
        name: 'B',
        normalizedName: 'b',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );

    expect(
      (await libraryRepository.watchUnsortedBooks().firstWhere(
        (books) => books.length == 2,
      )).map((item) => item.id),
      containsAll(['book-1', 'book-2']),
    );

    final afterFirstMembership = libraryRepository
        .watchUnsortedBooks()
        .firstWhere((books) => books.length == 1);
    await database.collectionsDao.addMembership(
      BookCollectionEntriesCompanion.insert(
        collectionId: 'collection-a',
        bookId: 'book-1',
        addedAt: DateTime(2026),
      ),
    );
    expect((await afterFirstMembership).single.id, 'book-2');

    final afterSecondMembership = libraryRepository
        .watchUnsortedBooks()
        .firstWhere((books) => books.length == 1);
    await database.collectionsDao.addMembership(
      BookCollectionEntriesCompanion.insert(
        collectionId: 'collection-b',
        bookId: 'book-1',
        addedAt: DateTime(2026),
      ),
    );
    expect((await afterSecondMembership).single.id, 'book-2');

    final afterRemovingOne = libraryRepository.watchUnsortedBooks().firstWhere(
      (books) => books.length == 1,
    );
    await database.collectionsDao.removeMembership('collection-a', 'book-1');
    expect((await afterRemovingOne).single.id, 'book-2');

    final afterRemovingFinal = libraryRepository
        .watchUnsortedBooks()
        .firstWhere((books) => books.length == 2);
    await database.collectionsDao.removeMembership('collection-b', 'book-1');
    expect(
      (await afterRemovingFinal).map((item) => item.id),
      containsAll(['book-1', 'book-2']),
    );
  });

  test('deleteBook cascades reading progress', () async {
    await libraryRepository.addBook(book());
    await readingProgressRepository.save(
      ReadingProgress(
        bookId: 'book-1',
        locatorJson: '{"chapter": 1}',
        progression: 0.5,
        currentChapterTitle: 'Chapter 1',
        currentPage: 5,
        totalPages: 10,
        updatedAt: DateTime(2026, 1, 1),
      ),
    );

    await libraryRepository.deleteBook('book-1');

    expect(await readingProgressRepository.getForBook('book-1'), isNull);
  });

  test('reading progress save, get, and watch work', () async {
    await libraryRepository.addBook(book());
    final watchedProgress = readingProgressRepository
        .watchForBook('book-1')
        .firstWhere((progress) => progress != null);
    final progress = ReadingProgress(
      bookId: 'book-1',
      locatorJson: '{"chapter": 2}',
      progression: 0.75,
      currentChapterTitle: 'Chapter 2',
      currentPage: 15,
      totalPages: 20,
      updatedAt: DateTime(2026, 1, 2),
    );

    await readingProgressRepository.save(progress);

    expect((await watchedProgress)!.progression, 0.75);
    expect(
      (await readingProgressRepository.getForBook('book-1'))!.locatorJson,
      '{"chapter": 2}',
    );
  });
}

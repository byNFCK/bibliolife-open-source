import 'package:bibliolife/features/library/application/providers/library_providers.dart';
import 'package:bibliolife/features/library/application/providers/library_repository_provider.dart';
import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_providers.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_repository_provider.dart';
import 'package:bibliolife/features/reader/domain/models/reading_progress.dart';
import 'package:bibliolife/features/reader/domain/repositories/reading_progress_repository.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final books = [
    _book(id: 'favorite', isFavorite: true, lastOpenedAt: DateTime(2026, 1, 2)),
    _book(id: 'unopened', isFavorite: false),
  ];
  final progress = ReadingProgress(
    bookId: 'favorite',
    locatorJson: null,
    progression: 0.5,
    currentChapterTitle: null,
    currentPage: null,
    totalPages: null,
    updatedAt: DateTime(2026, 1, 2),
  );

  ProviderContainer containerWithFakes() {
    return ProviderContainer(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(
          _FakeLibraryRepository(books),
        ),
        readingProgressRepositoryProvider.overrideWithValue(
          _FakeReadingProgressRepository(progress),
        ),
      ],
    );
  }

  test('allBooksProvider emits repository values', () async {
    final container = containerWithFakes();
    addTearDown(container.dispose);

    await _watchAllBooks(container);

    expect(container.read(allBooksProvider).value, books);
  });

  test('favorite provider exposes the repository favorite stream', () async {
      final container = containerWithFakes();
      addTearDown(container.dispose);
      await _watchAllBooks(container);
      await _watchFavoriteBooks(container);

    expect(container.read(favoriteBooksProvider).value!.single.id, 'favorite');
    expect(
      container.read(recentlyOpenedBooksProvider).value!.single.id,
      'favorite',
    );
  });

  test('bookByIdProvider returns the requested book', () async {
    final container = containerWithFakes();
    addTearDown(container.dispose);

    final provider = bookByIdProvider('unopened');
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    final book = await container.read(provider.future);
    subscription.close();
    expect(book!.id, 'unopened');
  });

  test('readingProgressProvider emits progress', () async {
    final container = containerWithFakes();
    addTearDown(container.dispose);

    await _watchReadingProgress(container, 'favorite');

    expect(
      container.read(readingProgressProvider('favorite')).value!.progression,
      0.5,
    );
  });
}

Future<void> _watchAllBooks(ProviderContainer container) async {
  final subscription = container.listen(
    allBooksProvider,
    (_, _) {},
    fireImmediately: true,
  );
  await container.read(allBooksProvider.future);
  subscription.close();
}

Future<void> _watchReadingProgress(
  ProviderContainer container,
  String bookId,
) async {
  final provider = readingProgressProvider(bookId);
  final subscription = container.listen(
    provider,
    (_, _) {},
    fireImmediately: true,
  );
  await container.read(provider.future);
  subscription.close();
}

Future<void> _watchFavoriteBooks(ProviderContainer container) async {
  final subscription = container.listen(
    favoriteBooksProvider,
    (_, _) {},
    fireImmediately: true,
  );
  await container.read(favoriteBooksProvider.future);
  subscription.close();
}

LibraryBook _book({
  required String id,
  required bool isFavorite,
  DateTime? lastOpenedAt,
}) {
  return LibraryBook(
    id: id,
    title: id,
    sortTitle: null,
    author: null,
    description: null,
    filePath: '/books/$id.epub',
    fileName: '$id.epub',
    fileExtension: 'epub',
    format: BookFormat.epub,
    mediaType: null,
    coverPath: null,
    language: null,
    publisher: null,
    publishedDate: null,
    isbn: null,
    pageCount: null,
    fileSizeBytes: 1,
    dateAdded: DateTime(2026, 1, 1),
    lastOpenedAt: lastOpenedAt,
    isFavorite: isFavorite,
  );
}

class _FakeLibraryRepository implements LibraryRepository {
  const _FakeLibraryRepository(this._books);

  final List<LibraryBook> _books;

  @override
  Stream<List<LibraryBook>> watchAllBooks() => Stream.value(_books);

  @override
  Stream<List<LibraryBook>> watchFavoriteBooks() => Stream.value(
    _books.where((book) => book.isFavorite).toList(growable: false),
  );

  @override
  Stream<List<LibraryBook>> watchUnsortedBooks() => watchAllBooks();

  @override
  Future<List<LibraryBook>> getAllBooks() async => _books;

  @override
  Future<LibraryBook?> getBookById(String id) async {
    for (final book in _books) {
      if (book.id == id) return book;
    }
    return null;
  }

  @override
  Future<LibraryBook?> findBookByFilePath(String filePath) async => null;

  @override
  Future<LibraryBook?> findBookByOriginalFilePath(
    String originalFilePath,
  ) async => null;

  @override
  Future<void> addBook(LibraryBook book) async {}

  @override
  Future<void> updateBook(LibraryBook book) async {}

  @override
  Future<void> deleteBook(String id) async {}

  @override
  Future<void> setFavorite(String id, bool isFavorite) async {}

  @override
  Future<void> markBookOpened(String id, DateTime openedAt) async {}
}

class _FakeReadingProgressRepository implements ReadingProgressRepository {
  @override
  Stream<List<ReadingProgress>> watchAll() => Stream.value(const []);

  const _FakeReadingProgressRepository(this._progress);

  final ReadingProgress _progress;

  @override
  Stream<ReadingProgress?> watchForBook(String bookId) =>
      Stream.value(_progress);

  @override
  Future<ReadingProgress?> getForBook(String bookId) async => _progress;

  @override
  Future<void> save(ReadingProgress progress) async {}

  @override
  Future<void> deleteForBook(String bookId) async {}
}

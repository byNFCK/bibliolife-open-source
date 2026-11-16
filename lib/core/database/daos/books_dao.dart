part of '../app_database.dart';

@DriftAccessor(tables: [Books, BookCollectionEntries])
class BooksDao extends DatabaseAccessor<AppDatabase> with _$BooksDaoMixin {
  BooksDao(super.db);

  Stream<List<Book>> watchAllBooks() => _orderedBooks().watch();

  Stream<List<Book>> watchFavoriteBooks() => (_favoriteBooks()).watch();

  Stream<List<Book>> watchUnsortedBooks() {
    final query =
        select(books).join([
            leftOuterJoin(
              bookCollectionEntries,
              bookCollectionEntries.bookId.equalsExp(books.id),
            ),
          ])
          ..where(bookCollectionEntries.bookId.isNull())
          ..orderBy([
            OrderingTerm(
              expression: books.lastOpenedAt,
              mode: OrderingMode.desc,
            ),
            OrderingTerm(expression: books.dateAdded, mode: OrderingMode.desc),
          ]);
    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(books)).toList(),
    );
  }

  Future<List<Book>> getAllBooks() => _orderedBooks().get();

  Future<Book?> getBookById(String id) {
    return (select(
      books,
    )..where((book) => book.id.equals(id))).getSingleOrNull();
  }

  Future<Book?> findBookByFilePath(String filePath) {
    return (select(
      books,
    )..where((book) => book.filePath.equals(filePath))).getSingleOrNull();
  }

  Future<Book?> findBookByOriginalFilePath(String originalFilePath) {
    return (select(books)
          ..where((book) => book.originalFilePath.equals(originalFilePath)))
        .getSingleOrNull();
  }

  Future<bool> isCoverPathReferenced(String coverPath) async =>
      (await (select(books)..where((book) => book.coverPath.equals(coverPath)))
          .getSingleOrNull()) !=
      null;

  Future<int> insertBook(BooksCompanion book) => into(books).insert(book);

  Future<bool> updateBook(Book book) => update(books).replace(book);

  Future<BookDetailsFieldsUpdateResult?> updateBookDetailsFields({
    required String id,
    required String title,
    required String? author,
    required String? authorsJson,
    bool updateTitle = true,
    bool updateAuthor = true,
    String? replacementCoverPath,
    BookCoverProvenance? replacementCoverProvenance,
    bool replaceCover = false,
    bool removeManualCover = false,
    bool clearCover = false,
  }) => transaction(() async {
    final current = await getBookById(id);
    if (current == null) return null;
    if (replaceCover && clearCover) {
      throw ArgumentError('A cover cannot be replaced and cleared together.');
    }
    final removeCover =
        removeManualCover && current.coverProvenance == 'manual';
    final updateCover = replaceCover || clearCover || removeCover;
    if (!updateTitle && !updateAuthor && !updateCover) {
      return BookDetailsFieldsUpdateResult(previous: current, current: current);
    }
    await (update(books)..where((book) => book.id.equals(id))).write(
      BooksCompanion(
        title: updateTitle ? Value(title) : const Value.absent(),
        sortTitle: updateTitle ? Value(title) : const Value.absent(),
        author: updateAuthor ? Value(author) : const Value.absent(),
        authorsJson: updateAuthor ? Value(authorsJson) : const Value.absent(),
        coverPath: updateCover
            ? Value(replacementCoverPath)
            : const Value.absent(),
        coverProvenance: replaceCover
            ? Value(
                (replacementCoverProvenance ?? BookCoverProvenance.manual).name,
              )
            : clearCover || removeCover
            ? const Value('none')
            : const Value.absent(),
      ),
    );
    final updated = await getBookById(id);
    if (updated == null) return null;
    return BookDetailsFieldsUpdateResult(previous: current, current: updated);
  });

  Future<int> deleteBookById(String id) {
    return (delete(books)..where((book) => book.id.equals(id))).go();
  }

  Future<int> setFavorite(String id, bool isFavorite) {
    return (update(books)..where((book) => book.id.equals(id))).write(
      BooksCompanion(isFavorite: Value(isFavorite)),
    );
  }

  Future<int> updateLastOpenedAt(String id, DateTime value) {
    return (update(books)..where((book) => book.id.equals(id))).write(
      BooksCompanion(lastOpenedAt: Value(value)),
    );
  }

  SimpleSelectStatement<Books, Book> _orderedBooks() {
    return select(books)..orderBy([
      (book) =>
          OrderingTerm(expression: book.lastOpenedAt, mode: OrderingMode.desc),
      (book) =>
          OrderingTerm(expression: book.dateAdded, mode: OrderingMode.desc),
    ]);
  }

  SimpleSelectStatement<Books, Book> _favoriteBooks() {
    return (select(books)
      ..where((book) => book.isFavorite.equals(true))
      ..orderBy([
        (book) => OrderingTerm(
          expression: book.lastOpenedAt,
          mode: OrderingMode.desc,
        ),
        (book) =>
            OrderingTerm(expression: book.dateAdded, mode: OrderingMode.desc),
      ]));
  }
}

class BookDetailsFieldsUpdateResult {
  const BookDetailsFieldsUpdateResult({
    required this.previous,
    required this.current,
  });

  final Book previous;
  final Book current;
}

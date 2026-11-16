part of '../app_database.dart';

@DriftAccessor(tables: [Collections, BookCollectionEntries, Books])
class CollectionsDao extends DatabaseAccessor<AppDatabase>
    with _$CollectionsDaoMixin {
  CollectionsDao(super.db);

  Stream<List<Collection>> watchAllCollections() =>
      _orderedCollections().watch();

  /// Watches each collection with its membership count and at most its three
  /// newest membership entries. This avoids a query per visible card.
  Stream<List<CollectionSummaryData>> watchCollectionSummaries() {
    return customSelect(
      '''
WITH ranked_memberships AS (
  SELECT collection_id, book_id,
         COUNT(*) OVER (PARTITION BY collection_id) AS book_count,
         ROW_NUMBER() OVER (
           PARTITION BY collection_id
           ORDER BY added_at DESC, book_id DESC
         ) AS position
  FROM book_collection_entries
)
SELECT c.id AS collection_id, c.name AS collection_name,
       c.normalized_name AS collection_normalized_name,
       c.description AS collection_description,
       c.custom_cover_path AS collection_custom_cover_path,
       c.created_at AS collection_created_at,
       c.updated_at AS collection_updated_at,
       c.sort_order AS collection_sort_order,
       COALESCE(r.book_count, 0) AS book_count,
       b.id AS preview_book_id, b.title AS preview_book_title,
       b.cover_path AS preview_book_cover_path
FROM collections c
LEFT JOIN ranked_memberships r
  ON r.collection_id = c.id AND r.position <= 3
LEFT JOIN books b ON b.id = r.book_id
ORDER BY CASE c.id WHEN 'system-finished' THEN 0 WHEN 'system-reading' THEN 1 WHEN 'system-to-read' THEN 2 ELSE 3 END,
         c.sort_order IS NULL ASC, c.sort_order ASC,
         c.normalized_name ASC, c.id ASC, r.position ASC
''',
      readsFrom: {collections, bookCollectionEntries, books},
    ).watch().map((rows) {
      final summaries = <String, _CollectionSummaryAccumulator>{};
      for (final row in rows) {
        final collection = Collection(
          id: row.read<String>('collection_id'),
          name: row.read<String>('collection_name'),
          normalizedName: row.read<String>('collection_normalized_name'),
          description: row.read<String?>('collection_description'),
          customCoverPath: row.read<String?>('collection_custom_cover_path'),
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('collection_created_at'),
          ),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('collection_updated_at'),
          ),
          sortOrder: row.read<int?>('collection_sort_order'),
        );
        final accumulator = summaries.putIfAbsent(
          collection.id,
          () => _CollectionSummaryAccumulator(collection),
        );
        final membershipBookId = row.read<String?>('preview_book_id');
        if (membershipBookId == null) continue;
        accumulator.bookCount = row.read<int>('book_count');
        if (accumulator.recentBooks.length < 3) {
          accumulator.recentBooks.add(
            CollectionPreviewBookData(
              id: membershipBookId,
              title: row.read<String>('preview_book_title'),
              coverPath: row.read<String?>('preview_book_cover_path'),
            ),
          );
        }
      }
      return summaries.values
          .map(
            (item) => CollectionSummaryData(
              collection: item.collection,
              bookCount: item.bookCount,
              recentBooks: List.unmodifiable(item.recentBooks),
            ),
          )
          .toList(growable: false);
    });
  }

  Future<Collection?> getCollectionById(String id) => (select(
    collections,
  )..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<int> insertCollection(CollectionsCompanion collection) =>
      into(collections).insert(collection);

  Future<int> updateCollection({
    required String id,
    required String name,
    required String normalizedName,
    required DateTime updatedAt,
    Value<String?> description = const Value.absent(),
    Value<String?> customCoverPath = const Value.absent(),
  }) => (update(collections)..where((row) => row.id.equals(id))).write(
    CollectionsCompanion(
      name: Value(name),
      normalizedName: Value(normalizedName),
      description: description,
      customCoverPath: customCoverPath,
      updatedAt: Value(updatedAt),
    ),
  );

  Future<int> deleteCollection(String id) =>
      (delete(collections)..where((row) => row.id.equals(id))).go();

  Future<bool> normalizedNameExists(
    String normalizedName, {
    String? exceptId,
  }) async {
    final query = select(collections)
      ..where((row) => row.normalizedName.equals(normalizedName));
    if (exceptId != null) query.where((row) => row.id.equals(exceptId).not());
    return await query.getSingleOrNull() != null;
  }

  Stream<List<Collection>> watchCollectionsForBook(String bookId) {
    final query =
        select(collections).join([
            innerJoin(
              bookCollectionEntries,
              bookCollectionEntries.collectionId.equalsExp(collections.id),
            ),
          ])
          ..where(bookCollectionEntries.bookId.equals(bookId))
          ..orderBy(_joinedCollectionOrdering());
    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(collections)).toList(),
    );
  }

  Stream<List<Book>> watchBooksInCollection(String collectionId) {
    final query =
        select(books).join([
            innerJoin(
              bookCollectionEntries,
              bookCollectionEntries.bookId.equalsExp(books.id),
            ),
          ])
          ..where(bookCollectionEntries.collectionId.equals(collectionId))
          ..orderBy([
            OrderingTerm(expression: books.sortTitle, mode: OrderingMode.asc),
            OrderingTerm(expression: books.title, mode: OrderingMode.asc),
            OrderingTerm(expression: books.id, mode: OrderingMode.asc),
          ]);
    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(books)).toList(),
    );
  }

  Future<int> addMembership(BookCollectionEntriesCompanion membership) => into(
    bookCollectionEntries,
  ).insert(membership, mode: InsertMode.insertOrIgnore);

  Future<int> removeMembership(String collectionId, String bookId) =>
      (delete(bookCollectionEntries)..where(
            (row) =>
                row.collectionId.equals(collectionId) &
                row.bookId.equals(bookId),
          ))
          .go();

  Future<bool> containsMembership(String collectionId, String bookId) async =>
      await (select(bookCollectionEntries)..where(
            (row) =>
                row.collectionId.equals(collectionId) &
                row.bookId.equals(bookId),
          ))
          .getSingleOrNull() !=
      null;

  Future<Set<String>> membershipBookIds(String collectionId) async {
    final rows = await (select(
      bookCollectionEntries,
    )..where((row) => row.collectionId.equals(collectionId))).get();
    return rows.map((row) => row.bookId).toSet();
  }

  Future<bool> bookExists(String bookId) async =>
      await (select(
        books,
      )..where((book) => book.id.equals(bookId))).getSingleOrNull() !=
      null;

  SimpleSelectStatement<Collections, Collection> _orderedCollections() =>
      select(collections)..orderBy([
        (row) => OrderingTerm(expression: _systemOrder(row.id)),
        (row) => OrderingTerm(
          expression: row.sortOrder.isNull(),
          mode: OrderingMode.asc,
        ),
        (row) =>
            OrderingTerm(expression: row.sortOrder, mode: OrderingMode.asc),
        (row) => OrderingTerm(
          expression: row.normalizedName,
          mode: OrderingMode.asc,
        ),
        (row) => OrderingTerm(expression: row.id, mode: OrderingMode.asc),
      ]);

  Expression<int> _systemOrder(Expression<String> id) =>
      CaseWhenExpression<int>(
        cases: [
          CaseWhen(id.equals(systemFinishedId), then: const Constant(0)),
          CaseWhen(id.equals(systemReadingId), then: const Constant(1)),
          CaseWhen(id.equals(systemToReadId), then: const Constant(2)),
        ],
        orElse: const Constant(3),
      );

  List<OrderingTerm> _joinedCollectionOrdering() => [
    OrderingTerm(expression: _systemOrder(collections.id)),
    OrderingTerm(
      expression: collections.sortOrder.isNull(),
      mode: OrderingMode.asc,
    ),
    OrderingTerm(expression: collections.sortOrder, mode: OrderingMode.asc),
    OrderingTerm(
      expression: collections.normalizedName,
      mode: OrderingMode.asc,
    ),
    OrderingTerm(expression: collections.id, mode: OrderingMode.asc),
  ];
}

class CollectionSummaryData {
  const CollectionSummaryData({
    required this.collection,
    required this.bookCount,
    required this.recentBooks,
  });

  final Collection collection;
  final int bookCount;
  final List<CollectionPreviewBookData> recentBooks;
}

class CollectionPreviewBookData {
  const CollectionPreviewBookData({
    required this.id,
    required this.title,
    required this.coverPath,
  });

  final String id;
  final String title;
  final String? coverPath;
}

class _CollectionSummaryAccumulator {
  _CollectionSummaryAccumulator(this.collection);

  final Collection collection;
  final List<CollectionPreviewBookData> recentBooks = [];
  var bookCount = 0;
}

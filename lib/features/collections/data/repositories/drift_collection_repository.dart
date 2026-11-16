import 'package:bibliolife/features/collections/domain/models/system_collection.dart';
import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/core/database/mappers/book_mapper.dart';
import 'package:bibliolife/core/database/mappers/collection_mapper.dart';
import 'package:bibliolife/features/collections/domain/models/library_collection.dart';
import 'package:bibliolife/features/collections/domain/models/collection_summary.dart';
import 'package:bibliolife/features/collections/domain/repositories/collection_repository.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

class DriftCollectionRepository implements CollectionRepository {
  DriftCollectionRepository(
    this._collectionsDao, {
    String Function()? idGenerator,
    DateTime Function()? clock,
  }) : _idGenerator = idGenerator ?? const Uuid().v4,
       _clock = clock ?? DateTime.now;

  final CollectionsDao _collectionsDao;
  final String Function() _idGenerator;
  final DateTime Function() _clock;

  @override
  Stream<List<LibraryCollection>> watchAll() => _collectionsDao
      .watchAllCollections()
      .map((items) => items.map((item) => item.toLibraryCollection()).toList());

  @override
  Stream<List<CollectionSummary>> watchSummaries() =>
      _collectionsDao.watchCollectionSummaries().map(
        (items) => items
            .map(
              (item) => CollectionSummary(
                collection: item.collection.toLibraryCollection(),
                bookCount: item.bookCount,
                recentBooks: item.recentBooks
                    .map(
                      (book) => CollectionPreviewBook(
                        id: book.id,
                        title: book.title,
                        coverPath: book.coverPath,
                      ),
                    )
                    .toList(growable: false),
              ),
            )
            .toList(growable: false),
      );

  @override
  Future<LibraryCollection?> getById(String id) async =>
      (await _collectionsDao.getCollectionById(id))?.toLibraryCollection();

  @override
  Future<LibraryCollection> create(String name) => saveEditor(
    name: name,
    description: null,
    customCoverPath: null,
    selectedBookIds: const {},
  );

  @override
  Future<LibraryCollection> saveEditor({
    String? collectionId,
    required String name,
    required String? description,
    required String? customCoverPath,
    required Set<String> selectedBookIds,
  }) async {
    final normalized = _nameOrThrow(name);
    final normalizedDescription = _descriptionOrNull(description);
    final selected = Set<String>.of(selectedBookIds);

    if (collectionId == null) {
      final now = _clock();
      final collection = LibraryCollection(
        id: _idGenerator(),
        name: normalized.displayName,
        normalizedName: normalized.normalizedName,
        description: normalizedDescription,
        customCoverPath: customCoverPath,
        createdAt: now,
        updatedAt: now,
        sortOrder: null,
      );
      try {
        await _collectionsDao.db.transaction(() async {
          if (await _collectionsDao.normalizedNameExists(
            normalized.normalizedName,
          )) {
            throw const DuplicateCollectionName();
          }
          await _validateBooks(selected);
          await _collectionsDao.insertCollection(
            collection.toCollectionsCompanion(),
          );
          for (final bookId in selected) {
            await _collectionsDao.addMembership(
              BookCollectionEntriesCompanion.insert(
                collectionId: collection.id,
                bookId: bookId,
                addedAt: _clock(),
              ),
            );
          }
        });
        return collection;
      } on CollectionRepositoryFailure {
        rethrow;
      } catch (_) {
        if (await _collectionsDao.normalizedNameExists(
          normalized.normalizedName,
        )) {
          throw const DuplicateCollectionName();
        }
        throw const CollectionStorageFailure();
      }
    }

    final current = await _collectionsDao.getCollectionById(collectionId);
    if (current == null) throw CollectionNotFound(collectionId);
    try {
      return await _collectionsDao.db.transaction(() async {
        final fresh = await _collectionsDao.getCollectionById(collectionId);
        if (fresh == null) throw CollectionNotFound(collectionId);
        final system = isSystemCollection(collectionId);
        if (system && name != fresh.name) throw const InvalidCollectionName();
        final normalizedName = system
            ? fresh.normalizedName
            : normalized.normalizedName;
        if (!system &&
            fresh.normalizedName != normalizedName &&
            await _collectionsDao.normalizedNameExists(
              normalized.normalizedName,
              exceptId: collectionId,
            )) {
          throw const DuplicateCollectionName();
        }

        final initialBookIds = await _collectionsDao.membershipBookIds(
          collectionId,
        );
        final addedBookIds = selected.difference(initialBookIds);
        final removedBookIds = initialBookIds.difference(selected);
        await _validateBooks(addedBookIds);
        final metadataChanged =
            fresh.name != normalized.displayName ||
            fresh.normalizedName != normalizedName ||
            fresh.description != normalizedDescription ||
            fresh.customCoverPath != customCoverPath;
        if (!metadataChanged &&
            addedBookIds.isEmpty &&
            removedBookIds.isEmpty) {
          return fresh.toLibraryCollection();
        }

        final updatedAt = _clock();
        await _collectionsDao.updateCollection(
          id: collectionId,
          name: normalized.displayName,
          normalizedName: normalizedName,
          description: Value(normalizedDescription),
          customCoverPath: Value(customCoverPath),
          updatedAt: updatedAt,
        );
        for (final bookId in addedBookIds) {
          await _collectionsDao.addMembership(
            BookCollectionEntriesCompanion.insert(
              collectionId: collectionId,
              bookId: bookId,
              addedAt: _clock(),
            ),
          );
        }
        for (final bookId in removedBookIds) {
          await _collectionsDao.removeMembership(collectionId, bookId);
        }
        return LibraryCollection(
          id: fresh.id,
          name: normalized.displayName,
          normalizedName: normalizedName,
          description: normalizedDescription,
          customCoverPath: customCoverPath,
          createdAt: fresh.createdAt,
          updatedAt: updatedAt,
          sortOrder: fresh.sortOrder,
        );
      });
    } on CollectionRepositoryFailure {
      rethrow;
    } catch (_) {
      if (!isSystemCollection(collectionId) &&
          await _collectionsDao.normalizedNameExists(
            normalized.normalizedName,
            exceptId: collectionId,
          )) {
        throw const DuplicateCollectionName();
      }
      throw const CollectionStorageFailure();
    }
  }

  @override
  Future<LibraryCollection> rename(String collectionId, String newName) async {
    if (isSystemCollection(collectionId)) {
      throw CollectionNotFound(collectionId);
    }
    final normalized = _nameOrThrow(newName);
    final current = await _collectionsDao.getCollectionById(collectionId);
    if (current == null) throw CollectionNotFound(collectionId);
    if (current.normalizedName != normalized.normalizedName &&
        await _collectionsDao.normalizedNameExists(
          normalized.normalizedName,
          exceptId: collectionId,
        )) {
      throw const DuplicateCollectionName();
    }
    final updatedAt = _clock();
    try {
      final changed = await _collectionsDao.updateCollection(
        id: collectionId,
        name: normalized.displayName,
        normalizedName: normalized.normalizedName,
        updatedAt: updatedAt,
      );
      if (changed == 0) throw CollectionNotFound(collectionId);
      return LibraryCollection(
        id: current.id,
        name: normalized.displayName,
        normalizedName: normalized.normalizedName,
        description: current.description,
        customCoverPath: current.customCoverPath,
        createdAt: current.createdAt,
        updatedAt: updatedAt,
        sortOrder: current.sortOrder,
      );
    } on CollectionRepositoryFailure {
      rethrow;
    } catch (_) {
      if (await _collectionsDao.normalizedNameExists(
        normalized.normalizedName,
        exceptId: collectionId,
      )) {
        throw const DuplicateCollectionName();
      }
      throw const CollectionStorageFailure();
    }
  }

  @override
  Future<void> delete(String collectionId) async {
    if (isSystemCollection(collectionId)) {
      throw CollectionNotFound(collectionId);
    }
    await _collectionsDao.deleteCollection(collectionId);
  }

  @override
  Stream<List<LibraryBook>> watchBooks(String collectionId) => _collectionsDao
      .watchBooksInCollection(collectionId)
      .map((items) => items.map((item) => item.toLibraryBook()).toList());

  @override
  Stream<List<LibraryCollection>> watchForBook(String bookId) => _collectionsDao
      .watchCollectionsForBook(bookId)
      .map((items) => items.map((item) => item.toLibraryCollection()).toList());

  @override
  Future<void> addBook(String collectionId, String bookId) async {
    if (await _collectionsDao.getCollectionById(collectionId) == null) {
      throw CollectionNotFound(collectionId);
    }
    if (!await _collectionsDao.bookExists(bookId)) {
      throw CollectionBookNotFound(bookId);
    }
    try {
      await _collectionsDao.addMembership(
        BookCollectionEntriesCompanion.insert(
          collectionId: collectionId,
          bookId: bookId,
          addedAt: _clock(),
        ),
      );
    } catch (_) {
      throw const CollectionStorageFailure();
    }
  }

  @override
  Future<void> removeBook(String collectionId, String bookId) async {
    await _collectionsDao.removeMembership(collectionId, bookId);
  }

  @override
  Future<bool> containsBook(String collectionId, String bookId) =>
      _collectionsDao.containsMembership(collectionId, bookId);

  Future<void> _validateBooks(Iterable<String> bookIds) async {
    for (final bookId in bookIds) {
      if (!await _collectionsDao.bookExists(bookId)) {
        throw CollectionBookNotFound(bookId);
      }
    }
  }

  String? _descriptionOrNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  CollectionName _nameOrThrow(String value) {
    final name = CollectionName.tryParse(value);
    if (name == null) throw const InvalidCollectionName();
    return name;
  }
}

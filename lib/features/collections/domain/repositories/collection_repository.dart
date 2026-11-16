import 'package:bibliolife/features/collections/domain/models/library_collection.dart';
import 'package:bibliolife/features/collections/domain/models/collection_summary.dart';
import 'package:bibliolife/shared/models/library_book.dart';

abstract interface class CollectionRepository {
  Stream<List<LibraryCollection>> watchAll();
  Stream<List<CollectionSummary>> watchSummaries();
  Future<LibraryCollection?> getById(String id);
  Future<LibraryCollection> create(String name);
  Future<LibraryCollection> rename(String collectionId, String newName);
  Future<LibraryCollection> saveEditor({
    String? collectionId,
    required String name,
    required String? description,
    required String? customCoverPath,
    required Set<String> selectedBookIds,
  });
  Future<void> delete(String collectionId);
  Stream<List<LibraryBook>> watchBooks(String collectionId);
  Stream<List<LibraryCollection>> watchForBook(String bookId);
  Future<void> addBook(String collectionId, String bookId);
  Future<void> removeBook(String collectionId, String bookId);
  Future<bool> containsBook(String collectionId, String bookId);
}

sealed class CollectionRepositoryFailure implements Exception {
  const CollectionRepositoryFailure();
}

class InvalidCollectionName extends CollectionRepositoryFailure {
  const InvalidCollectionName();
}

class DuplicateCollectionName extends CollectionRepositoryFailure {
  const DuplicateCollectionName();
}

class CollectionNotFound extends CollectionRepositoryFailure {
  const CollectionNotFound(this.collectionId);
  final String collectionId;
}

class CollectionBookNotFound extends CollectionRepositoryFailure {
  const CollectionBookNotFound(this.bookId);
  final String bookId;
}

class CollectionStorageFailure extends CollectionRepositoryFailure {
  const CollectionStorageFailure();
}

import 'package:bibliolife/features/collections/application/providers/collection_repository_provider.dart';
import 'package:bibliolife/features/collections/domain/models/library_collection.dart';
import 'package:bibliolife/features/collections/domain/models/collection_summary.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final allCollectionsProvider = StreamProvider<List<LibraryCollection>>((ref) {
  return ref.watch(collectionRepositoryProvider).watchAll();
});

final collectionSummariesProvider = StreamProvider<List<CollectionSummary>>((
  ref,
) {
  return ref.watch(collectionRepositoryProvider).watchSummaries();
});

final collectionByIdProvider =
    FutureProvider.family<LibraryCollection?, String>(
      (ref, id) => ref.watch(collectionRepositoryProvider).getById(id),
    );

final collectionsForBookProvider =
    StreamProvider.family<List<LibraryCollection>, String>((ref, bookId) {
      return ref.watch(collectionRepositoryProvider).watchForBook(bookId);
    });

final booksInCollectionProvider =
    StreamProvider.family<List<LibraryBook>, String>((ref, collectionId) {
      return ref.watch(collectionRepositoryProvider).watchBooks(collectionId);
    });

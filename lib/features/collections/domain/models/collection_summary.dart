import 'package:bibliolife/features/collections/domain/models/library_collection.dart';

/// Lightweight data used to render a collection in the collections list.
class CollectionSummary {
  const CollectionSummary({
    required this.collection,
    required this.bookCount,
    required this.recentBooks,
  });

  final LibraryCollection collection;
  final int bookCount;
  final List<CollectionPreviewBook> recentBooks;
}

class CollectionPreviewBook {
  const CollectionPreviewBook({
    required this.id,
    required this.title,
    required this.coverPath,
  });

  final String id;
  final String title;
  final String? coverPath;
}

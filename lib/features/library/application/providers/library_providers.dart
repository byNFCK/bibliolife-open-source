import 'package:bibliolife/features/library/application/providers/library_repository_provider.dart';
import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final allBooksProvider = StreamProvider<List<LibraryBook>>((ref) {
  return ref.watch(libraryRepositoryProvider).watchAllBooks();
});

final bookByIdProvider = StreamProvider.family<LibraryBook?, String>((ref, id) {
  return ref.watch(libraryRepositoryProvider).watchById(id);
});

final favoriteBooksProvider = StreamProvider<List<LibraryBook>>((ref) {
  return ref.watch(libraryRepositoryProvider).watchFavoriteBooks();
});

final recentlyOpenedBooksProvider = Provider<AsyncValue<List<LibraryBook>>>((
  ref,
) {
  return ref.watch(allBooksProvider).whenData((books) {
    final recent = books.where((book) => book.lastOpenedAt != null).toList();
    recent.sort((left, right) {
      final opened = right.lastOpenedAt!.compareTo(left.lastOpenedAt!);
      return opened != 0 ? opened : left.id.compareTo(right.id);
    });
    return recent.take(16).toList(growable: false);
  });
});

import 'package:bibliolife/features/library/application/providers/library_repository_provider.dart';
import 'package:bibliolife/features/import/application/providers/managed_book_deletion_provider.dart';
import 'package:bibliolife/features/library/application/use_cases/add_book.dart';
import 'package:bibliolife/features/library/application/use_cases/delete_book.dart';
import 'package:bibliolife/features/library/application/use_cases/mark_book_opened.dart';
import 'package:bibliolife/features/library/application/use_cases/set_book_favorite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final addBookProvider = Provider<AddBook>(
  (ref) => AddBook(ref.watch(libraryRepositoryProvider)),
);
final deleteBookProvider = Provider<DeleteBook>(
  (ref) => DeleteBook(ref.watch(managedBookDeletionServiceProvider)),
);
final setBookFavoriteProvider = Provider<SetBookFavorite>(
  (ref) => SetBookFavorite(ref.watch(libraryRepositoryProvider)),
);
final markBookOpenedProvider = Provider<MarkBookOpened>(
  (ref) => MarkBookOpened(ref.watch(libraryRepositoryProvider)),
);

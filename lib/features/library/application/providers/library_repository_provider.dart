import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/library/data/repositories/drift_library_repository.dart';
import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return DriftLibraryRepository(database.booksDao);
});

import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/collections/data/repositories/drift_collection_repository.dart';
import 'package:bibliolife/features/collections/domain/repositories/collection_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final collectionRepositoryProvider = Provider<CollectionRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return DriftCollectionRepository(database.collectionsDao);
});

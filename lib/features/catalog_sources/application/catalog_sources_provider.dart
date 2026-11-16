import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/catalog_sources/data/drift_catalog_source_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final catalogSourceRepositoryProvider = Provider<CatalogSourceRepository>(
  (ref) => DriftCatalogSourceRepository(ref.watch(appDatabaseProvider)),
);
final catalogSourcesBootstrapProvider = FutureProvider<void>((ref) {
  return ref.read(catalogSourceRepositoryProvider).ensureBuiltInSources();
});
final catalogSourcesProvider = StreamProvider<List<CatalogSource>>((ref) {
  return ref.watch(catalogSourceRepositoryProvider).watchAll();
});
final enabledCatalogSourcesProvider = Provider<List<CatalogSource>>(
  (ref) => ref
      .watch(catalogSourcesProvider)
      .maybeWhen(
        data: (items) => items.where((source) => source.isEnabled).toList(),
        orElse: () => const [],
      ),
);

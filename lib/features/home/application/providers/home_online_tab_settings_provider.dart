import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/data/built_in_catalog_sources.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/home/data/drift_home_online_tab_settings_repository.dart';
import 'package:bibliolife/features/home/domain/home_online_tab_settings_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final homeOnlineTabSettingsRepositoryProvider =
    Provider<HomeOnlineTabSettingsRepository>(
      (ref) =>
          DriftHomeOnlineTabSettingsRepository(ref.watch(appDatabaseProvider)),
    );

final homeOnlineTabVisibilityProvider = StreamProvider<Map<String, bool>>(
  (ref) => ref.watch(homeOnlineTabSettingsRepositoryProvider).watchVisibility(),
);

/// Ordered from the built-in source registry, not from Search enablement.
final visibleHomeCatalogSourcesProvider = Provider<List<CatalogSource>>((ref) {
  final sources = ref.watch(catalogSourcesProvider).asData?.value ?? const [];
  final byId = {for (final source in sources) source.id: source};
  final visibility =
      ref.watch(homeOnlineTabVisibilityProvider).asData?.value ??
      const <String, bool>{};
  return List.unmodifiable([
    for (final registered in builtInCatalogSources)
      if (visibility[registered.id] ?? true) ?byId[registered.id],
  ]);
});

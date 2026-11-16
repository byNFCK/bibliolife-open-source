import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/data/catalog_source_url_normalizer.dart';
import 'package:bibliolife/features/catalog_sources/data/drift_catalog_source_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('real Drift source resolves through the production provider', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final repository = DriftCatalogSourceRepository(
      database,
      idGenerator: () => 'provider-source',
    );
    final normalized = CatalogSourceUrlNormalizer.normalize(
      ' https://PROVIDER.example:443/opds ',
    );
    expect(normalized.isValid, isTrue);
    final seeded = await repository.addCustomSource(
      name: 'Provider Library',
      baseUri: normalized.uri!,
    );
    final container = ProviderContainer(
      overrides: [
        catalogSourceRepositoryProvider.overrideWithValue(repository),
      ],
    );
    final subscription = container.listen(catalogSourcesProvider, (_, _) {});

    try {
      final sources = await container
          .read(catalogSourcesProvider.future)
          .timeout(const Duration(seconds: 5));
      final resolved = _sourceById(sources, seeded.id);

      expect(resolved, isNotNull);
      expect(resolved!.id, 'provider-source');
      expect(resolved.name, 'Provider Library');
      expect(resolved.baseUri.toString(), 'https://provider.example/opds');

      const missingId = 'missing-provider-source';
      final providerState = container.read(catalogSourcesProvider);
      expect(providerState.hasValue, isTrue);
      expect(_sourceById(providerState.requireValue, missingId), isNull);
      expect(
        providerState.hasValue &&
            _sourceById(providerState.requireValue, missingId) == null,
        isTrue,
      );
    } finally {
      subscription.close();
      expect(() => container.dispose(), returnsNormally);
      await database.close().timeout(const Duration(seconds: 5));
    }
  });
}

CatalogSource? _sourceById(List<CatalogSource> sources, String id) {
  for (final source in sources) {
    if (source.id == id) return source;
  }
  return null;
}

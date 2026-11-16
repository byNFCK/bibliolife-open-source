import 'dart:async';

import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('source stream and enabled derived provider retain local enabled rows', () async {
    final repository = _StreamRepository();
    final container = ProviderContainer(
      overrides: [catalogSourceRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    container.listen(catalogSourcesProvider, (_, _) {});

    repository.emit([_source('enabled', true), _source('disabled', false)]);
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(enabledCatalogSourcesProvider).map((source) => source.id),
      ['enabled'],
    );

    repository.emit([_source('enabled', false), _source('disabled', true)]);
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(enabledCatalogSourcesProvider).map((source) => source.id),
      ['disabled'],
    );
  });

  test('bootstrap delegates seeding once per provider lifecycle', () async {
    final repository = _StreamRepository();
    final container = ProviderContainer(
      overrides: [catalogSourceRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(catalogSourcesBootstrapProvider.future);
    expect(repository.seedCalls, 1);
  });
}

class _StreamRepository implements CatalogSourceRepository {
  final _stream = StreamController<List<CatalogSource>>.broadcast();
  int seedCalls = 0;
  void emit(List<CatalogSource> value) => _stream.add(value);
  @override Stream<List<CatalogSource>> watchAll() => _stream.stream;
  @override Future<List<CatalogSource>> getAll() async => const [];
  @override Future<CatalogSource?> getById(String id) async => null;
  @override Future<void> ensureBuiltInSources() async { seedCalls++; }
  @override Future<CatalogSource> addCustomSource({required String name, required Uri baseUri}) => throw UnimplementedError();
  @override Future<void> updateCustomSource({required String id, required String name, required Uri baseUri}) => throw UnimplementedError();
  @override Future<void> setEnabled({required String id, required bool enabled}) => throw UnimplementedError();
  @override Future<void> deleteCustomSource(String id) => throw UnimplementedError();
  @override Future<bool> normalizedUrlExists(Uri uri, {String? excludingSourceId}) async => false;
}

CatalogSource _source(String id, bool enabled) => CatalogSource(
  id: id, name: id, baseUri: Uri.parse('https://$id.example/'),
  type: CatalogSourceType.unknownOpds, isBuiltIn: false, isEnabled: enabled,
  supportsSearch: false, supportsNavigation: false, supportsAcquisition: false,
  createdAt: DateTime(2026), updatedAt: DateTime(2026),
);

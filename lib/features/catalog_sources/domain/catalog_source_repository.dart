import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';

abstract interface class CatalogSourceRepository {
  Stream<List<CatalogSource>> watchAll();
  Future<List<CatalogSource>> getAll();
  Future<CatalogSource?> getById(String id);
  Future<void> ensureBuiltInSources();
  Future<CatalogSource> addCustomSource({
    required String name,
    required Uri baseUri,
  });
  Future<void> updateCustomSource({
    required String id,
    required String name,
    required Uri baseUri,
  });
  Future<void> setEnabled({required String id, required bool enabled});
  Future<void> deleteCustomSource(String id);
  Future<bool> normalizedUrlExists(Uri uri, {String? excludingSourceId});
}

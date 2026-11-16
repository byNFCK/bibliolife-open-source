import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/catalog_sources/data/built_in_catalog_sources.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_repository.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

class DriftCatalogSourceRepository implements CatalogSourceRepository {
  DriftCatalogSourceRepository(this._db, {String Function()? idGenerator})
    : _idGenerator = idGenerator ?? const Uuid().v4;
  final AppDatabase _db;
  final String Function() _idGenerator;
  @override
  Stream<List<CatalogSource>> watchAll() =>
      _db.select(_db.catalogSourcesEntries).watch().map((rows) {
        final sources = rows.map(_map).toList();
        sources.sort((a, b) {
          final built = (b.isBuiltIn ? 1 : 0) - (a.isBuiltIn ? 1 : 0);
          return built != 0
              ? built
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        return sources;
      });
  @override
  Future<List<CatalogSource>> getAll() => watchAll().first;
  @override
  Future<CatalogSource?> getById(String id) async {
    final row = await (_db.select(
      _db.catalogSourcesEntries,
    )..where((entry) => entry.id.equals(id))).getSingleOrNull();
    return row == null ? null : _map(row);
  }

  @override
  Future<void> ensureBuiltInSources() async {
    for (final source in builtInCatalogSources) {
      final existing = await (_db.select(
        _db.catalogSourcesEntries,
      )..where((r) => r.id.equals(source.id))).getSingleOrNull();
      if (existing == null) {
        await _db.into(_db.catalogSourcesEntries).insert(_toCompanion(source));
      } else if (_builtInFieldsDiffer(existing, source)) {
        await (_db.update(
          _db.catalogSourcesEntries,
        )..where((entry) => entry.id.equals(source.id))).write(
          CatalogSourcesEntriesCompanion(
            name: Value(source.name),
            baseUrl: Value(source.baseUri.toString()),
            type: Value(source.type.name),
            supportsSearch: Value(source.supportsSearch),
            supportsNavigation: Value(source.supportsNavigation),
            supportsAcquisition: Value(source.supportsAcquisition),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    }
  }

  @override
  Future<CatalogSource> addCustomSource({
    required String name,
    required Uri baseUri,
  }) async {
    if (await normalizedUrlExists(baseUri)) {
      throw StateError('duplicateUrl');
    }
    final now = DateTime.now();
    final source = CatalogSource(
      id: _idGenerator(),
      name: name.trim(),
      baseUri: baseUri,
      type: CatalogSourceType.unknownOpds,
      isBuiltIn: false,
      isEnabled: true,
      supportsSearch: false,
      supportsNavigation: false,
      supportsAcquisition: false,
      createdAt: now,
      updatedAt: now,
      health: CatalogSourceHealth.unknown,
    );
    await _db.into(_db.catalogSourcesEntries).insert(_toCompanion(source));
    return source;
  }

  @override
  Future<bool> normalizedUrlExists(Uri uri, {String? excludingSourceId}) async {
    final rows = await (_db.select(
      _db.catalogSourcesEntries,
    )..where((entry) => entry.baseUrl.equals(uri.toString()))).get();
    return rows.any((row) => row.id != excludingSourceId);
  }

  @override
  Future<void> updateCustomSource({
    required String id,
    required String name,
    required Uri baseUri,
  }) async {
    final row = await (_db.select(
      _db.catalogSourcesEntries,
    )..where((entry) => entry.id.equals(id))).getSingleOrNull();
    if (row == null) throw StateError('sourceNotFound');
    if (row.isBuiltIn) throw StateError('builtInImmutable');
    if (await normalizedUrlExists(baseUri, excludingSourceId: id)) {
      throw StateError('duplicateUrl');
    }
    final changedUrl = row.baseUrl != baseUri.toString();
    await (_db.update(
      _db.catalogSourcesEntries,
    )..where((entry) => entry.id.equals(id))).write(
      CatalogSourcesEntriesCompanion(
        name: Value(name.trim()),
        baseUrl: Value(baseUri.toString()),
        updatedAt: Value(DateTime.now()),
        type: changedUrl ? const Value('unknownOpds') : const Value.absent(),
        supportsSearch: changedUrl ? const Value(false) : const Value.absent(),
        supportsNavigation: changedUrl
            ? const Value(false)
            : const Value.absent(),
        supportsAcquisition: changedUrl
            ? const Value(false)
            : const Value.absent(),
        health: changedUrl ? const Value('unknown') : const Value.absent(),
        lastSuccessfulAccessAt: changedUrl
            ? const Value(null)
            : const Value.absent(),
        lastCheckedAt: changedUrl ? const Value(null) : const Value.absent(),
        lastErrorCode: changedUrl ? const Value(null) : const Value.absent(),
      ),
    );
  }

  @override
  Future<void> setEnabled({required String id, required bool enabled}) =>
      (_db.update(
        _db.catalogSourcesEntries,
      )..where((r) => r.id.equals(id))).write(
        CatalogSourcesEntriesCompanion(
          isEnabled: Value(enabled),
          updatedAt: Value(DateTime.now()),
        ),
      );
  @override
  Future<void> deleteCustomSource(String id) async {
    final row = await (_db.select(
      _db.catalogSourcesEntries,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null || row.isBuiltIn) {
      throw StateError('builtInCannotBeDeleted');
    }
    await (_db.delete(
      _db.catalogSourcesEntries,
    )..where((r) => r.id.equals(id))).go();
  }

  CatalogSource _map(CatalogSourcesEntry row) => CatalogSource(
    id: row.id,
    name: row.name,
    baseUri: Uri.parse(row.baseUrl),
    type: CatalogSourceType.values.byName(row.type),
    isBuiltIn: row.isBuiltIn,
    isEnabled: row.isEnabled,
    supportsSearch: row.supportsSearch,
    supportsNavigation: row.supportsNavigation,
    supportsAcquisition: row.supportsAcquisition,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    lastSuccessfulAccessAt: row.lastSuccessfulAccessAt,
    lastCheckedAt: row.lastCheckedAt,
    health: row.health == null
        ? CatalogSourceHealth.unknown
        : CatalogSourceHealth.values.byName(row.health!),
    lastErrorCode: row.lastErrorCode,
  );
  CatalogSourcesEntriesCompanion _toCompanion(CatalogSource s) =>
      CatalogSourcesEntriesCompanion.insert(
        id: s.id,
        name: s.name,
        baseUrl: s.baseUri.toString(),
        type: s.type.name,
        isBuiltIn: s.isBuiltIn,
        isEnabled: s.isEnabled,
        supportsSearch: s.supportsSearch,
        supportsNavigation: s.supportsNavigation,
        supportsAcquisition: s.supportsAcquisition,
        createdAt: s.createdAt,
        updatedAt: s.updatedAt,
        health: Value(s.health?.name),
        lastSuccessfulAccessAt: Value(s.lastSuccessfulAccessAt),
        lastCheckedAt: Value(s.lastCheckedAt),
        lastErrorCode: Value(s.lastErrorCode),
      );

  bool _builtInFieldsDiffer(CatalogSourcesEntry row, CatalogSource source) =>
      row.name != source.name ||
      row.baseUrl != source.baseUri.toString() ||
      row.type != source.type.name ||
      row.supportsSearch != source.supportsSearch ||
      row.supportsNavigation != source.supportsNavigation ||
      row.supportsAcquisition != source.supportsAcquisition;
}

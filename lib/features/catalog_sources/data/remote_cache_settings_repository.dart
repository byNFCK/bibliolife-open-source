import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_cache_budget.dart';
import 'package:drift/drift.dart';

abstract interface class RemoteCacheSettingsRepository {
  Future<RemoteCacheBudget> load();
  Stream<RemoteCacheBudget> watch();
  Future<void> save(RemoteCacheBudget budget);
}

class DriftRemoteCacheSettingsRepository
    implements RemoteCacheSettingsRepository {
  const DriftRemoteCacheSettingsRepository(this._dao);

  final RemoteCacheSettingsDao _dao;

  @override
  Future<RemoteCacheBudget> load() async {
    final entry = await _dao.load();
    return _normalise(entry?.maximumBytes);
  }

  @override
  Stream<RemoteCacheBudget> watch() =>
      _dao.watch().asyncMap((entry) => _normalise(entry?.maximumBytes));

  @override
  Future<void> save(RemoteCacheBudget budget) => _dao.upsert(
    RemoteCacheSettingsEntriesCompanion.insert(
      id: const Value(1),
      maximumBytes: budget.maximumBytes,
    ),
  );

  Future<RemoteCacheBudget> _normalise(int? value) async {
    final budget = RemoteCacheBudget.fromStored(value);
    if (value != budget.maximumBytes) await save(budget);
    return budget;
  }
}

import 'dart:async';

import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/catalog_sources/data/remote_cache_settings_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_cache_budget.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final remoteCacheSettingsRepositoryProvider =
    Provider<RemoteCacheSettingsRepository>(
      (ref) => DriftRemoteCacheSettingsRepository(
        ref.watch(appDatabaseProvider).remoteCacheSettingsDao,
      ),
    );

/// The authoritative, reactive persisted online-cache capacity.
final remoteCacheBudgetProvider = StreamProvider<RemoteCacheBudget>(
  (ref) => ref.watch(remoteCacheSettingsRepositoryProvider).watch(),
);

/// Starts storage before the first cache operation and keeps the one service
/// instance in sync with future persisted changes.
void bindRemoteCacheBudget(
  Ref ref,
  Future<void> Function(RemoteCacheBudget) set,
) {
  ref.listen<AsyncValue<RemoteCacheBudget>>(
    remoteCacheBudgetProvider,
    (_, next) => next.whenData((budget) => unawaited(set(budget))),
    fireImmediately: true,
  );
}

import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/connectivity/domain/app_connectivity_mode.dart';
import 'package:drift/drift.dart';

abstract interface class AppConnectivityModeRepository {
  Future<AppConnectivityState> load();
  Future<void> save(AppConnectivityState state);
}

class DriftAppConnectivityModeRepository
    implements AppConnectivityModeRepository {
  const DriftAppConnectivityModeRepository(this._dao);

  final AppConnectivitySettingsDao _dao;

  @override
  Future<AppConnectivityState> load() async {
    final stored = await _dao.load();
    if (stored == null) return const AppConnectivityState.offline();
    return AppConnectivityState(
      mode: stored.mode == AppConnectivityMode.online.name
          ? AppConnectivityMode.online
          : AppConnectivityMode.offline,
      hasAcknowledgedOnline: stored.hasAcknowledgedOnline,
    );
  }

  @override
  Future<void> save(AppConnectivityState state) => _dao.upsert(
    AppConnectivitySettingsEntriesCompanion.insert(
      id: const Value(1),
      mode: state.mode.name,
      hasAcknowledgedOnline: state.hasAcknowledgedOnline,
    ),
  );
}

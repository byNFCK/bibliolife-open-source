import 'dart:async';
import 'dart:developer' as developer;

import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/connectivity/data/app_connectivity_mode_repository.dart';
import 'package:bibliolife/features/connectivity/domain/app_connectivity_mode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appConnectivityModeRepositoryProvider =
    Provider<AppConnectivityModeRepository>(
      (ref) => DriftAppConnectivityModeRepository(
        ref.watch(appDatabaseProvider).appConnectivitySettingsDao,
      ),
    );

final appConnectivityModeProvider =
    NotifierProvider<AppConnectivityModeController, AppConnectivityState>(
      AppConnectivityModeController.new,
    );

final onlineAccessAllowedProvider = Provider<bool>(
  (ref) =>
      ref.watch(appConnectivityModeProvider).mode == AppConnectivityMode.online,
);
final canUseOnlineCatalogsProvider = Provider<bool>(
  (ref) => ref.watch(onlineAccessAllowedProvider),
);
final canDownloadOnlineBooksProvider = Provider<bool>(
  (ref) => ref.watch(onlineAccessAllowedProvider),
);
final canLoadRemoteMetadataProvider = Provider<bool>(
  (ref) => ref.watch(onlineAccessAllowedProvider),
);

class AppConnectivityModeController extends Notifier<AppConnectivityState> {
  final _revocations = StreamController<void>.broadcast();
  var _hasLocalChange = false;

  Stream<void> get onOnlineAccessRevoked => _revocations.stream;

  @override
  AppConnectivityState build() {
    ref.onDispose(_revocations.close);
    unawaited(_load());
    return const AppConnectivityState.offline();
  }

  Future<void> _load() async {
    try {
      final loaded = await ref
          .read(appConnectivityModeRepositoryProvider)
          .load();
      if (_hasLocalChange) return;
      state = loaded.copyWith(isLoaded: true);
      _debug(
        'APP_CONNECTIVITY_MODE_LOADED',
        'mode=${loaded.mode.name} source=stored',
      );
    } catch (_) {
      state = const AppConnectivityState.offline().copyWith(isLoaded: true);
      _debug('APP_CONNECTIVITY_MODE_LOADED', 'mode=offline source=default');
    }
  }

  Future<void> setMode(AppConnectivityMode mode) async {
    final previous = state;
    if (previous.mode == mode || previous.isPersisting) return;
    final next = previous.copyWith(
      mode: mode,
      hasAcknowledgedOnline:
          previous.hasAcknowledgedOnline || mode == AppConnectivityMode.online,
      isPersisting: true,
      error: null,
    );
    _hasLocalChange = true;
    state = next;
    try {
      await ref.read(appConnectivityModeRepositoryProvider).save(next);
      state = next.copyWith(isPersisting: false);
      _debug(
        'APP_CONNECTIVITY_MODE_CHANGED',
        'from=${previous.mode.name} to=${mode.name}',
      );
      if (previous.mode == AppConnectivityMode.online &&
          mode == AppConnectivityMode.offline) {
        _revocations.add(null);
        _debug('ONLINE_ACCESS_REVOKED', 'activeOperationsCancelled=0');
      }
    } catch (error) {
      state = previous.copyWith(error: error, isPersisting: false);
    }
  }

  static void _debug(String name, String message) {
    assert(() {
      developer.log(message, name: name);
      return true;
    }());
  }
}

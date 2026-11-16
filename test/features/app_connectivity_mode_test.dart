import 'package:bibliolife/features/connectivity/application/app_connectivity_mode_provider.dart';
import 'package:bibliolife/features/connectivity/application/network_access_policy.dart';
import 'package:bibliolife/features/connectivity/data/app_connectivity_mode_repository.dart';
import 'package:bibliolife/features/connectivity/domain/app_connectivity_mode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missing or malformed persisted mode defaults to offline', () async {
    final repository = _FakeRepository(const AppConnectivityState.offline());
    final container = ProviderContainer(
      overrides: [
        appConnectivityModeRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    expect(
      container.read(appConnectivityModeProvider).mode,
      AppConnectivityMode.offline,
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(appConnectivityModeProvider).mode,
      AppConnectivityMode.offline,
    );
  });

  test(
    'mode updates immediately, persists, and offline blocks before request',
    () async {
      final repository = _FakeRepository(const AppConnectivityState.offline());
      final container = ProviderContainer(
        overrides: [
          appConnectivityModeRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      await Future<void>.delayed(Duration.zero);

      var invoked = false;
      final gateway = PolicyAwareRemoteGateway(
        container.read(networkAccessPolicyProvider),
      );
      expect(
        () => gateway.run('catalog', () async => invoked = true),
        throwsA(isA<OfflineModeException>()),
      );
      expect(invoked, isFalse);

      await container
          .read(appConnectivityModeProvider.notifier)
          .setMode(AppConnectivityMode.online);
      expect(container.read(onlineAccessAllowedProvider), isTrue);
      await gateway.run('catalog', () async => invoked = true);
      expect(invoked, isTrue);
      expect(repository.saved?.mode, AppConnectivityMode.online);
    },
  );

  test('persistence failure restores previous mode', () async {
    final repository = _FakeRepository(const AppConnectivityState.offline())
      ..failSave = true;
    final container = ProviderContainer(
      overrides: [
        appConnectivityModeRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await Future<void>.delayed(Duration.zero);

    await container
        .read(appConnectivityModeProvider.notifier)
        .setMode(AppConnectivityMode.online);

    expect(
      container.read(appConnectivityModeProvider).mode,
      AppConnectivityMode.offline,
    );
  });
}

class _FakeRepository implements AppConnectivityModeRepository {
  _FakeRepository(this.loaded);
  final AppConnectivityState loaded;
  AppConnectivityState? saved;
  bool failSave = false;

  @override
  Future<AppConnectivityState> load() async => loaded;

  @override
  Future<void> save(AppConnectivityState state) async {
    if (failSave) throw StateError('write failed');
    saved = state;
  }
}

import 'package:bibliolife/app/router/app_router.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_repository.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/catalog_sources_screen.dart';
import 'package:bibliolife/features/connectivity/application/app_connectivity_mode_provider.dart';
import 'package:bibliolife/features/connectivity/data/app_connectivity_mode_repository.dart';
import 'package:bibliolife/features/connectivity/domain/app_connectivity_mode.dart';
import 'package:bibliolife/features/profile/presentation/screens/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'production Profile composition keeps Online outside Appearance',
    (tester) async {
      await tester.pumpWidget(_scope(const MaterialApp(home: ProfileScreen())));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.byKey(const Key('settings-heading-Online')), findsOneWidget);
      final mode = find.byKey(const Key('application-mode-settings-row'));
      expect(
        find.descendant(
          of: find.byKey(const Key('settings-section-online')),
          matching: mode,
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('settings-section-appearance')),
          matching: mode,
        ),
        findsNothing,
      );
      expect(find.text('Application mode'), findsOneWidget);
      expect(find.byType(SegmentedButton<AppConnectivityMode>), findsNothing);
      expect(
        find.byKey(const Key('application-mode-settings-row')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings-section-storage')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('settings-section-storage')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Online libraries'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Online libraries'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Default tab in Library'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Default tab in Library'), findsOneWidget);
    },
  );

  testWidgets('production router resolves direct Online Libraries route', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.go('/online-libraries');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(CatalogSourcesScreen), findsOneWidget);
    expect(find.text('Home online libraries'), findsNothing);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/online-libraries',
    );
  });
}

Widget _scope(Widget child) => ProviderScope(
  overrides: [
    catalogSourceRepositoryProvider.overrideWithValue(_Repository()),
    appConnectivityModeRepositoryProvider.overrideWithValue(
      _OfflineRepository(),
    ),
  ],
  child: child,
);

ProviderContainer _container() => ProviderContainer(
  overrides: [
    catalogSourceRepositoryProvider.overrideWithValue(_Repository()),
    appConnectivityModeRepositoryProvider.overrideWithValue(
      _OfflineRepository(),
    ),
  ],
);

class _OfflineRepository implements AppConnectivityModeRepository {
  @override
  Future<AppConnectivityState> load() async =>
      const AppConnectivityState.offline();
  @override
  Future<void> save(AppConnectivityState state) async {}
}

class _Repository implements CatalogSourceRepository {
  @override
  Stream<List<CatalogSource>> watchAll() => Stream.value(const []);
  @override
  Future<List<CatalogSource>> getAll() async => const [];
  @override
  Future<CatalogSource?> getById(String id) async => null;
  @override
  Future<void> ensureBuiltInSources() async {}
  @override
  Future<CatalogSource> addCustomSource({
    required String name,
    required Uri baseUri,
  }) => throw UnimplementedError();
  @override
  Future<void> updateCustomSource({
    required String id,
    required String name,
    required Uri baseUri,
  }) => throw UnimplementedError();
  @override
  Future<void> setEnabled({required String id, required bool enabled}) async {}
  @override
  Future<void> deleteCustomSource(String id) async {}
  @override
  Future<bool> normalizedUrlExists(
    Uri uri, {
    String? excludingSourceId,
  }) async => false;
}

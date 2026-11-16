import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_repository.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/catalog_sources_screen.dart';
import 'package:bibliolife/features/connectivity/application/app_connectivity_mode_provider.dart';
import 'package:bibliolife/features/connectivity/data/app_connectivity_mode_repository.dart';
import 'package:bibliolife/features/connectivity/domain/app_connectivity_mode.dart';
import 'package:bibliolife/features/home/application/providers/home_online_tab_settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('offline source management exposes clear production semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogSourceRepositoryProvider.overrideWithValue(_Repository()),
          appConnectivityModeRepositoryProvider.overrideWithValue(
            _OfflineRepository(),
          ),
          homeOnlineTabVisibilityProvider.overrideWith(
            (ref) => Stream.value(const <String, bool>{}),
          ),
        ],
        child: const MaterialApp(home: CatalogSourcesScreen()),
      ),
    );
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Offline mode is enabled. Libraries can be managed locally.',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Add source',
      ),
      findsOneWidget,
    );
  });
}

class _OfflineRepository implements AppConnectivityModeRepository {
  @override
  Future<AppConnectivityState> load() async =>
      const AppConnectivityState.offline();
  @override
  Future<void> save(AppConnectivityState state) async {}
}

class _Repository implements CatalogSourceRepository {
  @override
  Stream<List<CatalogSource>> watchAll() => Stream.value([_source()]);
  @override
  Future<List<CatalogSource>> getAll() async => [_source()];
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

CatalogSource _source() => CatalogSource(
  id: 'gutenberg',
  name: 'Project Gutenberg',
  baseUri: Uri.parse('https://gutenberg.org/'),
  type: CatalogSourceType.opds1,
  isBuiltIn: true,
  isEnabled: true,
  supportsSearch: false,
  supportsNavigation: true,
  supportsAcquisition: true,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

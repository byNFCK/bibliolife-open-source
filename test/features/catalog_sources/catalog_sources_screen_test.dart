import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_repository.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/catalog_sources_screen.dart';
import 'package:bibliolife/features/connectivity/application/app_connectivity_mode_provider.dart';
import 'package:bibliolife/features/connectivity/data/app_connectivity_mode_repository.dart';
import 'package:bibliolife/features/connectivity/domain/app_connectivity_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('offline screen retains local built-ins and custom management', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogSourceRepositoryProvider.overrideWithValue(_Repository()),
          appConnectivityModeRepositoryProvider.overrideWithValue(
            _OfflineRepository(),
          ),
        ],
        child: const MaterialApp(home: CatalogSourcesScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Offline mode is enabled'), findsOneWidget);
    expect(find.text('Built-in libraries'), findsOneWidget);
    expect(find.text('Project Gutenberg'), findsWidgets);
    expect(find.text('Standard Ebooks'), findsWidgets);
    expect(find.text('Open Library'), findsWidgets);
    expect(find.text('Internet Archive'), findsWidgets);
    expect(find.text('Public EPUB/PDF download provider'), findsOneWidget);
    expect(find.text('Custom libraries'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Custom'), 200);
    expect(find.text('Custom'), findsOneWidget);
    expect(find.text('Add library'), findsOneWidget);
    expect(find.byType(Switch), findsWidgets);
  });
}

class _Repository implements CatalogSourceRepository {
  @override
  Stream<List<CatalogSource>> watchAll() => Stream.value([
    _source('gutenberg', 'Project Gutenberg', true),
    _source('standard', 'Standard Ebooks', true),
    _source('open-library', 'Open Library', true),
    CatalogSource(
      id: 'builtin-internet-archive',
      name: 'Internet Archive',
      baseUri: Uri.parse('https://archive.org/'),
      type: CatalogSourceType.internetArchive,
      isBuiltIn: true,
      isEnabled: true,
      supportsSearch: false,
      supportsNavigation: false,
      supportsAcquisition: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
    _source('custom', 'Custom', false, builtIn: false),
  ]);
  @override
  Future<List<CatalogSource>> getAll() async => await watchAll().first;
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

class _OfflineRepository implements AppConnectivityModeRepository {
  @override
  Future<AppConnectivityState> load() async =>
      const AppConnectivityState.offline();

  @override
  Future<void> save(AppConnectivityState state) async {}
}

CatalogSource _source(
  String id,
  String name,
  bool enabled, {
  bool builtIn = true,
}) => CatalogSource(
  id: id,
  name: name,
  baseUri: Uri.parse('https://$id.example/'),
  type: CatalogSourceType.unknownOpds,
  isBuiltIn: builtIn,
  isEnabled: enabled,
  supportsSearch: false,
  supportsNavigation: false,
  supportsAcquisition: false,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

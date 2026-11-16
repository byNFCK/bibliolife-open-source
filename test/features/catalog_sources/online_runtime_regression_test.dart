import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_browser_controller.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway_provider.dart';
import 'package:bibliolife/features/catalog_sources/data/built_in_catalog_sources.dart';
import 'package:bibliolife/features/catalog_sources/data/drift_catalog_source_repository.dart';
import 'package:bibliolife/features/catalog_sources/data/source_aware_remote_catalog_transport.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:bibliolife/features/connectivity/application/app_connectivity_mode_provider.dart';
import 'package:bibliolife/features/connectivity/data/app_connectivity_mode_repository.dart';
import 'package:bibliolife/features/connectivity/domain/app_connectivity_mode.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production provider selects real HTTP OPDS transport lazily', () {
    final database = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);

    expect(
      container.read(remoteCatalogTransportProvider),
      isA<SourceAwareRemoteCatalogTransport>(),
    );
  });

  test(
    'Offline denial Online retry and later Offline denial are live',
    () async {
      final modeRepository = _ModeRepository();
      final sourceRepository = _SourceRepository();
      final transport = _Transport();
      final container = ProviderContainer(
        overrides: [
          appConnectivityModeRepositoryProvider.overrideWithValue(
            modeRepository,
          ),
          catalogSourceRepositoryProvider.overrideWithValue(sourceRepository),
          remoteCatalogTransportProvider.overrideWithValue(transport),
        ],
      );
      final provider = catalogBrowserControllerProvider('source');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(() {
        subscription.close();
        container.dispose();
      });
      await Future<void>.delayed(Duration.zero);
      final controller = container.read(provider.notifier);

      await controller.openRoot();
      expect(
        container.read(provider).failure,
        RemoteCatalogFailure.accessDenied,
      );
      expect(transport.calls, 0);

      await container
          .read(appConnectivityModeProvider.notifier)
          .setMode(AppConnectivityMode.online);
      expect(container.read(onlineAccessAllowedProvider), isTrue);
      await controller.retry();
      expect(container.read(provider).page?.title, 'Live Catalog');
      expect(transport.calls, 1);

      await container
          .read(appConnectivityModeProvider.notifier)
          .setMode(AppConnectivityMode.offline);
      expect(container.read(onlineAccessAllowedProvider), isFalse);
      await controller.refresh();
      expect(
        container.read(provider).failure,
        RemoteCatalogFailure.accessDenied,
      );
      expect(transport.calls, 1);
    },
  );

  test(
    'built-in reseeding corrects URLs and preserves enabled selection',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final repository = DriftCatalogSourceRepository(database);
      try {
        await repository.ensureBuiltInSources();
        await repository.setEnabled(
          id: 'builtin-project-gutenberg',
          enabled: false,
        );
        await repository.ensureBuiltInSources();

        final sources = await repository.getAll();
        final gutenberg = sources.singleWhere(
          (source) => source.id == 'builtin-project-gutenberg',
        );
        final standard = sources.singleWhere(
          (source) => source.id == 'builtin-standard-ebooks',
        );
        final openLibrary = sources.singleWhere(
          (source) => source.id == 'builtin-open-library',
        );
        expect(
          gutenberg.baseUri.toString(),
          'https://www.gutenberg.org/ebooks/search.opds/',
        );
        expect(gutenberg.isEnabled, isFalse);
        expect(gutenberg.supportsNavigation, isTrue);
        expect(
          standard.baseUri.toString(),
          'https://standardebooks.org/feeds/opds',
        );
        expect(standard.supportsNavigation, isFalse);
        expect(openLibrary.supportsNavigation, isFalse);
        final builtIns = {
          for (final source in builtInCatalogSources) source.id: source,
        };
        expect(builtIns.length, builtInCatalogSources.length);
        expect(
          builtIns.keys,
          containsAll([
            'builtin-google-books',
            'builtin-open-library',
            'builtin-project-gutenberg',
            'builtin-standard-ebooks',
          ]),
        );
        expect(builtIns['builtin-google-books']!.supportsSearch, isTrue);
        expect(builtIns['builtin-open-library']!.supportsSearch, isTrue);
        expect(builtIns['builtin-project-gutenberg']!.supportsSearch, isTrue);
        expect(builtIns['builtin-standard-ebooks']!.supportsSearch, isFalse);
      } finally {
        await database.close();
      }
    },
  );
}

CatalogSource _source() => CatalogSource(
  id: 'source',
  name: 'Library',
  baseUri: Uri.parse('https://catalog.example/root'),
  type: CatalogSourceType.opds1,
  isBuiltIn: true,
  isEnabled: true,
  supportsSearch: false,
  supportsNavigation: true,
  supportsAcquisition: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _ModeRepository implements AppConnectivityModeRepository {
  var persisted = const AppConnectivityState(
    mode: AppConnectivityMode.offline,
    hasAcknowledgedOnline: false,
    isLoaded: true,
  );
  @override
  Future<AppConnectivityState> load() async => persisted;
  @override
  Future<void> save(AppConnectivityState state) async {
    persisted = state.copyWith(isLoaded: true, isPersisting: false);
  }
}

class _SourceRepository implements CatalogSourceRepository {
  @override
  Future<CatalogSource?> getById(String id) async => _source();
  @override
  Future<List<CatalogSource>> getAll() async => [_source()];
  @override
  Stream<List<CatalogSource>> watchAll() => Stream.value([_source()]);
  @override
  Future<void> ensureBuiltInSources() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Transport implements RemoteCatalogTransport {
  int calls = 0;
  @override
  Future<RemoteCatalogPage> loadRoot(CatalogSource source) async {
    calls++;
    return RemoteCatalogPage(
      sourceId: source.id,
      location: RemoteCatalogLocation.fromUri(source.baseUri),
      title: 'Live Catalog',
    );
  }

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) => loadRoot(source);
  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) => loadRoot(source);
}

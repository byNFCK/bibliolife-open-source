import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_controller.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway_provider.dart';
import 'package:bibliolife/features/catalog_sources/data/drift_catalog_source_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:bibliolife/features/connectivity/application/network_access_policy.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'opaque locations canonicalize HTTPS and resolve relative links locally',
    () {
      final first = RemoteCatalogLocation.parse(
        ' https://CATALOG.example:443/root#ignored ',
      );
      final equal = RemoteCatalogLocation.parse('https://catalog.example/root');
      final next = first.resolve('../page/2?cursor=next#fragment');

      expect(first.toString(), 'https://catalog.example/root');
      expect(first, equal);
      expect(first.hashCode, equal.hashCode);
      expect(next.toString(), 'https://catalog.example/page/2?cursor=next');
      expect(
        () => RemoteCatalogLocation.parse('http://catalog.example/root'),
        throwsFormatException,
      );
    },
  );

  test('remote catalog result models are deterministic and immutable', () {
    final root = RemoteCatalogLocation.parse('https://catalog.example/');
    final next = root.resolve('page/2');
    final page = RemoteCatalogPage(
      sourceId: 'source',
      location: root,
      title: 'Root',
      navigation: [
        RemoteCatalogNavigationLink(
          title: 'Fiction',
          location: root.resolve('fiction'),
        ),
      ],
      publications: [
        RemoteCatalogPublicationSummary(
          remoteId: 'publication-1',
          title: 'A Book',
          authors: ['A. Author'],
          coverLocation: root.resolve('covers/1.jpg'),
          summary: 'Summary',
          hasAcquisition: true,
        ),
      ],
      nextPageLocation: next,
    );

    expect(page.sourceId, 'source');
    expect(page.location, root);
    expect(page.navigation.single.title, 'Fiction');
    expect(page.publications.single.remoteId, 'publication-1');
    expect(page.publications.single.authors, ['A. Author']);
    expect(page.publications.single.hasAcquisition, isTrue);
    expect(page.nextPageLocation, next);
    expect(
      () => page.publications.add(
        RemoteCatalogPublicationSummary(
          remoteId: 'unexpected',
          title: 'Unexpected',
        ),
      ),
      throwsUnsupportedError,
    );
  });

  test(
    'Offline denial checks policy once and never invokes transport',
    () async {
      final policy = _CountingPolicy(allowed: false);
      final transport = _FakeRemoteCatalogTransport();
      final gateway = _gateway(policy, transport);

      await expectLater(
        gateway.loadRoot(_source()),
        _throwsFailure(RemoteCatalogFailure.accessDenied),
      );

      expect(policy.checkCalls, 1);
      expect(transport.totalCalls, 0);
    },
  );

  test(
    'Online root request invokes policy and transport exactly once',
    () async {
      final policy = _CountingPolicy(allowed: true);
      final transport = _FakeRemoteCatalogTransport();
      final expected = _page('https://catalog.example/root');
      transport.rootResult = expected;
      final source = _source();

      final result = await _gateway(policy, transport).loadRoot(source);

      expect(result, same(expected));
      expect(policy.checkCalls, 1);
      expect(transport.rootCalls, 1);
      expect(transport.pageCalls, 0);
      expect(transport.requestedSource, same(source));
    },
  );

  test(
    'page request preserves its opaque location and deterministic result',
    () async {
      final policy = _CountingPolicy(allowed: true);
      final transport = _FakeRemoteCatalogTransport();
      final location = RemoteCatalogLocation.parse(
        'https://catalog.example/page/2?cursor=next',
      );
      final expected = _page(location.toString());
      transport.pageResult = expected;
      final source = _source();

      final result = await _gateway(
        policy,
        transport,
      ).loadPage(source: source, location: location);

      expect(result, same(expected));
      expect(policy.checkCalls, 1);
      expect(transport.rootCalls, 0);
      expect(transport.pageCalls, 1);
      expect(transport.requestedSource, same(source));
      expect(transport.requestedLocation, location);
    },
  );

  test('raw transport errors map to typed transport failure', () async {
    final policy = _CountingPolicy(allowed: true);
    final transport = _FakeRemoteCatalogTransport()
      ..error = StateError('socket details must not escape');

    await expectLater(
      _gateway(policy, transport).loadRoot(_source()),
      _throwsFailure(RemoteCatalogFailure.transport),
    );

    expect(policy.checkCalls, 1);
    expect(transport.totalCalls, 1);
  });

  test('malformed and unsupported failures remain transport-neutral', () async {
    for (final failure in [
      RemoteCatalogException.malformedCatalogResponse('malformed'),
      RemoteCatalogException.unsupportedCatalogFormat('unsupported'),
    ]) {
      final policy = _CountingPolicy(allowed: true);
      final transport = _FakeRemoteCatalogTransport()..error = failure;

      await expectLater(
        _gateway(policy, transport).loadRoot(_source()),
        _throwsFailure(failure.failure),
      );
      expect(policy.checkCalls, 1);
      expect(transport.totalCalls, 1);
    }
  });

  test(
    'disabled and invalid sources fail after policy but before transport',
    () async {
      final policy = _CountingPolicy(allowed: true);
      final transport = _FakeRemoteCatalogTransport();
      final gateway = _gateway(policy, transport);

      await expectLater(
        gateway.loadRoot(_source(enabled: false)),
        _throwsFailure(RemoteCatalogFailure.sourceDisabled),
      );
      await expectLater(
        gateway.loadRoot(
          _source(baseUri: Uri.parse('http://invalid.example/')),
        ),
        _throwsFailure(RemoteCatalogFailure.invalidSourceOrLocation),
      );

      expect(policy.checkCalls, 2);
      expect(transport.totalCalls, 0);
    },
  );

  test('provider overrides are lazy and wire policy-aware success', () async {
    final policy = _CountingPolicy(allowed: true);
    final transport = _FakeRemoteCatalogTransport()
      ..rootResult = _page('https://catalog.example/root');
    final container = ProviderContainer(
      overrides: [
        networkAccessPolicyProvider.overrideWithValue(policy),
        remoteCatalogTransportProvider.overrideWithValue(transport),
      ],
    );
    addTearDown(container.dispose);

    final gateway = container.read(remoteCatalogGatewayProvider);
    expect(policy.checkCalls, 0);
    expect(transport.totalCalls, 0);

    final page = await gateway.loadRoot(_source());
    expect(page.title, 'Catalog Page');
    expect(policy.checkCalls, 1);
    expect(transport.rootCalls, 1);
  });

  test('production default transport is lazy and makes no request on read', () {
    final database = AppDatabase(NativeDatabase.memory());
    final policy = _CountingPolicy(allowed: true);
    final container = ProviderContainer(
      overrides: [
        networkAccessPolicyProvider.overrideWithValue(policy),
        appDatabaseProvider.overrideWithValue(database),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);

    final gateway = container.read(remoteCatalogGatewayProvider);
    expect(gateway, isA<RemoteCatalogGateway>());
    expect(policy.checkCalls, 0);
  });

  test(
    'M1A local controller mutation makes zero remote gateway calls',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final repository = DriftCatalogSourceRepository(
        database,
        idGenerator: () => 'local-source',
      );
      final policy = _CountingPolicy(allowed: true);
      final transport = _FakeRemoteCatalogTransport();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          catalogSourceRepositoryProvider.overrideWithValue(repository),
          networkAccessPolicyProvider.overrideWithValue(policy),
          remoteCatalogTransportProvider.overrideWithValue(transport),
        ],
      );

      try {
        container.read(remoteCatalogGatewayProvider);
        final added = await container
            .read(catalogSourcesControllerProvider.notifier)
            .add('Local', 'https://local.example/opds');

        expect(added, isTrue);
        expect(await repository.getById('local-source'), isNotNull);
        expect(policy.checkCalls, 0);
        expect(transport.totalCalls, 0);
      } finally {
        container.dispose();
        await database.close();
      }
    },
  );
}

PolicyAwareRemoteCatalogGateway _gateway(
  NetworkAccessPolicy policy,
  RemoteCatalogTransport transport,
) => PolicyAwareRemoteCatalogGateway(policy: policy, transport: transport);

Matcher _throwsFailure(RemoteCatalogFailure failure) => throwsA(
  isA<RemoteCatalogException>().having(
    (error) => error.failure,
    'failure',
    failure,
  ),
);

CatalogSource _source({bool enabled = true, Uri? baseUri}) => CatalogSource(
  id: 'source',
  name: 'Catalog Source',
  baseUri: baseUri ?? Uri.parse('https://catalog.example/root'),
  type: CatalogSourceType.unknownOpds,
  isBuiltIn: false,
  isEnabled: enabled,
  supportsSearch: false,
  supportsNavigation: true,
  supportsAcquisition: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

RemoteCatalogPage _page(String location) => RemoteCatalogPage(
  sourceId: 'source',
  location: RemoteCatalogLocation.parse(location),
  title: 'Catalog Page',
);

class _CountingPolicy implements NetworkAccessPolicy {
  _CountingPolicy({required this.allowed});

  final bool allowed;
  int checkCalls = 0;

  @override
  bool get isOnlineAccessAllowed => allowed;

  @override
  void requireOnlineAccess(String operation) {
    checkCalls++;
    if (!allowed) throw OfflineModeException(operation);
  }
}

class _FakeRemoteCatalogTransport implements RemoteCatalogTransport {
  int rootCalls = 0;
  int pageCalls = 0;
  CatalogSource? requestedSource;
  RemoteCatalogLocation? requestedLocation;
  RemoteCatalogPage? rootResult;
  RemoteCatalogPage? pageResult;
  Object? error;

  int get totalCalls => rootCalls + pageCalls;

  @override
  Future<RemoteCatalogPage> loadRoot(CatalogSource source) async {
    rootCalls++;
    requestedSource = source;
    _throwIfControlled();
    return rootResult ?? _page(source.baseUri.toString());
  }

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) async {
    pageCalls++;
    requestedSource = source;
    requestedLocation = location;
    _throwIfControlled();
    return pageResult ?? _page(location.toString());
  }

  void _throwIfControlled() {
    if (error case final controlled?) throw controlled;
  }

  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) => throw UnimplementedError();
}

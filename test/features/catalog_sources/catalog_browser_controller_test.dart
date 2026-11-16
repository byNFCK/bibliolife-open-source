import 'dart:async';

import 'package:bibliolife/features/catalog_sources/application/catalog_browser_controller.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway_provider.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:bibliolife/features/connectivity/application/network_access_policy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('provider is lazy and root success selects source and page', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);

    expect(harness.gateway.calls, 0);
    expect(harness.state.page, isNull);
    await harness.controller.openRoot();

    expect(harness.gateway.rootCalls, 1);
    expect(harness.state.sourceName, 'Library');
    expect(harness.state.page?.title, 'Root');
    expect(harness.state.failure, isNull);
  });

  test('child navigation succeeds and remote back restores root', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.controller.openRoot();
    final child = _location('/child');
    harness.gateway.pageResults[child] = _page('Child', '/child');

    await harness.controller.openNavigation(child);
    expect(harness.state.page?.title, 'Child');
    expect(harness.state.canGoBack, isTrue);

    harness.controller.goBack();
    expect(harness.state.page?.title, 'Root');
    expect(harness.state.canGoBack, isFalse);
  });

  test(
    'missing disabled and invalid sources fail without gateway call',
    () async {
      for (final source in <CatalogSource?>[
        null,
        _source(enabled: false),
        _source(baseUri: Uri.parse('http://unsafe.example')),
      ]) {
        final harness = _Harness(source: source, missing: source == null);
        addTearDown(harness.dispose);
        await harness.controller.openRoot();
        expect(harness.gateway.calls, 0);
        expect(
          harness.state.failure,
          source == null
              ? RemoteCatalogFailure.sourceNotFound
              : source.isEnabled
              ? RemoteCatalogFailure.invalidSourceOrLocation
              : RemoteCatalogFailure.sourceDisabled,
        );
      }
    },
  );

  test('initial failure is recoverable by retry', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.gateway.error = const RemoteCatalogException.timeout();

    await harness.controller.openRoot();
    expect(harness.state.failure, RemoteCatalogFailure.timeout);

    harness.gateway.error = null;
    await harness.controller.retry();
    expect(harness.gateway.rootCalls, 2);
    expect(harness.state.page?.title, 'Root');
    expect(harness.state.failure, isNull);
  });

  test('stale completion cannot replace a newer navigation result', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.controller.openRoot();
    final first = _location('/first');
    final second = _location('/second');
    final firstResult = Completer<RemoteCatalogPage>();
    final secondResult = Completer<RemoteCatalogPage>();
    harness.gateway.pending[first] = firstResult;
    harness.gateway.pending[second] = secondResult;

    final requestA = harness.controller.openNavigation(first);
    final requestB = harness.controller.openNavigation(second);
    secondResult.complete(_page('Second', '/second'));
    await requestB;
    firstResult.complete(_page('First', '/first'));
    await requestA;

    expect(harness.state.page?.title, 'Second');
    expect(harness.state.location, second);
  });

  test('duplicate pending navigation makes one gateway call', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.controller.openRoot();
    final child = _location('/child');
    final pending = Completer<RemoteCatalogPage>();
    harness.gateway.pending[child] = pending;

    final first = harness.controller.openNavigation(child);
    final second = harness.controller.openNavigation(child);
    await Future<void>.delayed(Duration.zero);
    expect(harness.gateway.pageCalls, 1);
    pending.complete(_page('Child', '/child'));
    await Future.wait([first, second]);
  });

  test('controller disposal ignores a late completion safely', () async {
    final harness = _Harness();
    await harness.controller.openRoot();
    final child = _location('/late');
    final pending = Completer<RemoteCatalogPage>();
    harness.gateway.pending[child] = pending;

    final request = harness.controller.openNavigation(child);
    await Future<void>.delayed(Duration.zero);
    harness.dispose();
    pending.complete(_page('Late', '/late'));

    await expectLater(request, completes);
  });

  test('next page appends and deduplicates stable entries', () async {
    final next = _location('/page-2');
    final harness = _Harness(
      root: _page(
        'Root',
        '/root',
        next: next,
        publications: [_publication('one')],
        navigation: [_navigation('One', '/one')],
      ),
    );
    addTearDown(harness.dispose);
    harness.gateway.pageResults[next] = _page(
      'Page 2',
      '/page-2',
      publications: [_publication('one'), _publication('two')],
      navigation: [
        _navigation('One duplicate', '/one'),
        _navigation('Two', '/two'),
      ],
    );

    await harness.controller.openRoot();
    await harness.controller.loadNextPage();

    expect(harness.state.page?.publications.map((item) => item.remoteId), [
      'one',
      'two',
    ]);
    expect(harness.state.page?.navigation.map((item) => item.title), [
      'One',
      'Two',
    ]);
    expect(harness.state.hasNextPage, isFalse);
  });

  test('pagination failure preserves content and retry appends', () async {
    final next = _location('/page-2');
    final harness = _Harness(
      root: _page(
        'Root',
        '/root',
        next: next,
        publications: [_publication('one')],
      ),
    );
    addTearDown(harness.dispose);
    await harness.controller.openRoot();
    harness.gateway.error = const RemoteCatalogException.transport();

    await harness.controller.loadNextPage();
    expect(harness.state.page?.publications.length, 1);
    expect(harness.state.failure, RemoteCatalogFailure.transport);

    harness.gateway.error = null;
    harness.gateway.pageResults[next] = _page(
      'Page 2',
      '/page-2',
      publications: [_publication('two')],
    );
    await harness.controller.retry();
    expect(harness.state.page?.publications.length, 2);
  });

  test('real policy gateway integration blocks offline transport', () async {
    final policy = _Policy(allowed: false);
    final transport = _Transport();
    final harness = _Harness(
      gatewayOverride: PolicyAwareRemoteCatalogGateway(
        policy: policy,
        transport: transport,
      ),
    );
    addTearDown(harness.dispose);

    await harness.controller.openRoot();
    expect(harness.state.failure, RemoteCatalogFailure.accessDenied);
    expect(policy.calls, 1);
    expect(transport.calls, 0);
  });
}

class _Harness {
  _Harness({
    CatalogSource? source,
    bool missing = false,
    RemoteCatalogPage? root,
    RemoteCatalogGateway? gatewayOverride,
  }) : repository = _Repository(missing ? null : source ?? _source()),
       gateway = _Gateway(root ?? _page('Root', '/root')) {
    container = ProviderContainer(
      overrides: [
        catalogSourceRepositoryProvider.overrideWithValue(repository),
        remoteCatalogGatewayProvider.overrideWithValue(
          gatewayOverride ?? gateway,
        ),
      ],
    );
    subscription = container.listen(
      catalogBrowserControllerProvider('source'),
      (_, _) {},
    );
  }

  final _Repository repository;
  final _Gateway gateway;
  late final ProviderContainer container;
  late final ProviderSubscription<CatalogBrowserState> subscription;

  CatalogBrowserController get controller =>
      container.read(catalogBrowserControllerProvider('source').notifier);
  CatalogBrowserState get state =>
      container.read(catalogBrowserControllerProvider('source'));

  void dispose() {
    subscription.close();
    container.dispose();
  }
}

CatalogSource _source({bool enabled = true, Uri? baseUri}) => CatalogSource(
  id: 'source',
  name: 'Library',
  baseUri: baseUri ?? Uri.parse('https://catalog.example/root'),
  type: CatalogSourceType.opds1,
  isBuiltIn: true,
  isEnabled: enabled,
  supportsSearch: false,
  supportsNavigation: true,
  supportsAcquisition: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

RemoteCatalogLocation _location(String path) =>
    RemoteCatalogLocation.parse('https://catalog.example$path');

RemoteCatalogPage _page(
  String title,
  String path, {
  RemoteCatalogLocation? next,
  List<RemoteCatalogPublicationSummary> publications = const [],
  List<RemoteCatalogNavigationLink> navigation = const [],
}) => RemoteCatalogPage(
  sourceId: 'source',
  location: _location(path),
  title: title,
  nextPageLocation: next,
  publications: publications,
  navigation: navigation,
);

RemoteCatalogPublicationSummary _publication(String id) =>
    RemoteCatalogPublicationSummary(
      remoteId: id,
      title: 'Book $id',
      authors: ['Author $id'],
      hasAcquisition: true,
    );

RemoteCatalogNavigationLink _navigation(String title, String path) =>
    RemoteCatalogNavigationLink(title: title, location: _location(path));

class _Gateway implements RemoteCatalogGateway {
  _Gateway(this.root);
  final RemoteCatalogPage root;
  int rootCalls = 0;
  int pageCalls = 0;
  Object? error;
  final pageResults = <RemoteCatalogLocation, RemoteCatalogPage>{};
  final pending = <RemoteCatalogLocation, Completer<RemoteCatalogPage>>{};
  int get calls => rootCalls + pageCalls;

  @override
  Future<RemoteCatalogPage> loadRoot(CatalogSource source) async {
    rootCalls++;
    if (error case final controlled?) throw controlled;
    return root;
  }

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) async {
    pageCalls++;
    if (error case final controlled?) throw controlled;
    if (pending[location] case final controlled?) return controlled.future;
    return pageResults[location]!;
  }

  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) => throw UnimplementedError();
}

class _Repository implements CatalogSourceRepository {
  _Repository(this.source);
  final CatalogSource? source;
  @override
  Future<CatalogSource?> getById(String id) async => source;
  @override
  Future<List<CatalogSource>> getAll() async => [?source];
  @override
  Stream<List<CatalogSource>> watchAll() => Stream.value([?source]);
  @override
  Future<void> ensureBuiltInSources() async {}
  @override
  Future<CatalogSource> addCustomSource({
    required String name,
    required Uri baseUri,
  }) => throw UnimplementedError();
  @override
  Future<void> deleteCustomSource(String id) => throw UnimplementedError();
  @override
  Future<bool> normalizedUrlExists(Uri uri, {String? excludingSourceId}) =>
      throw UnimplementedError();
  @override
  Future<void> setEnabled({required String id, required bool enabled}) =>
      throw UnimplementedError();
  @override
  Future<void> updateCustomSource({
    required String id,
    required String name,
    required Uri baseUri,
  }) => throw UnimplementedError();
}

class _Policy implements NetworkAccessPolicy {
  _Policy({required this.allowed});
  final bool allowed;
  int calls = 0;
  @override
  bool get isOnlineAccessAllowed => allowed;
  @override
  void requireOnlineAccess(String operation) {
    calls++;
    if (!allowed) throw OfflineModeException(operation);
  }
}

class _Transport implements RemoteCatalogTransport {
  int calls = 0;
  @override
  Future<RemoteCatalogPage> loadRoot(CatalogSource source) async {
    calls++;
    return _page('Root', '/root');
  }

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) async {
    calls++;
    return _page('Page', location.uri.path);
  }

  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) => throw UnimplementedError();
}

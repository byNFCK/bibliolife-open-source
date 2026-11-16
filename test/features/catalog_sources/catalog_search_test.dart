import 'dart:async';
import 'dart:convert';

import 'package:bibliolife/features/catalog_sources/application/catalog_search_controller.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway_provider.dart';
import 'package:bibliolife/features/catalog_sources/data/http_opds_remote_catalog_transport.dart';
import 'package:bibliolife/features/catalog_sources/data/opds1_atom_parser.dart';
import 'package:bibliolife/features/catalog_sources/data/open_search_description_parser.dart';
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
  group('search metadata and OpenSearch', () {
    test('parser discovers direct and relative OpenSearch relations', () {
      const parser = Opds1AtomParser();
      final base = _location('/root');
      final direct = parser.parse(
        sourceId: 'source',
        location: base,
        body:
            '<feed xmlns="http://www.w3.org/2005/Atom"><title>Root</title>'
            '<link rel="search" href="/find?q={searchTerms}"/></feed>',
      );
      final openSearch = parser.parse(
        sourceId: 'source',
        location: base,
        body:
            '<feed xmlns="http://www.w3.org/2005/Atom"><title>Root</title>'
            '<link rel="http://opds-spec.org/search" '
            'type="application/opensearchdescription+xml" '
            'href="open-search.xml"/></feed>',
      );

      expect(
        direct.searchCapability.kind,
        RemoteCatalogSearchCapabilityKind.directTemplate,
      );
      expect(
        openSearch.searchCapability.location.toString(),
        'https://catalog.example/open-search.xml',
      );
    });

    test('missing or malformed search metadata stays unsupported', () {
      final page = const Opds1AtomParser().parse(
        sourceId: 'source',
        location: _location('/root'),
        body:
            '<feed xmlns="http://www.w3.org/2005/Atom" xmlns:x="urn:x">'
            '<title>Root</title><x:unknown/></feed>',
      );
      expect(page.searchCapability.isSupported, isFalse);
    });

    test('OpenSearch parser resolves relative template and rejects malformed', () {
      const parser = OpenSearchDescriptionParser();
      final template = parser.parseTemplate(
        body:
            '<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">'
            '<Url type="application/atom+xml" '
            'template="../search?q={searchTerms}&amp;count={count?}"/>'
            '</OpenSearchDescription>',
        descriptionLocation: _location('/meta/open-search.xml'),
      );
      expect(
        template.toString(),
        'https://catalog.example/search?q=%7BsearchTerms%7D&count=%7Bcount?%7D',
      );
      expect(
        () => parser.parseTemplate(
          body: '<broken>',
          descriptionLocation: _location('/open-search.xml'),
        ),
        _throwsFailure(RemoteCatalogFailure.malformedSearchDescription),
      );
    });

    test('OpenSearch parser upgrades Gutenberg legacy HTTP Atom template', () {
      const parser = OpenSearchDescriptionParser();
      final template = parser.parseTemplate(
        body:
            '<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">'
            '<Url type="application/atom+xml" '
            'template="http://m.gutenberg.org/ebooks/search.opds/?query={searchTerms}"/>'
            '</OpenSearchDescription>',
        descriptionLocation: RemoteCatalogLocation.parse(
          'https://www.gutenberg.org/catalog/osd-books.xml',
        ),
      );

      expect(
        template.toString(),
        'https://m.gutenberg.org/ebooks/search.opds/?query=%7BsearchTerms%7D',
      );
    });

    test('Gutenberg search feed maps book subsection entries to results', () {
      final page = const Opds1AtomParser().parse(
        sourceId: 'builtin-project-gutenberg',
        location: RemoteCatalogLocation.parse(
          'https://www.gutenberg.org/ebooks/search.opds/?query=Frankenstein',
        ),
        isSearchResult: true,
        body:
            '<feed xmlns="http://www.w3.org/2005/Atom"><title>Books</title>'
            '<entry><id>https://www.gutenberg.org/ebooks/84.opds</id>'
            '<title>Frankenstein; or, the modern prometheus</title>'
            '<content type="text">Mary Wollstonecraft Shelley</content>'
            '<link rel="subsection" href="/ebooks/84.opds"/>'
            '</entry></feed>',
      );

      final book = page.publications.single;
      expect(book.remoteId, 'https://www.gutenberg.org/ebooks/84.opds');
      expect(book.authors, ['Mary Wollstonecraft Shelley']);
      expect(
        book.detailsLocation.toString(),
        'https://www.gutenberg.org/ebooks/84.opds',
      );
      expect(book.acquisitions, hasLength(1));
      expect(
        book.acquisitions.single.relation,
        'http://opds-spec.org/acquisition/open-access',
      );
      expect(
        book.acquisitions.single.href,
        'https://www.gutenberg.org/ebooks/84.epub.images',
      );
      expect(book.acquisitions.single.mediaType, 'application/epub+zip');
    });

    test('Gutenberg search does not surface audio-only subsections', () {
      final page = const Opds1AtomParser().parse(
        sourceId: 'builtin-project-gutenberg',
        location: RemoteCatalogLocation.parse(
          'https://www.gutenberg.org/ebooks/search.opds/?query=Frankenstein',
        ),
        isSearchResult: true,
        body:
            '<feed xmlns="http://www.w3.org/2005/Atom"><title>Books</title>'
            '<entry><id>https://www.gutenberg.org/ebooks/6542.opds</id>'
            '<title>Frankenstein</title>'
            '<content>Author: Shelley Category: Sound</content>'
            '<link rel="subsection" href="/ebooks/6542.opds"/>'
            '</entry></feed>',
      );

      expect(page.publications, isEmpty);
    });

    test('HTTP direct search encodes Unicode exactly once', () async {
      final client = _Client()
        ..responses.add(_response(_searchFeed(), '/find'));
      final transport = HttpOpdsRemoteCatalogTransport(client: client);
      final capability = RemoteCatalogSearchCapability.directTemplate(
        RemoteCatalogLocation.parse(
          'https://catalog.example/find?q=%7BsearchTerms%7D',
        ),
      );

      final page = await transport.search(
        source: _source(),
        capability: capability,
        query: '  Книга café  ',
      );

      expect(page.publications.single.remoteId, 'book');
      expect(
        client.locations.single.toString(),
        'https://catalog.example/find?q=++%D0%9A%D0%BD%D0%B8%D0%B3%D0%B0+caf%C3%A9++',
      );
    });

    test(
      'OpenSearch description fetch resolves template then search feed',
      () async {
        final client = _Client()
          ..responses.add(
            _response(
              '<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">'
                  '<Url type="application/atom+xml" template="../find?q={searchTerms}"/>'
                  '</OpenSearchDescription>',
              '/meta/open.xml',
            ),
          )
          ..responses.add(_response(_searchFeed(), '/find?q=book'));
        final transport = HttpOpdsRemoteCatalogTransport(client: client);

        await transport.search(
          source: _source(),
          capability: RemoteCatalogSearchCapability.openSearchDescription(
            _location('/meta/open.xml'),
          ),
          query: 'book',
        );

        expect(client.calls, 2);
        expect(
          client.locations.last.toString(),
          'https://catalog.example/find?q=book',
        );
      },
    );
  });

  group('search controller', () {
    test(
      'initialize typing empty and overlong query make zero calls',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        expect(harness.gateway.calls, 0);
        await harness.controller.initialize(_capability());
        harness.controller.setQuery('typing only');
        await harness.controller.submit('   ');
        await harness.controller.submit('x' * 201);
        expect(harness.gateway.calls, 0);
        expect(harness.state.validationMessage, contains('200'));
      },
    );

    test('explicit submit trims and succeeds once then clear resets', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.controller.initialize(_capability());

      await harness.controller.submit('  two  words  ');
      expect(harness.gateway.queries, ['two  words']);
      expect(harness.state.lastSuccessfulQuery, 'two  words');
      expect(harness.state.page, isNotNull);

      harness.controller.clear();
      expect(harness.state.query, '');
      expect(harness.state.page, isNull);
    });

    test('unsupported capability never calls gateway', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.controller.initialize(
        const RemoteCatalogSearchCapability.unsupported(),
      );
      await harness.controller.submit('book');
      expect(harness.state.failure, RemoteCatalogFailure.searchUnsupported);
      expect(harness.gateway.calls, 0);
    });

    test(
      'stale query and duplicate submit protection are deterministic',
      () async {
        final harness = _Harness();
        addTearDown(harness.dispose);
        await harness.controller.initialize(_capability());
        final a = Completer<RemoteCatalogPage>();
        final b = Completer<RemoteCatalogPage>();
        harness.gateway.pending['a'] = a;
        harness.gateway.pending['b'] = b;

        final requestA = harness.controller.submit('a');
        await Future<void>.delayed(Duration.zero);
        final duplicateA = harness.controller.submit('a');
        final requestB = harness.controller.submit('b');
        await Future<void>.delayed(Duration.zero);
        expect(harness.gateway.queries, ['a', 'b']);
        b.complete(_results('b'));
        await requestB;
        a.complete(_results('a'));
        await Future.wait([requestA, duplicateA]);
        expect(harness.state.lastSuccessfulQuery, 'b');
      },
    );

    test('pagination appends deduplicates and retries after failure', () async {
      final next = _location('/next');
      final harness = _Harness(
        initial: _results('q', ids: ['one'], next: next),
      );
      addTearDown(harness.dispose);
      await harness.controller.initialize(_capability());
      await harness.controller.submit('q');
      harness.gateway.pageError = const RemoteCatalogException.transport();
      await harness.controller.loadNextPage();
      expect(harness.state.page?.publications.length, 1);

      harness.gateway.pageError = null;
      harness.gateway.next = _results('q', ids: ['one', 'two']);
      await harness.controller.retry();
      expect(harness.state.page?.publications.map((item) => item.remoteId), [
        'one',
        'two',
      ]);
    });

    test('policy integration denies Offline before transport', () async {
      final policy = _Policy(false);
      final transport = _Transport();
      final harness = _Harness(
        gatewayOverride: PolicyAwareRemoteCatalogGateway(
          policy: policy,
          transport: transport,
        ),
      );
      addTearDown(harness.dispose);
      await harness.controller.initialize(_capability());
      await harness.controller.submit('book');
      expect(harness.state.query, 'book');
      expect(harness.state.failure, RemoteCatalogFailure.accessDenied);
      expect(policy.calls, 1);
      expect(transport.calls, 0);
    });
  });
}

RemoteCatalogSearchCapability _capability() =>
    RemoteCatalogSearchCapability.directTemplate(
      RemoteCatalogLocation.parse(
        'https://catalog.example/find?q=%7BsearchTerms%7D',
      ),
    );

RemoteCatalogLocation _location(String path) =>
    RemoteCatalogLocation.parse('https://catalog.example$path');

String _searchFeed() =>
    '<feed xmlns="http://www.w3.org/2005/Atom"><title>Results</title><entry>'
    '<id>book</id><title>Book</title>'
    '<link rel="http://opds-spec.org/acquisition" href="/book.epub"/>'
    '</entry></feed>';

HttpCatalogResponse _response(String body, String path) => HttpCatalogResponse(
  statusCode: 200,
  bodyBytes: utf8.encode(body),
  effectiveLocation: _location(path),
  contentType: 'application/atom+xml',
);

CatalogSource _source() => CatalogSource(
  id: 'source',
  name: 'Library',
  baseUri: Uri.parse('https://catalog.example/root'),
  type: CatalogSourceType.opds1,
  isBuiltIn: true,
  isEnabled: true,
  supportsSearch: true,
  supportsNavigation: true,
  supportsAcquisition: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

RemoteCatalogPage _results(
  String query, {
  List<String>? ids,
  RemoteCatalogLocation? next,
}) => RemoteCatalogPage(
  sourceId: 'source',
  location: _location('/find'),
  title: 'Results',
  publications: (ids ?? [query])
      .map(
        (id) => RemoteCatalogPublicationSummary(
          remoteId: id,
          title: 'Book $id',
          authors: ['Author'],
          hasAcquisition: true,
        ),
      )
      .toList(),
  nextPageLocation: next,
);

Matcher _throwsFailure(RemoteCatalogFailure failure) => throwsA(
  isA<RemoteCatalogException>().having(
    (error) => error.failure,
    'failure',
    failure,
  ),
);

class _Client implements HttpCatalogClient {
  int calls = 0;
  final responses = <HttpCatalogResponse>[];
  final locations = <RemoteCatalogLocation>[];
  @override
  Future<HttpCatalogResponse> get({
    required RemoteCatalogLocation location,
    required Map<String, String> headers,
    required Duration timeout,
    required int maximumResponseBytes,
    required int maximumRedirects,
  }) async {
    calls++;
    locations.add(location);
    return responses.removeAt(0);
  }
}

class _Harness {
  _Harness({RemoteCatalogPage? initial, RemoteCatalogGateway? gatewayOverride})
    : gateway = _Gateway(initial ?? _results('default')) {
    container = ProviderContainer(
      overrides: [
        catalogSourceRepositoryProvider.overrideWithValue(_Repository()),
        remoteCatalogGatewayProvider.overrideWithValue(
          gatewayOverride ?? gateway,
        ),
      ],
    );
    subscription = container.listen(
      catalogSearchControllerProvider('source'),
      (_, _) {},
    );
  }
  final _Gateway gateway;
  late final ProviderContainer container;
  late final ProviderSubscription<CatalogSearchState> subscription;
  CatalogSearchController get controller =>
      container.read(catalogSearchControllerProvider('source').notifier);
  CatalogSearchState get state =>
      container.read(catalogSearchControllerProvider('source'));
  void dispose() {
    subscription.close();
    container.dispose();
  }
}

class _Gateway implements RemoteCatalogGateway {
  _Gateway(this.initial);
  final RemoteCatalogPage initial;
  final queries = <String>[];
  final pending = <String, Completer<RemoteCatalogPage>>{};
  Object? pageError;
  RemoteCatalogPage? next;
  int pageCalls = 0;
  int get calls => queries.length + pageCalls;
  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) async {
    queries.add(query);
    if (pending[query] case final completer?) return completer.future;
    return initial;
  }

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) async {
    pageCalls++;
    if (pageError case final error?) throw error;
    return next!;
  }

  @override
  Future<RemoteCatalogPage> loadRoot(CatalogSource source) =>
      throw UnimplementedError();
}

class _Repository implements CatalogSourceRepository {
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

class _Policy implements NetworkAccessPolicy {
  _Policy(this.allowed);
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
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) async {
    calls++;
    return _results(query);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

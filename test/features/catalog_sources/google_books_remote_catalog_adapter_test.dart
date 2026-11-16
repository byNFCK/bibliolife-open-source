import 'dart:convert';

import 'package:bibliolife/features/catalog_sources/data/google_books_remote_catalog_adapter.dart';
import 'package:bibliolife/features/catalog_sources/data/cached_retrying_http_catalog_client.dart';
import 'package:bibliolife/features/catalog_sources/data/http_opds_remote_catalog_transport.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_memory_cache.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_parser_executor.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_parsing_policy.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_payload_parser_dispatcher.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_retry_policy.dart';
import 'package:bibliolife/core/network/request_cancellation.dart';
import 'package:bibliolife/core/performance/online_pipeline_performance.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_access_hint.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:bibliolife/features/catalog_sources/domain/google_books_failure.dart';
import 'package:bibliolife/features/home/domain/models/home_feed_ranking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Home discovery stays provider relevance and never claims weekly popularity',
    () async {
      final client = _Client(
        _response({
          'totalItems': 1,
          'items': [_item()],
        }),
      );
      final page = await GoogleBooksRemoteCatalogAdapter(
        client: client,
        apiKey: 'configured',
      ).loadRoot(_source());

      expect(
        client.locations.single.uri.queryParameters['orderBy'],
        'relevance',
      );
      expect(page.homeRanking!.method, HomeFeedRankingMethod.providerRelevance);
      expect(page.homeRanking!.label, 'Recommended by Google Books');
    },
  );

  test(
    'maps Google metadata, identifiers, images, and safe access hints',
    () async {
      final client = _Client(
        _response({
          'totalItems': 1,
          'items': [_item()],
        }),
      );
      final adapter = GoogleBooksRemoteCatalogAdapter(
        client: client,
        apiKey: 'secret',
      );

      final page = await adapter.search(
        source: _source(),
        capability: _capability(),
        query: 'Jane Austen',
      );

      final book = page.publications.single;
      expect(client.locations.single.uri.queryParameters['q'], 'Jane Austen');
      expect(client.locations.single.uri.queryParameters['startIndex'], '0');
      expect(client.locations.single.uri.queryParameters['maxResults'], '40');
      expect(client.locations.single.uri.queryParameters['key'], 'secret');
      expect(book.remoteId, 'google-volume');
      expect(book.subtitle, 'A novel');
      expect(
        book.identifiers,
        containsAll(['ISBN_13:9780141439518', 'ISBN_10:0141439513']),
      );
      expect(book.imageCandidates, hasLength(3));
      expect(book.pageCount, 432);
      expect(book.accessMetadata['access.viewability'], 'PARTIAL');
      expect(book.accessMetadata['sale.listPrice.amount'], '7.99');
      expect(
        book.accessHints.map((hint) => hint.type),
        contains(RemoteCatalogAccessType.preview),
      );
      expect(
        book.accessHints.where(
          (hint) => hint.type == RemoteCatalogAccessType.authenticatedDownload,
        ),
        hasLength(1),
      );
    },
  );

  test('skips malformed items and accepts an empty items response', () async {
    final client = _Client(
      _response({
        'totalItems': 0,
        'items': [
          {'id': 'bad'},
          _item(id: ''),
        ],
      }),
    );
    final adapter = GoogleBooksRemoteCatalogAdapter(
      client: client,
      apiKey: 'test-key',
    );

    final page = await adapter.search(
      source: _source(),
      capability: _capability(),
      query: 'empty',
    );

    expect(page.publications, isEmpty);
    expect(page.nextPageLocation, isNull);
  });

  test(
    'upgrades trusted HTTP cover URLs without changing query parameters',
    () async {
      final item = _item();
      (item['volumeInfo'] as Map<String, dynamic>)['imageLinks'] = {
        'thumbnail':
            'http://books.google.com/books/content?id=volume&printsec=frontcover&zoom=2',
      };
      final page = await GoogleBooksRemoteCatalogAdapter(
        client: _Client(
          _response({
            'totalItems': 1,
            'items': [item],
          }),
        ),
        apiKey: 'configured',
      ).search(source: _source(), capability: _capability(), query: 'cover');

      final cover = page.publications.single.coverLocation!.uri;
      expect(cover.scheme, 'https');
      expect(cover.host, 'books.google.com');
      expect(cover.queryParameters['id'], 'volume');
      expect(cover.queryParameters['printsec'], 'frontcover');
      expect(cover.queryParameters['zoom'], '2');
    },
  );

  test('deduplicates repeated volume IDs within a response', () async {
    final client = _Client(
      _response({
        'totalItems': 2,
        'items': [_item(), _item()],
      }),
    );

    final page = await GoogleBooksRemoteCatalogAdapter(
      client: client,
      apiKey: 'test-key',
    ).search(source: _source(), capability: _capability(), query: 'Pride');

    expect(page.publications, hasLength(1));
  });

  test(
    'next page advances by requested page size and preserves query',
    () async {
      final client = _Client(
        _response({'totalItems': 200, 'items': List.filled(40, _item())}),
      );
      final adapter = GoogleBooksRemoteCatalogAdapter(
        client: client,
        apiKey: 'test-key',
      );
      final first = await adapter.search(
        source: _source(),
        capability: _capability(),
        query: 'Sherlock',
      );

      await adapter.loadPage(
        source: _source(),
        location: first.nextPageLocation!,
      );

      expect(client.locations.last.uri.queryParameters['q'], 'Sherlock');
      expect(client.locations.last.uri.queryParameters['startIndex'], '40');
    },
  );

  test('ACS and preview links are never direct downloads', () async {
    final item = _item();
    (item['accessInfo'] as Map)['epub'] = {
      'isAvailable': true,
      'acsTokenLink': 'https://books.google.test/acs',
    };
    final client = _Client(
      _response({
        'totalItems': 1,
        'items': [item],
      }),
    );
    final page = await GoogleBooksRemoteCatalogAdapter(
      client: client,
      apiKey: 'test-key',
    ).search(source: _source(), capability: _capability(), query: 'Pride');

    expect(
      page.publications.single.accessHints.any(
        (hint) => hint.type == RemoteCatalogAccessType.directDownload,
      ),
      isFalse,
    );
  });

  test('only a public-domain full-view Google EPUB is direct', () async {
    final item = _item();
    final access = (item['accessInfo'] as Map).cast<String, dynamic>();
    access['epub'] = {
      'isAvailable': true,
      'downloadLink': 'https://books.google.test/full.epub',
    };
    access['publicDomain'] = true;
    access['viewability'] = 'ALL_PAGES';
    access['accessViewStatus'] = 'FULL_PUBLIC_DOMAIN';
    final page = await GoogleBooksRemoteCatalogAdapter(
      client: _Client(
        _response({
          'totalItems': 1,
          'items': [item],
        }),
      ),
      apiKey: 'test-key',
    ).search(source: _source(), capability: _capability(), query: 'Pride');

    final hint = page.publications.single.accessHints.singleWhere(
      (value) => value.type == RemoteCatalogAccessType.directDownload,
    );
    expect(hint.uri, Uri.parse('https://books.google.test/full.epub'));
    expect(hint.isFullBook, isTrue);
    expect(hint.isDrmFree, isTrue);
    expect(hint.requiresAuthentication, isFalse);
  });

  test('only a public-domain full-view Google PDF is direct', () async {
    final item = _item();
    final access = (item['accessInfo'] as Map).cast<String, dynamic>();
    access['epub'] = const {};
    access['pdf'] = {
      'isAvailable': true,
      'downloadLink': 'https://books.google.test/full.pdf',
    };
    access['publicDomain'] = true;
    access['viewability'] = 'ALL_PAGES';
    access['accessViewStatus'] = 'FULL_PUBLIC_DOMAIN';
    final page = await GoogleBooksRemoteCatalogAdapter(
      client: _Client(
        _response({
          'totalItems': 1,
          'items': [item],
        }),
      ),
      apiKey: 'test-key',
    ).search(source: _source(), capability: _capability(), query: 'Pride');

    final hint = page.publications.single.accessHints.singleWhere(
      (value) => value.type == RemoteCatalogAccessType.directDownload,
    );
    expect(hint.mediaType, 'application/pdf');
    expect(hint.isDrmFree, isTrue);
  });

  test(
    'appends a configured key to a details request and keeps diagnostics redacted',
    () async {
      final logs = <String>[];
      final client = _Client(_response(_item()));
      final adapter = GoogleBooksRemoteCatalogAdapter(
        client: client,
        apiKey: 'secret-key',
        debugLog: logs.add,
      );

      await adapter.loadPage(
        source: _source(),
        location: RemoteCatalogLocation.parse(
          'https://www.googleapis.com/books/v1/volumes/google-volume',
        ),
      );

      expect(client.locations.single.uri.queryParameters['key'], 'secret-key');
      expect(
        logs.join('\n'),
        contains(
          'GOOGLE_BOOKS_CONFIGURATION apiKeyPresent=true apiKeyLength=10',
        ),
      );
      expect(logs.join('\n'), isNot(contains('secret-key')));
    },
  );

  test(
    'whitespace-only key fails before HTTP as a missing configuration',
    () async {
      final logs = <String>[];
      final client = _Client(
        _errorResponse(429, {
          'error': {'code': 429},
        }),
      );
      final adapter = GoogleBooksRemoteCatalogAdapter(
        client: client,
        apiKey: '  ',
        debugLog: logs.add,
      );

      await expectLater(
        adapter.search(
          source: _source(),
          capability: _capability(),
          query: 'war',
        ),
        throwsA(
          isA<GoogleBooksRequestException>().having(
            (error) => error.category,
            'category',
            GoogleBooksFailureCategory.apiKeyMissing,
          ),
        ),
      );
      expect(client.locations, isEmpty);
      expect(
        logs.join('\n'),
        contains(
          'GOOGLE_BOOKS_CONFIGURATION apiKeyPresent=false apiKeyLength=0',
        ),
      );
      expect(
        logs.join('\n'),
        contains('GOOGLE_BOOKS_REQUEST_BUILD_FAILED category=apiKeyMissing'),
      );
      expect(logs.join('\n'), isNot(contains('CATALOG_HTTP_REQUEST')));
    },
  );

  test('retries a transient limit once after Retry-After', () async {
    final delays = <Duration>[];
    final client = _SequenceClient([
      _errorResponse(
        429,
        {
          'error': {
            'code': 429,
            'status': 'RESOURCE_EXHAUSTED',
            'errors': [
              {'reason': 'rateLimitExceeded', 'domain': 'usageLimits'},
            ],
          },
        },
        headers: {'retry-after': '3'},
      ),
      _response({'totalItems': 0, 'items': []}),
    ]);

    await GoogleBooksRemoteCatalogAdapter(
      client: client,
      apiKey: 'configured',
      wait: (delay) async => delays.add(delay),
    ).search(source: _source(), capability: _capability(), query: 'war');

    expect(delays, [const Duration(seconds: 3)]);
    expect(client.locations, hasLength(2));
  });

  test(
    'quota, invalid key, and disabled API are typed without short retry',
    () async {
      for (final fixture in [
        (GoogleBooksFailureCategory.dailyLimitExceeded, 'dailyLimitExceeded'),
        (GoogleBooksFailureCategory.apiKeyInvalid, 'keyInvalid'),
        (GoogleBooksFailureCategory.apiNotEnabled, 'accessNotConfigured'),
      ]) {
        final delays = <Duration>[];
        final adapter = GoogleBooksRemoteCatalogAdapter(
          client: _Client(
            _errorResponse(429, {
              'error': {
                'code': 429,
                'status': 'PERMISSION_DENIED',
                'errors': [
                  {'reason': fixture.$2, 'domain': 'global'},
                ],
              },
            }),
          ),
          apiKey: 'configured',
          wait: (delay) async => delays.add(delay),
        );
        await expectLater(
          adapter.search(
            source: _source(),
            capability: _capability(),
            query: 'war',
          ),
          throwsA(
            isA<GoogleBooksRequestException>().having(
              (error) => error.category,
              'category',
              fixture.$1,
            ),
          ),
        );
        expect(delays, isEmpty);
      }
    },
  );

  test('emits a missing-configuration lifecycle terminal marker', () async {
    final markers = <String>[];
    final adapter = GoogleBooksRemoteCatalogAdapter(
      client: _Client(_response({'totalItems': 0, 'items': []})),
      apiKey: '',
      performanceMarker: _markerCollector(markers),
    );

    await expectLater(
      _search(adapter),
      throwsA(isA<GoogleBooksRequestException>()),
    );

    expect(markers, contains('google_early_exit reason=missing_configuration'));
    expect(
      markers,
      contains(
        'google_source_failed stage=configuration errorType=GoogleBooksRequestException',
      ),
    );
  });

  test('emits a cooldown lifecycle terminal marker', () async {
    final markers = <String>[];
    final adapter = GoogleBooksRemoteCatalogAdapter(
      client: _Client(
        _errorResponse(403, {
          'error': {
            'status': 'PERMISSION_DENIED',
            'errors': [
              {'reason': 'keyInvalid'},
            ],
          },
        }),
      ),
      apiKey: 'configured',
      performanceMarker: _markerCollector(markers),
    );

    await expectLater(
      _search(adapter),
      throwsA(isA<GoogleBooksRequestException>()),
    );
    markers.clear();
    await expectLater(
      _search(adapter),
      throwsA(isA<GoogleBooksRequestException>()),
    );

    expect(markers, contains('google_early_exit reason=cooldown'));
    expect(markers, isNot(contains('google_parse_started path=direct')));
  });

  test('emits a cancellation early-exit marker before parsing', () async {
    final markers = <String>[];
    final cancellation = CancellationTokenSource()
      ..cancel(RequestCancellationReason.queryReplaced);
    final adapter = GoogleBooksRemoteCatalogAdapter(
      client: _Client(_response({'totalItems': 0, 'items': []})),
      apiKey: 'configured',
      performanceMarker: _markerCollector(markers),
    );

    await expectLater(
      MetadataRequestScope.run(
        MetadataRequestContext(
          token: cancellation.token,
          sourceId: _source().id,
          priority: MetadataRequestPriority.activeSearch,
        ),
        () => _search(adapter),
      ),
      throwsA(isA<RequestCancelledException>()),
    );

    expect(markers, contains('google_early_exit reason=cancelled'));
    expect(markers, isNot(contains('google_parse_started path=direct')));
  });

  test(
    '200 network response reaches parse, mapping, and completion once',
    () async {
      final markers = <String>[];
      final adapter = GoogleBooksRemoteCatalogAdapter(
        client: _Client(
          _response({
            'totalItems': 1,
            'items': [_item()],
          }),
        ),
        apiKey: 'configured',
        performanceMarker: _markerCollector(markers),
      );

      await _search(adapter);

      expect(markers, contains('google_http_started'));
      expect(
        markers,
        contains(
          'google_http_completed status=200 bytes=${utf8.encode(jsonEncode({
            'totalItems': 1,
            'items': [_item()],
          })).length} cache=miss',
        ),
      );
      expect(markers, contains('google_parse_started path=direct'));
      expect(
        markers.where((marker) => marker.startsWith('google_parse_completed ')),
        hasLength(1),
      );
      expect(markers, contains('google_mapping_completed records=1'));
      expect(markers, contains('google_source_completed records=1'));
    },
  );

  test('cached HTTP response reaches the same parser boundary', () async {
    final markers = <String>[];
    final inner = _Client(
      _response({
        'totalItems': 1,
        'items': [_item()],
      }),
    );
    final adapter = GoogleBooksRemoteCatalogAdapter(
      client: CachedRetryingHttpCatalogClient(
        inner,
        MetadataMemoryCache(),
        const MetadataRetryPolicy(),
      ),
      apiKey: 'configured',
      performanceMarker: _markerCollector(markers),
    );
    final session = OnlineSearchPerformanceSession(id: 'test');

    await OnlinePerformanceScope.run(
      session,
      _source().id,
      () => _search(adapter),
    );
    markers.clear();
    await OnlinePerformanceScope.run(
      session,
      _source().id,
      () => _search(adapter),
    );

    expect(inner.locations, hasLength(1));
    expect(
      markers.any(
        (marker) =>
            marker.contains('google_http_completed status=200') &&
            marker.contains('cache=hit'),
      ),
      isTrue,
    );
    expect(markers, contains('google_parse_started path=direct'));
    expect(
      markers.where((marker) => marker.startsWith('google_parse_completed ')),
      hasLength(1),
    );
  });

  test('dispatcher path emits one Google parser-completion marker', () async {
    final markers = <String>[];
    final executor = MetadataParserExecutor();
    final adapter = GoogleBooksRemoteCatalogAdapter(
      client: _Client(
        _response({
          'totalItems': 1,
          'items': [_item()],
        }),
      ),
      apiKey: 'configured',
      parserDispatcher: MetadataPayloadParserDispatcher(
        const MetadataParsingPolicy(googleBooksThresholdBytes: 1 << 20),
        executor,
      ),
      performanceMarker: _markerCollector(markers),
    );

    await _search(adapter);
    executor.dispose();

    expect(markers, contains('google_parse_started path=dispatcher'));
    expect(
      markers.where((marker) => marker.startsWith('google_parse_completed ')),
      hasLength(1),
    );
    expect(markers, isNot(contains(startsWith('parser_execution'))));
  });

  test(
    'empty and non-success responses terminate without parser markers',
    () async {
      for (final response in [
        _rawResponse(200, const []),
        _errorResponse(400, {
          'error': {
            'status': 'INVALID_ARGUMENT',
            'errors': [
              {'reason': 'badRequest'},
            ],
          },
        }),
      ]) {
        final markers = <String>[];
        final adapter = GoogleBooksRemoteCatalogAdapter(
          client: _Client(response),
          apiKey: 'configured',
          performanceMarker: _markerCollector(markers),
        );

        await expectLater(
          _search(adapter),
          throwsA(isA<RemoteCatalogException>()),
        );

        expect(
          markers.where((marker) => marker.startsWith('google_parse_')),
          isEmpty,
        );
        expect(
          markers,
          contains(startsWith('google_source_failed stage=http')),
        );
        if (response.bodyBytes.isEmpty) {
          expect(markers, contains('google_early_exit reason=empty_response'));
        }
      }
    },
  );

  test('parser and mapping failures report their lifecycle stages', () async {
    final parserMarkers = <String>[];
    await expectLater(
      _search(
        GoogleBooksRemoteCatalogAdapter(
          client: _Client(_rawResponse(200, utf8.encode('{'))),
          apiKey: 'configured',
          performanceMarker: _markerCollector(parserMarkers),
        ),
      ),
      throwsA(isA<RemoteCatalogException>()),
    );
    expect(
      parserMarkers,
      contains(
        'google_source_failed stage=parse errorType=PayloadParserException',
      ),
    );

    final mappingMarkers = <String>[];
    await expectLater(
      _search(
        GoogleBooksRemoteCatalogAdapter(
          client: _Client(
            _response({
              'totalItems': 1,
              'items': [_item()],
            }),
          ),
          apiKey: 'configured',
          publicationMapper: (_) => throw StateError('mapping failed'),
          performanceMarker: _markerCollector(mappingMarkers),
        ),
      ),
      throwsA(isA<RemoteCatalogException>()),
    );
    expect(
      mappingMarkers,
      contains('google_source_failed stage=mapping errorType=StateError'),
    );
  });

  test('lifecycle markers exclude sensitive request values', () async {
    final markers = <String>[];
    final adapter = GoogleBooksRemoteCatalogAdapter(
      client: _Client(
        _response({
          'totalItems': 1,
          'items': [_item()],
        }),
      ),
      apiKey: 'secret-key',
      performanceMarker: _markerCollector(markers),
    );

    await adapter.search(
      source: _source(),
      capability: _capability(),
      query: 'Pride and Prejudice',
    );

    final output = markers.join('\n');
    expect(output, isNot(contains('secret-key')));
    expect(output, isNot(contains('Pride and Prejudice')));
    expect(output, isNot(contains('google-volume')));
  });
}

Future<void> _search(GoogleBooksRemoteCatalogAdapter adapter) =>
    adapter.search(source: _source(), capability: _capability(), query: 'test');

GoogleBooksPerformanceMarker _markerCollector(List<String> output) =>
    (name, {fields = const {}}) => output.add(
      '$name${fields.isEmpty ? '' : ' ${fields.entries.map((entry) => '${entry.key}=${entry.value}').join(' ')}'}',
    );

CatalogSource _source() => CatalogSource(
  id: 'builtin-google-books',
  name: 'Google Books',
  baseUri: Uri.parse('https://www.googleapis.com/books/v1/volumes'),
  type: CatalogSourceType.googleBooks,
  isBuiltIn: true,
  isEnabled: true,
  supportsSearch: true,
  supportsNavigation: false,
  supportsAcquisition: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

RemoteCatalogSearchCapability _capability() =>
    RemoteCatalogSearchCapability.directTemplate(
      RemoteCatalogLocation.parse(
        'https://www.googleapis.com/books/v1/volumes',
      ),
    );

Map<String, dynamic> _item({String id = 'google-volume'}) => {
  'id': id,
  'volumeInfo': {
    'title': 'Pride and Prejudice',
    'subtitle': 'A novel',
    'authors': ['Jane Austen'],
    'description': 'Description',
    'publisher': 'Publisher',
    'publishedDate': '1813',
    'pageCount': 432,
    'language': 'en',
    'categories': ['Fiction'],
    'industryIdentifiers': [
      {'type': 'ISBN_13', 'identifier': '9780141439518'},
      {'type': 'ISBN_10', 'identifier': '0141439513'},
    ],
    'imageLinks': {
      'thumbnail': 'https://images.google.test/thumb.jpg',
      'medium': 'https://images.google.test/medium.jpg',
      'large': 'https://images.google.test/large.jpg',
    },
    'previewLink': 'https://books.google.test/preview',
  },
  'accessInfo': {
    'country': 'DE',
    'epub': {
      'isAvailable': true,
      'acsTokenLink': 'https://books.google.test/acs',
    },
    'webReaderLink': 'https://books.google.test/read',
    'viewability': 'PARTIAL',
    'embeddable': true,
    'publicDomain': false,
    'textToSpeechPermission': 'ALLOWED',
    'accessViewStatus': 'SAMPLE',
  },
  'saleInfo': {
    'buyLink': 'https://books.google.test/buy',
    'saleability': 'FOR_SALE',
    'isEbook': true,
    'listPrice': {'amount': 7.99, 'currencyCode': 'EUR'},
    'retailPrice': {'amount': 6.99, 'currencyCode': 'EUR'},
  },
};

HttpCatalogResponse _response(Map<String, dynamic> body) => HttpCatalogResponse(
  statusCode: 200,
  bodyBytes: utf8.encode(jsonEncode(body)),
  effectiveLocation: RemoteCatalogLocation.parse(
    'https://www.googleapis.com/books/v1/volumes',
  ),
  contentType: 'application/json',
);

HttpCatalogResponse _errorResponse(
  int status,
  Map<String, dynamic> body, {
  Map<String, String> headers = const {},
}) => HttpCatalogResponse(
  statusCode: status,
  bodyBytes: utf8.encode(jsonEncode(body)),
  effectiveLocation: RemoteCatalogLocation.parse(
    'https://www.googleapis.com/books/v1/volumes',
  ),
  contentType: 'application/json',
  headers: headers,
);

HttpCatalogResponse _rawResponse(int status, List<int> body) =>
    HttpCatalogResponse(
      statusCode: status,
      bodyBytes: body,
      effectiveLocation: RemoteCatalogLocation.parse(
        'https://www.googleapis.com/books/v1/volumes',
      ),
      contentType: 'application/json',
    );

class _Client implements HttpCatalogClient {
  _Client(this.response);
  final HttpCatalogResponse response;
  final locations = <RemoteCatalogLocation>[];

  @override
  Future<HttpCatalogResponse> get({
    required RemoteCatalogLocation location,
    required Map<String, String> headers,
    required Duration timeout,
    required int maximumResponseBytes,
    required int maximumRedirects,
  }) async {
    locations.add(location);
    return response;
  }
}

class _SequenceClient implements HttpCatalogClient {
  _SequenceClient(this.responses);
  final List<HttpCatalogResponse> responses;
  final locations = <RemoteCatalogLocation>[];

  @override
  Future<HttpCatalogResponse> get({
    required RemoteCatalogLocation location,
    required Map<String, String> headers,
    required Duration timeout,
    required int maximumResponseBytes,
    required int maximumRedirects,
  }) async {
    locations.add(location);
    return responses.removeAt(0);
  }
}

import 'dart:typed_data';

import 'package:bibliolife/features/catalog_sources/data/cached_retrying_http_catalog_client.dart';
import 'package:bibliolife/features/catalog_sources/data/http_opds_remote_catalog_transport.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_memory_cache.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_retry_policy.dart';
import 'package:bibliolife/core/network/request_cancellation.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fresh hit avoids a second HTTP request', () async {
    final inner = _Client([200]);
    final client = CachedRetryingHttpCatalogClient(
      inner,
      MetadataMemoryCache(),
      const MetadataRetryPolicy(),
      wait: (_) async {},
    );
    await _get(client);
    await _get(client);
    expect(inner.calls, 1);
  });
  test('503 retries at most twice after initial request', () async {
    final inner = _Client([503, 503, 503]);
    final client = CachedRetryingHttpCatalogClient(
      inner,
      MetadataMemoryCache(),
      const MetadataRetryPolicy(),
      wait: (_) async {},
    );
    await _get(client);
    expect(inner.calls, 3);
  });
  test('304 reuses cached response', () async {
    var now = DateTime.now();
    final cache = MetadataMemoryCache(now: () => now);
    final inner = _Client([200, 304], headers: {'etag': 'tag'});
    final client = CachedRetryingHttpCatalogClient(
      inner,
      cache,
      const MetadataRetryPolicy(),
      wait: (_) async {},
    );
    final first = await _get(client);
    now = now.add(const Duration(hours: 1));
    final second = await _get(client);
    expect(second.bodyBytes, first.bodyBytes);
    expect(inner.calls, 2);
  });
  test('429 honors Retry-After and 4xx does not retry', () async {
    Duration? waited;
    final throttled = _Client([429, 200], headers: {'retry-after': '2'});
    final client = CachedRetryingHttpCatalogClient(
      throttled,
      MetadataMemoryCache(),
      const MetadataRetryPolicy(),
      wait: (delay) async => waited = delay,
    );
    await _get(client);
    expect(throttled.calls, 2);
    expect(waited, const Duration(seconds: 2));
    final forbidden = _Client([404]);
    await _get(
      CachedRetryingHttpCatalogClient(
        forbidden,
        MetadataMemoryCache(),
        const MetadataRetryPolicy(),
        wait: (_) async {},
      ),
    );
    expect(forbidden.calls, 1);
  });
  test('LRU respects entry and byte limits', () {
    final cache = MetadataMemoryCache(maximumEntries: 1, maximumBytes: 2);
    final response = HttpCatalogResponse(
      statusCode: 200,
      bodyBytes: Uint8List.fromList([1, 2]),
      effectiveLocation: RemoteCatalogLocation.parse('https://a.example'),
    );
    cache.put(
      'one',
      MetadataMemoryCacheEntry(
        value: response,
        expiresAt: DateTime.now(),
        bytes: 2,
      ),
    );
    cache.put(
      'two',
      MetadataMemoryCacheEntry(
        value: response,
        expiresAt: DateTime.now(),
        bytes: 2,
      ),
    );
    expect(cache.get<HttpCatalogResponse>('one'), isNull);
    expect(cache.cachedBytes, 2);
    expect(cache.evictionCount, 1);
  });
  test(
    'cancellation interrupts retry backoff without another HTTP attempt',
    () async {
      final source = CancellationTokenSource();
      final inner = _Client([503, 200]);
      final client = CachedRetryingHttpCatalogClient(
        inner,
        MetadataMemoryCache(),
        const MetadataRetryPolicy(),
        wait: (_) async {
          source.cancel(RequestCancellationReason.queryReplaced);
        },
      );
      await expectLater(
        MetadataRequestScope.run(
          MetadataRequestContext(
            token: source.token,
            sourceId: 'test',
            priority: MetadataRequestPriority.activeSearch,
          ),
          () => _get(client),
        ),
        throwsA(isA<RequestCancelledException>()),
      );
      expect(inner.calls, 1);
    },
  );
  test('different credential contexts do not share a cache entry', () async {
    final inner = _Client([200, 200]);
    final client = CachedRetryingHttpCatalogClient(
      inner,
      MetadataMemoryCache(),
      const MetadataRetryPolicy(),
      wait: (_) async {},
    );
    await client.get(
      location: RemoteCatalogLocation.parse(
        'https://google.example/books?q=x&key=alpha',
      ),
      headers: const {},
      timeout: const Duration(seconds: 1),
      maximumResponseBytes: 10,
      maximumRedirects: 1,
    );
    await client.get(
      location: RemoteCatalogLocation.parse(
        'https://google.example/books?q=x&key=bravo',
      ),
      headers: const {},
      timeout: const Duration(seconds: 1),
      maximumResponseBytes: 10,
      maximumRedirects: 1,
    );
    expect(inner.calls, 2);
  });
  test('injectable clock distinguishes five-minute search TTL', () {
    var now = DateTime(2026);
    final cache = MetadataMemoryCache(now: () => now);
    final response = HttpCatalogResponse(
      statusCode: 200,
      bodyBytes: Uint8List(0),
      effectiveLocation: RemoteCatalogLocation.parse(
        'https://catalog.example/search',
      ),
    );
    cache.put(
      'search',
      MetadataMemoryCacheEntry(
        value: response,
        expiresAt: now.add(const Duration(minutes: 5)),
        bytes: 0,
      ),
    );
    expect(cache.isFresh(cache.get<Object>('search')!), isTrue);
    now = now.add(const Duration(minutes: 6));
    expect(cache.isFresh(cache.get<Object>('search')!), isFalse);
  });
}

Future<HttpCatalogResponse> _get(HttpCatalogClient client) => client.get(
  location: RemoteCatalogLocation.parse('https://catalog.example/search?q=one'),
  headers: const {'Accept': 'application/json'},
  timeout: const Duration(seconds: 1),
  maximumResponseBytes: 1024,
  maximumRedirects: 1,
);

class _Client implements HttpCatalogClient {
  _Client(this.statuses, {this.headers = const {}});
  final List<int> statuses;
  final Map<String, String> headers;
  var calls = 0;
  @override
  Future<HttpCatalogResponse> get({
    required RemoteCatalogLocation location,
    required Map<String, String> headers,
    required Duration timeout,
    required int maximumResponseBytes,
    required int maximumRedirects,
  }) async => HttpCatalogResponse(
    statusCode: statuses[calls++],
    bodyBytes: Uint8List.fromList([1, 2]),
    effectiveLocation: location,
    headers: this.headers,
  );
}

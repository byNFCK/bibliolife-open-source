import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:bibliolife/core/network/request_cancellation.dart';
import 'package:bibliolife/core/performance/online_pipeline_performance.dart';
import 'package:bibliolife/features/catalog_sources/data/http_opds_remote_catalog_transport.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_memory_cache.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_retry_policy.dart';
import 'package:bibliolife/features/catalog_sources/data/remote_cache_service.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';

/// Shared metadata transport: fresh LRU hit, conditional stale request, then
/// bounded retry. It caches only successful 200 responses.
class CachedRetryingHttpCatalogClient implements HttpCatalogClient {
  CachedRetryingHttpCatalogClient(
    this._inner,
    this._cache,
    this._retry, {
    this.diskCache,
    Future<void> Function(Duration)? wait,
  }) : _wait = wait ?? Future<void>.delayed;
  final HttpCatalogClient _inner;
  final MetadataMemoryCache _cache;
  final MetadataRetryPolicy _retry;
  final RemoteCacheService? diskCache;
  final Future<void> Function(Duration) _wait;
  final Map<String, Future<void>> _weeklyRevalidations = {};

  @override
  Future<HttpCatalogResponse> get({
    required RemoteCatalogLocation location,
    required Map<String, String> headers,
    required Duration timeout,
    required int maximumResponseBytes,
    required int maximumRedirects,
  }) async {
    final key = _key(location, headers);
    var cached = _cache.get<HttpCatalogResponse>(key);
    final disk = diskCache;
    if (cached == null && disk != null) {
      final diskEntry = await disk.readMetadata(key);
      if (diskEntry != null) {
        cached = MetadataMemoryCacheEntry(
          value: HttpCatalogResponse(
            statusCode: 200,
            bodyBytes: diskEntry.bodyBytes,
            headers: const {},
            effectiveLocation: location,
          ),
          expiresAt: diskEntry.expiresAt,
          bytes: diskEntry.bodyBytes.length,
          etag: diskEntry.etag,
          lastModified: diskEntry.lastModified,
        );
        _cache.put(key, cached);
      }
    }
    if (cached != null && _cache.isFresh(cached)) {
      OnlinePerformanceScope.session?.cacheHitCount++;
      OnlinePerformanceScope.session?.recordCoordinatorEvent('cacheAvoided');
      _recordCacheState();
      return cached.value;
    }
    // Weekly ranking pages are deliberately stale-while-revalidate.  A tab
    // gets its last known provider order immediately; a coalesced refresh
    // updates the shared cache for a later active-tab refresh/revisit without
    // taking over the visible Home spinner.
    if (cached != null && _isWeeklyRanking(location)) {
      OnlinePerformanceScope.session?.cacheHitCount++;
      final refresh = _weeklyRevalidations.putIfAbsent(
        key,
        () => _revalidateWeekly(
          key: key,
          cached: cached!,
          location: location,
          headers: headers,
          timeout: timeout,
          maximumResponseBytes: maximumResponseBytes,
          maximumRedirects: maximumRedirects,
        ),
      );
      unawaited(refresh.whenComplete(() => _weeklyRevalidations.remove(key)));
      _recordCacheState();
      return cached.value;
    }
    OnlinePerformanceScope.session?.cacheMissCount++;
    final conditional = <String, String>{...headers};
    if (cached?.etag != null) {
      OnlinePerformanceScope.session?.recordCoordinatorEvent('revalidation');
      conditional['If-None-Match'] = cached!.etag!;
    }
    if (cached?.lastModified != null) {
      OnlinePerformanceScope.session?.recordCoordinatorEvent('revalidation');
      conditional['If-Modified-Since'] = cached!.lastModified!;
    }
    for (var retry = 0; ; retry++) {
      throwIfMetadataRequestCancelled();
      try {
        final response = await _inner.get(
          location: location,
          headers: conditional,
          timeout: timeout,
          maximumResponseBytes: maximumResponseBytes,
          maximumRedirects: maximumRedirects,
        );
        if (response.statusCode == 304 && cached != null) {
          OnlinePerformanceScope.session?.recordCoordinatorEvent('cache304');
          _store(key, cached.value, _ttl(location), response.headers);
          _recordCacheState();
          return cached.value;
        }
        if (_retry.shouldRetryStatus(response.statusCode, retry)) {
          OnlinePerformanceScope.session?.recordCoordinatorEvent('retry');
          await _backoff(retry, response.headers['retry-after']);
          continue;
        }
        if (response.statusCode >= 200 && response.statusCode < 300) {
          if (retry > 0) {
            OnlinePerformanceScope.session?.recordCoordinatorEvent(
              'retryCompleted',
            );
          }
          _store(key, response, _ttl(location), response.headers);
          _recordCacheState();
        }
        return response;
      } on RequestCancelledException {
        if (retry > 0) {
          OnlinePerformanceScope.session?.recordCoordinatorEvent(
            'retryCancelled',
          );
        }
        rethrow;
      } on TimeoutException {
        rethrow;
      } on Object {
        if (retry >= _retry.maximumRetries) {
          rethrow;
        }
        await _backoff(retry, null);
      }
    }
  }

  Future<void> _backoff(int retry, String? retryAfter) async {
    final seconds = int.tryParse(retryAfter ?? '');
    if (seconds != null) {
      OnlinePerformanceScope.session?.recordCoordinatorEvent('retryAfter');
    }
    final delay = _retry.delayFor(
      retry,
      retryAfter: seconds == null ? null : Duration(seconds: seconds),
    );
    final token = MetadataRequestScope.current?.token;
    if (token == null) {
      return _wait(delay);
    }
    await Future.any([
      _wait(delay),
      token.whenCancelled.then<void>(
        (reason) => throw RequestCancelledException(reason),
      ),
    ]);
    throwIfMetadataRequestCancelled();
  }

  Duration _ttl(RemoteCatalogLocation location) => _isWeeklyRanking(location)
      ? const Duration(hours: 6)
      : location.uri.path.contains('/metadata/') ||
            location.uri.path.contains('/volumes/') &&
                !location.uri.queryParameters.containsKey('q')
      ? const Duration(minutes: 30)
      : const Duration(minutes: 5);

  bool _isWeeklyRanking(RemoteCatalogLocation location) {
    final uri = location.uri;
    if (uri.host.endsWith('gutenberg.org') &&
        uri.path == '/browse/scores/top-en.html') {
      return true;
    }
    if (uri.host == 'openlibrary.org' && uri.path == '/trending/weekly.json') {
      return true;
    }
    return uri.host == 'archive.org' &&
        uri.path == '/advancedsearch.php' &&
        uri.queryParameters['sort[]'] == 'week desc';
  }

  Future<void> _revalidateWeekly({
    required String key,
    required MetadataMemoryCacheEntry<HttpCatalogResponse> cached,
    required RemoteCatalogLocation location,
    required Map<String, String> headers,
    required Duration timeout,
    required int maximumResponseBytes,
    required int maximumRedirects,
  }) async {
    try {
      final conditional = <String, String>{...headers};
      if (cached.etag != null) conditional['If-None-Match'] = cached.etag!;
      if (cached.lastModified != null) {
        conditional['If-Modified-Since'] = cached.lastModified!;
      }
      final response = await _inner.get(
        location: location,
        headers: conditional,
        timeout: timeout,
        maximumResponseBytes: maximumResponseBytes,
        maximumRedirects: maximumRedirects,
      );
      if (response.statusCode == 304) {
        _store(key, cached.value, _ttl(location), response.headers);
      } else if (response.statusCode >= 200 && response.statusCode < 300) {
        _store(key, response, _ttl(location), response.headers);
      }
    } on Object {
      // Keep the last valid weekly ranking. Provider adapters own the visible
      // error boundary when no cache exists.
    }
  }

  void _store(
    String key,
    HttpCatalogResponse response,
    Duration ttl,
    Map<String, String> headers,
  ) {
    final entry = MetadataMemoryCacheEntry(
      value: response,
      expiresAt: DateTime.now().add(ttl),
      bytes: response.bodyBytes.length,
      etag: headers['etag'],
      lastModified: headers['last-modified'],
    );
    _cache.put(key, entry);
    final disk = diskCache;
    if (disk != null) {
      unawaited(
        disk.writeMetadata(
          key,
          RemoteMetadataCacheEntry(
            bodyBytes: Uint8List.fromList(response.bodyBytes),
            expiresAt: entry.expiresAt,
            etag: entry.etag,
            lastModified: entry.lastModified,
          ),
        ),
      );
    }
  }

  void _recordCacheState() => OnlinePerformanceScope.session?.recordCacheState(
    evictions: _cache.evictionCount,
    bytes: _cache.cachedBytes,
  );
  String _key(
    RemoteCatalogLocation location,
    Map<String, String> headers,
  ) => sha256
      .convert(
        utf8.encode(
          '${location.uri}|${headers.entries.where((e) => e.key.toLowerCase() != 'if-none-match' && e.key.toLowerCase() != 'if-modified-since').map((e) => '${e.key}:${e.value}').join('|')}',
        ),
      )
      .toString();
}

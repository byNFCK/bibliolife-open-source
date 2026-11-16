import 'dart:async';
import 'dart:io';

import 'package:bibliolife/core/network/request_cancellation.dart';
import 'package:bibliolife/core/performance/online_pipeline_performance.dart';
import 'package:flutter/foundation.dart';

import 'package:bibliolife/features/catalog_sources/data/opds1_atom_parser.dart';
import 'package:bibliolife/features/catalog_sources/data/open_search_description_parser.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_payload_parser_dispatcher.dart';
import 'package:bibliolife/features/catalog_sources/data/payload_parser_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';

const remoteCatalogAcceptHeader =
    'application/atom+xml;profile=opds-catalog, application/atom+xml, '
    'application/xml;q=0.9, text/xml;q=0.8';
const remoteCatalogUserAgent = 'BiblioLife/1.0';

class HttpOpdsRemoteCatalogTransport implements RemoteCatalogTransport {
  HttpOpdsRemoteCatalogTransport({
    HttpCatalogClient? client,
    this._parser = const Opds1AtomParser(),
    this.requestTimeout = const Duration(seconds: 15),
    this.maximumResponseBytes = 2 * 1024 * 1024,
    this.maximumRedirects = 5,
    this.parserDispatcher,
  }) : _client = client ?? IoHttpCatalogClient();

  final HttpCatalogClient _client;
  final Opds1AtomParser _parser;
  final Duration requestTimeout;
  final int maximumResponseBytes;
  final int maximumRedirects;
  final MetadataPayloadParserDispatcher? parserDispatcher;

  @override
  Future<RemoteCatalogPage> loadRoot(CatalogSource source) {
    final location = _location(source.baseUri);
    return _load(source.id, location);
  }

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) => _load(source.id, location);

  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) async {
    try {
      var template = capability.location;
      if (!capability.isSupported || template == null) {
        throw const RemoteCatalogException.searchUnsupported();
      }
      if (capability.kind ==
          RemoteCatalogSearchCapabilityKind.openSearchDescription) {
        _logRequest(source.id, 'opensearch-description', template);
        final description = await _client.get(
          location: template,
          headers: const {
            'Accept':
                'application/opensearchdescription+xml, application/xml;q=0.9',
            'User-Agent': remoteCatalogUserAgent,
          },
          timeout: requestTimeout,
          maximumResponseBytes: maximumResponseBytes,
          maximumRedirects: maximumRedirects,
        );
        _logResponse(source.id, 'opensearch-description', description);
        if (description.statusCode != HttpStatus.ok) {
          throw RemoteCatalogException.httpStatus(
            'OpenSearch description returned HTTP ${description.statusCode}.',
          );
        }
        if (description.bodyBytes.isEmpty) {
          throw const RemoteCatalogException.emptyResponse();
        }
        final descriptionBytes = Uint8List.fromList(description.bodyBytes);
        final parsedDescription = parserDispatcher == null
            ? parseOpenSearchDescriptionPayload(
                descriptionBytes,
                baseUri: description.effectiveLocation.toString(),
              )
            : await parserDispatcher!.openSearch(
                descriptionBytes,
                sourceId: source.id,
                baseUri: description.effectiveLocation.toString(),
              );
        template = RemoteCatalogLocation.parse(parsedDescription.template);
        _log(
          'CATALOG_ADAPTER source=${source.id} parser=openSearch template=$template',
        );
      }
      final location = _buildSearchLocation(template, query);
      _log('CATALOG_ADAPTER source=${source.id} parser=opds1 query=$query');
      return await _load(source.id, location, isSearchResult: true);
    } on RequestCancelledException {
      rethrow;
    } on RemoteCatalogException {
      rethrow;
    } on TimeoutException {
      throw const RemoteCatalogException.timeout();
    } on HttpCatalogResponseTooLargeException {
      throw const RemoteCatalogException.responseTooLarge();
    } on HttpCatalogInsecureRedirectException {
      throw const RemoteCatalogException.insecureRedirect();
    } on FormatException {
      throw const RemoteCatalogException.malformedSearchDescription();
    } on Object {
      throw const RemoteCatalogException.transport();
    }
  }

  RemoteCatalogLocation _buildSearchLocation(
    RemoteCatalogLocation template,
    String query,
  ) {
    var value = template.toString();
    final required = RegExp('%7BsearchTerms%7D', caseSensitive: false);
    if (!required.hasMatch(value)) {
      throw const RemoteCatalogException.unsupportedSearchTemplate(
        'The search template has no searchTerms parameter.',
      );
    }
    value = value.replaceAll(required, Uri.encodeQueryComponent(query));
    value = value.replaceAll(
      RegExp(
        r'([?&])[^=&]+=%7B(?:startIndex|startPage|count)%3F%7D',
        caseSensitive: false,
      ),
      '',
    );
    if (RegExp('%7B[^}]+%7D', caseSensitive: false).hasMatch(value)) {
      throw const RemoteCatalogException.unsupportedSearchTemplate(
        'The search template contains an unsupported required parameter.',
      );
    }
    return RemoteCatalogLocation.parse(value);
  }

  Future<RemoteCatalogPage> _load(
    String sourceId,
    RemoteCatalogLocation location, {
    bool isSearchResult = false,
  }) async {
    try {
      _logRequest(sourceId, 'opds1', location);
      final response = await _client.get(
        location: location,
        headers: const {
          'Accept': remoteCatalogAcceptHeader,
          'User-Agent': remoteCatalogUserAgent,
        },
        timeout: requestTimeout,
        maximumResponseBytes: maximumResponseBytes,
        maximumRedirects: maximumRedirects,
      );
      _logResponse(sourceId, 'opds1', response);
      if (response.statusCode != HttpStatus.ok) {
        throw RemoteCatalogException.httpStatus(
          'Remote catalog returned HTTP ${response.statusCode}.',
        );
      }
      if (response.bodyBytes.isEmpty) {
        throw const RemoteCatalogException.emptyResponse(
          'Remote catalog returned an empty response.',
        );
      }

      final performance = biblioLifeNetPerfLogsEnabled
          ? OnlinePerformanceScope.session
          : null;
      final parserStopwatch = performance == null
          ? null
          : (Stopwatch()..start());
      throwIfMetadataRequestCancelled();
      try {
        final mappingStopwatch = performance == null
            ? null
            : (Stopwatch()..start());
        final bytes = Uint8List.fromList(response.bodyBytes);
        final parsed = parserDispatcher == null
            ? _parser.parseBytes(
                sourceId: sourceId,
                location: response.effectiveLocation,
                bytes: bytes,
                isSearchResult: isSearchResult,
              )
            : await parserDispatcher!.opds(
                bytes,
                sourceId: sourceId,
                location: response.effectiveLocation,
                search: isSearchResult,
              );
        parserStopwatch?.stop();
        throwIfMetadataRequestCancelled();
        final page = mapParsedOpdsFeedToDomain(parsed);
        throwIfMetadataRequestCancelled();
        mappingStopwatch?.stop();
        performance?.recordParser(
          sourceId: sourceId,
          parser: 'opds1Atom',
          responseBytes: response.bodyBytes.length,
          decode: Duration(microseconds: parsed.diagnostics.decodeMicros),
          parse: Duration(microseconds: parsed.diagnostics.parseMicros),
          extract: Duration(microseconds: parsed.diagnostics.extractMicros),
          mapping: mappingStopwatch?.elapsed ?? Duration.zero,
          itemCount: page.publications.length,
          skippedItemCount: parsed.diagnostics.skippedItemCount,
        );
        return page;
      } on RemoteCatalogException catch (error) {
        _log(
          'CATALOG_PARSE_FAILED source=$sourceId parser=opds1 reason=${error.failure.name}',
        );
        if (_isClearlyIncompatible(response.contentType) &&
            error.failure != RemoteCatalogFailure.malformedCatalogResponse) {
          throw const RemoteCatalogException.unsupportedCatalogFormat(
            'The response is not a supported Atom catalog.',
          );
        }
        rethrow;
      }
    } on RequestCancelledException {
      rethrow;
    } on RemoteCatalogException {
      rethrow;
    } on TimeoutException {
      throw const RemoteCatalogException.timeout(
        'Remote catalog request timed out.',
      );
    } on HttpCatalogResponseTooLargeException {
      throw const RemoteCatalogException.responseTooLarge(
        'Remote catalog response exceeded the size limit.',
      );
    } on HttpCatalogInsecureRedirectException {
      throw const RemoteCatalogException.insecureRedirect(
        'Remote catalog redirected to a non-HTTPS location.',
      );
    } on PayloadParserException catch (error) {
      throw RemoteCatalogException.malformedCatalogResponse(error.detail);
    } on FormatException {
      throw const RemoteCatalogException.malformedCatalogResponse(
        'Remote catalog response is not valid UTF-8.',
      );
    } on Object {
      throw const RemoteCatalogException.transport(
        'Remote catalog transport failed.',
      );
    }
  }

  RemoteCatalogLocation _location(Uri uri) {
    try {
      return RemoteCatalogLocation.fromUri(uri);
    } on FormatException {
      throw const RemoteCatalogException.invalidSourceOrLocation();
    }
  }

  bool _isClearlyIncompatible(String? contentType) {
    final normalized = contentType?.split(';').first.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return false;
    return normalized != 'application/atom+xml' &&
        normalized != 'application/xml' &&
        normalized != 'text/xml' &&
        normalized != 'application/octet-stream' &&
        normalized != 'text/plain';
  }

  void _logRequest(String sourceId, String adapter, RemoteCatalogLocation url) {
    _log(
      'CATALOG_HTTP_REQUEST source=$sourceId adapter=$adapter method=GET url=$url',
    );
  }

  void _logResponse(
    String sourceId,
    String adapter,
    HttpCatalogResponse response,
  ) {
    _log(
      'CATALOG_HTTP_RESPONSE source=$sourceId adapter=$adapter status=${response.statusCode} contentType=${response.contentType ?? 'unknown'} bytes=${response.bodyBytes.length} url=${response.effectiveLocation}${response.redirects.isEmpty ? '' : ' redirects=${response.redirects.join(',')}'}',
    );
  }

  void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }
}

abstract interface class HttpCatalogClient {
  Future<HttpCatalogResponse> get({
    required RemoteCatalogLocation location,
    required Map<String, String> headers,
    required Duration timeout,
    required int maximumResponseBytes,
    required int maximumRedirects,
  });
}

class HttpCatalogResponse {
  const HttpCatalogResponse({
    required this.statusCode,
    required this.bodyBytes,
    required this.effectiveLocation,
    this.contentType,
    this.headers = const {},
    this.redirects = const [],
  });

  final int statusCode;
  final List<int> bodyBytes;
  final RemoteCatalogLocation effectiveLocation;
  final String? contentType;
  final Map<String, String> headers;
  final List<RemoteCatalogLocation> redirects;
}

class IoHttpCatalogClient implements HttpCatalogClient {
  IoHttpCatalogClient({Duration idleTimeout = const Duration(seconds: 30)})
    : _client = HttpClient()
        ..autoUncompress = true
        ..idleTimeout = idleTimeout;

  final HttpClient _client;
  var _closed = false;

  void close({bool force = false}) {
    if (_closed) return;
    _closed = true;
    _client.close(force: force);
  }

  @override
  Future<HttpCatalogResponse> get({
    required RemoteCatalogLocation location,
    required Map<String, String> headers,
    required Duration timeout,
    required int maximumResponseBytes,
    required int maximumRedirects,
  }) async {
    final cancellation = MetadataRequestScope.current?.token;
    if (cancellation?.isCancelled ?? false) {
      throw RequestCancelledException(cancellation!.reason!);
    }
    if (_closed) {
      throw StateError('The catalog HTTP client has already been disposed.');
    }
    final metric = biblioLifeNetPerfLogsEnabled
        ? OnlinePerformanceScope.session?.networkStarted(
            sourceId: OnlinePerformanceScope.sourceId,
            method: 'GET',
            uri: location.uri,
          )
        : null;
    HttpClientRequest? activeRequest;
    var cancelled = false;
    final removeCancellationListener = cancellation?.addListener((_) {
      cancelled = true;
      activeRequest?.abort();
    });
    try {
      var current = location;
      final redirects = <RemoteCatalogLocation>[];
      for (var redirectCount = 0; ; redirectCount++) {
        _throwIfCancelled(cancellation, cancelled);
        activeRequest = await _client.getUrl(current.uri).timeout(timeout);
        _throwIfCancelled(cancellation, cancelled, activeRequest);
        final request = activeRequest;
        request.followRedirects = false;
        headers.forEach(request.headers.set);
        final response = await request.close().timeout(timeout);
        _throwIfCancelled(cancellation, cancelled, request);

        if (response.isRedirect) {
          if (redirectCount >= maximumRedirects) {
            throw const HttpException('Too many redirects.');
          }
          final redirect = response.headers.value(HttpHeaders.locationHeader);
          if (redirect == null) {
            throw const HttpException('Redirect has no Location header.');
          }
          try {
            current = current.resolve(redirect);
            redirects.add(current);
          } on FormatException {
            throw const HttpCatalogInsecureRedirectException();
          }
          await response.drain<void>();
          _throwIfCancelled(cancellation, cancelled, request);
          continue;
        }

        final bytes = await _readBody(
          response,
          timeout: timeout,
          maximumResponseBytes: maximumResponseBytes,
          cancellation: cancellation,
          isCancelled: () => cancelled,
          activeRequest: request,
        );
        final responseHeaders = <String, String>{};
        response.headers.forEach((name, values) {
          if (values.isNotEmpty) {
            responseHeaders[name.toLowerCase()] = values.first;
          }
        });
        final result = HttpCatalogResponse(
          statusCode: response.statusCode,
          bodyBytes: bytes,
          effectiveLocation: current,
          contentType: response.headers.value(HttpHeaders.contentTypeHeader),
          headers: responseHeaders,
          redirects: redirects,
        );
        metric?.completed(
          statusCode: result.statusCode,
          responseBytes: result.bodyBytes.length,
        );
        return result;
      }
    } on Object catch (error) {
      if (cancelled || cancellation?.isCancelled == true) {
        OnlinePerformanceScope.session?.recordCoordinatorEvent('aborted');
        if (biblioLifeNetPerfVerboseLogsEnabled) {
          debugPrint(
            'REQUEST_TRANSPORT_ABORTED source=${OnlinePerformanceScope.sourceId} uri=${sanitizedUri(location.uri)} reason=${cancellation!.reason!.name}',
          );
        }
        throw RequestCancelledException(cancellation!.reason!);
      }
      if (error is TimeoutException) {
        activeRequest?.abort();
        OnlinePerformanceScope.session?.recordCoordinatorEvent('timeout');
      }
      metric?.failed(error.runtimeType.toString());
      rethrow;
    } finally {
      removeCancellationListener?.call();
    }
  }

  void _throwIfCancelled(
    CancellationToken? cancellation,
    bool cancelled, [
    HttpClientRequest? request,
  ]) {
    if (!cancelled && cancellation?.isCancelled != true) return;
    request?.abort();
    throw RequestCancelledException(
      cancellation?.reason ?? RequestCancellationReason.parentCancelled,
    );
  }

  Future<List<int>> _readBody(
    HttpClientResponse response, {
    required Duration timeout,
    required int maximumResponseBytes,
    required CancellationToken? cancellation,
    required bool Function() isCancelled,
    required HttpClientRequest activeRequest,
  }) {
    final bytes = <int>[];
    final result = Completer<List<int>>();
    late StreamSubscription<List<int>> subscription;
    void cancel(RequestCancellationReason reason) {
      activeRequest.abort();
      unawaited(subscription.cancel());
      if (!result.isCompleted) {
        result.completeError(RequestCancelledException(reason));
      }
    }

    final removeCancellationListener = cancellation?.addListener(cancel);
    subscription = response
        .timeout(timeout)
        .listen(
          (chunk) {
            if (isCancelled() || cancellation?.isCancelled == true) {
              cancel(
                cancellation?.reason ??
                    RequestCancellationReason.parentCancelled,
              );
              return;
            }
            if (bytes.length + chunk.length > maximumResponseBytes) {
              unawaited(subscription.cancel());
              if (!result.isCompleted) {
                result.completeError(
                  const HttpCatalogResponseTooLargeException(),
                );
              }
              return;
            }
            bytes.addAll(chunk);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!result.isCompleted) result.completeError(error, stackTrace);
          },
          onDone: () {
            if (!result.isCompleted) result.complete(bytes);
          },
          cancelOnError: true,
        );
    return result.future.whenComplete(() => removeCancellationListener?.call());
  }
}

class HttpCatalogResponseTooLargeException implements Exception {
  const HttpCatalogResponseTooLargeException();
}

class HttpCatalogInsecureRedirectException implements Exception {
  const HttpCatalogInsecureRedirectException();
}

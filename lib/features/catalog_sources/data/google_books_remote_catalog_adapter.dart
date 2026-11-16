import 'dart:async';
import 'dart:convert';

import 'package:bibliolife/core/network/request_cancellation.dart';
import 'package:bibliolife/core/performance/online_pipeline_performance.dart';
import 'package:bibliolife/features/catalog_sources/data/http_opds_remote_catalog_transport.dart';
import 'package:bibliolife/features/catalog_sources/data/google_books_payload_parser.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_payload_parser_dispatcher.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_parsing_policy.dart';
import 'package:bibliolife/features/catalog_sources/data/payload_parser_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/google_books_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_access_hint.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:bibliolife/features/home/domain/models/home_feed_ranking.dart';
import 'package:flutter/foundation.dart';

const googleBooksApiKey = String.fromEnvironment('GOOGLE_BOOKS_API_KEY');
const _googleBooksPageSize = 40;

typedef GoogleBooksPerformanceMarker =
    void Function(String name, {Map<String, Object?> fields});

typedef GoogleBooksPublicationMapper =
    RemoteCatalogPublicationSummary? Function(ParsedGoogleBook item);

class GoogleBooksRemoteCatalogAdapter implements RemoteCatalogTransport {
  GoogleBooksRemoteCatalogAdapter({
    HttpCatalogClient? client,
    this.apiKey = googleBooksApiKey,
    this.requestTimeout = const Duration(seconds: 15),
    this.maximumResponseBytes = 2 * 1024 * 1024,
    this.maximumRedirects = 5,
    DateTime Function()? now,
    Future<void> Function(Duration)? wait,
    this._debugLog,
    this.parserDispatcher,
    GoogleBooksPerformanceMarker? performanceMarker,
    this.publicationMapper,
  }) : _client = client ?? IoHttpCatalogClient(),
       _now = now ?? DateTime.now,
       _wait = wait ?? Future<void>.delayed,
       _performanceMarker = performanceMarker ?? onlinePerformanceMarker;

  final HttpCatalogClient _client;
  final MetadataPayloadParserDispatcher? parserDispatcher;
  final String apiKey;
  final Duration requestTimeout;
  final int maximumResponseBytes;
  final int maximumRedirects;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _wait;
  final void Function(String)? _debugLog;
  final GoogleBooksPerformanceMarker _performanceMarker;
  final GoogleBooksPublicationMapper? publicationMapper;
  DateTime? _retryNotBefore;
  var _configurationLogged = false;

  @override
  Future<RemoteCatalogPage> loadRoot(CatalogSource source) => _loadSearch(
    source,
    query: 'subject:fiction',
    startIndex: 0,
    discovery: true,
  );

  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) {
    return _loadSearch(source, query: query, startIndex: 0);
  }

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) async {
    final path = location.uri.path;
    if (path.startsWith('/books/v1/volumes/') &&
        path.length > '/books/v1/volumes/'.length) {
      final page = await _load(source, location.uri, details: true);
      return page;
    }
    final parameters = location.uri.queryParameters;
    final query = parameters['q'];
    if (query == null || query.trim().isEmpty) {
      throw const RemoteCatalogException.invalidSourceOrLocation(
        'Google Books page has no query cursor.',
      );
    }
    final startIndex = int.tryParse(parameters['startIndex'] ?? '') ?? 0;
    return _loadSearch(
      source,
      query: query,
      startIndex: startIndex,
      discovery: query == 'subject:fiction',
    );
  }

  Future<RemoteCatalogPage> _loadSearch(
    CatalogSource source, {
    required String query,
    required int startIndex,
    bool discovery = false,
  }) => _load(
    source,
    source.baseUri.replace(
      queryParameters: _parameters({
        'q': query,
        'startIndex': '$startIndex',
        'maxResults': '$_googleBooksPageSize',
        // The official API exposes relevance/newest only.  Home discovery is
        // explicitly provider relevance, never a fabricated weekly ranking.
        'orderBy': 'relevance',
        'printType': 'books',
        'projection': 'full',
      }),
    ),
    query: query,
    startIndex: startIndex,
    discovery: discovery,
  );

  Future<RemoteCatalogPage> _load(
    CatalogSource source,
    Uri uri, {
    String? query,
    int? startIndex,
    bool details = false,
    bool discovery = false,
  }) async {
    var stage = 'configuration';
    try {
      _marker('google_load_started');
      _logConfiguration();
      if (!apiKeyPresent) {
        final failure = GoogleBooksRequestException(
          category: GoogleBooksFailureCategory.apiKeyMissing,
          statusCode: 0,
        );
        _log(
          'GOOGLE_BOOKS_REQUEST_BUILD_FAILED category=${failure.category.name} apiKeyPresent=false detail=compileTimeKeyMissing',
        );
        _marker(
          'google_early_exit',
          fields: {'reason': 'missing_configuration'},
        );
        throw failure;
      }
      late Uri requestedUri;
      try {
        requestedUri = _withApiKey(uri);
      } on Object {
        final failure = GoogleBooksRequestException(
          category: GoogleBooksFailureCategory.requestConstructionFailed,
          statusCode: 0,
        );
        _log(
          'GOOGLE_BOOKS_REQUEST_BUILD_FAILED category=requestConstructionFailed apiKeyPresent=true detail=invalidRequestUri',
        );
        _marker('google_early_exit', fields: {'reason': 'other'});
        throw failure;
      }
      var attempt = 0;
      late HttpCatalogResponse response;
      while (true) {
        final cooldown = _retryNotBefore;
        if (cooldown != null && _now().isBefore(cooldown)) {
          _marker('google_early_exit', fields: {'reason': 'cooldown'});
          throw GoogleBooksRequestException(
            category: GoogleBooksFailureCategory.rateLimitExceeded,
            statusCode: 429,
            retryAfter: cooldown.difference(_now()),
          );
        }
        final location = RemoteCatalogLocation.fromUri(requestedUri);
        stage = 'http';
        final cacheHits = OnlinePerformanceScope.session?.cacheHitCount;
        _marker('google_http_started');
        response = await _client.get(
          location: location,
          headers: const {
            'Accept': 'application/json',
            'User-Agent': remoteCatalogUserAgent,
          },
          timeout: requestTimeout,
          maximumResponseBytes: maximumResponseBytes,
          maximumRedirects: maximumRedirects,
        );
        final cache =
            cacheHits != null &&
                OnlinePerformanceScope.session?.cacheHitCount == cacheHits + 1
            ? 'hit'
            : 'miss';
        _marker(
          'google_http_completed',
          fields: {
            'status': response.statusCode,
            'bytes': response.bodyBytes.length,
            'cache': cache,
          },
        );
        if (response.statusCode == 200) break;
        final failure = _googleFailure(response);
        _logGoogleFailure(failure);
        if (failure.isTransient && attempt == 0) {
          final delay = failure.retryAfter ?? _backoff(attempt);
          _retryNotBefore = _now().add(delay);
          attempt++;
          await _waitForRetry(delay);
          _retryNotBefore = null;
          continue;
        }
        if (!failure.isTransient) {
          _retryNotBefore = _now().add(_configurationCooldown(failure));
        }
        throw failure;
      }
      final performance = biblioLifeNetPerfLogsEnabled
          ? OnlinePerformanceScope.session
          : null;
      throwIfMetadataRequestCancelled();
      if (response.bodyBytes.isEmpty) {
        _marker('google_early_exit', fields: {'reason': 'empty_response'});
        throw const RemoteCatalogException.malformedCatalogResponse(
          'Google Books returned invalid JSON.',
        );
      }
      final bytes = Uint8List.fromList(response.bodyBytes);
      stage = 'parse';
      final path = parserDispatcher == null ? 'direct' : 'dispatcher';
      final execution =
          parserDispatcher != null &&
              parserDispatcher!.policy.shouldUseBackground(
                MetadataParserType.googleBooks,
                bytes.length,
              ) &&
              MetadataRequestScope.current?.token != null
          ? 'background'
          : 'local';
      _marker('google_parse_started', fields: {'path': path});
      final parsed = parserDispatcher == null
          ? parseGoogleBooksPayload(bytes, details: details)
          : await parserDispatcher!.google(
              bytes,
              sourceId: source.id,
              details: details,
            );
      _marker(
        'google_parse_completed',
        fields: {
          'bytes': bytes.length,
          'execution': execution,
          'path': path,
          'parseMicros': parsed.diagnostics.parseMicros,
        },
      );
      throwIfMetadataRequestCancelled();
      stage = 'mapping';
      final mappingStopwatch = performance == null
          ? null
          : (Stopwatch()..start());
      final publications = <RemoteCatalogPublicationSummary>[];
      final acceptedIds = <String>{};
      for (final item in parsed.books) {
        throwIfMetadataRequestCancelled();
        final publication = publicationMapper?.call(item) ?? _publication(item);
        if (publication != null && acceptedIds.add(publication.remoteId)) {
          publications.add(publication);
        }
      }
      mappingStopwatch?.stop();
      _marker(
        'google_mapping_completed',
        fields: {'records': publications.length},
      );
      performance?.recordParser(
        sourceId: source.id,
        parser: 'googleBooksJson',
        responseBytes: response.bodyBytes.length,
        itemCount: publications.length,
        decode: Duration(microseconds: parsed.diagnostics.decodeMicros),
        parse: Duration(microseconds: parsed.diagnostics.parseMicros),
        extract: Duration(microseconds: parsed.diagnostics.extractMicros),
        mapping: mappingStopwatch?.elapsed ?? Duration.zero,
        skippedItemCount: parsed.diagnostics.skippedItemCount,
      );
      final total = parsed.totalItems;
      final current = startIndex ?? 0;
      final next =
          !details &&
              publications.isNotEmpty &&
              (parsed.books.length >= _googleBooksPageSize ||
                  current + parsed.books.length < total)
          ? _searchLocation(
              source.baseUri,
              query!,
              current + _googleBooksPageSize,
            )
          : null;
      _marker(
        'google_source_completed',
        fields: {'records': publications.length},
      );
      return RemoteCatalogPage(
        sourceId: source.id,
        location: response.effectiveLocation,
        title: details ? 'Google Books details' : 'Google Books search',
        publications: publications,
        nextPageLocation: next,
        searchCapability: RemoteCatalogSearchCapability.directTemplate(
          RemoteCatalogLocation.fromUri(source.baseUri),
        ),
        homeRanking: discovery ? const HomeFeedRanking.googleRelevance() : null,
      );
    } on RequestCancelledException {
      _marker('google_early_exit', fields: {'reason': 'cancelled'});
      rethrow;
    } on RemoteCatalogException catch (error) {
      _sourceFailed(stage, error);
      rethrow;
    } on TimeoutException catch (error) {
      _sourceFailed(stage, error);
      throw const RemoteCatalogException.timeout();
    } on PayloadParserException catch (error) {
      _sourceFailed('parse', error);
      throw const RemoteCatalogException.malformedCatalogResponse(
        'Google Books returned invalid JSON.',
      );
    } on FormatException catch (error) {
      _sourceFailed('parse', error);
      throw const RemoteCatalogException.malformedCatalogResponse(
        'Google Books returned invalid JSON.',
      );
    } on Object catch (error) {
      _sourceFailed(stage, error);
      throw const RemoteCatalogException.transport();
    }
  }

  void _marker(String name, {Map<String, Object?> fields = const {}}) =>
      _performanceMarker(name, fields: fields);

  void _sourceFailed(String stage, Object error) => _marker(
    'google_source_failed',
    fields: {'stage': stage, 'errorType': error.runtimeType},
  );

  RemoteCatalogLocation _searchLocation(
    Uri base,
    String query,
    int startIndex,
  ) => RemoteCatalogLocation.fromUri(
    base.replace(
      queryParameters: _parameters({
        'q': query,
        'startIndex': '$startIndex',
        'maxResults': '$_googleBooksPageSize',
        'orderBy': 'relevance',
        'printType': 'books',
        'projection': 'full',
      }),
    ),
  );

  Map<String, String> _parameters(Map<String, String> values) => {
    ...values,
    if (apiKey.trim().isNotEmpty) 'key': apiKey.trim(),
  };

  bool get apiKeyPresent => apiKey.trim().isNotEmpty;

  Uri _withApiKey(Uri uri) =>
      uri.replace(queryParameters: _parameters(uri.queryParameters));

  GoogleBooksRequestException _googleFailure(HttpCatalogResponse response) {
    final retryAfter = _retryAfter(response.headers['retry-after']);
    if (!apiKeyPresent) {
      return GoogleBooksRequestException(
        category: GoogleBooksFailureCategory.apiKeyMissing,
        statusCode: response.statusCode,
        retryAfter: retryAfter,
      );
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['error'] is! Map) {
        return GoogleBooksRequestException(
          category: GoogleBooksFailureCategory.malformedGoogleError,
          statusCode: response.statusCode,
          retryAfter: retryAfter,
        );
      }
      final error = (decoded['error'] as Map).cast<String, dynamic>();
      final status = _short(error['status']);
      final reasons = error['errors'] is List
          ? (error['errors'] as List)
                .whereType<Map>()
                .map((item) => _short(item['reason']))
                .whereType<String>()
                .toList()
          : const <String>[];
      final reason = reasons.firstOrNull;
      final joined =
          '${status ?? ''} ${reason ?? ''} ${_short(error['message']) ?? ''}'
              .toLowerCase();
      final category =
          joined.contains('keyinvalid') || joined.contains('api key not valid')
          ? GoogleBooksFailureCategory.apiKeyInvalid
          : joined.contains('accessnotconfigured') ||
                joined.contains('service disabled')
          ? GoogleBooksFailureCategory.apiNotEnabled
          : joined.contains('iprefererblocked') ||
                joined.contains('referer') ||
                joined.contains('restriction')
          ? GoogleBooksFailureCategory.apiKeyRestrictionRejected
          : joined.contains('dailylimitexceeded') ||
                joined.contains('daily limit')
          ? GoogleBooksFailureCategory.dailyLimitExceeded
          : joined.contains('quotaexceeded') ||
                joined.contains('quota exceeded')
          ? GoogleBooksFailureCategory.quotaExceeded
          : joined.contains('ratelimitexceeded') ||
                joined.contains('rate limit')
          ? GoogleBooksFailureCategory.rateLimitExceeded
          : joined.contains('resource_exhausted') ||
                joined.contains('resource exhausted')
          ? GoogleBooksFailureCategory.resourceExhausted
          : joined.contains('permissiondenied') ||
                joined.contains('permission denied')
          ? GoogleBooksFailureCategory.permissionDenied
          : GoogleBooksFailureCategory.malformedGoogleError;
      return GoogleBooksRequestException(
        category: category,
        statusCode: response.statusCode,
        googleStatus: status,
        reason: reason,
        retryAfter: retryAfter,
      );
    } on Object {
      return GoogleBooksRequestException(
        category: GoogleBooksFailureCategory.malformedGoogleError,
        statusCode: response.statusCode,
        retryAfter: retryAfter,
      );
    }
  }

  Duration? _retryAfter(String? value) {
    final seconds = int.tryParse(value?.trim() ?? '');
    return seconds == null || seconds < 0 ? null : Duration(seconds: seconds);
  }

  Duration _backoff(int attempt) => Duration(seconds: 1 << attempt);

  Future<void> _waitForRetry(Duration delay) async {
    final token = MetadataRequestScope.current?.token;
    if (token == null) {
      await _wait(delay);
      return;
    }
    await Future.any<void>([
      _wait(delay),
      token.whenCancelled.then<void>(
        (reason) => throw RequestCancelledException(reason),
      ),
    ]);
    throwIfMetadataRequestCancelled();
  }

  Duration _configurationCooldown(GoogleBooksRequestException failure) =>
      switch (failure.category) {
        GoogleBooksFailureCategory.dailyLimitExceeded ||
        GoogleBooksFailureCategory.quotaExceeded => const Duration(minutes: 15),
        _ => const Duration(minutes: 5),
      };

  String? _short(Object? value) {
    if (value is! String) return null;
    final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.isEmpty ? null : text.substring(0, text.length.clamp(0, 120));
  }

  void _logConfiguration() {
    if (_configurationLogged) return;
    _configurationLogged = true;
    final mode = kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug';
    _log(
      'GOOGLE_BOOKS_CONFIGURATION apiKeyPresent=$apiKeyPresent apiKeyLength=${apiKey.trim().length} buildMode=$mode',
    );
  }

  void _logGoogleFailure(GoogleBooksRequestException failure) => _log(
    'GOOGLE_BOOKS_REQUEST_FAILED status=${failure.statusCode} category=${failure.category.name} googleStatus=${failure.googleStatus ?? 'absent'} reason=${failure.reason ?? 'absent'} retryAfterSeconds=${failure.retryAfter?.inSeconds ?? 'absent'} apiKeyAttached=$apiKeyPresent',
  );

  RemoteCatalogPublicationSummary? _publication(ParsedGoogleBook item) {
    final id = item.id;
    final data = item.volume.cast<String, dynamic>();
    final title = data['title'];
    if (title is! String || title.trim().isEmpty) return null;
    final access = item.access.cast<String, dynamic>();
    final sale = item.sale.cast<String, dynamic>();
    final imageLinks = data['imageLinks'] is Map
        ? (data['imageLinks'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final images = <RemoteCatalogLocation>[
      for (final key in const [
        'extraLarge',
        'large',
        'medium',
        'small',
        'thumbnail',
        'smallThumbnail',
      ])
        ..._coverImage(imageLinks[key]),
    ];
    final identifiers = _identifiers(data['industryIdentifiers']);
    return RemoteCatalogPublicationSummary(
      remoteId: id,
      title: title.trim(),
      subtitle: _text(data['subtitle']),
      authors: _strings(data['authors']),
      coverLocation: images.firstOrNull,
      imageCandidates: images,
      summary: _text(data['description']),
      publisher: _text(data['publisher']),
      language: _text(data['language']),
      publishedDate: _text(data['publishedDate']),
      pageCount: (data['pageCount'] as num?)?.toInt(),
      identifiers: identifiers,
      subjects: _strings(data['categories']),
      rights: _text(data['maturityRating']),
      detailsLocation: RemoteCatalogLocation.parse(
        'https://www.googleapis.com/books/v1/volumes/${Uri.encodeComponent(id)}',
      ),
      accessHints: _accessHints(access, sale, data),
      accessMetadata: _accessMetadata(access, sale),
    );
  }

  Map<String, String> _accessMetadata(
    Map<String, dynamic> access,
    Map<String, dynamic> sale,
  ) {
    final epub = access['epub'] is Map
        ? (access['epub'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final pdf = access['pdf'] is Map
        ? (access['pdf'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return {
      ..._metadata('access.viewability', access['viewability']),
      ..._metadata('access.embeddable', access['embeddable']),
      ..._metadata('access.publicDomain', access['publicDomain']),
      ..._metadata(
        'access.textToSpeechPermission',
        access['textToSpeechPermission'],
      ),
      ..._metadata('access.accessViewStatus', access['accessViewStatus']),
      ..._metadata('access.country', access['country']),
      ..._metadata('access.epub.isAvailable', epub['isAvailable']),
      ..._metadata(
        'access.epub.hasDownloadLink',
        _https(epub['downloadLink']) != null,
      ),
      ..._metadata(
        'access.epub.hasAcsToken',
        _https(epub['acsTokenLink']) != null,
      ),
      ..._metadata('access.pdf.isAvailable', pdf['isAvailable']),
      ..._metadata(
        'access.pdf.hasDownloadLink',
        _https(pdf['downloadLink']) != null,
      ),
      ..._metadata('sale.saleability', sale['saleability']),
      ..._metadata('sale.isEbook', sale['isEbook']),
      ..._priceMetadata('sale.listPrice', sale['listPrice']),
      ..._priceMetadata('sale.retailPrice', sale['retailPrice']),
    };
  }

  Map<String, String> _metadata(String key, Object? value) => switch (value) {
    String text when text.trim().isNotEmpty => {key: text.trim()},
    bool flag => {key: '$flag'},
    num number => {key: '$number'},
    _ => const {},
  };

  Map<String, String> _priceMetadata(String prefix, Object? value) {
    if (value is! Map) return const {};
    return {
      ..._metadata('$prefix.amount', value['amount']),
      ..._metadata('$prefix.currencyCode', value['currencyCode']),
    };
  }

  List<RemoteCatalogAccessHint> _accessHints(
    Map<String, dynamic> access,
    Map<String, dynamic> sale,
    Map<String, dynamic> volume,
  ) {
    final result = <RemoteCatalogAccessHint>[];
    final country = _text(access['country']);
    final epub = access['epub'] is Map
        ? (access['epub'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final pdf = access['pdf'] is Map
        ? (access['pdf'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    // Google often reports epub.isAvailable for an ACS-protected or
    // authenticated file.  Only a public-domain, full-view download without
    // an ACS token is a direct EPUB candidate; final ZIP validation still
    // happens in the established download pipeline.
    final epubDownload = _https(epub['downloadLink']);
    final acsToken = _https(epub['acsTokenLink']);
    final viewability = _text(access['viewability'])?.toUpperCase();
    final viewStatus = _text(access['accessViewStatus'])?.toUpperCase();
    final publicDomain = access['publicDomain'] == true;
    final fullPublicView =
        publicDomain &&
        (viewability == 'ALL_PAGES' || viewStatus == 'FULL_PUBLIC_DOMAIN');
    if (epub['isAvailable'] == true &&
        epubDownload != null &&
        acsToken == null &&
        fullPublicView) {
      result.add(
        RemoteCatalogAccessHint(
          type: RemoteCatalogAccessType.directDownload,
          uri: epubDownload.uri,
          mediaType: 'application/epub+zip',
          isFullBook: true,
          isDrmFree: true,
          country: country,
        ),
      );
    } else if (epub['isAvailable'] == true && epubDownload != null) {
      result.add(
        RemoteCatalogAccessHint(
          type: RemoteCatalogAccessType.authenticatedDownload,
          uri: epubDownload.uri,
          mediaType: 'application/epub+zip',
          requiresAuthentication: true,
          country: country,
        ),
      );
    }
    if (acsToken case final uri?) {
      result.add(
        RemoteCatalogAccessHint(
          type: RemoteCatalogAccessType.authenticatedDownload,
          uri: uri.uri,
          mediaType: 'application/epub+zip',
          requiresAuthentication: true,
          country: country,
        ),
      );
    }
    final pdfDownload = _https(pdf['downloadLink']);
    if (pdf['isAvailable'] == true && pdfDownload != null && fullPublicView) {
      result.add(
        RemoteCatalogAccessHint(
          type: RemoteCatalogAccessType.directDownload,
          uri: pdfDownload.uri,
          mediaType: 'application/pdf',
          isFullBook: true,
          isDrmFree: true,
          country: country,
        ),
      );
    } else if (pdf['isAvailable'] == true && pdfDownload != null) {
      result.add(
        RemoteCatalogAccessHint(
          type: RemoteCatalogAccessType.authenticatedDownload,
          uri: pdfDownload.uri,
          mediaType: 'application/pdf',
          requiresAuthentication: true,
          country: country,
        ),
      );
    }
    if (_https(volume['previewLink']) case final uri?) {
      result.add(
        RemoteCatalogAccessHint(
          type: RemoteCatalogAccessType.preview,
          uri: uri.uri,
          country: country,
        ),
      );
    }
    if (_https(access['webReaderLink']) case final uri?) {
      result.add(
        RemoteCatalogAccessHint(
          type: RemoteCatalogAccessType.externalRead,
          uri: uri.uri,
          country: country,
        ),
      );
    }
    if (_https(volume['infoLink']) case final uri?) {
      result.add(
        RemoteCatalogAccessHint(
          type: RemoteCatalogAccessType.externalRead,
          uri: uri.uri,
          country: country,
        ),
      );
    }
    if (_https(sale['buyLink']) case final uri?) {
      result.add(
        RemoteCatalogAccessHint(
          type: RemoteCatalogAccessType.purchase,
          uri: uri.uri,
          country: country,
        ),
      );
    }
    return result;
  }

  List<String> _identifiers(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value.whereType<Map>())
        if (item['type'] is String && item['identifier'] is String)
          '${item['type']}:${item['identifier']}',
    ];
  }

  List<String> _strings(Object? value) => value is List
      ? value
            .whereType<String>()
            .where((item) => item.trim().isNotEmpty)
            .toList()
      : const [];

  String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  RemoteCatalogLocation? _https(Object? value) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return null;
    try {
      return RemoteCatalogLocation.fromUri(uri);
    } on FormatException {
      return null;
    }
  }

  List<RemoteCatalogLocation> _coverImage(Object? value) {
    if (value is! String) return const [];
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.host.isEmpty) return const [];
    final host = uri.host.toLowerCase();
    final normalized = uri.scheme.toLowerCase() == 'https'
        ? uri
        : uri.scheme.toLowerCase() == 'http' && _isGoogleCoverHost(host)
        ? uri.replace(scheme: 'https')
        : null;
    if (normalized == null) return const [];
    RemoteCatalogLocation? image;
    try {
      image = RemoteCatalogLocation.fromUri(normalized);
    } on FormatException {
      image = null;
    }
    return image == null ? const [] : [image];
  }

  bool _isGoogleCoverHost(String host) =>
      host == 'books.google.com' || host == 'books.googleusercontent.com';

  void _log(String message) {
    if (!kDebugMode) return;
    final log = _debugLog;
    if (log != null) {
      log(message);
    } else {
      debugPrint(message);
    }
  }
}

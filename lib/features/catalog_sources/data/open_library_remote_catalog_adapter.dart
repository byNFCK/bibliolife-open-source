import 'dart:async';

import 'package:bibliolife/core/network/request_cancellation.dart';
import 'package:bibliolife/core/performance/online_pipeline_performance.dart';
import 'package:bibliolife/features/catalog_sources/data/http_opds_remote_catalog_transport.dart';
import 'package:bibliolife/features/catalog_sources/data/open_library_payload_parser.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_payload_parser_dispatcher.dart';
import 'package:bibliolife/features/catalog_sources/data/payload_parser_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:bibliolife/features/home/domain/models/home_feed_ranking.dart';
import 'package:flutter/foundation.dart';

class OpenLibraryRemoteCatalogAdapter implements RemoteCatalogTransport {
  OpenLibraryRemoteCatalogAdapter({
    HttpCatalogClient? client,
    this.requestTimeout = const Duration(seconds: 15),
    this.maximumResponseBytes = 2 * 1024 * 1024,
    this.maximumRedirects = 5,
    this.parserDispatcher,
  }) : _client = client ?? IoHttpCatalogClient();

  final HttpCatalogClient _client;
  final MetadataPayloadParserDispatcher? parserDispatcher;
  final Duration requestTimeout;
  final int maximumResponseBytes;
  final int maximumRedirects;

  static final _searchTemplate = RemoteCatalogLocation.parse(
    'https://openlibrary.org/search.json?q=%7BsearchTerms%7D',
  );

  @override
  Future<RemoteCatalogPage> loadRoot(CatalogSource source) => _load(
    source,
    Uri.https('openlibrary.org', '/trending/weekly.json', {
      'limit': '40',
      'offset': '0',
    }),
    weeklyTrending: true,
  );

  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) =>
      _load(source, _searchTemplate.uri.replace(queryParameters: {'q': query}));

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) => _load(
    source,
    location.uri,
    weeklyTrending: location.uri.path == '/trending/weekly.json',
  );

  Future<RemoteCatalogPage> _load(
    CatalogSource source,
    Uri uri, {
    bool weeklyTrending = false,
  }) async {
    final location = RemoteCatalogLocation.fromUri(uri);
    try {
      _log(
        'CATALOG_HTTP_REQUEST source=${source.id} adapter=openLibraryJson method=GET url=$location',
      );
      final response = await _client.get(
        location: location,
        headers: const {
          'Accept': 'application/json',
          'User-Agent': remoteCatalogUserAgent,
        },
        timeout: requestTimeout,
        maximumResponseBytes: maximumResponseBytes,
        maximumRedirects: maximumRedirects,
      );
      _log(
        'CATALOG_HTTP_RESPONSE source=${source.id} adapter=openLibraryJson status=${response.statusCode} contentType=${response.contentType ?? 'unknown'} bytes=${response.bodyBytes.length} url=${response.effectiveLocation}${response.redirects.isEmpty ? '' : ' redirects=${response.redirects.join(',')}'}',
      );
      if (response.statusCode != 200) {
        throw RemoteCatalogException.httpStatus(
          'Open Library returned HTTP ${response.statusCode}.',
        );
      }
      final performance = biblioLifeNetPerfLogsEnabled
          ? OnlinePerformanceScope.session
          : null;
      throwIfMetadataRequestCancelled();
      final bytes = Uint8List.fromList(response.bodyBytes);
      final parsed = parserDispatcher == null
          ? parseOpenLibraryPayload(bytes)
          : await parserDispatcher!.openLibrary(bytes, sourceId: source.id);
      throwIfMetadataRequestCancelled();
      final mappingStopwatch = performance == null
          ? null
          : (Stopwatch()..start());
      final publications = <RemoteCatalogPublicationSummary>[];
      for (var index = 0; index < parsed.documents.length; index++) {
        throwIfMetadataRequestCancelled();
        final publication = _publication(parsed.documents[index]);
        if (publication != null) {
          publications.add(
            weeklyTrending
                ? publication.copyWith(
                    homeRanking: HomeFeedPublicationRanking(
                      rank:
                          (int.tryParse(uri.queryParameters['offset'] ?? '') ??
                              0) +
                          index +
                          1,
                      method: HomeFeedRankingMethod.weeklyPopularity,
                      evidence: HomeFeedRankingEvidence.exactProviderReported,
                      period: const Duration(days: 7),
                    ),
                  )
                : publication,
          );
        }
      }
      mappingStopwatch?.stop();
      performance?.recordParser(
        sourceId: source.id,
        parser: 'openLibraryJson',
        responseBytes: response.bodyBytes.length,
        itemCount: publications.length,
        decode: Duration(microseconds: parsed.diagnostics.decodeMicros),
        parse: Duration(microseconds: parsed.diagnostics.parseMicros),
        extract: Duration(microseconds: parsed.diagnostics.extractMicros),
        mapping: mappingStopwatch?.elapsed ?? Duration.zero,
        skippedItemCount: parsed.diagnostics.skippedItemCount,
      );
      _log(
        'OPEN_LIBRARY_RECORD_MAPPED source=${source.id} sourceRecordCount=${publications.length}',
      );
      final next = weeklyTrending
          ? (parsed.documents.length == 40
                ? _nextTrendingLocation(response.effectiveLocation.uri)
                : null)
          : parsed.start + parsed.documents.length < parsed.numFound
          ? _nextLocation(response.effectiveLocation.uri)
          : null;
      return RemoteCatalogPage(
        sourceId: source.id,
        location: response.effectiveLocation,
        title: weeklyTrending
            ? 'Open Library weekly trending'
            : 'Open Library search',
        publications: publications,
        nextPageLocation: next,
        searchCapability: RemoteCatalogSearchCapability.directTemplate(
          _searchTemplate,
        ),
        homeRanking: weeklyTrending
            ? const HomeFeedRanking.weeklyPopularity()
            : null,
      );
    } on RequestCancelledException {
      rethrow;
    } on RemoteCatalogException {
      rethrow;
    } on TimeoutException {
      throw const RemoteCatalogException.timeout();
    } on PayloadParserException catch (error) {
      _log(
        'CATALOG_PARSE_FAILED source=${source.id} parser=openLibraryJson reason=${error.kind.name}',
      );
      throw const RemoteCatalogException.malformedCatalogResponse(
        'Open Library returned invalid JSON.',
      );
    } on Object catch (error) {
      _log(
        'OPEN_LIBRARY_RECORD_SKIPPED source=${source.id} reason=${error.runtimeType}',
      );
      throw const RemoteCatalogException.transport();
    }
  }

  RemoteCatalogLocation _nextLocation(Uri current) {
    final page = int.tryParse(current.queryParameters['page'] ?? '') ?? 1;
    return RemoteCatalogLocation.fromUri(
      current.replace(
        queryParameters: {...current.queryParameters, 'page': '${page + 1}'},
      ),
    );
  }

  RemoteCatalogLocation _nextTrendingLocation(Uri current) {
    final offset = int.tryParse(current.queryParameters['offset'] ?? '') ?? 0;
    return RemoteCatalogLocation.fromUri(
      current.replace(
        queryParameters: {
          ...current.queryParameters,
          'offset': '${offset + 40}',
        },
      ),
    );
  }

  RemoteCatalogPublicationSummary? _publication(
    ParsedOpenLibraryDocument parsed,
  ) {
    final document = parsed.fields.cast<String, dynamic>();
    final key = document['key'];
    final title = document['title'];
    if (key is! String || key.isEmpty || title is! String || title.isEmpty) {
      return null;
    }
    final coverId = document['cover_i'];
    final coverEditionKey = _text(document['cover_edition_key']);
    final details = Uri.tryParse('https://openlibrary.org$key');
    final editionKeys = _strings(document['edition_key']);
    final workUrl = details != null && details.scheme == 'https'
        ? RemoteCatalogLocation.fromUri(details)
        : null;
    final cover = _cover(coverId, coverEditionKey);
    return RemoteCatalogPublicationSummary(
      remoteId: key,
      title: title,
      subtitle: _text(document['subtitle']),
      authors: _strings(document['author_name']),
      coverLocation: cover.firstOrNull,
      imageCandidates: cover,
      publisher: _strings(document['publisher']).firstOrNull,
      language: _strings(document['language']).map(_language).firstOrNull,
      publishedDate: _publicationDate(document),
      pageCount: (document['number_of_pages_median'] as num?)?.toInt(),
      subjects: _strings(document['subject']),
      identifiers: _identifiers(document),
      detailsLocation: workUrl,
      sourceLinks: _sourceLinks(workUrl, editionKeys),
      sourceMetadata: {
        'openLibrary.workKey': key,
        ..._optionalMetadata('openLibrary.coverEditionKey', coverEditionKey),
        if (document['first_publish_year'] is num)
          'openLibrary.firstPublishYear':
              '${(document['first_publish_year'] as num).toInt()}',
        if (document['edition_count'] is num)
          'openLibrary.editionCount':
              '${(document['edition_count'] as num).toInt()}',
        if (document['ebook_access'] is String)
          'openLibrary.ebookAccess': document['ebook_access'] as String,
        if (document['has_fulltext'] is bool)
          'openLibrary.hasFulltext': '${document['has_fulltext']}',
      },
      sourceLists: {
        'openLibrary.editionKeys': editionKeys,
        'openLibrary.authorKeys': _strings(document['author_key']),
        'openLibrary.publishYears': _strings(document['publish_year']),
        'openLibrary.publishers': _strings(document['publisher']),
        'openLibrary.languages': _strings(document['language']).map(_language),
        'openLibrary.internetArchiveIds': _strings(document['ia']),
      },
    );
  }

  List<String> _identifiers(Map<String, dynamic> document) => [
    for (final value in _strings(document['isbn'])) 'ISBN:$value',
    for (final value in _strings(document['lccn'])) 'LCCN:$value',
    for (final value in _strings(document['oclc'])) 'OCLC:$value',
    for (final value in _strings(document['ia'])) 'IA:$value',
  ];

  List<RemoteCatalogLocation> _cover(Object? coverId, String? editionKey) => [
    if (coverId is num)
      RemoteCatalogLocation.parse(
        'https://covers.openlibrary.org/b/id/${coverId.toInt()}-L.jpg?default=false',
      )
    else if (editionKey != null)
      RemoteCatalogLocation.parse(
        'https://covers.openlibrary.org/b/olid/$editionKey-L.jpg?default=false',
      ),
  ];

  List<RemoteCatalogLocation> _sourceLinks(
    RemoteCatalogLocation? workUrl,
    Iterable<String> editionKeys,
  ) {
    final editions = <RemoteCatalogLocation>[
      for (final edition in editionKeys.take(1))
        RemoteCatalogLocation.parse('https://openlibrary.org/books/$edition'),
    ];
    return workUrl == null ? editions : [workUrl, ...editions];
  }

  Map<String, String> _optionalMetadata(String key, String? value) =>
      value == null ? const {} : {key: value};

  Iterable<String> _strings(Object? value) => value is List
      ? value.whereType<String>().where((item) => item.trim().isNotEmpty)
      : const <String>[];

  String _language(String value) =>
      value.trim().toLowerCase().replaceAll('_', '-');

  String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  String? _publicationDate(Map<String, dynamic> document) {
    final year = (document['first_publish_year'] as num?)?.toInt();
    if (year != null) return '$year';
    final published = _strings(document['publish_year']).firstOrNull;
    return published;
  }

  void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }
}

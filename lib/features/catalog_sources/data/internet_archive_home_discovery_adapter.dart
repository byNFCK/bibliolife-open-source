import 'dart:async';
import 'dart:convert';

import 'package:bibliolife/core/network/request_cancellation.dart';
import 'package:bibliolife/features/catalog_sources/data/http_opds_remote_catalog_transport.dart';
import 'package:bibliolife/features/catalog_sources/data/internet_archive_acquisition_resolver.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/internet_archive_acquisition.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_acquisition.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:bibliolife/features/home/domain/models/home_feed_ranking.dart';

/// Bounded popular-text discovery for Home only; it exposes no text Search.
class InternetArchiveHomeDiscoveryAdapter implements RemoteCatalogTransport {
  InternetArchiveHomeDiscoveryAdapter({
    HttpCatalogClient? client,
    InternetArchiveAcquisitionResolver? acquisitions,
  }) : _client = client ?? IoHttpCatalogClient(),
       _acquisitions =
           acquisitions ??
           HttpInternetArchiveAcquisitionResolver(client: client);

  final HttpCatalogClient _client;
  final InternetArchiveAcquisitionResolver _acquisitions;
  static const _pageSize = 24;
  static const _verificationConcurrency = 4;

  @override
  Future<RemoteCatalogPage> loadRoot(CatalogSource source) =>
      _loadDiscovery(source, 1);

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) {
    if (location.uri.path.startsWith('/metadata/')) {
      return _loadDetails(source, location);
    }
    return _loadDiscovery(
      source,
      int.tryParse(location.uri.queryParameters['page'] ?? '') ?? 1,
    );
  }

  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) => throw const RemoteCatalogException.searchUnsupported();

  Future<RemoteCatalogPage> _loadDiscovery(
    CatalogSource source,
    int page,
  ) async {
    final location = RemoteCatalogLocation.fromUri(
      Uri.https('archive.org', '/advancedsearch.php', {
        'q':
            'mediatype:texts AND -mediatype:collection AND -access-restricted:true',
        'fl[]': 'identifier,title,creator,year,week',
        'sort[]': 'week desc',
        'sort[1]': 'identifier asc',
        'rows': '$_pageSize',
        'page': '$page',
        'output': 'json',
      }),
    );
    try {
      final response = await _client.get(
        location: location,
        headers: const {'Accept': 'application/json'},
        timeout: const Duration(seconds: 15),
        maximumResponseBytes: 2 * 1024 * 1024,
        maximumRedirects: 5,
      );
      if (response.statusCode != 200) {
        throw RemoteCatalogException.httpStatus(
          'Internet Archive returned HTTP ${response.statusCode}.',
        );
      }
      throwIfMetadataRequestCancelled();
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final result = decoded is Map ? decoded['response'] : null;
      final docs = result is Map && result['docs'] is List
          ? result['docs'] as List
          : const <Object?>[];
      final total = result is Map && result['numFound'] is num
          ? (result['numFound'] as num).toInt()
          : 0;
      final next = page * _pageSize < total
          ? RemoteCatalogLocation.fromUri(
              location.uri.replace(
                queryParameters: {
                  ...location.uri.queryParameters,
                  'page': '${page + 1}',
                },
              ),
            )
          : null;
      final candidates = <RemoteCatalogPublicationSummary>[];
      for (var index = 0; index < docs.length; index++) {
        final publication = _publication(docs[index]);
        if (publication == null) continue;
        final ranking = publication.homeRanking!;
        candidates.add(
          publication.copyWith(
            homeRanking: HomeFeedPublicationRanking(
              rank: (page - 1) * _pageSize + index + 1,
              providerScore: ranking.providerScore,
              period: ranking.period,
              method: ranking.method,
              evidence: ranking.evidence,
            ),
          ),
        );
      }
      if (candidates.isNotEmpty &&
          candidates.every((item) => item.homeRanking?.providerScore == null)) {
        throw const RemoteCatalogException.malformedCatalogResponse(
          'Internet Archive weekly popularity is unavailable.',
        );
      }
      final verified = await _verifyPublicAcquisitions(candidates);
      return RemoteCatalogPage(
        sourceId: source.id,
        location: response.effectiveLocation,
        title: source.name,
        publications: verified,
        nextPageLocation: next,
        homeRanking: const HomeFeedRanking.weeklyPopularity(),
      );
    } on RequestCancelledException {
      rethrow;
    } on RemoteCatalogException {
      rethrow;
    } on TimeoutException {
      throw const RemoteCatalogException.timeout();
    } on FormatException {
      throw const RemoteCatalogException.malformedCatalogResponse(
        'Internet Archive returned invalid JSON.',
      );
    } on Object {
      throw const RemoteCatalogException.transport();
    }
  }

  RemoteCatalogPublicationSummary? _publication(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['identifier'];
    final title = raw['title'];
    if (id is! String ||
        !_safeIdentifier(id) ||
        title is! String ||
        title.trim().isEmpty) {
      return null;
    }
    final weekly = raw['week'];
    final weeklyScore = weekly is num ? weekly : num.tryParse('$weekly');
    if (weeklyScore == null || weeklyScore < 0) return null;
    return RemoteCatalogPublicationSummary(
      remoteId: id,
      title: title.trim(),
      authors: _strings(raw['creator']),
      publishedDate: raw['year']?.toString(),
      coverLocation: RemoteCatalogLocation.parse(
        'https://archive.org/services/img/$id',
      ),
      detailsLocation: RemoteCatalogLocation.parse(
        'https://archive.org/metadata/$id',
      ),
      identifiers: ['IA:$id'],
      sourceMetadata: {
        'internetArchive.identifier': id,
        'internetArchive.weeklyPopularity': '$weeklyScore',
      },
      homeRanking: HomeFeedPublicationRanking(
        providerScore: weeklyScore,
        period: const Duration(days: 7),
        method: HomeFeedRankingMethod.weeklyPopularity,
        evidence: HomeFeedRankingEvidence.exactProviderReported,
      ),
    );
  }

  Future<List<RemoteCatalogPublicationSummary>> _verifyPublicAcquisitions(
    List<RemoteCatalogPublicationSummary> candidates,
  ) async {
    final verified = <RemoteCatalogPublicationSummary>[];
    for (
      var start = 0;
      start < candidates.length;
      start += _verificationConcurrency
    ) {
      final chunk = candidates
          .skip(start)
          .take(_verificationConcurrency)
          .toList(growable: false);
      final resolved = await Future.wait(
        chunk.map((item) async {
          try {
            final result = await _acquisitions.resolve([item.remoteId]);
            return (item, _toAcquisition(result));
          } on RequestCancelledException {
            rethrow;
          } on Object {
            // A single stale or malformed metadata record must not make an
            // otherwise usable weekly page disappear. It is equivalent to an
            // unavailable acquisition and is excluded from Home.
            return (item, null);
          }
        }),
      );
      for (final item in resolved) {
        if (item.$2 case final acquisition?) {
          verified.add(
            RemoteCatalogPublicationSummary(
              remoteId: item.$1.remoteId,
              title: item.$1.title,
              authors: item.$1.authors,
              coverLocation: item.$1.coverLocation,
              detailsLocation: item.$1.detailsLocation,
              identifiers: item.$1.identifiers,
              sourceMetadata: item.$1.sourceMetadata,
              homeRanking: item.$1.homeRanking,
              acquisitions: [acquisition],
            ),
          );
        }
      }
    }
    // Advanced Search determines the order. Filtering inaccessible entries
    // never re-sorts the remaining weekly ranks.
    return List.unmodifiable(verified);
  }

  Future<RemoteCatalogPage> _loadDetails(
    CatalogSource source,
    RemoteCatalogLocation location,
  ) async {
    final identifier = location.uri.pathSegments.last;
    if (!_safeIdentifier(identifier)) {
      throw const RemoteCatalogException.invalidSourceOrLocation();
    }
    final result = await _acquisitions.resolve([identifier]);
    final acquisition = _toAcquisition(result);
    return RemoteCatalogPage(
      sourceId: source.id,
      location: location,
      title: source.name,
      publications: [
        RemoteCatalogPublicationSummary(
          remoteId: identifier,
          title: identifier,
          detailsLocation: location,
          identifiers: ['IA:$identifier'],
          acquisitions: acquisition == null ? const [] : [acquisition],
          sourceMetadata: {'internetArchive.identifier': identifier},
        ),
      ],
    );
  }

  RemoteAcquisition? _toAcquisition(InternetArchiveAcquisitionResult result) {
    if (result.uri == null ||
        result.mediaType == null ||
        (result.availability != InternetArchiveAvailability.directEpub &&
            result.availability != InternetArchiveAvailability.directPdf)) {
      return null;
    }
    return RemoteAcquisition(
      relation: 'http://opds-spec.org/acquisition/open-access',
      href: result.uri.toString(),
      mediaType: result.mediaType,
    );
  }

  List<String> _strings(Object? value) => switch (value) {
    String text when text.trim().isNotEmpty => [text.trim()],
    List values =>
      values
          .whereType<String>()
          .where((value) => value.trim().isNotEmpty)
          .toList(),
    _ => const [],
  };

  bool _safeIdentifier(String value) =>
      RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value);
}

import 'dart:async';
import 'dart:convert';

import 'package:bibliolife/core/network/request_cancellation.dart';
import 'package:bibliolife/features/catalog_sources/data/http_opds_remote_catalog_transport.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_acquisition.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:bibliolife/features/home/domain/models/home_feed_ranking.dart';

const _scoresLocation = 'https://dev.gutenberg.org/browse/scores/top-en.html';

class GutenbergWeeklyEntry {
  const GutenbergWeeklyEntry({
    required this.ebookId,
    required this.rank,
    required this.downloadCount,
    required this.title,
  });

  final String ebookId;
  final int rank;
  final int downloadCount;
  final String title;
}

/// Parses the one authoritative seven-day books list, deliberately bounded by
/// the following heading so yesterday, thirty-day and author lists cannot leak
/// into Home discovery.
List<GutenbergWeeklyEntry> parseGutenbergWeeklyRanking(String html) {
  final heading = RegExp(
    r'<h[1-6][^>]*>\s*Top\s+100\s+EBooks\s+last\s+7\s+days\s*</h[1-6]>',
    caseSensitive: false,
  ).firstMatch(html);
  if (heading == null) {
    throw const FormatException('Gutenberg seven-day books heading missing.');
  }
  final tail = html.substring(heading.end);
  final nextHeading = RegExp(
    r'<h[1-6]\b',
    caseSensitive: false,
  ).firstMatch(tail);
  final section = nextHeading == null
      ? tail
      : tail.substring(0, nextHeading.start);
  final itemPattern = RegExp(
    r'''<li[^>]*>\s*<a[^>]+href=["'](?:https?://(?:www\.)?gutenberg\.org)?/ebooks/(\d+)(?:[^"']*)["'][^>]*>(.*?)\s*\((\d[\d,]*)\)\s*</a>\s*</li>''',
    caseSensitive: false,
    dotAll: true,
  );
  final seen = <String>{};
  final result = <GutenbergWeeklyEntry>[];
  for (final match in itemPattern.allMatches(section)) {
    final id = match.group(1)!;
    if (!seen.add(id)) continue;
    final count = int.tryParse(match.group(3)!.replaceAll(',', ''));
    final title = _text(match.group(2)!);
    if (count == null || count < 0 || title.isEmpty) continue;
    result.add(
      GutenbergWeeklyEntry(
        ebookId: id,
        rank: result.length + 1,
        downloadCount: count,
        title: title,
      ),
    );
  }
  if (result.isEmpty) {
    throw const FormatException(
      'Gutenberg seven-day books list was malformed.',
    );
  }
  return List.unmodifiable(result);
}

String _text(String value) => value
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

class ProjectGutenbergWeeklyAdapter implements RemoteCatalogTransport {
  ProjectGutenbergWeeklyAdapter({HttpCatalogClient? client})
    : _client = client ?? IoHttpCatalogClient();

  final HttpCatalogClient _client;

  @override
  Future<RemoteCatalogPage> loadRoot(CatalogSource source) => _load(source);

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) => _load(source);

  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) => throw const RemoteCatalogException.searchUnsupported();

  Future<RemoteCatalogPage> _load(CatalogSource source) async {
    final location = RemoteCatalogLocation.parse(_scoresLocation);
    try {
      final response = await _client.get(
        location: location,
        headers: const {
          'Accept': 'text/html,application/xhtml+xml',
          'User-Agent': remoteCatalogUserAgent,
        },
        timeout: const Duration(seconds: 15),
        maximumResponseBytes: 2 * 1024 * 1024,
        maximumRedirects: 5,
      );
      if (response.statusCode != 200) {
        throw RemoteCatalogException.httpStatus(
          'Project Gutenberg returned HTTP ${response.statusCode}.',
        );
      }
      throwIfMetadataRequestCancelled();
      final entries = parseGutenbergWeeklyRanking(
        utf8.decode(response.bodyBytes, allowMalformed: false),
      );
      return RemoteCatalogPage(
        sourceId: source.id,
        location: response.effectiveLocation,
        title: 'Project Gutenberg weekly popularity',
        homeRanking: const HomeFeedRanking.weeklyPopularity(),
        publications: entries.map(_publication),
      );
    } on RequestCancelledException {
      rethrow;
    } on RemoteCatalogException {
      rethrow;
    } on TimeoutException {
      throw const RemoteCatalogException.timeout();
    } on FormatException {
      throw const RemoteCatalogException.malformedCatalogResponse(
        'Project Gutenberg weekly ranking was invalid.',
      );
    } on Object {
      throw const RemoteCatalogException.transport();
    }
  }

  RemoteCatalogPublicationSummary _publication(GutenbergWeeklyEntry entry) {
    final id = entry.ebookId;
    return RemoteCatalogPublicationSummary(
      remoteId: id,
      title: entry.title,
      coverLocation: RemoteCatalogLocation.parse(
        'https://www.gutenberg.org/cache/epub/$id/pg$id.cover.medium.jpg',
      ),
      detailsLocation: RemoteCatalogLocation.parse(
        'https://www.gutenberg.org/ebooks/$id',
      ),
      identifiers: ['gutenberg:$id'],
      acquisitions: [
        RemoteAcquisition(
          relation: 'http://opds-spec.org/acquisition/open-access',
          href: 'https://www.gutenberg.org/ebooks/$id.epub.images',
          mediaType: 'application/epub+zip',
        ),
      ],
      sourceMetadata: {
        'gutenberg.ebookId': id,
        'gutenberg.weeklyRank': '${entry.rank}',
        'gutenberg.weeklyDownloads': '${entry.downloadCount}',
      },
      homeRanking: HomeFeedPublicationRanking(
        rank: entry.rank,
        providerScore: entry.downloadCount,
        period: const Duration(days: 7),
        method: HomeFeedRankingMethod.weeklyPopularity,
        evidence: HomeFeedRankingEvidence.exactProviderReported,
      ),
    );
  }
}

import 'dart:convert';

import 'package:bibliolife/features/catalog_sources/data/http_opds_remote_catalog_transport.dart';
import 'package:bibliolife/features/catalog_sources/data/internet_archive_home_discovery_adapter.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/internet_archive_acquisition.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Home discovery uses weekly order and keeps verified public files',
    () async {
      final client = _Client();
      final adapter = InternetArchiveHomeDiscoveryAdapter(
        client: client,
        acquisitions: _Acquisitions(),
      );
      final page = await adapter.loadRoot(_source());

      expect(page.publications, hasLength(1));
      final publication = page.publications.single;
      expect(publication.remoteId, 'public-book');
      expect(
        publication.detailsLocation.toString(),
        'https://archive.org/metadata/public-book',
      );
      expect(page.nextPageLocation, isNotNull);
      expect(publication.homeRanking!.providerScore, 77);
      expect(publication.homeRanking!.rank, 1);
      expect(client.location.uri.queryParameters['sort[]'], 'week desc');
      expect(client.location.uri.queryParameters['fl[]'], contains('week'));
    },
  );

  test('keeps other weekly results when one metadata lookup fails', () async {
    final adapter = InternetArchiveHomeDiscoveryAdapter(
      client: _FailureIsolationClient(),
      acquisitions: _FailureIsolationAcquisitions(),
    );

    final page = await adapter.loadRoot(_source());

    expect(page.publications.map((item) => item.remoteId), ['public-item']);
    expect(page.publications.single.homeRanking?.rank, 2);
  });
}

CatalogSource _source() => CatalogSource(
  id: 'builtin-internet-archive',
  name: 'Internet Archive',
  baseUri: Uri.parse('https://archive.org/'),
  type: CatalogSourceType.internetArchive,
  isBuiltIn: true,
  isEnabled: false,
  supportsSearch: false,
  supportsNavigation: false,
  supportsAcquisition: true,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

class _Client implements HttpCatalogClient {
  late RemoteCatalogLocation location;

  @override
  Future<HttpCatalogResponse> get({
    required RemoteCatalogLocation location,
    required Map<String, String> headers,
    required Duration timeout,
    required int maximumResponseBytes,
    required int maximumRedirects,
  }) async {
    this.location = location;
    return HttpCatalogResponse(
      statusCode: 200,
      bodyBytes: utf8.encode(
        jsonEncode({
          'response': {
            'numFound': 25,
            'docs': [
              {
                'identifier': 'public-book',
                'title': 'Public Book',
                'creator': 'Writer',
                'week': 77,
              },
              {'identifier': 'borrow-only', 'title': 'Ignored', 'week': 76},
              {'identifier': '../bad', 'title': 'Ignored', 'week': 75},
            ],
          },
        }),
      ),
      effectiveLocation: location,
      contentType: 'application/json',
    );
  }
}

class _Acquisitions implements InternetArchiveAcquisitionResolver {
  @override
  Future<InternetArchiveAcquisitionResult> resolve(
    Iterable<String> identifiers,
  ) async => identifiers.single == 'public-book'
      ? InternetArchiveAcquisitionResult.directEpub(
          identifier: 'public-book',
          uri: Uri.parse('https://archive.org/download/public-book/book.epub'),
        )
      : InternetArchiveAcquisitionResult.borrowingRequired(
          identifier: identifiers.single,
        );
}

class _FailureIsolationClient implements HttpCatalogClient {
  @override
  Future<HttpCatalogResponse> get({
    required RemoteCatalogLocation location,
    required Map<String, String> headers,
    required Duration timeout,
    required int maximumResponseBytes,
    required int maximumRedirects,
  }) async => HttpCatalogResponse(
    statusCode: 200,
    bodyBytes: utf8.encode(
      jsonEncode({
        'response': {
          'numFound': 2,
          'docs': [
            {'identifier': 'broken-item', 'title': 'Broken', 'week': 120},
            {'identifier': 'public-item', 'title': 'Public', 'week': 110},
          ],
        },
      }),
    ),
    effectiveLocation: location,
    contentType: 'application/json',
  );
}

class _FailureIsolationAcquisitions
    implements InternetArchiveAcquisitionResolver {
  @override
  Future<InternetArchiveAcquisitionResult> resolve(
    Iterable<String> identifiers,
  ) async {
    final identifier = identifiers.single;
    if (identifier == 'broken-item') throw StateError('metadata unavailable');
    return InternetArchiveAcquisitionResult.directEpub(
      identifier: identifier,
      uri: Uri.parse('https://archive.org/download/$identifier/book.epub'),
    );
  }
}

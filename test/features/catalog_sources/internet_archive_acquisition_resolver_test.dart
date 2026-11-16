import 'dart:convert';

import 'package:bibliolife/features/catalog_sources/data/http_opds_remote_catalog_transport.dart';
import 'package:bibliolife/features/catalog_sources/data/internet_archive_acquisition_resolver.dart';
import 'package:bibliolife/features/catalog_sources/domain/internet_archive_acquisition.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selects only a concrete public EPUB file from metadata', () async {
    final client = _Client({
      'metadata': {'identifier': 'public-book'},
      'files': [
        {'name': 'reader.html'},
        {'name': 'public-book.epub'},
      ],
    });

    final result = await HttpInternetArchiveAcquisitionResolver(
      client: client,
    ).resolve(['public-book']);

    expect(result.availability, InternetArchiveAvailability.directEpub);
    expect(
      result.uri,
      Uri.parse('https://archive.org/download/public-book/public-book.epub'),
    );
  });

  test(
    'borrow-only and restricted records are never direct downloads',
    () async {
      final borrowed = await HttpInternetArchiveAcquisitionResolver(
        client: _Client({
          'metadata': {'access-restricted': 'true'},
          'files': [
            {'name': 'book.epub'},
          ],
        }),
      ).resolve(['borrow-book']);
      final restricted = await HttpInternetArchiveAcquisitionResolver(
        client: _Client({
          'metadata': {},
          'files': [
            {'name': 'book.epub', 'private': 'true'},
            {'name': 'reader.html'},
          ],
        }),
      ).resolve(['restricted-book']);

      expect(
        borrowed.availability,
        InternetArchiveAvailability.borrowingRequired,
      );
      expect(restricted.availability, InternetArchiveAvailability.metadataOnly);
    },
  );

  test(
    'skips LCP-protected EPUB files when an unprotected EPUB is present',
    () async {
      final result = await HttpInternetArchiveAcquisitionResolver(
        client: _Client({
          'metadata': {},
          'files': [
            {'name': 'book_lcp.epub'},
            {'name': 'book.epub'},
          ],
        }),
      ).resolve(['book']);

      expect(result.availability, InternetArchiveAvailability.directEpub);
      expect(
        result.uri,
        Uri.parse('https://archive.org/download/book/book.epub'),
      );
    },
  );

  test('accepts a concrete public PDF when no EPUB is available', () async {
    final result = await HttpInternetArchiveAcquisitionResolver(
      client: _Client({
        'metadata': {},
        'files': [
          {'name': 'reader.html'},
          {'name': 'public-book.pdf'},
        ],
      }),
    ).resolve(['public-book']);

    expect(result.availability, InternetArchiveAvailability.directPdf);
    expect(
      result.uri,
      Uri.parse('https://archive.org/download/public-book/public-book.pdf'),
    );
  });

  test(
    'LCP-only Internet Archive metadata is not exposed as Download',
    () async {
      final result = await HttpInternetArchiveAcquisitionResolver(
        client: _Client({
          'metadata': {},
          'files': [
            {'name': 'book_lcp.epub'},
          ],
        }),
      ).resolve(['book']);

      expect(result.availability, InternetArchiveAvailability.metadataOnly);
    },
  );

  test(
    'malformed Internet Archive metadata completes as unavailable',
    () async {
      final result = await HttpInternetArchiveAcquisitionResolver(
        client: _Client.raw('not-json'),
      ).resolve(['book']);

      expect(result.availability, InternetArchiveAvailability.metadataOnly);
    },
  );
}

class _Client implements HttpCatalogClient {
  _Client(Map<String, dynamic> body)
    : bodyBytes = utf8.encode(jsonEncode(body));

  _Client.raw(String body) : bodyBytes = utf8.encode(body);

  final List<int> bodyBytes;
  @override
  Future<HttpCatalogResponse> get({
    required RemoteCatalogLocation location,
    required Map<String, String> headers,
    required Duration timeout,
    required int maximumResponseBytes,
    required int maximumRedirects,
  }) async => HttpCatalogResponse(
    statusCode: 200,
    bodyBytes: bodyBytes,
    effectiveLocation: location,
    contentType: 'application/json',
  );
}

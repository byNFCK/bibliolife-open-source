import 'dart:convert';

import 'package:bibliolife/features/catalog_sources/data/http_opds_remote_catalog_transport.dart';
import 'package:bibliolife/features/catalog_sources/data/open_library_remote_catalog_adapter.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:bibliolife/features/home/domain/models/home_feed_ranking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Open Library Home uses weekly trending order and its pagination cursor',
    () async {
      final trailing = List.filled(
        38,
        '{"key":"/works/OL3W","title":"More"}',
      ).join(',');
      final client = _Client(
        '{"works":[{"key":"/works/OL2W","title":"Second"},'
        '{"key":"/works/OL1W","title":"First"},$trailing]}',
      );
      final adapter = OpenLibraryRemoteCatalogAdapter(client: client);

      final first = await adapter.loadRoot(_source());
      expect(client.location.uri.path, '/trending/weekly.json');
      expect(client.location.uri.queryParameters['offset'], '0');
      expect(first.publications.take(2).map((item) => item.remoteId), [
        '/works/OL2W',
        '/works/OL1W',
      ]);
      expect(first.publications.first.homeRanking!.rank, 1);
      expect(first.homeRanking!.method, HomeFeedRankingMethod.weeklyPopularity);

      await adapter.loadPage(
        source: _source(),
        location: first.nextPageLocation!,
      );
      expect(client.location.uri.queryParameters['offset'], '40');
    },
  );

  test('Open Library JSON search maps publications and pagination', () async {
    final client = _Client(
      '{"numFound":3,"start":0,"docs":['
      '{"key":"/works/OL1W","title":"Romeo and Juliet",'
      '"author_name":["William Shakespeare"],"cover_i":12,'
      '"author_key":["OL9388A"],"language":["eng"],"first_publish_year":1597,'
      '"publisher":["Example Press"],"isbn":["9780141396507","0141396502"],'
      '"lccn":["79009143"],"oclc":["123"],"ia":["romeojuliet00shak"],'
      '"edition_key":["OL1M"],"cover_edition_key":"OL1M",'
      '"number_of_pages_median":244,"subject":["Drama","Tragedy"],'
      '"edition_count":10,"has_fulltext":true},'
      '{"key":"/works/OL2W","title":"Untitled"}]}',
    );
    final adapter = OpenLibraryRemoteCatalogAdapter(client: client);

    final root = await adapter.loadRoot(_source());
    final page = await adapter.search(
      source: _source(),
      capability: root.searchCapability,
      query: 'Romeo and Juliet',
    );

    expect(client.location.toString(), contains('q=Romeo+and+Juliet'));
    final book = page.publications.first;
    expect(book.remoteId, '/works/OL1W');
    expect(book.authors, ['William Shakespeare']);
    expect(
      book.coverLocation.toString(),
      'https://covers.openlibrary.org/b/id/12-L.jpg?default=false',
    );
    expect(
      book.detailsLocation.toString(),
      'https://openlibrary.org/works/OL1W',
    );
    expect(book.language, 'eng');
    expect(book.publishedDate, '1597');
    expect(book.pageCount, 244);
    expect(
      book.identifiers,
      containsAll([
        'ISBN:9780141396507',
        'LCCN:79009143',
        'OCLC:123',
        'IA:romeojuliet00shak',
      ]),
    );
    expect(book.sourceMetadata['openLibrary.workKey'], '/works/OL1W');
    expect(book.sourceLists['openLibrary.authorKeys'], ['OL9388A']);
    expect(book.sourceLinks, hasLength(2));
    expect(page.nextPageLocation.toString(), contains('page=2'));
  });

  test('Open Library keeps a missing cover absent', () async {
    final page = await OpenLibraryRemoteCatalogAdapter(
      client: _Client(
        '{"numFound":1,"docs":[{"key":"/works/OL2W","title":"No cover"}]}',
      ),
    ).search(source: _source(), capability: _sourceCapability(), query: 'none');

    expect(page.publications.single.coverLocation, isNull);
    expect(page.publications.single.imageCandidates, isEmpty);
  });

  test(
    'Open Library malformed JSON is typed instead of sent to Atom parser',
    () async {
      final adapter = OpenLibraryRemoteCatalogAdapter(
        client: _Client('<html/>'),
      );
      await expectLater(
        adapter.search(
          source: _source(),
          capability: _sourceCapability(),
          query: 'Romeo',
        ),
        throwsA(
          isA<RemoteCatalogException>().having(
            (error) => error.failure,
            'failure',
            RemoteCatalogFailure.malformedCatalogResponse,
          ),
        ),
      );
    },
  );
}

CatalogSource _source() => CatalogSource(
  id: 'builtin-open-library',
  name: 'Open Library',
  baseUri: Uri.parse('https://openlibrary.org/'),
  type: CatalogSourceType.openLibrary,
  isBuiltIn: true,
  isEnabled: true,
  supportsSearch: true,
  supportsNavigation: false,
  supportsAcquisition: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

RemoteCatalogSearchCapability _sourceCapability() =>
    RemoteCatalogSearchCapability.directTemplate(
      RemoteCatalogLocation.parse(
        'https://openlibrary.org/search.json?q=%7BsearchTerms%7D',
      ),
    );

class _Client implements HttpCatalogClient {
  _Client(this.body);

  final String body;
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
      bodyBytes: utf8.encode(body),
      effectiveLocation: location,
      contentType: 'application/json; charset=utf-8',
    );
  }
}

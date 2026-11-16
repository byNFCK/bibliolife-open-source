import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:bibliolife/features/catalog_sources/data/google_books_payload_parser.dart';
import 'package:bibliolife/features/catalog_sources/data/internet_archive_metadata_parser.dart';
import 'package:bibliolife/features/catalog_sources/data/open_library_payload_parser.dart';
import 'package:bibliolife/features/catalog_sources/data/open_search_description_parser.dart';
import 'package:bibliolife/features/catalog_sources/data/opds1_atom_parser.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'pure JSON and OpenSearch parser DTOs cross an isolate boundary',
    () async {
      final results = await Future.wait([
        Isolate.run(_parseGoogleInIsolate),
        Isolate.run(_parseOpenLibraryInIsolate),
        Isolate.run(_parseInternetArchiveInIsolate),
        Isolate.run(_parseOpenSearchInIsolate),
      ]);

      expect(results, ['g-1:One', '/works/one:One', 'book.epub', true]);
    },
  );

  test(
    'OPDS feed DTO crosses an isolate boundary before one domain mapping',
    () async {
      final feed = await Isolate.run(_parseOpdsInIsolate);

      expect(
        feed.publications.single.acquisitions.single.href,
        'https://catalog.example/books/one.epub',
      );
      expect(feed.nextPageLocation, 'https://catalog.example/page/2');
      final page = mapParsedOpdsFeedToDomain(feed);
      expect(page.publications.single.remoteId, 'urn:book:one');
      expect(
        page.publications.single.acquisitions.single.advertisesEpub,
        isTrue,
      );
    },
  );

  test('bounded generated fixtures retain compact ordered parser output', () {
    final google = parseGoogleBooksPayload(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'totalItems': 60,
            'items': List.generate(
              60,
              (index) => index % 10 == 0
                  ? {'id': 'bad-$index'}
                  : {
                      'id': 'g-$index',
                      'volumeInfo': {'title': 'Google $index'},
                    },
            ),
          }),
        ),
      ),
      details: false,
    );
    final openLibrary = parseOpenLibraryPayload(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'start': 0,
            'numFound': 60,
            'docs': List.generate(
              60,
              (index) => index % 10 == 0
                  ? {'key': '/works/bad-$index'}
                  : {
                      'key': '/works/$index',
                      'title': 'Open $index',
                      'isbn': ['978000$index'],
                    },
            ),
          }),
        ),
      ),
    );
    final archive = parseInternetArchiveMetadata(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'metadata': {},
            'files': List.generate(
              80,
              (index) => {
                'name': index == 79 ? 'public.epub' : 'file-$index.txt',
              },
            ),
          }),
        ),
      ),
    );
    final entries = List.generate(
      50,
      (index) =>
          '<entry><id>urn:$index</id><title>OPDS $index</title><author><name>A</name></author><link rel="http://opds-spec.org/acquisition" type="application/epub+zip" href="books/$index.epub"/><link rel="http://opds-spec.org/image/thumbnail" href="covers/$index.jpg"/></entry>',
    ).join();
    final opds = const Opds1AtomParser().parseBytes(
      sourceId: 'opds',
      location: RemoteCatalogLocation.parse('https://catalog.example/root/'),
      bytes: Uint8List.fromList(
        utf8.encode(
          '<feed xmlns="http://www.w3.org/2005/Atom"><title>Large</title><link rel="next" href="page/2"/>$entries</feed>',
        ),
      ),
    );

    expect(google.books, hasLength(54));
    expect(google.skippedItemCount, 6);
    expect(openLibrary.documents, hasLength(54));
    expect(openLibrary.skippedDocumentCount, 6);
    expect(archive.files, hasLength(80));
    expect(archive.files.last.name, 'public.epub');
    expect(opds.publications, hasLength(50));
    expect(opds.publications.first.remoteId, 'urn:0');
    expect(opds.nextPageLocation, 'https://catalog.example/root/page/2');
  });
}

String _parseGoogleInIsolate() {
  final page = parseGoogleBooksPayload(
    Uint8List.fromList(
      utf8.encode(
        '{"totalItems":1,"items":[{"id":"g-1","volumeInfo":{"title":"One"}}]}',
      ),
    ),
    details: false,
  );
  return '${page.books.single.id}:${page.books.single.volume['title']}';
}

String _parseOpenLibraryInIsolate() {
  final page = parseOpenLibraryPayload(
    Uint8List.fromList(
      utf8.encode(
        '{"start":0,"numFound":1,"docs":[{"key":"/works/one","title":"One"}]}',
      ),
    ),
  );
  return '${page.documents.single.fields['key']}:${page.documents.single.fields['title']}';
}

String _parseInternetArchiveInIsolate() {
  final metadata = parseInternetArchiveMetadata(
    Uint8List.fromList(
      utf8.encode('{"metadata":{},"files":[{"name":"book.epub"}]}'),
    ),
  );
  return metadata.files.single.name;
}

bool _parseOpenSearchInIsolate() => parseOpenSearchDescriptionPayload(
  Uint8List.fromList(
    utf8.encode(
      '<OpenSearchDescription><Url type="application/atom+xml" template="https://catalog.example/?q={searchTerms}"/></OpenSearchDescription>',
    ),
  ),
  baseUri: 'https://catalog.example/open-search.xml',
).template.contains('%7BsearchTerms%7D');

ParsedOpdsFeed _parseOpdsInIsolate() => const Opds1AtomParser().parseBytes(
  sourceId: 'opds',
  location: RemoteCatalogLocation.parse('https://catalog.example/feed/root'),
  bytes: Uint8List.fromList(
    utf8.encode('''
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Catalog</title>
  <link rel="next" href="../page/2" />
  <entry>
    <id>urn:book:one</id><title>One</title><author><name>Author</name></author>
    <link rel="http://opds-spec.org/acquisition/open-access" type="application/epub+zip" href="../books/one.epub" />
    <link rel="http://opds-spec.org/image/thumbnail" href="../covers/one.jpg" />
  </entry>
</feed>'''),
  ),
);

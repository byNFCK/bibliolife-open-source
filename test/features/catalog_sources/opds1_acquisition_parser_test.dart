import 'package:bibliolife/features/catalog_sources/data/opds1_atom_parser.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_acquisition.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = Opds1AtomParser();
  final location = RemoteCatalogLocation.parse(
    'https://catalog.example/feeds/root.xml',
  );

  RemoteAcquisition parseLink(String link) {
    final page = parser.parse(
      sourceId: 'source',
      location: location,
      body:
          '<feed xmlns="http://www.w3.org/2005/Atom" '
          'xmlns:opds="http://opds-spec.org/2010/catalog">'
          '<title>Feed</title><entry><id>book</id><title>Book</title>'
          '$link</entry></feed>',
    );
    return page.publications.single.acquisitions.single;
  }

  test('parses direct generic EPUB and resolves relative location', () {
    final value = parseLink(
      '<link rel="http://opds-spec.org/acquisition" '
      'href="../book.epub" type="application/epub+zip" '
      'title="EPUB" length="123"/>',
    );
    expect(value.href, 'https://catalog.example/book.epub');
    expect(value.mediaType, 'application/epub+zip');
    expect(value.title, 'EPUB');
    expect(value.sizeBytes, 123);
    expect(value.isDirectSupportedEpub, isTrue);
  });

  test('parses open-access relation', () {
    final value = parseLink(
      '<link rel="http://opds-spec.org/acquisition/open-access" '
      'href="/book.epub" type="application/epub+zip"/>',
    );
    expect(value.kind, RemoteAcquisitionKind.openAccess);
  });

  test('preserves ordered indirect acquisition chain', () {
    final value = parseLink(
      '<link rel="http://opds-spec.org/acquisition/borrow" '
      'href="/borrow" type="application/atom+xml">'
      '<opds:indirectAcquisition type="application/vnd.vendor">'
      '<opds:indirectAcquisition type="application/epub+zip"/>'
      '</opds:indirectAcquisition></link>',
    );
    expect(value.indirectMediaTypes, [
      'application/vnd.vendor',
      'application/epub+zip',
    ]);
    expect(value.expectedFinalMediaType, 'application/epub+zip');
    expect(value.isIndirect, isTrue);
  });

  test('retains multiple formats in original order', () {
    final page = parser.parse(
      sourceId: 'source',
      location: location,
      body: _feed([
        _link('/book.pdf', 'application/pdf'),
        _link('/book.epub', 'application/epub+zip'),
      ]),
    );
    expect(
      page.publications.single.acquisitions.map((value) => value.mediaType),
      ['application/pdf', 'application/epub+zip'],
    );
  });

  test('retains insecure HTTP as inspectable unsupported metadata', () {
    final value = parseLink(
      '<link rel="http://opds-spec.org/acquisition" '
      'href="http://catalog.example/book.epub" '
      'type="application/epub+zip"/>',
    );
    expect(value.isSecure, isFalse);
    expect(value.advertisesEpub, isTrue);
  });

  test('retains authentication indication', () {
    final value = parseLink(
      '<link rel="http://opds-spec.org/acquisition/borrow" '
      'href="/book.epub" type="application/epub+zip" '
      'authentication="required"/>',
    );
    expect(value.requiresAuthentication, isTrue);
  });

  test('deduplicates exact links but retains distinct relations', () {
    final page = parser.parse(
      sourceId: 'source',
      location: location,
      body: _feed([
        _link('/book.epub', 'application/epub+zip'),
        _link('/book.epub', 'application/epub+zip'),
        _link(
          '/book.epub',
          'application/epub+zip',
          relation: 'http://opds-spec.org/acquisition/sample',
        ),
      ]),
    );
    expect(page.publications.single.acquisitions, hasLength(2));
  });

  test('malformed acquisition URI is retained safely', () {
    final value = parseLink(
      '<link rel="http://opds-spec.org/acquisition" '
      'href="https://[invalid" type="application/epub+zip"/>',
    );
    expect(value.isMalformed, isTrue);
    expect(value.isSecure, isFalse);
  });

  test('unknown acquisition suffix is retained', () {
    final value = parseLink(
      '<link rel="http://opds-spec.org/acquisition/vendor-specific" '
      'href="/book.bin" type="application/octet-stream"/>',
    );
    expect(value.kind, RemoteAcquisitionKind.unknown);
    expect(value.relation, endsWith('/vendor-specific'));
  });
}

String _feed(List<String> links) =>
    '<feed xmlns="http://www.w3.org/2005/Atom"><title>Feed</title>'
    '<entry><id>book</id><title>Book</title>${links.join()}</entry></feed>';

String _link(
  String href,
  String type, {
  String relation = 'http://opds-spec.org/acquisition',
}) => '<link rel="$relation" href="$href" type="$type"/>';

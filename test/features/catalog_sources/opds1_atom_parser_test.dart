import 'package:bibliolife/features/catalog_sources/data/opds1_atom_parser.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = Opds1AtomParser();
  final location = RemoteCatalogLocation.parse(
    'https://catalog.example/feeds/root.xml',
  );

  test('parses navigation relative links next and unknown namespaces', () {
    final page = parser.parse(
      sourceId: 'source',
      location: location,
      body: '''
<atom:feed xmlns:atom="http://www.w3.org/2005/Atom" xmlns:x="urn:ignored">
  <atom:title>Library</atom:title><x:unknown>ignored</x:unknown>
  <atom:link rel="next" href="?page=2#ignored"/>
  <atom:entry><atom:id>nav-1</atom:id><atom:title>Fiction</atom:title>
    <atom:link rel="subsection" href="../fiction"/></atom:entry>
  <atom:entry><atom:title>External</atom:title>
    <atom:link rel="subsection" href="http://unsafe.example/"/></atom:entry>
</atom:feed>
''',
    );

    expect(page.title, 'Library');
    expect(page.navigation.single.title, 'Fiction');
    expect(
      page.navigation.single.location.toString(),
      'https://catalog.example/fiction',
    );
    expect(
      page.nextPageLocation.toString(),
      'https://catalog.example/feeds/root.xml?page=2',
    );
  });

  test('parses acquisition fields and discards insecure cover', () {
    final page = parser.parse(
      sourceId: 'source',
      location: location,
      body: '''
<feed xmlns="http://www.w3.org/2005/Atom"><title>Books</title><entry>
  <id>book-1</id><title>One</title>
  <author><name>A. One</name></author><author><name>B. Two</name></author>
  <summary>Summary</summary>
  <link rel="http://opds-spec.org/image" href="http://unsafe/cover.jpg"/>
  <link rel="http://opds-spec.org/acquisition/open-access" href="/book.epub"/>
</entry></feed>
''',
    );

    final publication = page.publications.single;
    expect(publication.remoteId, 'book-1');
    expect(publication.title, 'One');
    expect(publication.authors, ['A. One', 'B. Two']);
    expect(publication.summary, 'Summary');
    expect(publication.coverLocation, isNull);
    expect(publication.hasAcquisition, isTrue);
  });

  test(
    'accepts Standard Ebooks public EPUB enclosures only for its source',
    () {
      const feed = '''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>New releases</title>
  <entry>
    <id>standard-example</id>
    <title>Example</title>
    <author><name>Author</name></author>
    <link rel="enclosure" type="application/epub+zip" href="/example.epub" />
  </entry>
</feed>''';

      final standard = parser.parse(
        sourceId: 'builtin-standard-ebooks',
        location: RemoteCatalogLocation.parse(
          'https://standardebooks.org/feeds/atom/new-releases',
        ),
        body: feed,
      );
      final other = parser.parse(
        sourceId: 'other-source',
        location: RemoteCatalogLocation.parse('https://example.test/feed'),
        body: feed,
      );

      expect(standard.publications, hasLength(1));
      expect(
        standard.publications.single.acquisitions.single.relation,
        'http://opds-spec.org/acquisition/open-access',
      );
      expect(other.publications, isEmpty);
    },
  );

  test('supports mixed feeds cover resolution and content fallback', () {
    final page = parser.parse(
      sourceId: 'source',
      location: location,
      body: '''
<feed xmlns="http://www.w3.org/2005/Atom"><title>Mixed</title>
  <entry><title>Browse</title><link rel="collection" href="/browse"/></entry>
  <entry><id>book-2</id><title>Two</title><content>Fallback text</content>
    <link rel="http://opds-spec.org/image/thumbnail" href="covers/two.jpg"/>
    <link rel="http://opds-spec.org/acquisition" href="/two.epub"/></entry>
</feed>
''',
    );

    expect(
      page.navigation.single.location.toString(),
      'https://catalog.example/browse',
    );
    expect(page.publications.single.summary, 'Fallback text');
    expect(
      page.publications.single.coverLocation.toString(),
      'https://catalog.example/feeds/covers/two.jpg',
    );
  });

  test('resolves a relative Gutenberg search cover before details load', () {
    final page = parser.parse(
      sourceId: 'builtin-project-gutenberg',
      location: RemoteCatalogLocation.parse(
        'https://www.gutenberg.org/ebooks/search.opds/?query=time',
      ),
      isSearchResult: true,
      body: '''
<feed xmlns="http://www.w3.org/2005/Atom"><title>Search</title><entry>
  <id>https://www.gutenberg.org/ebooks/35</id><title>The Time Machine</title>
  <content>H. G. Wells</content>
  <link rel="http://opds-spec.org/image" href="35/pg35.cover.medium.jpg"/>
  <link rel="alternate" href="/ebooks/35.opds" type="application/atom+xml"/>
</entry></feed>
''',
    );

    expect(
      page.publications.single.coverLocation.toString(),
      'https://www.gutenberg.org/ebooks/search.opds/35/pg35.cover.medium.jpg',
    );
  });

  test('summary wins and bibliographic content is never a description', () {
    final page = parser.parse(
      sourceId: 'source',
      location: location,
      body: '''
<feed xmlns="http://www.w3.org/2005/Atom"><title>Books</title>
  <entry><id>summary</id><title>Summary book</title>
    <summary>Genuine descriptive prose.</summary>
    <content type="html">&lt;table&gt;&lt;tr&gt;&lt;td&gt;Subjects: Fiction&lt;/td&gt;&lt;/tr&gt;&lt;tr&gt;&lt;td&gt;Rights: Public domain&lt;/td&gt;&lt;/tr&gt;&lt;/table&gt;</content>
    <link rel="http://opds-spec.org/acquisition" href="/summary.epub"/></entry>
  <entry><id>metadata</id><title>Metadata only</title>
    <content type="html">&lt;table&gt;&lt;tr&gt;&lt;td&gt;Subjects: Fiction&lt;/td&gt;&lt;/tr&gt;&lt;tr&gt;&lt;td&gt;Rights: Public domain&lt;/td&gt;&lt;/tr&gt;&lt;/table&gt;</content>
    <category term="Fiction"/>
    <link rel="http://opds-spec.org/acquisition" href="/metadata.epub"/></entry>
</feed>
''',
    );

    expect(page.publications.first.summary, 'Genuine descriptive prose.');
    expect(page.publications.last.summary, isNull);
    expect(page.publications.last.subjects, ['Fiction']);
  });

  test(
    'extracts genuine prose from Gutenberg inline bibliographic content',
    () {
      final page = parser.parse(
        sourceId: 'builtin-project-gutenberg',
        location: location,
        body: '''
<feed xmlns="http://www.w3.org/2005/Atom"><title>Books</title>
  <entry><id>inline</id><title>Inline</title>
    <content>Title: Inline Note: Illustrated Credits: Produced by Example Summary: A concise genuine story about courage and friendship.</content>
    <link rel="http://opds-spec.org/acquisition" href="/inline.epub"/></entry>
</feed>
''',
      );

      expect(
        page.publications.single.summary,
        'A concise genuine story about courage and friendship.',
      );
    },
  );

  test('retains sanitized Gutenberg-like structured publication metadata', () {
    final page = parser.parse(
      sourceId: 'builtin-project-gutenberg',
      location: location,
      body: '''
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:dc="http://purl.org/dc/terms/">
  <title>Gutenberg</title><entry>
    <id>https://www.gutenberg.org/ebooks/2701</id>
    <title>Moby Dick</title><author><name>Herman Melville</name></author>
    <summary type="html">&lt;p&gt;A whale &amp;amp; voyage.&lt;/p&gt;&lt;script&gt;bad()&lt;/script&gt;&lt;p&gt;(This is an automatically generated summary.)&lt;/p&gt;&lt;p&gt;Language: English&lt;/p&gt;&lt;p&gt;Rights: Public domain&lt;/p&gt;</summary>
    <dc:publisher>Project Gutenberg</dc:publisher>
    <dc:language>en-us</dc:language><dc:issued>2001-07-01</dc:issued>
    <dc:identifier>gutenberg:2701</dc:identifier>
    <dc:identifier>urn:isbn:978-0-306-40615-7</dc:identifier>
    <category term="Whaling" label="Whaling -- Fiction"/>
    <category term="Sea stories"/>
    <rights>Public domain</rights>
    <link rel="alternate" href="/ebooks/2701" type="text/html"/>
    <link rel="http://opds-spec.org/acquisition/open-access"
          href="/ebooks/2701.epub3.images" type="application/epub+zip"/>
  </entry>
</feed>
''',
    );

    final publication = page.publications.single;
    expect(publication.summary, 'A whale & voyage.');
    expect(publication.publisher, 'Project Gutenberg');
    expect(publication.language, 'en-US');
    expect(publication.publishedDate, '2001-07-01');
    expect(publication.identifiers, [
      'gutenberg:2701',
      'urn:isbn:978-0-306-40615-7',
    ]);
    expect(publication.subjects, ['Whaling -- Fiction', 'Sea stories']);
    expect(publication.rights, 'Public domain');
    expect(
      publication.detailsLocation.toString(),
      'https://catalog.example/ebooks/2701',
    );
  });

  test('empty feed is valid and incomplete entries are ignored', () {
    final page = parser.parse(
      sourceId: 'source',
      location: location,
      body: '''
<feed xmlns="http://www.w3.org/2005/Atom"><title>Empty</title>
  <entry><id>missing-title</id><link rel="http://opds-spec.org/acquisition"/></entry>
  <entry><title>Missing ID</title><link rel="http://opds-spec.org/acquisition"/></entry>
</feed>
''',
    );
    expect(page.navigation, isEmpty);
    expect(page.publications, isEmpty);
  });

  test('malformed XML maps to malformed response', () {
    expect(
      () => parser.parse(
        sourceId: 'source',
        location: location,
        body: '<feed><title>Broken</feed>',
      ),
      _throwsFailure(RemoteCatalogFailure.malformedCatalogResponse),
    );
  });

  test('non-feed XML and feed without title are rejected', () {
    expect(
      () => parser.parse(
        sourceId: 'source',
        location: location,
        body: '<entry xmlns="http://www.w3.org/2005/Atom"/>',
      ),
      _throwsFailure(RemoteCatalogFailure.unsupportedCatalogFormat),
    );
    expect(
      () => parser.parse(
        sourceId: 'source',
        location: location,
        body: '<feed xmlns="http://www.w3.org/2005/Atom"/>',
      ),
      _throwsFailure(RemoteCatalogFailure.malformedCatalogResponse),
    );
  });
}

Matcher _throwsFailure(RemoteCatalogFailure failure) => throwsA(
  isA<RemoteCatalogException>().having(
    (error) => error.failure,
    'failure',
    failure,
  ),
);

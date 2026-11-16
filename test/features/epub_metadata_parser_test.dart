import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bibliolife/features/metadata/data/parsers/epub_metadata_parser.dart';
import 'package:bibliolife/features/metadata/data/services/epub_metadata_normalizer.dart';
import 'package:bibliolife/features/metadata/domain/entities/metadata_extraction_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bibliolife_epub_test');
  });

  tearDown(() => directory.delete(recursive: true));

  test('preserves Ukrainian and supplementary Unicode metadata', () async {
    const title =
        '\u041a\u043d\u0438\u0433\u0430 \u0456 \u0457 \u0457\u0436\u0430\u043a \uD83D\uDE80';
    const author =
        '\u0422\u0430\u0440\u0430\u0441 \u0490\u0440\u0438\u0433\u043e\u0440\u043e\u0432\u0438\u0447';
    const description =
        '\u041e\u043f\u0438\u0441: \u0645\u0631\u062d\u0628\u0627 \u4f60\u597d \uD83E\uDDEA';
    const publisher =
        '\u0412\u0438\u0434\u0430\u0432\u043d\u0438\u0446\u0442\u0432\u043e \u00c9ditions';
    final epub = await _writeEpub(directory, {
      'META-INF/container.xml':
          '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
      'book.opf':
          '<package><metadata><dc:title xmlns:dc="x">$title</dc:title><dc:creator xmlns:dc="x">$author</dc:creator><dc:description xmlns:dc="x">$description</dc:description><dc:publisher xmlns:dc="x">$publisher</dc:publisher></metadata></package>',
    }, name: 'unicode.epub');

    final metadata =
        (await EpubMetadataParser().parse(epub.path)
                as MetadataExtractionSuccess)
            .metadata;

    expect(metadata.title, title);
    expect(metadata.authors, [author]);
    expect(metadata.description, description);
    expect(metadata.publisher, publisher);
  });

  test('honors a declared ISO-8859-1 OPF encoding', () async {
    const title = 'L\u00e9tranger';
    final epub = await _writeEpub(directory, {
      'META-INF/container.xml':
          '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
      'book.opf': Uint8List.fromList(
        latin1.encode(
          '<?xml version="1.0" encoding="ISO-8859-1"?><package><metadata><dc:title xmlns:dc="x">$title</dc:title></metadata></package>',
        ),
      ),
    }, name: 'latin1.epub');

    final metadata =
        (await EpubMetadataParser().parse(epub.path)
                as MetadataExtractionSuccess)
            .metadata;

    expect(metadata.title, title);
  });

  test('recovers only confident UTF-8-as-Latin-1 mojibake', () {
    const correct = '\u0423\u043a\u0440\u0430\u0457\u043d\u0430';
    final mojibake = latin1.decode(utf8.encode(correct));

    expect(recoverUtf8MojibakeIfConfident(mojibake), correct);
    expect(
      recoverUtf8MojibakeIfConfident('Ordinary English'),
      'Ordinary English',
    );
    expect(recoverUtf8MojibakeIfConfident(correct), correct);
  });

  test(
    'extracts EPUB 3 metadata, ordered authors, ISBN-13 and cover',
    () async {
      final epub = await _writeEpub(directory, {
        'META-INF/container.xml': '''
        <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>
      ''',
        'OPS/book.opf': '''
        <package xmlns:dc="http://purl.org/dc/elements/1.1/"><metadata>
          <dc:title id="title">Main title</dc:title><meta refines="#title" property="title-type">main</meta><meta refines="#title" property="file-as">Title, Main</meta>
          <dc:creator id="a1">First Author</dc:creator><dc:creator id="a2">Second Author</dc:creator>
          <dc:identifier>0-306-40615-2</dc:identifier><dc:identifier>978-0-306-40615-7</dc:identifier>
        </metadata><manifest><item id="cover" href="images/cover%20image.jpg" media-type="image/jpeg" properties="cover-image"/></manifest></package>
      ''',
        'OPS/images/cover image.jpg': Uint8List.fromList([1, 2, 3]),
      });

      final result = await EpubMetadataParser().parse(epub.path);

      expect(result, isA<MetadataExtractionSuccess>());
      final metadata = (result as MetadataExtractionSuccess).metadata;
      expect(metadata.title, 'Main title');
      expect(metadata.sortTitle, 'Title, Main');
      expect(metadata.authors, ['First Author', 'Second Author']);
      expect(metadata.isbn, '9780306406157');
      expect(metadata.coverExtension, 'jpg');
      expect(metadata.coverBytes, [1, 2, 3]);
    },
  );

  test('extracts EPUB 2 cover metadata and accepts ISBN-10 fallback', () async {
    final epub = await _writeEpub(directory, {
      'META-INF/container.xml':
          '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
      'book.opf':
          '''<package><metadata><dc:title xmlns:dc="x">Book</dc:title><dc:identifier xmlns:dc="x">0-306-40615-2</dc:identifier><meta name="cover" content="cover-id"/></metadata><manifest><item id="cover-id" href="cover.png" media-type="image/png"/></manifest></package>''',
      'cover.png': Uint8List.fromList([4, 5]),
    });

    final result = await EpubMetadataParser().parse(epub.path);

    final metadata = (result as MetadataExtractionSuccess).metadata;
    expect(metadata.isbn, '0306406152');
    expect(metadata.coverExtension, 'png');
  });

  test('extracts rich EPUB 3 metadata without flattening contributors', () async {
    final epub = await _writeEpub(directory, {
      'META-INF/container.xml':
          '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
      'book.opf': '''
        <package xmlns:dc="http://purl.org/dc/elements/1.1/">
          <metadata>
            <dc:title>Rich Book</dc:title>
            <dc:creator>Alice Author</dc:creator>
            <dc:creator>Bob Author</dc:creator>
            <dc:contributor>Casey Editor</dc:contributor>
            <dc:description>&lt;p&gt;First &amp;amp; safe.&lt;/p&gt;&lt;script&gt;alert('no')&lt;/script&gt;&lt;style&gt;hidden{}&lt;/style&gt;&lt;p&gt;Second paragraph.&lt;/p&gt;</dc:description>
            <dc:publisher>Example Press</dc:publisher>
            <dc:language>en-us</dc:language>
            <dc:date>2024-03-05</dc:date>
            <dc:identifier>urn:uuid:not-an-isbn</dc:identifier>
            <dc:identifier opf:scheme="ISBN" xmlns:opf="opf">978-0-306-40615-7</dc:identifier>
            <dc:subject>Fiction</dc:subject><dc:subject>History</dc:subject>
            <dc:rights>CC BY</dc:rights>
            <dc:source>Local archive</dc:source>
            <dc:type>Text</dc:type>
            <dc:coverage>Ukraine</dc:coverage>
            <meta id="series" property="belongs-to-collection">Chronicles</meta>
            <meta refines="#series" property="collection-type">series</meta>
            <meta refines="#series" property="group-position">2.5</meta>
            <meta property="edition">Third</meta>
            <meta property="dcterms:modified">2025-01-02T03:04:05Z</meta>
          </metadata>
        </package>
      ''',
    }, name: 'rich.epub');

    final metadata =
        (await EpubMetadataParser().parse(epub.path)
                as MetadataExtractionSuccess)
            .metadata;

    expect(metadata.authors, ['Alice Author', 'Bob Author']);
    expect(metadata.contributors, ['Casey Editor']);
    expect(metadata.description, 'First & safe.\nSecond paragraph.');
    expect(metadata.publisher, 'Example Press');
    expect(metadata.language, 'en-US');
    expect(metadata.publishedDate, '2024-03-05');
    expect(metadata.isbn, '9780306406157');
    expect(metadata.identifiers, ['urn:uuid:not-an-isbn', '978-0-306-40615-7']);
    expect(metadata.subjects, ['Fiction', 'History']);
    expect(metadata.rights, 'CC BY');
    expect(metadata.seriesName, 'Chronicles');
    expect(metadata.seriesIndex, 2.5);
    expect(metadata.edition, 'Third');
    expect(metadata.source, 'Local archive');
    expect(metadata.type, 'Text');
    expect(metadata.coverage, 'Ukraine');
    expect(metadata.modifiedDate, '2025-01-02T03:04:05Z');
  });

  test(
    'cleans a Gutenberg-style OPF description before it enters metadata',
    () async {
      final epub = await _writeEpub(directory, {
        'META-INF/container.xml':
            '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
        'book.opf':
            '<package><metadata><dc:title xmlns:dc="x">Title</dc:title><dc:description xmlns:dc="x">Useful prose. (This is an automatically generated summary.) Language: English Rights: Public domain</dc:description></metadata></package>',
      }, name: 'gutenberg-description.epub');

      final metadata =
          (await EpubMetadataParser().parse(epub.path)
                  as MetadataExtractionSuccess)
              .metadata;

      expect(metadata.description, 'Useful prose.');
    },
  );

  test('supports calibre series and rejects malformed optional values', () async {
    final epub = await _writeEpub(directory, {
      'META-INF/container.xml':
          '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
      'book.opf': '''
        <package><metadata>
          <dc:title xmlns:dc="x">Legacy</dc:title>
          <dc:identifier xmlns:dc="x">gutenberg-123</dc:identifier>
          <dc:identifier xmlns:dc="x">978-0-306-40615-8</dc:identifier>
          <dc:language xmlns:dc="x">not a language</dc:language>
          <dc:date xmlns:dc="x">yesterday</dc:date>
          <meta name="calibre:series" content="Legacy Series"/>
          <meta name="calibre:series_index" content="4"/>
        </metadata></package>
      ''',
    }, name: 'legacy-rich.epub');

    final metadata =
        (await EpubMetadataParser().parse(epub.path)
                as MetadataExtractionSuccess)
            .metadata;

    expect(metadata.isbn, isNull);
    expect(metadata.language, isNull);
    expect(metadata.publishedDate, isNull);
    expect(metadata.seriesName, 'Legacy Series');
    expect(metadata.seriesIndex, 4);
    expect(metadata.subjects, isEmpty);
    expect(metadata.rights, isNull);
  });

  test(
    'scans only front spine documents when package metadata lacks ISBN',
    () async {
      final epub = await _writeEpub(directory, {
        'META-INF/container.xml':
            '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
        'book.opf':
            '<package><metadata><dc:title xmlns:dc="x">Book</dc:title></metadata><manifest><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/><item id="two" href="two.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="one"/><itemref idref="two"/></spine></package>',
        'one.xhtml': '<html><body><p>ISBN 978-0-306-40615-7</p></body></html>',
        'two.xhtml': '<html><body>no ISBN</body></html>',
      }, name: 'spine-isbn.epub');

      final metadata =
          (await EpubMetadataParser().parse(epub.path)
                  as MetadataExtractionSuccess)
              .metadata;

      expect(metadata.isbn, '9780306406157');
    },
  );

  test('preserves UTF-8 Ukrainian metadata without mojibake', () async {
    final epub = await _writeEpub(directory, {
      'META-INF/container.xml':
          '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
      'book.opf':
          '<package><metadata><dc:title xmlns:dc="x">Українська книга</dc:title><dc:creator xmlns:dc="x">Тарас Автор</dc:creator><dc:description xmlns:dc="x">Опис українською</dc:description><dc:publisher xmlns:dc="x">Видавництво</dc:publisher></metadata><manifest><item id="cover" href="cover.jpg" properties="cover-image"/></manifest></package>',
      'cover.jpg': Uint8List.fromList([7, 8]),
    });
    final metadata =
        (await EpubMetadataParser().parse(epub.path)
                as MetadataExtractionSuccess)
            .metadata;
    expect(metadata.title, 'Українська книга');
    expect(metadata.authors, ['Тарас Автор']);
    expect(metadata.description, 'Опис українською');
    expect(metadata.publisher, 'Видавництво');
    expect(metadata.coverBytes, [7, 8]);
  });

  test(
    'reports malformed archives and missing required publication files',
    () async {
      final malformed = File(
        '${directory.path}${Platform.pathSeparator}bad.epub',
      );
      await malformed.writeAsString('not a zip');
      final missingContainer = await _writeEpub(directory, {
        'book.opf': '<package/>',
      }, name: 'missing.epub');

      expect(
        await EpubMetadataParser().parse(malformed.path),
        isA<MetadataMalformedPublication>(),
      );
      expect(
        await EpubMetadataParser().parse(missingContainer.path),
        isA<MetadataMalformedPublication>(),
      );
    },
  );
}

Future<File> _writeEpub(
  Directory directory,
  Map<String, Object> entries, {
  String name = 'book.epub',
}) async {
  final archive = Archive();
  for (final entry in entries.entries) {
    final bytes = entry.value is Uint8List
        ? entry.value as Uint8List
        : Uint8List.fromList(utf8.encode(entry.value as String));
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(ZipEncoder().encodeBytes(archive));
  return file;
}

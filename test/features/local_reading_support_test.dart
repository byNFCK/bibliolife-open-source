import 'dart:io';
import 'dart:typed_data';

import 'package:bibliolife/features/metadata/data/parsers/comic_metadata_parser.dart';
import 'package:bibliolife/features/metadata/data/parsers/fb2_metadata_parser.dart';
import 'package:bibliolife/features/metadata/domain/entities/metadata_extraction_result.dart';
import 'package:bibliolife/features/reader/application/services/reflowable_book_loader.dart';
import 'package:bibliolife/features/reader/domain/models/reader_kind.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('local book formats', () {
    test('normalizes every readable local extension', () {
      expect(BookFormat.fromFileName('Story.TXT'), BookFormat.txt);
      expect(BookFormat.fromFileName('comic.CBZ'), BookFormat.cbz);
      expect(BookFormat.fromFileName('book.unknown'), BookFormat.unknown);
      expect(
        BookFormat.supportedExtensions,
        containsAll(['epub', 'pdf', 'fb2', 'cbz', 'txt']),
      );
    });

    test('selects one reader family per normalized format', () {
      expect(readerKindFor(BookFormat.epub), ReaderKind.epub);
      expect(readerKindFor(BookFormat.pdf), ReaderKind.pdf);
      expect(readerKindFor(BookFormat.fb2), ReaderKind.reflowable);
      expect(readerKindFor(BookFormat.txt), ReaderKind.reflowable);
      expect(readerKindFor(BookFormat.cbz), ReaderKind.comic);
      expect(readerKindFor(BookFormat.cbr), ReaderKind.comic);
    });
  });

  test('naturally sorts comic page names', () {
    final pages = ['nested/10.jpg', 'nested/2.jpg', 'nested/1.jpg']
      ..sort(naturalCompare);
    expect(pages, ['nested/1.jpg', 'nested/2.jpg', 'nested/10.jpg']);
  });

  group('plain text decoding', () {
    test('accepts UTF-8 with BOM', () {
      expect(
        decodePlainText(Uint8List.fromList([0xef, 0xbb, 0xbf, 0xd0, 0xa2])),
        'Т',
      );
    });

    test('accepts UTF-16 little and big endian', () {
      expect(
        decodePlainText(Uint8List.fromList([0xff, 0xfe, 0x22, 0x04])),
        'Т',
      );
      expect(
        decodePlainText(Uint8List.fromList([0xfe, 0xff, 0x04, 0x22])),
        'Т',
      );
    });

    test('falls back to Windows-1251 without replacement glyphs', () {
      expect(
        decodePlainText(Uint8List.fromList([0xd2, 0xe5, 0xf1, 0xf2])),
        'Тест',
      );
    });
  });

  test('decodes an FB2 XML declaration using Windows-1251', () {
    final prefix = Uint8List.fromList(
      '<?xml version="1.0" encoding="windows-1251"?><FictionBook><body><p>'
          .codeUnits,
    );
    final suffix = Uint8List.fromList('</p></body></FictionBook>'.codeUnits);
    final bytes = Uint8List.fromList([
      ...prefix,
      0xd2,
      0xe5,
      0xf1,
      0xf2,
      ...suffix,
    ]);
    expect(decodeFb2Xml(bytes), contains('\u0422\u0435\u0441\u0442'));
  });

  test('parses FB2 metadata, cover reference and genres', () async {
    final file = await File(
      '${Directory.systemTemp.path}/bibliolife-fb2-metadata-test.fb2',
    ).create();
    addTearDown(() => file.delete());
    await file.writeAsString(
      '''<?xml version="1.0" encoding="utf-8"?>
<FictionBook xmlns:l="http://www.w3.org/1999/xlink"><description><title-info>
<book-title>Тестова книга</book-title><author><first-name>Іван</first-name><last-name>Автор</last-name></author>
<lang>uk</lang><genre>prose</genre><annotation><p>Опис книги.</p></annotation>
<coverpage><image l:href="#cover"/></coverpage></title-info></description>
<binary id="cover" content-type="image/png">AQID</binary><body><section><p>Текст</p></section></body></FictionBook>''',
    );
    final result = await Fb2MetadataParser().parse(file.path);
    expect(result, isA<MetadataExtractionSuccess>());
    final metadata = (result as MetadataExtractionSuccess).metadata;
    expect(metadata.title, 'Тестова книга');
    expect(metadata.authors, ['Іван Автор']);
    expect(metadata.language, 'uk');
    expect(metadata.subjects, ['prose']);
    expect(metadata.coverBytes, Uint8List.fromList([1, 2, 3]));
  });
}

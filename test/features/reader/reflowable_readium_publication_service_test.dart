import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bibliolife/features/reader/application/services/reflowable_readium_publication_service.dart';
import 'package:bibliolife/features/reader/application/services/reflowable_book_loader.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'bibliolife-readium-reflowable-',
    );
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('TXT becomes a valid cached EPUB with one continuous document', () async {
    final source = File('${temporary.path}/book.txt');
    await source.writeAsString('First paragraph.\n\nSecond paragraph.');
    final cache = Directory('${temporary.path}/cache');
    final service = ReflowableReadiumPublicationService(
      cacheDirectory: () async => cache,
    );
    final book = _book(source.path, BookFormat.txt);

    final events = <Map<String, Object?>>[];
    void observe(String stage, String result, Map<String, Object?> fields) =>
        events.add({'stage': stage, 'result': result, ...fields});
    final first = await service.prepare(book, onDiagnostic: observe);
    final generated = events.last;
    expect(generated['conversionCacheStatus'], 'regenerated');
    events.clear();
    final second = await service.prepare(book, onDiagnostic: observe);
    expect(events.last['conversionCacheStatus'], 'hit');
    expect(
      events.last['generatedPublicationId'],
      generated['generatedPublicationId'],
    );
    expect(events.any((e) => e['stage'] == 'text_decode'), false);

    expect(second, first);
    final archive = ZipDecoder().decodeBytes(await File(first).readAsBytes());
    expect(_text(archive.findFile('mimetype')!), 'application/epub+zip');
    expect(archive.findFile('mimetype')?.compression, CompressionType.none);
    final content = _text(archive.findFile('OEBPS/text/content.xhtml')!);
    expect(content, contains('First paragraph.'));
    expect(content, contains('class="empty-line"'));
    expect(
      content,
      contains('class="empty-line" aria-hidden="true">&#160;</p>'),
    );
    expect(content, contains('Second paragraph.'));
    expect(content, isNot(contains('PageView')));
    _expectAppearanceNeutralCss(content);
    expect(
      File(
        'lib/features/reader/application/services/reflowable_readium_publication_service.dart',
      ).readAsStringSync(),
      isNot(contains('ReaderSettingsState')),
    );
  });

  test('FB2 headings and emphasis become Readium XHTML and TOC', () async {
    final source = File('${temporary.path}/book.fb2');
    await source.writeAsString(
      '''<?xml version="1.0" encoding="utf-8"?>
<FictionBook><body><section><title><p>Chapter One</p></title>
<p>Before <emphasis>inside</emphasis> after.</p></section></body></FictionBook>''',
    );
    final service = ReflowableReadiumPublicationService(
      cacheDirectory: () async => Directory('${temporary.path}/cache'),
    );

    final output = await service.prepare(_book(source.path, BookFormat.fb2));
    final archive = ZipDecoder().decodeBytes(await File(output).readAsBytes());
    final content = _text(archive.findFile('OEBPS/text/content.xhtml')!);
    final nav = _text(archive.findFile('OEBPS/nav.xhtml')!);

    expect(content, contains('<h1 id="block-0">Chapter One</h1>'));
    expect(content, contains('<em>inside</em>'));
    expect(nav, contains('Chapter One'));
    expect(nav, contains('text/content.xhtml#block-0'));
    _expectAppearanceNeutralCss(content);
  });

  test(
    'cache identity is source revision only and avoids repeat parsing',
    () async {
      final source = File('${temporary.path}/book.txt');
      await source.writeAsString('first');
      final loader = _CountingLoader();
      final service = ReflowableReadiumPublicationService(
        loader: loader,
        cacheDirectory: () async => Directory('${temporary.path}/cache'),
      );
      final book = _book(source.path, BookFormat.txt);

      final first = await service.prepare(book);
      final cached = await service.prepare(book);
      expect(cached, first);
      expect(loader.calls, 1);

      await source.writeAsString('second source revision');
      final revised = await service.prepare(book);
      expect(revised, isNot(first));
      expect(loader.calls, 2);
    },
  );
  test(
    'decode failure is attributed once without logging exception contents',
    () async {
      final source = File('${temporary.path}/secret.txt');
      await source.writeAsString('SECRET BOOK TEXT');
      final events = <Map<String, Object?>>[];
      final service = ReflowableReadiumPublicationService(
        loader: _FailingLoader(),
        cacheDirectory: () async => Directory('${temporary.path}/cache'),
      );
      await expectLater(
        service.prepare(
          _book(source.path, BookFormat.txt),
          onDiagnostic: (stage, result, fields) =>
              events.add({'stage': stage, 'result': result, ...fields}),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(events.where((e) => e['result'] == 'failed'), hasLength(1));
      expect(events.last['stage'], 'text_decode');
      expect(jsonEncode(events), isNot(contains('SECRET')));
    },
  );
  test('a throwing diagnostic observer cannot change conversion', () async {
    final source = File('${temporary.path}/book.txt');
    await source.writeAsString('content');
    final service = ReflowableReadiumPublicationService(
      cacheDirectory: () async => Directory('${temporary.path}/cache'),
    );
    final output = await service.prepare(
      _book(source.path, BookFormat.txt),
      onDiagnostic: (_, _, _) => throw StateError('observer'),
    );
    expect(await File(output).exists(), true);
  });
}

class _CountingLoader extends ReflowableBookLoader {
  int calls = 0;

  @override
  Future<ReflowableBook> load(LibraryBook book) async {
    calls++;
    return const ReflowableBook(
      blocks: [
        ReflowBlock.text(ReflowBlockKind.paragraph, [ReflowSpan('content')]),
      ],
    );
  }
}

void _expectAppearanceNeutralCss(String content) {
  final style = RegExp(
    r'<style>(.*?)</style>',
    dotAll: true,
  ).firstMatch(content)!.group(1)!;
  expect(style, isNot(contains('font-family')));
  expect(style, isNot(contains('font-size')));
  expect(style, isNot(contains('line-height')));
  expect(style, isNot(contains('text-align')));
  expect(style, isNot(contains('color:')));
  expect(style, isNot(contains('body{margin')));
}

String _text(ArchiveFile file) => utf8.decode(file.readBytes()!);

LibraryBook _book(String filePath, BookFormat format) => LibraryBook(
  id: 'book-${format.name}',
  title: 'Converted title',
  sortTitle: null,
  author: 'Author',
  description: null,
  filePath: filePath,
  fileName: 'book.${format.normalizedExtension}',
  fileExtension: format.normalizedExtension,
  format: format,
  mediaType: null,
  coverPath: null,
  language: 'en',
  publisher: null,
  publishedDate: null,
  isbn: null,
  pageCount: null,
  fileSizeBytes: File(filePath).lengthSync(),
  dateAdded: DateTime(2026),
  lastOpenedAt: null,
  isFavorite: false,
);

class _FailingLoader extends ReflowableBookLoader {
  @override
  Future<ReflowableBook> load(LibraryBook book) async =>
      throw const FormatException('SECRET BOOK TEXT /private/path');
}

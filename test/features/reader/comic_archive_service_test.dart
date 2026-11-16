import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bibliolife/features/reader/application/services/comic_archive_service.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('bibliolife-comic-');
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test(
    'CBZ cache hit uses page manifest without rescanning extraction',
    () async {
      final source = File('${temporary.path}/book.cbz');
      final archive = Archive()
        ..addFile(ArchiveFile('2.jpg', 1, <int>[2]))
        ..addFile(ArchiveFile('1.jpg', 1, <int>[1]));
      await source.writeAsBytes(ZipEncoder().encodeBytes(archive));
      final cache = Directory('${temporary.path}/cache');
      final service = ComicArchiveService(cacheDirectory: () async => cache);

      final first = await service.prepare(_book(source.path));
      expect(first.pages.map((value) => value.split(RegExp(r'[/\\]')).last), [
        '1.jpg',
        '2.jpg',
      ]);

      final manifest = cache
          .listSync(recursive: true)
          .whereType<File>()
          .singleWhere((value) => value.path.endsWith('.pages.json'));
      await File('${manifest.parent.path}/3.jpg').writeAsBytes(<int>[3]);

      final second = await service.prepare(_book(source.path));
      expect(
        second.pages.length,
        2,
        reason: 'cache hit must trust the manifest',
      );
    },
  );
}

LibraryBook _book(String filePath) => LibraryBook(
  id: 'comic-book',
  title: 'Comic',
  sortTitle: null,
  author: null,
  description: null,
  filePath: filePath,
  fileName: 'book.cbz',
  fileExtension: 'cbz',
  format: BookFormat.cbz,
  mediaType: null,
  coverPath: null,
  language: null,
  publisher: null,
  publishedDate: null,
  isbn: null,
  pageCount: null,
  fileSizeBytes: File(filePath).lengthSync(),
  dateAdded: DateTime(2026),
  lastOpenedAt: null,
  isFavorite: false,
);

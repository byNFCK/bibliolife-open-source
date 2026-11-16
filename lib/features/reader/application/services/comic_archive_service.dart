import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:bibliolife/features/metadata/data/parsers/comic_metadata_parser.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

enum ComicArchiveFailure { missingFile, corrupt, encrypted, unsupported }

class ComicArchiveException implements Exception {
  const ComicArchiveException(this.failure);
  final ComicArchiveFailure failure;
}

class ComicArchiveService {
  ComicArchiveService({ComicCacheDirectoryProvider? cacheDirectory})
    : _cacheDirectory = cacheDirectory ?? getApplicationCacheDirectory;

  final ComicCacheDirectoryProvider _cacheDirectory;

  Future<ComicArchive> prepare(LibraryBook book) async {
    if (book.format != BookFormat.cbz) {
      throw const ComicArchiveException(ComicArchiveFailure.unsupported);
    }
    final source = File(book.filePath);
    if (!await source.exists()) {
      throw const ComicArchiveException(ComicArchiveFailure.missingFile);
    }
    final stat = await source.stat();
    final signature = '${stat.size}-${stat.modified.millisecondsSinceEpoch}';
    final root = Directory(
      path.join((await _cacheDirectory()).path, 'bibliolife-comics', book.id),
    );
    final output = Directory(path.join(root.path, signature));
    final cacheHit = await _valid(output);
    if (cacheHit) {
      final cachedPages = await _readPageManifest(output);
      if (cachedPages != null) return ComicArchive(cachedPages);
    } else {
      await _removeStaleDirectories(root, signature);
      if (await output.exists()) await output.delete(recursive: true);
      await output.create(recursive: true);
      try {
        await Isolate.run(() => _extractCbz(book.filePath, output.path));
      } on ComicArchiveException {
        if (await output.exists()) await output.delete(recursive: true);
        rethrow;
      } on Object {
        if (await output.exists()) await output.delete(recursive: true);
        throw const ComicArchiveException(ComicArchiveFailure.corrupt);
      }
    }
    final pages = await _scanPages(output);
    if (pages.isEmpty) {
      throw const ComicArchiveException(ComicArchiveFailure.corrupt);
    }
    await _writePageManifest(output, pages);
    if (!cacheHit) {
      await File(path.join(output.path, '.complete')).writeAsString(signature);
    }
    return ComicArchive(List.unmodifiable(pages));
  }

  Future<List<String>> _scanPages(Directory output) async {
    final pages = await output
        .list(recursive: true, followLinks: false)
        .where((entry) => entry is File && isComicImagePath(entry.path))
        .cast<File>()
        .toList();
    pages.sort(
      (a, b) => naturalCompare(
        path.relative(a.path, from: output.path),
        path.relative(b.path, from: output.path),
      ),
    );
    return pages.map((page) => page.path).toList(growable: false);
  }

  Future<List<String>?> _readPageManifest(Directory output) async {
    final manifest = File(path.join(output.path, '.pages.json'));
    if (!await manifest.exists()) return null;
    try {
      final decoded = jsonDecode(await manifest.readAsString());
      if (decoded is! List || decoded.isEmpty) return null;
      final relativePages = decoded.whereType<String>().toList(growable: false);
      if (relativePages.length != decoded.length ||
          relativePages.any(
            (value) =>
                path.isAbsolute(value) ||
                path.normalize(value).split(path.separator).contains('..'),
          )) {
        return null;
      }
      return List.unmodifiable(
        relativePages.map((value) => path.join(output.path, value)),
      );
    } on Object {
      return null;
    }
  }

  Future<void> _writePageManifest(Directory output, List<String> pages) =>
      File(path.join(output.path, '.pages.json')).writeAsString(
        jsonEncode(
          pages
              .map((value) => path.relative(value, from: output.path))
              .toList(),
        ),
        flush: true,
      );

  Future<void> _removeStaleDirectories(Directory root, String keep) async {
    if (!await root.exists()) return;
    await for (final entry in root.list(followLinks: false)) {
      if (entry is Directory && path.basename(entry.path) != keep) {
        await entry.delete(recursive: true);
      }
    }
  }

  Future<bool> _valid(Directory directory) async =>
      await File(path.join(directory.path, '.complete')).exists();
}

typedef ComicCacheDirectoryProvider = Future<Directory> Function();

class ComicArchive {
  const ComicArchive(this.pages);
  final List<String> pages;
}

void _extractCbz(String sourcePath, String destinationPath) {
  final input = InputFileStream(sourcePath);
  try {
    final archive = ZipDecoder().decodeStream(input, verify: true);
    for (final entry in archive.files) {
      if (entry.isDirectory || !isComicImagePath(entry.name)) continue;
      final relative = path.normalize(entry.name).replaceAll('\\', '/');
      if (relative.startsWith('/') || relative.split('/').contains('..')) {
        throw const ComicArchiveException(ComicArchiveFailure.corrupt);
      }
      final output = File(
        path.joinAll([destinationPath, ...relative.split('/')]),
      );
      output.parent.createSync(recursive: true);
      output.writeAsBytesSync(entry.readBytes()!, flush: true);
    }
  } on ArchiveException {
    throw const ComicArchiveException(ComicArchiveFailure.corrupt);
  } finally {
    input.closeSync();
  }
}

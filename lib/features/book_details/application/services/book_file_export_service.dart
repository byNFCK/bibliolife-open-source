import 'dart:io';

import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:path/path.dart' as path;

enum BookFileSaveOutcome { saved, cancelled, failed, unavailable, busy }

abstract interface class BookFileSaver {
  Future<BookFileSaveOutcome> save({
    required String sourcePath,
    required String fileName,
    required String mimeType,
    required int sizeBytes,
  });
}

class BookFileExportSource {
  const BookFileExportSource({
    required this.path,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String path;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
}

class BookFileExportService {
  const BookFileExportService(this._saver);

  final BookFileSaver _saver;

  Future<BookFileSaveOutcome> export(LibraryBook book) async {
    final source = await resolveSource(book);
    if (source == null) return BookFileSaveOutcome.unavailable;
    try {
      return await _saver.save(
        sourcePath: source.path,
        fileName: source.fileName,
        mimeType: source.mimeType,
        sizeBytes: source.sizeBytes,
      );
    } on Object {
      return BookFileSaveOutcome.failed;
    }
  }

  Future<BookFileExportSource?> resolveSource(LibraryBook book) async {
    final extension = book.format.normalizedExtension;
    if (extension.isEmpty) return null;
    final expectedSize = book.fileSizeBytes;
    if (expectedSize <= 0) return null;

    final managed = File(book.filePath);
    final managedStatus = await _status(managed);
    if (managedStatus != null) {
      if (managedStatus.type != FileSystemEntityType.file ||
          managedStatus.size <= 0 ||
          managedStatus.size != expectedSize ||
          !_hasFormatExtension(book.filePath, extension)) {
        return null;
      }
      return _source(book, book.filePath, managedStatus.size, extension);
    }

    final originalPath = book.originalFilePath;
    if (originalPath == null ||
        originalPath.isEmpty ||
        !_hasFormatExtension(originalPath, extension)) {
      return null;
    }
    final original = File(originalPath);
    final originalStatus = await _status(original);
    if (originalStatus == null ||
        originalStatus.type != FileSystemEntityType.file ||
        originalStatus.size <= 0 ||
        originalStatus.size != expectedSize) {
      return null;
    }
    return _source(book, originalPath, originalStatus.size, extension);
  }

  Future<FileStat?> _status(File file) async {
    try {
      final stat = await file.stat();
      return stat.type == FileSystemEntityType.notFound ? null : stat;
    } on FileSystemException {
      return null;
    }
  }

  BookFileExportSource _source(
    LibraryBook book,
    String sourcePath,
    int size,
    String extension,
  ) {
    final originalName = path.basename(book.fileName.trim());
    final validStoredName = _hasFormatExtension(originalName, extension);
    final name = _safeName(
      validStoredName ? originalName : '${book.title}.$extension',
      extension,
    );
    return BookFileExportSource(
      path: sourcePath,
      fileName: name,
      mimeType: _mimeType(book.format),
      sizeBytes: size,
    );
  }

  bool _hasFormatExtension(String value, String extension) =>
      path.extension(value).toLowerCase() == '.$extension';

  String _safeName(String candidate, String extension) {
    final sanitized = candidate
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    final basename = path.basenameWithoutExtension(sanitized);
    final safeBase = basename.isEmpty ? 'book' : basename;
    return '$safeBase.$extension';
  }

  String _mimeType(BookFormat format) => switch (format) {
    BookFormat.epub => 'application/epub+zip',
    BookFormat.pdf => 'application/pdf',
    BookFormat.fb2 => 'application/x-fictionbook+xml',
    BookFormat.cbz => 'application/vnd.comicbook+zip',
    BookFormat.cbr => 'application/vnd.comicbook-rar',
    BookFormat.txt => 'text/plain',
    BookFormat.unknown => 'application/octet-stream',
  };
}

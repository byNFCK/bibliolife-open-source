import 'dart:io';

import 'package:bibliolife/features/book_details/application/services/book_file_export_service.dart';
import 'package:bibliolife/features/book_details/data/services/android_book_file_saver.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;
  late _RecordingSaver saver;
  late BookFileExportService service;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'book-export-test-',
    );
    saver = _RecordingSaver();
    service = BookFileExportService(saver);
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'all supported formats keep their original extension and MIME type',
    () async {
      const formats = {
        BookFormat.epub: ('epub', 'application/epub+zip'),
        BookFormat.pdf: ('pdf', 'application/pdf'),
        BookFormat.fb2: ('fb2', 'application/x-fictionbook+xml'),
        BookFormat.cbz: ('cbz', 'application/vnd.comicbook+zip'),
        BookFormat.cbr: ('cbr', 'application/vnd.comicbook-rar'),
        BookFormat.txt: ('txt', 'text/plain'),
      };

      for (final entry in formats.entries) {
        final bytes = [1, 2, 3, 4];
        final source = File(
          '${temporaryDirectory.path}/source.${entry.value.$1}',
        );
        await source.writeAsBytes(bytes);
        final book = _book(
          format: entry.key,
          fileExtension: entry.value.$1,
          fileName: 'An original.${entry.value.$1}',
          filePath: source.path,
          fileSizeBytes: bytes.length,
        );

        final resolved = await service.resolveSource(book);
        expect(resolved?.path, source.path);
        expect(resolved?.fileName, 'An original.${entry.value.$1}');
        expect(resolved?.mimeType, entry.value.$2);
      }
    },
  );

  test('managed original is preferred and source remains untouched', () async {
    final managed = File('${temporaryDirectory.path}/managed.fb2');
    final external = File('${temporaryDirectory.path}/external.fb2');
    await managed.writeAsBytes([1, 2, 3, 4]);
    await external.writeAsBytes([5, 6, 7, 8]);

    final outcome = await service.export(
      _book(
        format: BookFormat.fb2,
        fileExtension: 'fb2',
        fileName: 'Source.fb2',
        filePath: managed.path,
        originalFilePath: external.path,
        fileSizeBytes: 4,
      ),
    );

    expect(outcome, BookFileSaveOutcome.saved);
    expect(saver.sourcePath, managed.path);
    expect(await managed.readAsBytes(), [1, 2, 3, 4]);
    expect(await external.readAsBytes(), [5, 6, 7, 8]);
  });

  test(
    'uses validated external original only when managed copy is missing',
    () async {
      final original = File('${temporaryDirectory.path}/original.txt');
      await original.writeAsBytes([1, 2, 3]);
      final result = await service.resolveSource(
        _book(
          format: BookFormat.txt,
          fileExtension: 'txt',
          fileName: 'Original.txt',
          filePath: '${temporaryDirectory.path}/missing.txt',
          originalFilePath: original.path,
          fileSizeBytes: 3,
        ),
      );

      expect(result?.path, original.path);
      expect(result?.fileName, 'Original.txt');
    },
  );

  test(
    'never exports a mismatched, empty, missing, or unknown source',
    () async {
      final mismatched = File('${temporaryDirectory.path}/source.epub');
      final empty = File('${temporaryDirectory.path}/empty.pdf');
      await mismatched.writeAsBytes([1, 2, 3]);
      await empty.writeAsBytes([]);

      for (final book in [
        _book(
          format: BookFormat.fb2,
          fileExtension: 'fb2',
          filePath: mismatched.path,
          originalFilePath: mismatched.path,
          fileSizeBytes: 3,
        ),
        _book(
          format: BookFormat.pdf,
          fileExtension: 'pdf',
          filePath: empty.path,
          fileSizeBytes: 1,
        ),
        _book(
          filePath: '${temporaryDirectory.path}/gone.epub',
          fileSizeBytes: 3,
        ),
        _book(
          format: BookFormat.unknown,
          fileExtension: '',
          filePath: mismatched.path,
          fileSizeBytes: 3,
        ),
      ]) {
        expect(await service.export(book), BookFileSaveOutcome.unavailable);
      }
      expect(saver.calls, 0);
    },
  );

  test('fallback requires matching format and exact imported size', () async {
    final wrongFormat = File('${temporaryDirectory.path}/original.epub');
    final wrongSize = File('${temporaryDirectory.path}/original.fb2');
    await wrongFormat.writeAsBytes([1, 2, 3]);
    await wrongSize.writeAsBytes([1, 2]);

    expect(
      await service.resolveSource(
        _book(
          format: BookFormat.fb2,
          fileExtension: 'fb2',
          filePath: '${temporaryDirectory.path}/missing.fb2',
          originalFilePath: wrongFormat.path,
          fileSizeBytes: 3,
        ),
      ),
      isNull,
    );
    expect(
      await service.resolveSource(
        _book(
          format: BookFormat.fb2,
          fileExtension: 'fb2',
          filePath: '${temporaryDirectory.path}/missing.fb2',
          originalFilePath: wrongSize.path,
          fileSizeBytes: 3,
        ),
      ),
      isNull,
    );
  });

  test(
    'stored filename extension is corrected and unsafe characters removed',
    () async {
      final source = File('${temporaryDirectory.path}/safe.epub');
      await source.writeAsBytes([1]);
      final resolved = await service.resolveSource(
        _book(
          title: 'A title',
          fileName: r'bad:name.pdf',
          filePath: source.path,
          fileSizeBytes: 1,
        ),
      );
      expect(resolved?.fileName, 'A title.epub');
    },
  );

  test('cancel and platform failure remain distinct outcomes', () async {
    final source = File('${temporaryDirectory.path}/book.epub');
    await source.writeAsBytes([1, 2]);
    final book = _book(filePath: source.path, fileSizeBytes: 2);

    saver.outcome = BookFileSaveOutcome.cancelled;
    expect(await service.export(book), BookFileSaveOutcome.cancelled);
    saver.outcome = BookFileSaveOutcome.failed;
    expect(await service.export(book), BookFileSaveOutcome.failed);
    expect(saver.calls, 2);
  });

  test(
    'Android adapter sends only file metadata and maps picker outcomes',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('bibliolife/book-file-save-test');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      var status = 'saved';
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {'status': status};
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final adapter = AndroidBookFileSaver(channel: channel);

      expect(
        await adapter.save(
          sourcePath: '/managed/original.fb2',
          fileName: 'Book.fb2',
          mimeType: 'application/x-fictionbook+xml',
          sizeBytes: 1234,
        ),
        BookFileSaveOutcome.saved,
      );
      expect(calls.single.method, 'save');
      expect(calls.single.arguments, {
        'sourcePath': '/managed/original.fb2',
        'fileName': 'Book.fb2',
        'mimeType': 'application/x-fictionbook+xml',
        'sizeBytes': 1234,
      });
      status = 'cancelled';
      expect(
        await adapter.save(
          sourcePath: '/managed/original.fb2',
          fileName: 'Book.fb2',
          mimeType: 'application/x-fictionbook+xml',
          sizeBytes: 1234,
        ),
        BookFileSaveOutcome.cancelled,
      );
      status = 'busy';
      expect(
        await adapter.save(
          sourcePath: '/managed/original.fb2',
          fileName: 'Book.fb2',
          mimeType: 'application/x-fictionbook+xml',
          sizeBytes: 1234,
        ),
        BookFileSaveOutcome.busy,
      );
      status = 'failed';
      expect(
        await adapter.save(
          sourcePath: '/managed/original.fb2',
          fileName: 'Book.fb2',
          mimeType: 'application/x-fictionbook+xml',
          sizeBytes: 1234,
        ),
        BookFileSaveOutcome.failed,
      );
    },
  );
}

class _RecordingSaver implements BookFileSaver {
  BookFileSaveOutcome outcome = BookFileSaveOutcome.saved;
  int calls = 0;
  String? sourcePath;

  @override
  Future<BookFileSaveOutcome> save({
    required String sourcePath,
    required String fileName,
    required String mimeType,
    required int sizeBytes,
  }) async {
    calls++;
    this.sourcePath = sourcePath;
    return outcome;
  }
}

LibraryBook _book({
  BookFormat format = BookFormat.epub,
  String fileExtension = 'epub',
  String fileName = 'Book.epub',
  String filePath = '/missing/book.epub',
  String? originalFilePath,
  int fileSizeBytes = 1,
  String title = 'Book',
}) => LibraryBook(
  id: 'book',
  title: title,
  sortTitle: null,
  author: null,
  description: null,
  filePath: filePath,
  originalFilePath: originalFilePath,
  fileName: fileName,
  fileExtension: fileExtension,
  format: format,
  mediaType: null,
  coverPath: null,
  language: null,
  publisher: null,
  publishedDate: null,
  isbn: null,
  pageCount: null,
  fileSizeBytes: fileSizeBytes,
  dateAdded: DateTime(2026),
  lastOpenedAt: null,
  isFavorite: false,
);

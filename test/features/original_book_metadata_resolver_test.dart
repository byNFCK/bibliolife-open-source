import 'dart:io';
import 'dart:typed_data';

import 'package:bibliolife/features/book_details/application/services/original_book_metadata_resolver.dart';
import 'package:bibliolife/features/metadata/data/services/cover_storage_service.dart';
import 'package:bibliolife/features/metadata/domain/entities/extracted_book_metadata.dart';
import 'package:bibliolife/features/metadata/domain/entities/metadata_extraction_result.dart';
import 'package:bibliolife/features/metadata/domain/repositories/book_metadata_repository.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late _MetadataRepository repository;
  late OriginalBookMetadataResolver resolver;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('original-metadata-');
    repository = _MetadataRepository();
    resolver = OriginalBookMetadataResolver(
      metadataRepository: repository,
      imageValidator: const _ImageValidator(),
    );
  });

  tearDown(() => root.delete(recursive: true));

  test(
    'resolves trusted parser metadata from the managed source file',
    () async {
      final source = File('${root.path}/managed.epub')..writeAsBytesSync([1]);
      repository.result = MetadataExtractionSuccess(
        _metadata(
          title: 'Source title',
          authors: const ['Source author'],
          coverBytes: Uint8List.fromList([1, 2]),
          coverExtension: 'png',
        ),
      );

      final result = await resolver.resolve(
        _book(filePath: source.path, fileName: 'Original.epub'),
      );

      expect(repository.filePath, source.path);
      expect(repository.format, BookFormat.epub);
      expect(result.title, 'Source title');
      expect(result.author, 'Source author');
      expect(result.coverBytes, [1, 2]);
      expect(result.coverExtension, 'png');
    },
  );

  test(
    'uses the import filename fallback for valid TXT and CBR sources',
    () async {
      for (final entry in [
        (BookFormat.txt, 'notes.txt', 'notes.txt'),
        (BookFormat.cbr, 'comic.cbr', 'comic.cbr'),
      ]) {
        final source = File('${root.path}/${entry.$2}')..writeAsBytesSync([1]);
        repository.result = const MetadataUnsupportedFormat();

        final result = await resolver.resolve(
          _book(format: entry.$1, filePath: source.path, fileName: entry.$2),
        );

        expect(result.title, entry.$3);
        expect(result.author, isNull);
        expect(result.coverBytes, isNull);
        expect(repository.filePath, source.path);
      }
    },
  );

  test(
    'rejects missing, empty, mismatched and unreadable source files',
    () async {
      final empty = File('${root.path}/empty.epub')..createSync();
      final nonempty = File('${root.path}/source.epub')..writeAsBytesSync([1]);

      await expectLater(
        resolver.resolve(_book(filePath: '${root.path}/missing.epub')),
        throwsA(isA<OriginalBookMetadataUnavailable>()),
      );
      await expectLater(
        resolver.resolve(_book(filePath: empty.path)),
        throwsA(isA<OriginalBookMetadataUnavailable>()),
      );
      await expectLater(
        resolver.resolve(
          _book(filePath: nonempty.path, format: BookFormat.pdf),
        ),
        throwsA(isA<OriginalBookMetadataUnavailable>()),
      );
      repository.result = const MetadataFileReadFailed();
      await expectLater(
        resolver.resolve(_book(filePath: nonempty.path)),
        throwsA(isA<OriginalBookMetadataUnavailable>()),
      );
    },
  );

  test(
    'does not return partial metadata for an invalid extracted cover',
    () async {
      final source = File('${root.path}/source.epub')..writeAsBytesSync([1]);
      repository.result = MetadataExtractionSuccess(
        _metadata(
          title: 'Parser title',
          authors: const ['Parser author'],
          coverBytes: Uint8List.fromList([1]),
          coverExtension: 'exe',
        ),
      );

      await expectLater(
        resolver.resolve(_book(filePath: source.path)),
        throwsA(isA<OriginalBookMetadataUnavailable>()),
      );
    },
  );

  test(
    'rejects stable title fallback instead of using edited book metadata',
    () async {
      final source = File('${root.path}/book.epub')..writeAsBytesSync([1]);
      repository.result = MetadataExtractionSuccess(_metadata());

      await expectLater(
        resolver.resolve(
          _book(
            filePath: source.path,
            fileName: '550e8400-e29b-41d4-a716-446655440000.epub',
            title: 'Manually edited title',
          ),
        ),
        throwsA(isA<OriginalBookMetadataUnavailable>()),
      );
    },
  );
}

ExtractedBookMetadata _metadata({
  String? title,
  List<String> authors = const [],
  Uint8List? coverBytes,
  String? coverExtension,
}) => ExtractedBookMetadata(
  title: title,
  sortTitle: null,
  authors: authors,
  description: null,
  language: null,
  publisher: null,
  publishedDate: null,
  isbn: null,
  coverBytes: coverBytes,
  coverExtension: coverExtension,
  mediaType: null,
);

LibraryBook _book({
  String title = 'Edited title',
  String filePath = 'managed.epub',
  String fileName = 'book.epub',
  BookFormat format = BookFormat.epub,
}) => LibraryBook(
  id: 'original-resolver',
  title: title,
  sortTitle: null,
  author: 'Edited author',
  description: null,
  filePath: filePath,
  originalFilePath: 'external-source.epub',
  fileName: fileName,
  fileExtension: format.normalizedExtension,
  format: format,
  mediaType: null,
  coverPath: null,
  language: null,
  publisher: null,
  publishedDate: null,
  isbn: null,
  pageCount: null,
  fileSizeBytes: 1,
  dateAdded: DateTime(2026),
  lastOpenedAt: null,
  isFavorite: false,
);

class _MetadataRepository implements BookMetadataRepository {
  MetadataExtractionResult result = const MetadataParsingFailed();
  String? filePath;
  BookFormat? format;

  @override
  Future<MetadataExtractionResult> extractMetadata({
    required String filePath,
    required BookFormat format,
  }) async {
    this.filePath = filePath;
    this.format = format;
    return result;
  }
}

class _ImageValidator implements CoverImageValidator {
  const _ImageValidator();

  @override
  Future<bool> isDecodable(Uint8List bytes) async => bytes.isNotEmpty;
}

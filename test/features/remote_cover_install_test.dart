import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bibliolife/features/catalog_sources/data/remote_cache_service.dart';
import 'package:bibliolife/features/import/data/services/book_importer.dart';
import 'package:bibliolife/features/import/data/services/import_file_picker.dart';
import 'package:bibliolife/features/import/domain/entities/import_result.dart';
import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';
import 'package:bibliolife/features/metadata/data/services/cover_storage_service.dart';
import 'package:bibliolife/features/metadata/domain/entities/extracted_book_metadata.dart';
import 'package:bibliolife/features/metadata/domain/entities/metadata_extraction_result.dart';
import 'package:bibliolife/features/metadata/domain/entities/trusted_remote_book_metadata.dart';
import 'package:bibliolife/features/metadata/domain/repositories/book_metadata_repository.dart';
import 'package:bibliolife/shared/models/book_cover_provenance.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory documents;
  late File source;
  var importNumber = 0;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('remote-cover-install-');
    documents = Directory('${root.path}${Platform.pathSeparator}documents');
    await documents.create();
    source = File('${root.path}${Platform.pathSeparator}download.epub');
    await source.writeAsBytes([0, 1, 2]);
  });
  tearDown(() => root.delete(recursive: true));

  Future<void> drainBackgroundPromotion() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<_Harness> harness({
    Uint8List? remoteBytes,
    Uint8List? embeddedBytes,
    Future<Uint8List?> Function()? remoteFetcher,
  }) async {
    final repository = _Repository();
    final bookId = 'installed-${++importNumber}';
    var physicalRequests = 0;
    final cache = RemoteCacheService(
      cacheDirectory: () async =>
          Directory('${root.path}${Platform.pathSeparator}cache'),
      validateFetchedCovers: false,
      coverFetcher: (_) async {
        physicalRequests++;
        return remoteFetcher == null ? remoteBytes : remoteFetcher();
      },
      availableBytes: () async => 1024 * 1024 * 1024,
    );
    final importer = BookImporter(
      filePicker: const _NoPicker(),
      libraryRepository: repository,
      metadataRepository: _Metadata(embeddedBytes),
      coverStorageService: CoverStorageService(
        documentsDirectory: () async => documents,
        imageValidator: const _FixtureImageValidator(),
      ),
      remoteCache: cache,
      documentsDirectory: () async => documents,
      idGenerator: () => bookId,
    );
    return _Harness(importer, repository, cache, () => physicalRequests);
  }

  test(
    'online cover is promoted durably and beats a different embedded cover',
    () async {
      final fixture = await harness(
        remoteBytes: Uint8List.fromList([1, 1, 1]),
        embeddedBytes: Uint8List.fromList([2, 2, 2]),
      );
      await fixture.cache.cover(_remoteMetadata.coverLocation!);
      expect(fixture.physicalRequestCount(), 1);

      final result = await fixture.importer.importLocalFile(
        PickedImportFile(path: source.path, name: 'download.epub'),
        remoteMetadata: _remoteMetadata,
      );
      final book = (result as ImportSuccess).book;
      final saved = await fixture.repository.getBookById(book.id);

      expect(saved?.coverProvenance, BookCoverProvenance.online);
      expect(fixture.physicalRequestCount(), 1);
      expect(saved?.coverPath, startsWith(documents.path));
      expect(await File(saved!.coverPath!).readAsBytes(), [1, 1, 1]);
      final refreshed = await fixture.importer.refreshBookMetadata(saved.id);
      expect(refreshed?.coverProvenance, BookCoverProvenance.online);
      expect(await File(refreshed!.coverPath!).readAsBytes(), [1, 1, 1]);
      await fixture.cache.clear();
      expect(await File(saved.coverPath!).exists(), isTrue);
    },
  );

  test(
    'missing or broken online cover starts as placeholder then uses embedded',
    () async {
      for (final remote in <Uint8List?>[
        null,
        Uint8List.fromList([9, 9, 9]),
      ]) {
        final fixture = await harness(
          remoteBytes: remote,
          embeddedBytes: Uint8List.fromList([2, 2, 2]),
        );
        final update = fixture.repository.nextUpdate;
        final result = await fixture.importer.importLocalFile(
          PickedImportFile(path: source.path, name: 'download.epub'),
          remoteMetadata: _remoteMetadata,
        );
        expect(
          (result as ImportSuccess).book.coverProvenance,
          BookCoverProvenance.none,
        );

        final updated = await update;
        expect(updated.coverProvenance, BookCoverProvenance.embedded);
        expect(await File(updated.coverPath!).readAsBytes(), [2, 2, 2]);
        await drainBackgroundPromotion();
      }
    },
  );

  test(
    'no valid remote or embedded cover keeps the placeholder state',
    () async {
      final fixture = await harness(remoteBytes: Uint8List.fromList([9]));
      final result = await fixture.importer.importLocalFile(
        PickedImportFile(path: source.path, name: 'download.epub'),
        remoteMetadata: _remoteMetadata,
      );

      final saved = await fixture.repository.getBookById(
        (result as ImportSuccess).book.id,
      );
      expect(saved?.coverPath, isNull);
      expect(saved?.coverProvenance, BookCoverProvenance.none);
      await Future<void>.delayed(Duration.zero);
      expect(fixture.repository.updateCount, 0);
      await drainBackgroundPromotion();
    },
  );

  test('deleting an installed book removes only its durable cover', () async {
    final fixture = await harness(remoteBytes: Uint8List.fromList([1, 1, 1]));
    await fixture.cache.cover(_remoteMetadata.coverLocation!);
    final result = await fixture.importer.importLocalFile(
      PickedImportFile(path: source.path, name: 'download.epub'),
      remoteMetadata: _remoteMetadata,
    );
    final book = (result as ImportSuccess).book;
    final saved = (await fixture.repository.getBookById(book.id))!;
    final cover = File(saved.coverPath!);
    final unrelated = File(
      '${documents.path}${Platform.pathSeparator}covers${Platform.pathSeparator}other.png',
    );
    await unrelated.parent.create(recursive: true);
    await unrelated.writeAsBytes([1]);

    await fixture.importer.removeImportedFile(saved);

    expect(await cover.exists(), isFalse);
    expect(await unrelated.exists(), isTrue);
  });

  test(
    'cold remote promotion is coalesced and does not delay import',
    () async {
      final cover = Completer<Uint8List?>();
      final fixture = await harness(remoteFetcher: () => cover.future);
      final firstUpdate = fixture.repository.nextUpdate;

      final result = await fixture.importer.importLocalFile(
        PickedImportFile(path: source.path, name: 'download.epub'),
        remoteMetadata: _remoteMetadata,
      );

      expect(
        (result as ImportSuccess).book.coverProvenance,
        BookCoverProvenance.none,
      );
      for (
        var attempt = 0;
        attempt < 20 && fixture.physicalRequestCount() == 0;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(fixture.physicalRequestCount(), 1);
      cover.complete(Uint8List.fromList([1, 1, 1]));
      final updated = await firstUpdate.timeout(const Duration(seconds: 1));
      expect(updated.coverProvenance, BookCoverProvenance.online);
      await Future<void>.delayed(Duration.zero);
      expect(fixture.physicalRequestCount(), 1);
    },
  );
}

final _remoteMetadata = TrustedRemoteBookMetadata(
  sourceId: 'source',
  publicationId: 'remote-id',
  title: 'Remote title',
  coverLocation: Uri.parse('https://covers.example/cover.png'),
  acquisitionLocation: Uri.parse('https://books.example/book.epub'),
);

class _Harness {
  const _Harness(
    this.importer,
    this.repository,
    this.cache,
    this.physicalRequestCount,
  );

  final BookImporter importer;
  final _Repository repository;
  final RemoteCacheService cache;
  final int Function() physicalRequestCount;
}

class _NoPicker implements ImportFilePicker {
  const _NoPicker();

  @override
  Future<PickedImportFile?> pickBookFile() async => null;
}

class _Metadata implements BookMetadataRepository {
  const _Metadata(this.cover);
  final Uint8List? cover;

  @override
  Future<MetadataExtractionResult> extractMetadata({
    required String filePath,
    required BookFormat format,
  }) async => MetadataExtractionSuccess(
    ExtractedBookMetadata(
      title: 'Downloaded',
      sortTitle: null,
      authors: const [],
      description: null,
      language: null,
      publisher: null,
      publishedDate: null,
      isbn: null,
      coverBytes: cover,
      coverExtension: 'png',
      mediaType: 'application/epub+zip',
    ),
  );
}

class _FixtureImageValidator implements CoverImageValidator {
  const _FixtureImageValidator();

  @override
  Future<bool> isDecodable(Uint8List bytes) async =>
      bytes.isNotEmpty && (bytes.first == 1 || bytes.first == 2);
}

class _Repository implements LibraryRepository {
  final _books = <String, LibraryBook>{};
  final _updates = StreamController<LibraryBook>.broadcast();
  int updateCount = 0;

  Future<LibraryBook> get nextUpdate => _updates.stream.first;

  @override
  Future<void> addBook(LibraryBook book) async => _books[book.id] = book;

  @override
  Future<void> deleteBook(String id) async => _books.remove(id);

  @override
  Future<LibraryBook?> findBookByFilePath(String filePath) async =>
      _firstWhere((book) => book.filePath == filePath);

  @override
  Future<LibraryBook?> findBookByOriginalFilePath(
    String originalFilePath,
  ) async => _firstWhere((book) => book.originalFilePath == originalFilePath);

  @override
  Future<List<LibraryBook>> getAllBooks() async => _books.values.toList();

  @override
  Future<LibraryBook?> getBookById(String id) async => _books[id];

  @override
  Future<void> markBookOpened(String id, DateTime openedAt) async {}

  @override
  Future<void> setFavorite(String id, bool isFavorite) async {}

  @override
  Future<void> updateBook(LibraryBook book) async {
    updateCount++;
    _books[book.id] = book;
    _updates.add(book);
  }

  @override
  Stream<List<LibraryBook>> watchAllBooks() =>
      Stream.value(_books.values.toList());

  @override
  Stream<List<LibraryBook>> watchFavoriteBooks() => Stream.value(
    _books.values.where((book) => book.isFavorite).toList(growable: false),
  );

  @override
  Stream<List<LibraryBook>> watchUnsortedBooks() => watchAllBooks();

  LibraryBook? _firstWhere(bool Function(LibraryBook book) test) {
    for (final book in _books.values) {
      if (test(book)) return book;
    }
    return null;
  }
}

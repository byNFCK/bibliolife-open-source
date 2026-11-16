import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_temporary_epub_importer.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_download_queue_coordinator.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_download_queue_facade.dart';
import 'package:bibliolife/features/catalog_sources/data/drift_remote_download_task_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download_plan.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_download_task.dart'
    as queue;
import 'package:bibliolife/features/catalog_sources/domain/remote_temporary_epub_import.dart';
import 'package:bibliolife/features/import/data/services/book_importer.dart';
import 'package:bibliolife/features/import/data/services/import_file_picker.dart';
import 'package:bibliolife/features/import/domain/entities/import_result.dart';
import 'package:bibliolife/features/library/data/repositories/drift_library_repository.dart';
import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';
import 'package:bibliolife/features/metadata/data/repositories/local_book_metadata_repository.dart';
import 'package:bibliolife/features/metadata/domain/entities/trusted_remote_book_metadata.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory root;
  late Directory documents;
  late AppDatabase database;
  late DriftLibraryRepository repository;
  late _Harness harness;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('remote-import-temp-');
    documents = await Directory.systemTemp.createTemp('remote-import-docs-');
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftLibraryRepository(database.booksDao);
    harness = _Harness(root, documents, repository);
  });
  tearDown(() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
    if (await documents.exists()) await documents.delete(recursive: true);
  });

  test(
    'download completes into a readable library file without a details observer',
    () async {
      final input = await harness.input(
        title: 'After navigation',
        author: 'Author',
      );
      final tasks = DriftRemoteDownloadTaskRepository(database);
      final downloader = _ControlledQueueDownloader();
      final facade = RemoteDownloadQueueFacade(
        tasks,
        RemoteDownloadQueueCoordinator(tasks, downloader),
        harness.importer,
        () async => root,
        (id) async => await repository.getBookById(id) != null,
      );
      final metadata = TrustedRemoteBookMetadata(
        sourceId: input.sourceId,
        publicationId: input.publicationRemoteId,
        title: input.remoteTitle,
        authors: input.remoteAuthors,
        description: 'Remote provenance',
        acquisitionLocation: input.acquisitionUri,
      );
      final plan = RemoteBookDownloadPlan(
        remoteMetadata: metadata,
        sourceId: input.sourceId,
        publicationRemoteId: input.publicationRemoteId,
        publicationTitle: input.remoteTitle,
        authors: input.remoteAuthors,
        acquisitionUri: input.acquisitionUri,
        declaredMediaType: 'application/epub+zip',
        expectedFinalMediaType: 'application/epub+zip',
        expectedSizeBytes: null,
        suggestedFilename: input.suggestedFilename,
        acquisitionRelation: 'http://opds-spec.org/acquisition/open-access',
        isIndirect: false,
        requiresAuthentication: false,
        supported: true,
        unsupportedReason: null,
      );
      final booksUpdated = repository.watchAllBooks().firstWhere(
        (books) => books.isNotEmpty,
      );
      final task = await facade.enqueueOrReuse(plan);
      await downloader.started.future;
      final imported = tasks
          .watchById(task.id)
          .firstWhere(
            (value) => value?.state == queue.RemoteDownloadTaskState.imported,
          );
      downloader.result.complete(
        RemoteBookDownloadResult(
          temporaryFilePath: input.temporaryFilePath,
          byteCount: input.downloadedByteCount,
          declaredMediaType: 'application/epub+zip',
          effectiveUri: input.acquisitionUri,
          suggestedFilename: input.suggestedFilename,
          sourceId: input.sourceId,
          publicationRemoteId: input.publicationRemoteId,
          checksum: input.sha256,
        ),
      );
      final done = await imported;
      final books = await booksUpdated;
      expect(books, hasLength(1));
      expect(books.single.catalogSourceId, input.sourceId);
      expect(books.single.remotePublicationId, input.publicationRemoteId);
      expect(
        books.single.remoteAcquisitionLocation,
        input.acquisitionUri.toString(),
      );
      expect(done!.importedBookId, books.single.id);
      expect(await File(books.single.filePath).exists(), isTrue);
      expect(await File(books.single.filePath).length(), greaterThan(0));
      expect(downloader.calls, 1);
      final again = await facade.enqueueOrReuse(plan);
      expect(again.id, task.id);
      expect(await repository.getAllBooks(), hasLength(1));
      expect(downloader.calls, 1);
    },
  );
  test(
    'valid result imports through BookImporter and updates Drift stream',
    () async {
      final pendingBooks = repository.watchAllBooks().firstWhere(
        (books) => books.isNotEmpty,
      );
      final input = await harness.input(
        title: 'Package Title',
        author: 'Package Author',
      );
      final result = await harness.importer.import(input);
      expect(result, isA<RemoteTemporaryEpubImported>());
      final books = await pendingBooks;
      expect(books, hasLength(1));
      expect(books.single.title, 'Package Title');
      expect(books.single.author, 'Package Author');
      expect(books.single.authors, ['Package Author']);
      expect(books.single.contributors, ['Fixture Editor']);
      expect(books.single.subjects, ['Fixture Subject']);
      expect(books.single.identifiers, ['id-1', '978-0-306-40615-7']);
      expect(books.single.isbn, '9780306406157');
      expect(books.single.publisher, 'Fixture Press');
      expect(books.single.publishedDate, '2024');
      expect(books.single.rights, 'Fixture rights');
      expect(books.single.seriesName, 'Fixture Series');
      expect(books.single.seriesIndex, 1);
      expect(books.single.filePath, startsWith(documents.path));
      expect(books.single.filePath, endsWith('.epub'));
      expect(books.single.originalFilePath, input.temporaryFilePath);
      expect(books.single.isFavorite, isFalse);
      expect(await File(input.temporaryFilePath).exists(), isFalse);
      expect(
        documents
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.part')),
        isEmpty,
      );
    },
  );

  test(
    'same EPUB bytes under another filename returns existing book',
    () async {
      final first = await harness.input(title: 'Same', author: 'Author');
      final imported = await harness.importer.import(first);
      final existing = (imported as RemoteTemporaryEpubImported).book;
      final second = await harness.input(
        title: 'Same',
        author: 'Author',
        filename: 'Another.epub',
        bytes: await File(existing.filePath).readAsBytes(),
        publicationId: 'other-remote',
      );
      final duplicate = await harness.importer.import(second);
      expect(
        (duplicate as RemoteTemporaryEpubAlreadyInLibrary).book.id,
        existing.id,
      );
      expect(await repository.getAllBooks(), hasLength(1));
      expect(await File(second.temporaryFilePath).exists(), isFalse);
      expect(_managedEpubs(documents), hasLength(1));
    },
  );

  test(
    'trusted remote metadata fills EPUB gaps and provenance survives reload',
    () async {
      final input = await harness.input(
        title: 'Sparse EPUB',
        author: 'EPUB Author',
        bytes: _sparseEpub('Sparse EPUB', 'EPUB Author', 'sparse-id'),
        publicationId: 'gutenberg:999',
        remoteMetadata: TrustedRemoteBookMetadata(
          sourceId: 'builtin-project-gutenberg',
          publicationId: 'gutenberg:999',
          title: 'Remote title',
          authors: const ['Remote Author'],
          description: 'Remote summary',
          publisher: 'Remote Press',
          language: 'en-US',
          publishedDate: '2024-03-05',
          identifiers: const ['urn:isbn:978-0-306-40615-7'],
          subjects: const ['Remote subject'],
          rights: 'Public domain',
          publicationLocation: Uri.parse(
            'https://www.gutenberg.org/ebooks/999',
          ),
          acquisitionLocation: Uri.parse(
            'https://www.gutenberg.org/ebooks/999.epub',
          ),
        ),
      );

      final imported = await harness.importer.import(input);
      final book = await repository.getBookById(
        (imported as RemoteTemporaryEpubImported).book.id,
      );

      expect(book?.title, 'Sparse EPUB');
      expect(book?.author, 'EPUB Author');
      expect(book?.description, 'Remote summary');
      expect(book?.publisher, 'Remote Press');
      expect(book?.isbn, '9780306406157');
      expect(book?.subjects, ['Remote subject']);
      expect(book?.catalogSourceId, 'builtin-project-gutenberg');
      expect(book?.remotePublicationId, 'gutenberg:999');
      expect(book?.metadataOrigins['title'], 'epub');
      expect(book?.metadataOrigins['description'], 'remote');
    },
  );

  test(
    'persisted queue task restores complete metadata into real importer after reload',
    () async {
      final input = await harness.input(
        title: 'Queued sparse EPUB',
        author: 'EPUB Author',
        bytes: _sparseEpub('Queued sparse EPUB', 'EPUB Author', 'queue-id'),
        publicationId: 'gutenberg:queue',
      );
      final metadata = TrustedRemoteBookMetadata(
        sourceId: 'builtin-project-gutenberg',
        publicationId: 'gutenberg:queue',
        title: 'Remote title',
        authors: const ['Remote Author'],
        description: 'Meaningful sanitized remote description.',
        publisher: 'Remote Press',
        language: 'en-US',
        publishedDate: '2024-03-05',
        identifiers: const ['urn:isbn:978-0-306-40615-7'],
        subjects: const ['Remote subject'],
        rights: 'Public domain',
        publicationLocation: Uri.parse(
          'https://www.gutenberg.org/ebooks/queue',
        ),
        acquisitionLocation: Uri.parse(
          'https://www.gutenberg.org/ebooks/queue.epub',
        ),
      );
      final tasks = DriftRemoteDownloadTaskRepository(database);
      final now = DateTime(2026, 7, 25);
      await tasks.create(
        queue.RemoteDownloadTask(
          id: 'queue-task',
          sourceId: metadata.sourceId,
          publicationRemoteId: metadata.publicationId,
          title: metadata.title,
          authors: metadata.authors,
          acquisitionUri: metadata.acquisitionLocation.toString(),
          suggestedFilename: 'Queued.epub',
          state: queue.RemoteDownloadTaskState.completedTemporary,
          downloadedBytes: await File(input.temporaryFilePath).length(),
          temporaryFilePath: input.temporaryFilePath,
          sha256: input.sha256,
          retryCount: 0,
          createdAt: now,
          updatedAt: now,
          remoteMetadata: metadata,
        ),
      );
      final reloadedTasks = DriftRemoteDownloadTaskRepository(database);
      final network = _NoQueueDownloader();
      final facade = RemoteDownloadQueueFacade(
        reloadedTasks,
        RemoteDownloadQueueCoordinator(reloadedTasks, network),
        harness.importer,
        () async => root,
        (id) async => await repository.getBookById(id) != null,
      );

      await facade.importCompleted('queue-task');

      final importedTask = await reloadedTasks.getById('queue-task');
      final book = await repository.getBookById(importedTask!.importedBookId!);
      expect(book?.description, metadata.description);
      expect(book?.publisher, metadata.publisher);
      expect(book?.language, metadata.language);
      expect(book?.publishedDate, metadata.publishedDate);
      expect(book?.subjects, metadata.subjects);
      expect(book?.rights, metadata.rights);
      expect(book?.isbn, '9780306406157');
      expect(book?.catalogSourceId, metadata.sourceId);
      expect(book?.remotePublicationId, metadata.publicationId);
      expect(
        book?.remotePublicationLocation,
        metadata.publicationLocation.toString(),
      );
      expect(
        book?.remoteAcquisitionLocation,
        metadata.acquisitionLocation.toString(),
      );
      expect(book?.metadataOrigins['description'], 'remote');
      expect(network.calls, 0);
    },
  );

  test('persists only prose from a dirty Gutenberg remote description', () async {
    final input = await harness.input(
      title: 'Clean description',
      author: 'EPUB Author',
      bytes: _sparseEpub('Clean description', 'EPUB Author', 'clean-id'),
      publicationId: 'gutenberg:clean',
      remoteMetadata: TrustedRemoteBookMetadata(
        sourceId: 'builtin-project-gutenberg',
        publicationId: 'gutenberg:clean',
        title: 'Clean description',
        authors: const ['Remote Author'],
        description:
            'Useful book description. (This is an automatically generated summary.) Reading level: Easy Language: English Subjects: Adventure LoC Class: PR Rights: Public domain',
        language: 'en',
        identifiers: const ['gutenberg:clean'],
        subjects: const ['Adventure'],
        rights: 'Public domain',
        publicationLocation: Uri.parse(
          'https://www.gutenberg.org/ebooks/clean',
        ),
        acquisitionLocation: Uri.parse(
          'https://www.gutenberg.org/ebooks/clean.epub',
        ),
      ),
    );

    final result = await harness.importer.import(input);
    final id = (result as RemoteTemporaryEpubImported).book.id;
    final reloaded = await repository.getBookById(id);

    expect(reloaded?.description, 'Useful book description.');
    expect(reloaded?.description, isNot(contains('automatically generated')));
    expect(reloaded?.description, isNot(contains('Language:')));
    expect(reloaded?.language, 'en');
    expect(reloaded?.subjects, ['Adventure']);
    expect(reloaded?.rights, 'Public domain');
  });

  test(
    'local refresh updates metadata and preserves identity and reading data',
    () async {
      final imported = await harness.importer.import(
        await harness.input(title: 'Before', author: 'Original Author'),
      );
      final book = (imported as RemoteTemporaryEpubImported).book;
      await repository.setFavorite(book.id, true);
      await database.readingProgressDao.upsertProgress(
        ReadingProgressEntriesCompanion.insert(
          bookId: book.id,
          locatorJson: const Value('{"href":"chapter.xhtml"}'),
          updatedAt: DateTime(2026, 7, 25),
        ),
      );
      await File(
        book.filePath,
      ).writeAsBytes(_epub('After', 'Updated Author', 'updated-id'));

      final refreshed = await harness.bookImporter.refreshBookMetadata(book.id);
      final reloaded = await repository.getBookById(book.id);

      expect(refreshed?.id, book.id);
      expect(reloaded?.id, book.id);
      expect(reloaded?.filePath, book.filePath);
      expect(reloaded?.title, 'Before');
      expect(reloaded?.author, 'Updated Author');
      expect(reloaded?.authors, ['Updated Author']);
      expect(reloaded?.isFavorite, isTrue);
      expect(
        (await database.readingProgressDao.getProgressForBook(
          book.id,
        ))?.locatorJson,
        '{"href":"chapter.xhtml"}',
      );
    },
  );

  test(
    'refresh cleans a Gutenberg-style EPUB description before update',
    () async {
      final imported = await harness.importer.import(
        await harness.input(title: 'Before', author: 'Original Author'),
      );
      final book = (imported as RemoteTemporaryEpubImported).book;
      await File(book.filePath).writeAsBytes(
        _epub(
          'Before',
          'Original Author',
          'refresh-clean-id',
          description:
              'Useful refreshed prose. (This is an automatically generated summary.) Language: English Rights: Public domain',
        ),
      );

      await harness.bookImporter.refreshBookMetadata(book.id);
      final reloaded = await repository.getBookById(book.id);

      expect(reloaded?.description, 'Useful refreshed prose.');
      expect(reloaded?.rights, 'Fixture rights');
    },
  );

  test(
    'refresh persistence failure leaves old metadata authoritative',
    () async {
      final imported = await harness.importer.import(
        await harness.input(title: 'Stable', author: 'Original Author'),
      );
      final book = (imported as RemoteTemporaryEpubImported).book;
      await File(
        book.filePath,
      ).writeAsBytes(_epub('Changed', 'Changed Author', 'changed-id'));
      final failingImporter = BookImporter(
        filePicker: _NoPicker(),
        libraryRepository: _FailingUpdateLibraryRepository(repository),
        metadataRepository: LocalBookMetadataRepository(),
        documentsDirectory: () async => documents,
        idGenerator: () => 'unused',
      );

      await expectLater(
        failingImporter.refreshBookMetadata(book.id),
        throwsStateError,
      );
      final reloaded = await repository.getBookById(book.id);
      expect(reloaded?.title, 'Stable');
      expect(reloaded?.author, 'Original Author');
    },
  );

  test('the exact completed import submitted twice is idempotent', () async {
    final input = await harness.input(title: 'Once', author: 'Author');
    final first = await harness.importer.import(input);
    final second = await harness.importer.import(input);
    expect(first, isA<RemoteTemporaryEpubImported>());
    expect(
      (second as RemoteTemporaryEpubAlreadyInLibrary).book.id,
      (first as RemoteTemporaryEpubImported).book.id,
    );
    expect(await repository.getAllBooks(), hasLength(1));
    expect(_managedEpubs(documents), hasLength(1));
  });

  test('manual local import is detected by EPUB byte identity', () async {
    final bytes = _epub('Manual', 'Local Author', 'manual-id');
    final manualSource = File(path.join(root.path, 'manual.epub'));
    await manualSource.writeAsBytes(bytes);
    final manual = await harness.bookImporter.importLocalFile(
      PickedImportFile(path: manualSource.path, name: 'manual.epub'),
    );
    final manuallyImported = (manual as ImportSuccess).book;
    final input = await harness.input(
      title: 'Remote title ignored',
      author: 'Remote Author',
      filename: 'remote-copy.epub',
      publicationId: 'manual-remote',
      bytes: bytes,
    );

    final result = await harness.importer.import(input);

    expect(
      (result as RemoteTemporaryEpubAlreadyInLibrary).book.id,
      manuallyImported.id,
    );
    expect(await repository.getAllBooks(), hasLength(1));
    expect(_managedEpubs(documents), hasLength(1));
    expect(await File(input.temporaryFilePath).exists(), isFalse);
  });

  test('same title with different EPUB bytes is not a duplicate', () async {
    await harness.importer.import(
      await harness.input(title: 'Shared title', author: 'One'),
    );
    final result = await harness.importer.import(
      await harness.input(
        title: 'Shared title',
        author: 'Two',
        publicationId: 'second',
      ),
    );
    expect(result, isA<RemoteTemporaryEpubImported>());
    expect(await repository.getAllBooks(), hasLength(2));
  });

  test(
    'same remote identity with different bytes is a typed conflict',
    () async {
      await harness.importer.import(
        await harness.input(title: 'First', author: 'One'),
      );
      final conflict = await harness.importer.import(
        await harness.input(title: 'Changed', author: 'Two'),
      );
      expect(
        (conflict as RemoteTemporaryEpubImportFailed).failure,
        RemoteTemporaryEpubImportFailure.conflictingRemoteIdentity,
      );
      expect(await repository.getAllBooks(), hasLength(1));
    },
  );

  test(
    'missing changed checksum invalid EPUB and outside path are rejected',
    () async {
      final valid = await harness.input(title: 'Book', author: 'Author');
      final missing = _copyInput(
        valid,
        temporaryFilePath: path.join(
          root.path,
          'remote-downloads',
          'missing',
          'none.epub',
        ),
      );
      final changedSize = _copyInput(
        valid,
        downloadedByteCount: valid.downloadedByteCount + 1,
      );
      final checksum = _copyInput(valid, sha256: List.filled(64, '0').join());
      final invalidFile = await harness.input(
        title: 'Invalid',
        author: 'Author',
        bytes: [1, 2, 3],
        publicationId: 'invalid',
      );
      final outsideFile = File(path.join(documents.path, 'outside.epub'));
      await outsideFile.writeAsBytes(
        await File(valid.temporaryFilePath).readAsBytes(),
      );
      final outside = _copyInput(valid, temporaryFilePath: outsideFile.path);

      expect(
        await harness.importer.import(missing),
        _failed(RemoteTemporaryEpubImportFailure.missingTemporaryFile),
      );
      expect(
        await harness.importer.import(changedSize),
        _failed(RemoteTemporaryEpubImportFailure.changedSize),
      );
      expect(
        await harness.importer.import(checksum),
        _failed(RemoteTemporaryEpubImportFailure.checksumMismatch),
      );
      expect(
        await harness.importer.import(invalidFile),
        _failed(RemoteTemporaryEpubImportFailure.invalidEpub),
      );
      expect(
        await harness.importer.import(outside),
        _failed(RemoteTemporaryEpubImportFailure.uncontrolledPath),
      );
      expect(await repository.getAllBooks(), isEmpty);
    },
  );

  test(
    'database failure removes permanent output and preserves temp for retry',
    () async {
      final failing = _FailingLibraryRepository(repository);
      final failingHarness = _Harness(root, documents, failing);
      final input = await failingHarness.input(
        title: 'Retry',
        author: 'Author',
      );
      final result = await failingHarness.importer.import(input);
      expect(
        result,
        _failed(RemoteTemporaryEpubImportFailure.persistenceFailure),
      );
      expect(await File(input.temporaryFilePath).exists(), isTrue);
      expect(_managedEpubs(documents), isEmpty);
      expect(
        documents
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.part')),
        isEmpty,
      );
    },
  );

  test(
    'storage failure preserves temp and creates no row or partial',
    () async {
      final blockedPath = File(path.join(root.path, 'not-a-directory'));
      await blockedPath.writeAsString('blocked');
      final bookImporter = BookImporter(
        filePicker: _NoPicker(),
        libraryRepository: repository,
        metadataRepository: LocalBookMetadataRepository(),
        documentsDirectory: () async => Directory(blockedPath.path),
        idGenerator: () => 'blocked-book',
      );
      final importer = ProductionRemoteTemporaryEpubImporter(
        bookImporter,
        repository,
        () async => root,
      );
      final input = await harness.input(title: 'Retry', author: 'Author');

      expect(
        await importer.import(input),
        _failed(RemoteTemporaryEpubImportFailure.storageFailure),
      );
      expect(await File(input.temporaryFilePath).exists(), isTrue);
      expect(await repository.getAllBooks(), isEmpty);
      expect(
        root
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.part')),
        isEmpty,
      );
    },
  );
}

Matcher _failed(RemoteTemporaryEpubImportFailure failure) =>
    isA<RemoteTemporaryEpubImportFailed>().having(
      (value) => value.failure,
      'failure',
      failure,
    );

List<File> _managedEpubs(Directory directory) => directory
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.epub'))
    .toList();

RemoteTemporaryEpubImportInput _copyInput(
  RemoteTemporaryEpubImportInput input, {
  String? temporaryFilePath,
  int? downloadedByteCount,
  String? sha256,
}) => RemoteTemporaryEpubImportInput(
  temporaryFilePath: temporaryFilePath ?? input.temporaryFilePath,
  sourceId: input.sourceId,
  publicationRemoteId: input.publicationRemoteId,
  remoteTitle: input.remoteTitle,
  remoteAuthors: input.remoteAuthors,
  acquisitionUri: input.acquisitionUri,
  sha256: sha256 ?? input.sha256,
  downloadedByteCount: downloadedByteCount ?? input.downloadedByteCount,
  suggestedFilename: input.suggestedFilename,
  remoteMetadata: input.remoteMetadata,
);

class _Harness {
  _Harness(this.root, this.documents, this.repository) {
    var id = 0;
    bookImporter = BookImporter(
      filePicker: _NoPicker(),
      libraryRepository: repository,
      metadataRepository: LocalBookMetadataRepository(),
      documentsDirectory: () async => documents,
      idGenerator: () => 'book-${++id}',
    );
    importer = ProductionRemoteTemporaryEpubImporter(
      bookImporter,
      repository,
      () async => root,
    );
  }

  final Directory root;
  final Directory documents;
  final LibraryRepository repository;
  late final BookImporter bookImporter;
  late final ProductionRemoteTemporaryEpubImporter importer;
  var sequence = 0;

  Future<RemoteTemporaryEpubImportInput> input({
    required String title,
    required String author,
    String filename = 'Downloaded.epub',
    String publicationId = 'remote-book',
    List<int>? bytes,
    TrustedRemoteBookMetadata? remoteMetadata,
  }) async {
    final content = bytes ?? _epub(title, author, 'id-${++sequence}');
    final directory = Directory(
      path.join(root.path, 'remote-downloads', 'work-${++sequence}'),
    );
    await directory.create(recursive: true);
    final file = File(path.join(directory.path, filename));
    await file.writeAsBytes(content);
    return RemoteTemporaryEpubImportInput(
      temporaryFilePath: file.path,
      sourceId: 'source',
      publicationRemoteId: publicationId,
      remoteTitle: 'Remote $title',
      remoteAuthors: const ['Remote Author'],
      acquisitionUri: Uri.parse('https://catalog.example/book.epub'),
      sha256: sha256.convert(content).toString(),
      downloadedByteCount: content.length,
      suggestedFilename: filename,
      remoteMetadata: remoteMetadata,
    );
  }
}

class _ControlledQueueDownloader implements RemoteBookDownloader {
  final started = Completer<void>();
  final result = Completer<RemoteBookDownloadResult>();
  int calls = 0;

  @override
  Future<RemoteBookDownloadResult> download({
    required RemoteBookDownloadPlan plan,
    required RemoteBookDownloadCancellation cancellation,
    required void Function(RemoteBookDownloadProgress progress) onProgress,
  }) {
    calls++;
    started.complete();
    return result.future;
  }
}

class _NoQueueDownloader implements RemoteBookDownloader {
  int calls = 0;

  @override
  Future<RemoteBookDownloadResult> download({
    required RemoteBookDownloadPlan plan,
    required RemoteBookDownloadCancellation cancellation,
    required void Function(RemoteBookDownloadProgress progress) onProgress,
  }) {
    calls++;
    throw StateError('Import must not download metadata or EPUB bytes');
  }
}

List<int> _epub(
  String title,
  String author,
  String identifier, {
  String description = '&lt;p&gt;Fixture description.&lt;/p&gt;',
}) {
  final archive = Archive()
    ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
    ..addFile(
      ArchiveFile.string(
        'META-INF/container.xml',
        '<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles><rootfile full-path="OEBPS/content.opf" '
            'media-type="application/oebps-package+xml"/></rootfiles></container>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/content.opf',
        '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" '
            'unique-identifier="uid"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:identifier id="uid">$identifier</dc:identifier>'
            '<dc:identifier>978-0-306-40615-7</dc:identifier>'
            '<dc:title>$title</dc:title><dc:creator>$author</dc:creator>'
            '<dc:contributor>Fixture Editor</dc:contributor>'
            '<dc:description>$description</dc:description>'
            '<dc:publisher>Fixture Press</dc:publisher><dc:date>2024</dc:date>'
            '<dc:subject>Fixture Subject</dc:subject><dc:rights>Fixture rights</dc:rights>'
            '<dc:language>en</dc:language>'
            '<meta name="calibre:series" content="Fixture Series"/>'
            '<meta name="calibre:series_index" content="1"/>'
            '</metadata><manifest/><spine/></package>',
      ),
    );
  return ZipEncoder().encode(archive);
}

List<int> _sparseEpub(String title, String author, String identifier) {
  final archive = Archive()
    ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
    ..addFile(
      ArchiveFile.string(
        'META-INF/container.xml',
        '<?xml version="1.0"?><container><rootfiles><rootfile '
            'full-path="book.opf"/></rootfiles></container>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'book.opf',
        '<package><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:identifier>$identifier</dc:identifier><dc:title>$title</dc:title>'
            '<dc:creator>$author</dc:creator></metadata></package>',
      ),
    );
  return ZipEncoder().encode(archive);
}

class _NoPicker implements ImportFilePicker {
  @override
  Future<PickedImportFile?> pickBookFile() async => null;
}

class _FailingLibraryRepository implements LibraryRepository {
  _FailingLibraryRepository(this.delegate);
  final LibraryRepository delegate;
  @override
  Future<void> addBook(LibraryBook book) async =>
      throw StateError('db failure');
  @override
  Future<List<LibraryBook>> getAllBooks() => delegate.getAllBooks();
  @override
  Future<LibraryBook?> getBookById(String id) => delegate.getBookById(id);
  @override
  Future<LibraryBook?> findBookByOriginalFilePath(String originalFilePath) =>
      delegate.findBookByOriginalFilePath(originalFilePath);
  @override
  Stream<List<LibraryBook>> watchAllBooks() => delegate.watchAllBooks();
  @override
  Stream<List<LibraryBook>> watchFavoriteBooks() =>
      delegate.watchFavoriteBooks();
  @override
  Stream<List<LibraryBook>> watchUnsortedBooks() =>
      delegate.watchUnsortedBooks();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Function.apply(delegate.noSuchMethod, [invocation]);
}

class _FailingUpdateLibraryRepository implements LibraryRepository {
  _FailingUpdateLibraryRepository(this.delegate);
  final LibraryRepository delegate;
  @override
  Future<void> updateBook(LibraryBook book) async =>
      throw StateError('update failure');
  @override
  Future<List<LibraryBook>> getAllBooks() => delegate.getAllBooks();
  @override
  Future<LibraryBook?> getBookById(String id) => delegate.getBookById(id);
  @override
  Stream<List<LibraryBook>> watchAllBooks() => delegate.watchAllBooks();
  @override
  Stream<List<LibraryBook>> watchFavoriteBooks() =>
      delegate.watchFavoriteBooks();
  @override
  Stream<List<LibraryBook>> watchUnsortedBooks() =>
      delegate.watchUnsortedBooks();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Function.apply(delegate.noSuchMethod, [invocation]);
}

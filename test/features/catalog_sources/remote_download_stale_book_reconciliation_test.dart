import 'dart:io';

import 'package:bibliolife/core/database/app_database.dart' as db;
import 'package:bibliolife/features/catalog_sources/application/remote_download_queue_coordinator.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_download_queue_facade.dart';
import 'package:bibliolife/features/catalog_sources/data/drift_remote_download_task_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download_plan.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_download_task.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_temporary_epub_import.dart';
import 'package:bibliolife/features/metadata/domain/entities/trusted_remote_book_metadata.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final state in [
    RemoteDownloadTaskState.imported,
    RemoteDownloadTaskState.duplicate,
  ]) {
    test(
      '$state with missing local book and temp file permits reimport',
      () async {
        final harness = await _Harness.create();
        addTearDown(harness.dispose);
        final file = await harness.controlledFile('retained.epub', [1, 2, 3]);
        await harness.repository.create(
          harness.task(
            state,
            temporaryFilePath: file.path,
            checksum: sha256.convert([1, 2, 3]).toString(),
            importedBookId: 'deleted-local-book',
          ),
        );

        final observed = await harness.facade.observeById('old').first;
        expect(observed.phase, RemoteDownloadUiPhase.importing);
        expect(observed.task?.importedBookId, isNull);
        expect(harness.downloader.calls, 0);

        await _untilTaskState(
          harness.repository,
          'old',
          RemoteDownloadTaskState.imported,
        );
        final imported = await harness.repository.getById('old');
        expect(imported?.state, RemoteDownloadTaskState.imported);
        expect(imported?.importedBookId, 'reimported-book');
        expect(imported?.remoteMetadata?.description, 'Remote description');
        expect(harness.downloader.calls, 0);
      },
    );
  }

  test(
    'stale imported history without temp allows one fresh download',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.repository.create(
        harness.task(
          RemoteDownloadTaskState.imported,
          temporaryFilePath: '${harness.root.path}/missing.epub',
          checksum: 'missing',
          importedBookId: 'deleted-local-book',
        ),
      );

      final tasks = await Future.wait([
        harness.facade.enqueueOrReuse(harness.plan),
        harness.facade.enqueueOrReuse(harness.plan),
      ]);
      await _until(() => harness.downloader.calls == 1);

      expect(tasks[0].id, tasks[1].id);
      expect(tasks[0].id, isNot('old'));
      expect(
        (await harness.repository.getById('old'))?.state,
        RemoteDownloadTaskState.deleted,
      );
      expect(
        (await harness.repository.getById(
          tasks[0].id,
        ))?.remoteMetadata?.description,
        'Remote description',
      );
    },
  );

  test('existing local book preserves imported history reuse', () async {
    final harness = await _Harness.create(localBookExists: true);
    addTearDown(harness.dispose);
    await harness.repository.create(
      harness.task(
        RemoteDownloadTaskState.imported,
        importedBookId: 'existing-book',
      ),
    );

    final reused = await harness.facade.enqueueOrReuse(harness.plan);

    expect(reused.id, 'old');
    expect(reused.state, RemoteDownloadTaskState.imported);
    expect(harness.downloader.calls, 0);
  });
}

class _Harness {
  _Harness(
    this.database,
    this.repository,
    this.root,
    this.downloader,
    this.facade,
  );

  final db.AppDatabase database;
  final DriftRemoteDownloadTaskRepository repository;
  final Directory root;
  final _Downloader downloader;
  final RemoteDownloadQueueFacade facade;

  static Future<_Harness> create({bool localBookExists = false}) async {
    final database = db.AppDatabase(NativeDatabase.memory());
    final repository = DriftRemoteDownloadTaskRepository(database);
    final root = await Directory.systemTemp.createTemp('stale-queue-');
    final downloader = _Downloader();
    final facade = RemoteDownloadQueueFacade(
      repository,
      RemoteDownloadQueueCoordinator(repository, downloader),
      _Importer(),
      () async => root,
      (_) async => localBookExists,
    );
    return _Harness(database, repository, root, downloader, facade);
  }

  RemoteBookDownloadPlan get plan => RemoteBookDownloadPlan(
    sourceId: 'source',
    publicationRemoteId: 'publication',
    publicationTitle: 'Remote Book',
    authors: const ['Author'],
    acquisitionUri: Uri.parse('https://example.test/book.epub'),
    declaredMediaType: 'application/epub+zip',
    acquisitionRelation: 'http://opds-spec.org/acquisition/open-access',
    isIndirect: false,
    expectedFinalMediaType: 'application/epub+zip',
    expectedSizeBytes: 3,
    suggestedFilename: 'Remote Book.epub',
    requiresAuthentication: false,
    supported: true,
    unsupportedReason: null,
    remoteMetadata: metadata,
  );

  TrustedRemoteBookMetadata get metadata => TrustedRemoteBookMetadata(
    sourceId: 'source',
    publicationId: 'publication',
    title: 'Remote Book',
    authors: const ['Author'],
    description: 'Remote description',
    acquisitionLocation: Uri.parse('https://example.test/book.epub'),
  );

  RemoteDownloadTask task(
    RemoteDownloadTaskState state, {
    String? temporaryFilePath,
    String? checksum,
    String? importedBookId,
  }) => RemoteDownloadTask(
    id: 'old',
    sourceId: 'source',
    publicationRemoteId: 'publication',
    title: 'Remote Book',
    authors: const ['Author'],
    acquisitionUri: 'https://example.test/book.epub',
    suggestedFilename: 'Remote Book.epub',
    state: state,
    downloadedBytes: 3,
    retryCount: 0,
    createdAt: DateTime(2026, 7, 25),
    updatedAt: DateTime(2026, 7, 25),
    temporaryFilePath: temporaryFilePath,
    sha256: checksum,
    importedBookId: importedBookId,
    remoteMetadata: metadata,
  );

  Future<File> controlledFile(String name, List<int> bytes) async {
    final directory = Directory('${root.path}/remote-downloads/old');
    await directory.create(recursive: true);
    return File('${directory.path}/$name')..writeAsBytesSync(bytes);
  }

  Future<void> dispose() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

class _Downloader implements RemoteBookDownloader {
  int calls = 0;

  @override
  Future<RemoteBookDownloadResult> download({
    required RemoteBookDownloadPlan plan,
    required RemoteBookDownloadCancellation cancellation,
    required void Function(RemoteBookDownloadProgress progress) onProgress,
  }) async {
    calls++;
    return RemoteBookDownloadResult(
      temporaryFilePath: 'fresh.epub',
      byteCount: 3,
      declaredMediaType: 'application/epub+zip',
      effectiveUri: plan.acquisitionUri!,
      checksum: 'fresh',
      suggestedFilename: plan.suggestedFilename,
      sourceId: plan.sourceId,
      publicationRemoteId: plan.publicationRemoteId,
      remoteMetadata: plan.remoteMetadata,
    );
  }
}

class _Importer implements RemoteTemporaryEpubImporter {
  @override
  Future<RemoteTemporaryEpubImportResult> import(
    RemoteTemporaryEpubImportInput input,
  ) async => RemoteTemporaryEpubImported(
    LibraryBook(
      id: 'reimported-book',
      title: input.remoteTitle,
      sortTitle: null,
      author: input.remoteAuthors.join(', '),
      description: input.remoteMetadata?.description,
      filePath: 'managed.epub',
      fileName: 'managed.epub',
      fileExtension: 'epub',
      format: BookFormat.epub,
      mediaType: 'application/epub+zip',
      coverPath: null,
      language: null,
      publisher: null,
      publishedDate: null,
      isbn: null,
      pageCount: null,
      fileSizeBytes: input.downloadedByteCount,
      dateAdded: DateTime(2026, 7, 25),
      lastOpenedAt: null,
      isFavorite: false,
    ),
  );
}

Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Condition was not reached');
}

Future<void> _untilTaskState(
  DriftRemoteDownloadTaskRepository repository,
  String id,
  RemoteDownloadTaskState state,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if ((await repository.getById(id))?.state == state) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Task did not reach $state');
}

import 'dart:io';

import 'package:bibliolife/core/database/app_database.dart' as db;
import 'package:bibliolife/features/catalog_sources/application/remote_download_queue_coordinator.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_download_queue_facade.dart';
import 'package:bibliolife/features/catalog_sources/data/drift_remote_download_task_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download_plan.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_download_task.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_temporary_epub_import.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (var run = 1; run <= 2; run++) {
    test(
      'startup reconciliation is local, safe, and idempotent run $run',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'bibliolife_recovery_$run',
        );
        final controlled = Directory('${root.path}/remote-downloads/task')
          ..createSync(recursive: true);
        final partial = File('${controlled.path}/book.epub.part')
          ..writeAsBytesSync([1, 2, 3]);
        final valid = File('${controlled.path}/complete.epub')
          ..writeAsBytesSync([4, 5, 6]);
        final unrelated = File('${root.path}/unrelated.part')
          ..writeAsBytesSync([7]);
        final database = db.AppDatabase(NativeDatabase.memory());
        final repository = DriftRemoteDownloadTaskRepository(database);
        final downloader = _NeverDownloader();
        final facade = RemoteDownloadQueueFacade(
          repository,
          RemoteDownloadQueueCoordinator(repository, downloader),
          _NeverImporter(),
          () async => root,
          (_) async => true,
        );
        addTearDown(() async {
          await database.close();
          if (await root.exists()) await root.delete(recursive: true);
        });

        await repository.create(
          _task(
            'downloading',
            RemoteDownloadTaskState.downloading,
            temporaryFilePath: partial.path,
          ),
        );
        await repository.create(
          _task(
            'complete',
            RemoteDownloadTaskState.completedTemporary,
            temporaryFilePath: valid.path,
          ),
        );
        await repository.create(
          _task(
            'missing',
            RemoteDownloadTaskState.completedTemporary,
            temporaryFilePath: '${controlled.path}/missing.epub',
          ),
        );
        await repository.create(
          _task('queued', RemoteDownloadTaskState.queued),
        );
        await repository.create(
          _task(
            'failed',
            RemoteDownloadTaskState.failed,
            failure: RemoteDownloadFailureCategory.transport,
          ),
        );
        await repository.create(
          _task(
            'interrupted',
            RemoteDownloadTaskState.pausedByAppRestart,
            failure: RemoteDownloadFailureCategory.interruptedByRestart,
          ),
        );
        await repository.create(
          _task(
            'imported',
            RemoteDownloadTaskState.imported,
            importedBookId: 'local-a',
          ),
        );
        await repository.create(
          _task(
            'duplicate',
            RemoteDownloadTaskState.duplicate,
            importedBookId: 'local-b',
          ),
        );
        await repository.create(
          _task(
            'importing',
            RemoteDownloadTaskState.importing,
            temporaryFilePath: valid.path,
          ),
        );

        await facade.reconcileOnStartup();
        await facade.reconcileOnStartup();

        expect(await partial.exists(), isFalse);
        expect(await unrelated.exists(), isTrue);
        expect(await valid.exists(), isTrue);
        expect(
          (await repository.getById('downloading'))?.state,
          RemoteDownloadTaskState.pausedByAppRestart,
        );
        expect(
          (await repository.getById('downloading'))?.failure,
          RemoteDownloadFailureCategory.interruptedByRestart,
        );
        expect(
          (await repository.getById('complete'))?.state,
          RemoteDownloadTaskState.completedTemporary,
        );
        expect(
          (await repository.getById('missing'))?.state,
          RemoteDownloadTaskState.failed,
        );
        expect(
          (await repository.getById('missing'))?.failure,
          RemoteDownloadFailureCategory.storage,
        );
        expect(
          (await repository.getById('queued'))?.state,
          RemoteDownloadTaskState.queued,
        );
        expect(
          (await repository.getById('failed'))?.state,
          RemoteDownloadTaskState.failed,
        );
        expect(
          (await repository.getById('interrupted'))?.state,
          RemoteDownloadTaskState.pausedByAppRestart,
        );
        expect(
          (await repository.getById('imported'))?.importedBookId,
          'local-a',
        );
        expect(
          (await repository.getById('duplicate'))?.importedBookId,
          'local-b',
        );
        expect(
          (await repository.getById('importing'))?.state,
          RemoteDownloadTaskState.failed,
        );
        expect(
          (await repository.getById('importing'))?.failure,
          RemoteDownloadFailureCategory.importFailure,
        );
        expect(downloader.calls, 0);
        expect(downloader.policyCalls, 0);
        expect(downloader.httpCalls, 0);
      },
    );
  }

  test('unexpected importer error becomes terminal import failure', () async {
    final root = await Directory.systemTemp.createTemp(
      'bibliolife_import_error',
    );
    final controlled = Directory('${root.path}/remote-downloads/task')
      ..createSync(recursive: true);
    final temporary = File('${controlled.path}/book.epub')
      ..writeAsBytesSync([1]);
    final database = db.AppDatabase(NativeDatabase.memory());
    final repository = DriftRemoteDownloadTaskRepository(database);
    final facade = RemoteDownloadQueueFacade(
      repository,
      RemoteDownloadQueueCoordinator(repository, _NeverDownloader()),
      _NeverImporter(),
      () async => root,
      (_) async => true,
    );
    addTearDown(() async {
      await database.close();
      if (await root.exists()) await root.delete(recursive: true);
    });
    await repository.create(
      _task(
        'import-error',
        RemoteDownloadTaskState.completedTemporary,
        temporaryFilePath: temporary.path,
        sha256: 'checksum',
      ),
    );

    await facade.importCompleted('import-error');

    expect(
      (await repository.getById('import-error'))?.state,
      RemoteDownloadTaskState.failed,
    );
    expect(
      (await repository.getById('import-error'))?.failure,
      RemoteDownloadFailureCategory.importFailure,
    );
  });
}

class _NeverDownloader implements RemoteBookDownloader {
  int calls = 0;
  int policyCalls = 0;
  int httpCalls = 0;

  @override
  Future<RemoteBookDownloadResult> download({
    required RemoteBookDownloadPlan plan,
    required RemoteBookDownloadCancellation cancellation,
    required void Function(RemoteBookDownloadProgress progress) onProgress,
  }) {
    calls++;
    throw StateError('Recovery must not download');
  }
}

class _NeverImporter implements RemoteTemporaryEpubImporter {
  @override
  Future<RemoteTemporaryEpubImportResult> import(
    RemoteTemporaryEpubImportInput input,
  ) {
    throw StateError('Recovery must not import');
  }
}

RemoteDownloadTask _task(
  String id,
  RemoteDownloadTaskState state, {
  String? temporaryFilePath,
  String? sha256,
  String? importedBookId,
  RemoteDownloadFailureCategory? failure,
}) => RemoteDownloadTask(
  id: id,
  sourceId: 'source',
  publicationRemoteId: id,
  title: 'Book $id',
  authors: const ['Author'],
  acquisitionUri: 'https://example.test/$id.epub',
  suggestedFilename: '$id.epub',
  state: state,
  downloadedBytes: 0,
  retryCount: 0,
  createdAt: DateTime(2026, 7, 25),
  updatedAt: DateTime(2026, 7, 25),
  temporaryFilePath: temporaryFilePath,
  sha256: sha256,
  importedBookId: importedBookId,
  failure: failure,
);

import 'dart:async';

import 'package:bibliolife/core/database/app_database.dart' as db;
import 'package:bibliolife/features/catalog_sources/application/remote_download_queue_coordinator.dart';
import 'package:bibliolife/features/catalog_sources/data/drift_remote_download_task_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download_plan.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_download_task.dart';
import 'package:bibliolife/features/metadata/domain/entities/trusted_remote_book_metadata.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late db.AppDatabase database;
  late DriftRemoteDownloadTaskRepository repository;
  late _ControlledDownloader downloader;
  late RemoteDownloadQueueCoordinator coordinator;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    repository = DriftRemoteDownloadTaskRepository(database);
    downloader = _ControlledDownloader();
    coordinator = RemoteDownloadQueueCoordinator(repository, downloader);
  });

  tearDown(() => database.close());

  test('runs exactly one task and preserves FIFO for two tasks', () async {
    final first = await coordinator.submit(_plan('first'));
    final second = await coordinator.submit(_plan('second'));
    await _until(() => downloader.calls == 1);
    expect(downloader.started, ['first']);
    expect(
      (await repository.getById(first.id))?.state,
      RemoteDownloadTaskState.downloading,
    );
    expect(
      (await repository.getById(second.id))?.state,
      RemoteDownloadTaskState.queued,
    );

    downloader.succeed(0);
    await _until(() => downloader.calls == 2);
    expect(downloader.started, ['first', 'second']);
    downloader.succeed(1);
    await _until(
      () async =>
          (await repository.getById(second.id))?.state ==
          RemoteDownloadTaskState.completedTemporary,
    );
  });

  test('online success persists terminal progress and result', () async {
    final task = await coordinator.submit(_plan('success'));
    await _until(() => downloader.calls == 1);
    downloader.progress(0, 40, 100);
    downloader.succeed(0, bytes: 100);
    await _until(
      () async =>
          (await repository.getById(task.id))?.state ==
          RemoteDownloadTaskState.completedTemporary,
    );
    final result = await repository.getById(task.id);
    expect(result?.downloadedBytes, 100);
    expect(result?.totalBytes, 100);
    expect(result?.temporaryFilePath, contains('success.epub'));
    expect(result?.sha256, 'hash-success');
    expect(result?.remoteMetadata?.description, 'Description success');
  });

  test('duplicate enqueue creates one task and one downloader call', () async {
    final results = await Future.wait([
      coordinator.submit(_plan('same')),
      coordinator.submit(_plan('same')),
    ]);
    await _until(() => downloader.calls == 1);
    expect(results[0].id, results[1].id);
    expect(await repository.getAll(), hasLength(1));
    downloader.succeed(0);
    await _until(
      () async =>
          (await repository.getById(results[0].id))?.state ==
          RemoteDownloadTaskState.completedTemporary,
    );
  });

  test('cancel persists before and ignores late success', () async {
    final task = await coordinator.submit(_plan('cancel'));
    await _until(() => downloader.calls == 1);
    await coordinator.cancel(task.id);
    expect(
      (await repository.getById(task.id))?.state,
      RemoteDownloadTaskState.cancelled,
    );
    downloader.succeed(0);
    await _until(() => downloader.completedCalls == 1);
    expect(
      (await repository.getById(task.id))?.state,
      RemoteDownloadTaskState.cancelled,
    );
  });

  test('failure advances queue', () async {
    final first = await coordinator.submit(_plan('fail'));
    final second = await coordinator.submit(_plan('after'));
    await _until(() => downloader.calls == 1);
    downloader.fail(0, RemoteBookDownloadFailure.transport);
    await _until(() => downloader.calls == 2);
    expect(
      (await repository.getById(first.id))?.state,
      RemoteDownloadTaskState.failed,
    );
    expect(downloader.started, ['fail', 'after']);
    downloader.succeed(1);
    await _until(
      () async =>
          (await repository.getById(second.id))?.state ==
          RemoteDownloadTaskState.completedTemporary,
    );
  });

  test(
    'unexpected downloader error becomes terminal failure and advances queue',
    () async {
      final first = await coordinator.submit(_plan('unexpected'));
      final second = await coordinator.submit(_plan('after-unexpected'));
      await _until(() => downloader.calls == 1);
      downloader.failUnexpected(0);
      await _until(() => downloader.calls == 2);
      expect(
        (await repository.getById(first.id))?.state,
        RemoteDownloadTaskState.failed,
      );
      downloader.succeed(1);
      await _until(
        () async =>
            (await repository.getById(second.id))?.state ==
            RemoteDownloadTaskState.completedTemporary,
      );
    },
  );

  test(
    'operation timeout cancels a stalled downloader and publishes failure',
    () async {
      final timeoutDownloader = _ControlledDownloader();
      final timeoutCoordinator = RemoteDownloadQueueCoordinator(
        repository,
        timeoutDownloader,
        operationTimeout: const Duration(milliseconds: 20),
      );
      final task = await timeoutCoordinator.submit(_plan('stalled'));
      await _until(() => timeoutDownloader.calls == 1);

      await _until(
        () async =>
            (await repository.getById(task.id))?.state ==
            RemoteDownloadTaskState.failed,
      );

      final failed = await repository.getById(task.id);
      expect(failed?.failure, RemoteDownloadFailureCategory.timeout);
      expect(timeoutDownloader.cancellations.single.isCancelled, isTrue);
    },
  );

  test('retry creates new attempt and stale progress is ignored', () async {
    final task = await coordinator.submit(_plan('retry'));
    await _until(() => downloader.calls == 1);
    downloader.fail(0, RemoteBookDownloadFailure.timeout);
    await _until(
      () async =>
          (await repository.getById(task.id))?.state ==
          RemoteDownloadTaskState.failed,
    );
    await coordinator.retry(task.id);
    await _until(() => downloader.calls == 2);
    final retried = await repository.getById(task.id);
    expect(retried?.attemptId, 1);
    await repository.updateProgress(task.id, 0, 90, 100);
    expect((await repository.getById(task.id))?.downloadedBytes, 0);
    downloader.succeed(1);
    await _until(
      () async =>
          (await repository.getById(task.id))?.state ==
          RemoteDownloadTaskState.completedTemporary,
    );
  });

  test(
    'offline attempt checks once, starts no transport, and does not loop',
    () async {
      final offline = _OfflineDownloader();
      final offlineCoordinator = RemoteDownloadQueueCoordinator(
        repository,
        offline,
      );
      final task = await offlineCoordinator.submit(_plan('offline'));
      await _until(
        () async =>
            (await repository.getById(task.id))?.state ==
            RemoteDownloadTaskState.failed,
      );
      expect(offline.policyChecks, 1);
      expect(offline.transportCalls, 0);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(offline.policyChecks, 1);
    },
  );

  test(
    'progress writes are throttled while terminal progress is exact',
    () async {
      final task = await coordinator.submit(_plan('progress'));
      await _until(() => downloader.calls == 1);
      for (var bytes = 1; bytes <= 20; bytes++) {
        downloader.progress(0, bytes, 100);
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final beforeTerminal = (await repository.getById(
        task.id,
      ))!.downloadedBytes;
      expect(beforeTerminal, lessThan(20));
      downloader.succeed(0, bytes: 100);
      await _until(
        () async =>
            (await repository.getById(task.id))?.state ==
            RemoteDownloadTaskState.completedTemporary,
      );
      expect((await repository.getById(task.id))?.downloadedBytes, 100);
    },
  );
}

class _ControlledDownloader implements RemoteBookDownloader {
  final pending = <Completer<RemoteBookDownloadResult>>[];
  final progressCallbacks =
      <void Function(RemoteBookDownloadProgress progress)>[];
  final started = <String>[];
  final cancellations = <RemoteBookDownloadCancellation>[];
  int completedCalls = 0;
  int get calls => pending.length;

  @override
  Future<RemoteBookDownloadResult> download({
    required RemoteBookDownloadPlan plan,
    required RemoteBookDownloadCancellation cancellation,
    required void Function(RemoteBookDownloadProgress progress) onProgress,
  }) {
    started.add(plan.publicationRemoteId);
    cancellations.add(cancellation);
    final completer = Completer<RemoteBookDownloadResult>();
    pending.add(completer);
    progressCallbacks.add(onProgress);
    return completer.future.whenComplete(() => completedCalls++);
  }

  void progress(int index, int bytes, int total) {
    progressCallbacks[index](
      RemoteBookDownloadProgress(
        phase: RemoteBookDownloadPhase.downloading,
        bytesReceived: bytes,
        totalBytes: total,
      ),
    );
  }

  void succeed(int index, {int bytes = 42}) {
    final id = started[index];
    pending[index].complete(
      RemoteBookDownloadResult(
        temporaryFilePath: 'controlled/$id.epub',
        byteCount: bytes,
        declaredMediaType: 'application/epub+zip',
        effectiveUri: Uri.parse('https://example.test/$id.epub'),
        checksum: 'hash-$id',
        suggestedFilename: '$id.epub',
        sourceId: 'source',
        publicationRemoteId: id,
      ),
    );
  }

  void fail(int index, RemoteBookDownloadFailure failure) {
    pending[index].completeError(RemoteBookDownloadException(failure));
  }

  void failUnexpected(int index) {
    pending[index].completeError(StateError('unexpected downloader failure'));
  }
}

class _OfflineDownloader implements RemoteBookDownloader {
  int policyChecks = 0;
  int transportCalls = 0;

  @override
  Future<RemoteBookDownloadResult> download({
    required RemoteBookDownloadPlan plan,
    required RemoteBookDownloadCancellation cancellation,
    required void Function(RemoteBookDownloadProgress progress) onProgress,
  }) async {
    policyChecks++;
    throw const RemoteBookDownloadException(
      RemoteBookDownloadFailure.accessDenied,
    );
  }
}

RemoteBookDownloadPlan _plan(String id) => RemoteBookDownloadPlan(
  sourceId: 'source',
  publicationRemoteId: id,
  publicationTitle: 'Book $id',
  authors: const ['Author'],
  acquisitionUri: Uri.parse('https://example.test/$id.epub'),
  declaredMediaType: 'application/epub+zip',
  acquisitionRelation: 'http://opds-spec.org/acquisition/open-access',
  isIndirect: false,
  expectedFinalMediaType: 'application/epub+zip',
  expectedSizeBytes: 100,
  suggestedFilename: '$id.epub',
  requiresAuthentication: false,
  supported: true,
  unsupportedReason: null,
  remoteMetadata: TrustedRemoteBookMetadata(
    sourceId: 'source',
    publicationId: id,
    title: 'Book $id',
    authors: const ['Author'],
    description: 'Description $id',
    publisher: 'Publisher',
    language: 'en',
    publishedDate: '1901',
    identifiers: const ['isbn:9781234567890'],
    subjects: const ['Fiction'],
    rights: 'Public domain',
    publicationLocation: Uri.parse('https://example.test/$id'),
    acquisitionLocation: Uri.parse('https://example.test/$id.epub'),
  ),
);

Future<void> _until(FutureOr<bool> Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Condition was not reached');
}

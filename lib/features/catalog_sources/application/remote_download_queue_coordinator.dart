import 'dart:async';

import 'package:bibliolife/features/catalog_sources/domain/remote_book_download.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download_plan.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_download_task.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_download_task_repository.dart';

class RemoteDownloadQueueCoordinator {
  RemoteDownloadQueueCoordinator(
    this._tasks,
    this._downloader, {
    this.operationTimeout = const Duration(minutes: 10),
  });
  final RemoteDownloadTaskRepository _tasks;
  final RemoteBookDownloader _downloader;
  final Duration operationTimeout;
  RemoteBookDownloadCancellation? _cancellation;
  bool _running = false;
  Future<void> _submissionTail = Future.value();

  /// Called after a successful download is durably recorded.
  Future<void> Function(String taskId)? onDownloadCompleted;

  Future<RemoteDownloadTask> submit(RemoteBookDownloadPlan plan) async {
    final previous = _submissionTail;
    final release = Completer<void>();
    _submissionTail = release.future;
    await previous;
    try {
      return await _submitLocked(plan);
    } finally {
      release.complete();
    }
  }

  Future<RemoteDownloadTask> _submitLocked(RemoteBookDownloadPlan plan) async {
    final uri = plan.acquisitionUri;
    if (uri == null) throw StateError('Download plan has no acquisition URI');
    final existing = await _tasks.findActiveByIdentity(
      plan.sourceId,
      plan.publicationRemoteId,
      uri.toString(),
    );
    if (existing != null) return existing;
    final now = DateTime.now();
    final task = RemoteDownloadTask(
      id: '${now.microsecondsSinceEpoch}-${plan.sourceId}-${plan.publicationRemoteId}',
      sourceId: plan.sourceId,
      publicationRemoteId: plan.publicationRemoteId,
      title: plan.publicationTitle,
      authors: plan.authors,
      acquisitionUri: uri.toString(),
      declaredMediaType: plan.declaredMediaType,
      expectedFinalMediaType: plan.expectedFinalMediaType,
      suggestedFilename: plan.suggestedFilename,
      expectedSizeBytes: plan.expectedSizeBytes,
      state: RemoteDownloadTaskState.queued,
      downloadedBytes: 0,
      retryCount: 0,
      createdAt: now,
      updatedAt: now,
      remoteMetadata: plan.remoteMetadata,
    );
    await _tasks.create(task);
    unawaited(runNext());
    return (await _tasks.getById(task.id))!;
  }

  Future<void> retry(String id) async {
    final task = await _tasks.getById(id);
    if (task == null || !task.canRetry) return;
    await _tasks.transition(id, RemoteDownloadTaskState.queued);
    unawaited(runNext());
  }

  Future<void> cancel(String id) async {
    final task = await _tasks.getById(id);
    if (task?.state == RemoteDownloadTaskState.downloading) {
      await _tasks.transition(
        id,
        RemoteDownloadTaskState.cancelled,
        attemptId: task!.attemptId,
        failure: RemoteDownloadFailureCategory.cancelled,
      );
      _cancellation?.cancel();
    } else if (task?.state == RemoteDownloadTaskState.queued) {
      await _tasks.transition(id, RemoteDownloadTaskState.cancelled);
    }
  }

  Future<void> runNext() async {
    if (_running) {
      return;
    }
    final all = await _tasks.getAll();
    final task = all
        .where((t) => t.state == RemoteDownloadTaskState.queued)
        .fold<RemoteDownloadTask?>(
          null,
          (a, b) => a == null || b.createdAt.isBefore(a.createdAt) ? b : a,
        );
    if (task == null) {
      return;
    }
    _running = true;
    await _tasks.transition(task.id, RemoteDownloadTaskState.downloading);
    final active = (await _tasks.getById(task.id))!;
    final cancellation = RemoteBookDownloadCancellation();
    _cancellation = cancellation;
    var lastProgressWrite = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      final result = await _downloader
          .download(
            plan: _plan(active),
            cancellation: cancellation,
            onProgress: (p) {
              final now = DateTime.now();
              if (p.bytesReceived != p.totalBytes &&
                  now.difference(lastProgressWrite) <
                      const Duration(milliseconds: 200)) {
                return;
              }
              lastProgressWrite = now;
              unawaited(
                _tasks.updateProgress(
                  active.id,
                  active.attemptId,
                  p.bytesReceived,
                  p.totalBytes,
                ),
              );
            },
          )
          .timeout(
            operationTimeout,
            onTimeout: () {
              cancellation.cancel();
              throw const RemoteBookDownloadException(
                RemoteBookDownloadFailure.timeout,
              );
            },
          );
      final latest = await _tasks.getById(active.id);
      if (latest?.state == RemoteDownloadTaskState.downloading &&
          latest?.attemptId == active.attemptId) {
        await _tasks.transition(
          active.id,
          RemoteDownloadTaskState.completedTemporary,
          attemptId: active.attemptId,
          temporaryFilePath: result.temporaryFilePath,
          sha256: result.checksum,
          downloadedBytes: result.byteCount,
          totalBytes: result.byteCount,
        );
        final onCompleted = onDownloadCompleted;
        if (onCompleted != null) await onCompleted(active.id);
      }
    } on RemoteBookDownloadException catch (e) {
      final state = e.failure == RemoteBookDownloadFailure.cancelled
          ? RemoteDownloadTaskState.cancelled
          : RemoteDownloadTaskState.failed;
      final latest = await _tasks.getById(active.id);
      if (latest?.state == RemoteDownloadTaskState.downloading &&
          latest?.attemptId == active.attemptId) {
        await _tasks.transition(
          active.id,
          state,
          attemptId: active.attemptId,
          failure: _failure(e.failure),
        );
      }
    } on Object {
      final latest = await _tasks.getById(active.id);
      if (latest?.state == RemoteDownloadTaskState.downloading &&
          latest?.attemptId == active.attemptId) {
        await _tasks.transition(
          active.id,
          RemoteDownloadTaskState.failed,
          attemptId: active.attemptId,
          failure: RemoteDownloadFailureCategory.transport,
        );
      }
    } finally {
      if (identical(_cancellation, cancellation)) _cancellation = null;
      _running = false;
      await runNext();
    }
  }

  RemoteBookDownloadPlan _plan(RemoteDownloadTask t) => RemoteBookDownloadPlan(
    sourceId: t.sourceId,
    publicationRemoteId: t.publicationRemoteId,
    publicationTitle: t.title,
    authors: t.authors,
    acquisitionUri: Uri.parse(t.acquisitionUri),
    declaredMediaType: t.declaredMediaType,
    acquisitionRelation: 'http://opds-spec.org/acquisition/open-access',
    isIndirect: false,
    expectedFinalMediaType: t.expectedFinalMediaType,
    expectedSizeBytes: t.expectedSizeBytes,
    suggestedFilename: t.suggestedFilename,
    requiresAuthentication: false,
    supported: true,
    unsupportedReason: null,
    remoteMetadata: t.remoteMetadata,
  );
  RemoteDownloadFailureCategory _failure(RemoteBookDownloadFailure f) =>
      switch (f) {
        RemoteBookDownloadFailure.accessDenied =>
          RemoteDownloadFailureCategory.accessDenied,
        RemoteBookDownloadFailure.timeout =>
          RemoteDownloadFailureCategory.timeout,
        RemoteBookDownloadFailure.authenticationRequired ||
        RemoteBookDownloadFailure.authenticationFailed =>
          RemoteDownloadFailureCategory.authenticationRequired,
        RemoteBookDownloadFailure.notFound =>
          RemoteDownloadFailureCategory.notFound,
        RemoteBookDownloadFailure.tooLarge =>
          RemoteDownloadFailureCategory.tooLarge,
        RemoteBookDownloadFailure.invalidZip ||
        RemoteBookDownloadFailure.notEpub ||
        RemoteBookDownloadFailure.wrongMediaType =>
          RemoteDownloadFailureCategory.invalidEpub,
        RemoteBookDownloadFailure.fileSystem =>
          RemoteDownloadFailureCategory.storage,
        _ => RemoteDownloadFailureCategory.transport,
      };
}

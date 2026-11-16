import 'dart:io';
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_download_queue_coordinator.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download_plan.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_download_task.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_download_task_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_temporary_epub_import.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';

enum RemoteDownloadUiPhase {
  idle,
  queued,
  downloading,
  interrupted,
  completedTemporary,
  importing,
  imported,
  duplicate,
  failed,
  cancelled,
}

class RemoteDownloadUiState {
  const RemoteDownloadUiState({required this.phase, this.task});

  const RemoteDownloadUiState.idle()
    : phase = RemoteDownloadUiPhase.idle,
      task = null;

  final RemoteDownloadUiPhase phase;
  final RemoteDownloadTask? task;
  double? get progress {
    final total = task?.totalBytes;
    return total == null || total <= 0
        ? null
        : (task!.downloadedBytes / total).clamp(0, 1);
  }
}

class RemoteDownloadQueueFacade {
  RemoteDownloadQueueFacade(
    this._tasks,
    this._coordinator,
    this._importer,
    this._temporaryDirectory,
    this._localBookExists,
  ) {
    _coordinator.onDownloadCompleted = importCompleted;
  }

  final RemoteDownloadTaskRepository _tasks;
  final RemoteDownloadQueueCoordinator _coordinator;
  final RemoteTemporaryEpubImporter _importer;
  final Future<Directory> Function() _temporaryDirectory;
  final Future<bool> Function(String id) _localBookExists;
  final Map<String, Future<void>> _importsInFlight = {};
  final Set<String> _reportedExistingImports = <String>{};
  final Map<String, Future<RemoteDownloadTask?>> _reconciliations = {};

  void dispose() {
    if (_coordinator.onDownloadCompleted == importCompleted) {
      _coordinator.onDownloadCompleted = null;
    }
  }

  Future<RemoteDownloadTask> enqueueOrReuse(RemoteBookDownloadPlan plan) async {
    _log(
      'ACQUISITION_REQUESTED sourceId=${plan.sourceId} remoteId=${plan.publicationRemoteId}',
    );
    final uri = plan.acquisitionUri;
    if (uri != null) {
      final existing = await _tasks.findActiveByIdentity(
        plan.sourceId,
        plan.publicationRemoteId,
        uri.toString(),
      );
      if (existing != null) await _reconcileTerminalTask(existing);
    }
    return _coordinator.submit(plan);
  }

  Stream<RemoteDownloadUiState> observeById(String id) =>
      _tasks.watchById(id).asyncMap(_reconcileAndMap);

  Stream<RemoteDownloadUiState> observeByIdentity(
    String sourceId,
    String publicationId,
    Uri acquisitionUri,
  ) => _tasks
      .watchByIdentity(sourceId, publicationId, acquisitionUri.toString())
      .asyncMap(_reconcileAndMap);

  Stream<List<RemoteDownloadTask>> watchAll() =>
      _tasks.watchAll().asyncMap((tasks) async {
        final reconciledTasks = <RemoteDownloadTask>[];
        for (final task in tasks) {
          final reconciled = await _reconcileTerminalTask(task);
          if (reconciled != null) reconciledTasks.add(reconciled);
        }
        return reconciledTasks;
      });

  Future<void> retry(String id) async {
    final task = await _tasks.getById(id);
    if (task?.failure == RemoteDownloadFailureCategory.importFailure &&
        task?.temporaryFilePath != null) {
      await importCompleted(id);
      return;
    }
    await _coordinator.retry(id);
  }

  Future<void> cancel(String id) => _coordinator.cancel(id);

  Future<void> importCompleted(String id) {
    return _importsInFlight.putIfAbsent(id, () async {
      try {
        await _performImport(id);
      } finally {
        _importsInFlight.remove(id);
      }
    });
  }

  Future<void> _performImport(String id) async {
    try {
      final task = await _tasks.getById(id);
      if (task == null ||
          (task.state != RemoteDownloadTaskState.completedTemporary &&
              !(task.state == RemoteDownloadTaskState.failed &&
                  task.failure ==
                      RemoteDownloadFailureCategory.importFailure)) ||
          task.temporaryFilePath == null ||
          task.sha256 == null) {
        return;
      }
      _log(
        'ACQUISITION_IMPORT_STARTED sourceId=${task.sourceId} remoteId=${task.publicationRemoteId}',
      );
      await _tasks.transition(id, RemoteDownloadTaskState.importing);
      final result = await _importer.import(
        RemoteTemporaryEpubImportInput(
          temporaryFilePath: task.temporaryFilePath!,
          sourceId: task.sourceId,
          publicationRemoteId: task.publicationRemoteId,
          remoteTitle: task.title,
          remoteAuthors: task.authors,
          acquisitionUri: Uri.parse(task.acquisitionUri),
          sha256: task.sha256!,
          downloadedByteCount: task.downloadedBytes,
          suggestedFilename: task.suggestedFilename,
          remoteMetadata: task.remoteMetadata,
        ),
      );
      switch (result) {
        case RemoteTemporaryEpubImported(:final book):
          _log(
            'ACQUISITION_IMPORT_COMPLETED sourceId=${task.sourceId} remoteId=${task.publicationRemoteId} localBookId=${book.id}',
          );
          await _tasks.transition(
            id,
            RemoteDownloadTaskState.imported,
            importedBookId: book.id,
          );
        case RemoteTemporaryEpubAlreadyInLibrary(:final book):
          _log(
            'ACQUISITION_EXISTING_IMPORT_REUSED sourceId=${task.sourceId} remoteId=${task.publicationRemoteId} localBookId=${book.id}',
          );
          await _tasks.transition(
            id,
            RemoteDownloadTaskState.duplicate,
            importedBookId: book.id,
          );
        case RemoteTemporaryEpubImportFailed(:final failure):
          _log(
            'ACQUISITION_IMPORT_FAILED sourceId=${task.sourceId} remoteId=${task.publicationRemoteId} failure=${failure.name}',
          );
          await _tasks.transition(
            id,
            RemoteDownloadTaskState.failed,
            failure: RemoteDownloadFailureCategory.importFailure,
          );
      }
    } on Object catch (error) {
      _log(
        'ACQUISITION_IMPORT_FAILED taskId=$id errorType=${error.runtimeType}',
      );
      final latest = await _tasks.getById(id);
      if (latest?.state == RemoteDownloadTaskState.importing) {
        await _tasks.transition(
          id,
          RemoteDownloadTaskState.failed,
          failure: RemoteDownloadFailureCategory.importFailure,
        );
      }
    }
  }

  Future<void> deleteTemporaryEpub(String id) async {
    final task = await _tasks.getById(id);
    if (task?.state != RemoteDownloadTaskState.completedTemporary ||
        task?.temporaryFilePath == null) {
      return;
    }
    final file = File(task!.temporaryFilePath!);
    if (!await _isControlled(file.path)) return;
    if (await file.exists()) await file.delete();
    await _tasks.transition(id, RemoteDownloadTaskState.deleted);
  }

  Future<void> removeHistory(String id) async {
    final task = await _tasks.getById(id);
    if (task == null || task.isActive) return;
    if (task.state == RemoteDownloadTaskState.completedTemporary) {
      await deleteTemporaryEpub(id);
      return;
    }
    await _tasks.transition(id, RemoteDownloadTaskState.deleted);
  }

  Future<void> reconcileOnStartup() async {
    final tasks = await _tasks.getAll();
    for (final task in tasks) {
      final reconciled = await _reconcileTerminalTask(task);
      if (reconciled == null) continue;
      if (reconciled.state == RemoteDownloadTaskState.downloading) {
        final partial = reconciled.temporaryFilePath;
        if (partial != null &&
            partial.toLowerCase().endsWith('.part') &&
            await _isControlled(partial)) {
          final file = File(partial);
          if (await file.exists()) await file.delete();
        }
      } else if (reconciled.state ==
          RemoteDownloadTaskState.completedTemporary) {
        final filePath = reconciled.temporaryFilePath;
        if (filePath == null || !await File(filePath).exists()) {
          await _tasks.transition(
            reconciled.id,
            RemoteDownloadTaskState.failed,
            failure: RemoteDownloadFailureCategory.storage,
          );
        } else {
          await importCompleted(reconciled.id);
        }
      }
    }
    await _tasks.recoverInterrupted();
  }

  Future<void> reconcileImported(String id) async {
    final task = await _tasks.getById(id);
    await _reconcileTerminalTask(task);
  }

  Future<bool> _isControlled(String filePath) async {
    final root = path.normalize(
      path.absolute(
        path.join((await _temporaryDirectory()).path, 'remote-downloads'),
      ),
    );
    return path.isWithin(root, path.normalize(path.absolute(filePath)));
  }

  Future<RemoteDownloadUiState> _reconcileAndMap(
    RemoteDownloadTask? task,
  ) async {
    final reconciled = await _reconcileTerminalTask(task);
    if (reconciled != null &&
        (reconciled.state == RemoteDownloadTaskState.imported ||
            reconciled.state == RemoteDownloadTaskState.duplicate) &&
        reconciled.importedBookId != null &&
        _reportedExistingImports.add(reconciled.id)) {
      _log(
        'ACQUISITION_EXISTING_IMPORT_REUSED sourceId=${reconciled.sourceId} remoteId=${reconciled.publicationRemoteId} localBookId=${reconciled.importedBookId}',
      );
    }
    if (reconciled?.state == RemoteDownloadTaskState.completedTemporary) {
      unawaited(importCompleted(reconciled!.id));
      return RemoteDownloadUiState(
        phase: RemoteDownloadUiPhase.importing,
        task: reconciled,
      );
    }
    return _uiState(reconciled);
  }

  Future<RemoteDownloadTask?> _reconcileTerminalTask(
    RemoteDownloadTask? task,
  ) async {
    if (task == null ||
        (task.state != RemoteDownloadTaskState.imported &&
            task.state != RemoteDownloadTaskState.duplicate)) {
      return task;
    }
    final running = _reconciliations[task.id];
    if (running != null) return running;
    final future = _performTerminalReconciliation(task);
    _reconciliations[task.id] = future;
    try {
      return await future;
    } finally {
      _reconciliations.remove(task.id);
    }
  }

  Future<RemoteDownloadTask?> _performTerminalReconciliation(
    RemoteDownloadTask task,
  ) async {
    final localId = task.importedBookId;
    if (localId != null && await _localBookExists(localId)) return task;
    if (await _retainedTemporaryEpubIsValid(task)) {
      await _tasks.transition(
        task.id,
        RemoteDownloadTaskState.completedTemporary,
      );
      return _tasks.getById(task.id);
    }
    await _tasks.transition(task.id, RemoteDownloadTaskState.deleted);
    return null;
  }

  Future<bool> _retainedTemporaryEpubIsValid(RemoteDownloadTask task) async {
    final filePath = task.temporaryFilePath;
    final expectedHash = task.sha256;
    if (filePath == null ||
        expectedHash == null ||
        !await _isControlled(filePath)) {
      return false;
    }
    final file = File(filePath);
    if (!await file.exists()) return false;
    try {
      return (await sha256.bind(file.openRead()).first).toString() ==
          expectedHash;
    } on FileSystemException {
      return false;
    }
  }

  RemoteDownloadUiState _uiState(RemoteDownloadTask? task) {
    if (task == null || task.state == RemoteDownloadTaskState.deleted) {
      return const RemoteDownloadUiState.idle();
    }
    final phase = switch (task.state) {
      RemoteDownloadTaskState.queued => RemoteDownloadUiPhase.queued,
      RemoteDownloadTaskState.downloading => RemoteDownloadUiPhase.downloading,
      RemoteDownloadTaskState.pausedByAppRestart =>
        RemoteDownloadUiPhase.interrupted,
      RemoteDownloadTaskState.completedTemporary =>
        RemoteDownloadUiPhase.completedTemporary,
      RemoteDownloadTaskState.importing => RemoteDownloadUiPhase.importing,
      RemoteDownloadTaskState.imported => RemoteDownloadUiPhase.imported,
      RemoteDownloadTaskState.duplicate => RemoteDownloadUiPhase.duplicate,
      RemoteDownloadTaskState.failed => RemoteDownloadUiPhase.failed,
      RemoteDownloadTaskState.cancelled => RemoteDownloadUiPhase.cancelled,
      RemoteDownloadTaskState.deleted => RemoteDownloadUiPhase.idle,
    };
    return RemoteDownloadUiState(phase: phase, task: task);
  }

  void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }
}

import 'dart:convert';
import 'package:bibliolife/core/database/app_database.dart' as db;
import 'package:bibliolife/features/catalog_sources/domain/remote_download_task.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_download_task_repository.dart';
import 'package:bibliolife/features/catalog_sources/data/trusted_remote_metadata_snapshot.dart';
import 'package:drift/drift.dart';

class DriftRemoteDownloadTaskRepository
    implements RemoteDownloadTaskRepository {
  DriftRemoteDownloadTaskRepository(this._db);
  final db.AppDatabase _db;
  @override
  Stream<List<RemoteDownloadTask>> watchAll() =>
      (_db.select(_db.remoteDownloadTasks)
            ..where(
              (t) => t.state.equals(RemoteDownloadTaskState.deleted.name).not(),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
          .watch()
          .map((rows) => rows.map(_map).toList());
  @override
  Stream<RemoteDownloadTask?> watchById(String id) =>
      (_db.select(_db.remoteDownloadTasks)..where((t) => t.id.equals(id)))
          .watchSingleOrNull()
          .map((row) => row == null ? null : _map(row));
  @override
  Stream<RemoteDownloadTask?> watchByIdentity(String s, String p, String u) =>
      (_db.select(_db.remoteDownloadTasks)
            ..where(
              (t) =>
                  t.sourceId.equals(s) &
                  t.publicationRemoteId.equals(p) &
                  t.acquisitionUri.equals(u) &
                  t.state.equals(RemoteDownloadTaskState.deleted.name).not(),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
            ..limit(1))
          .watchSingleOrNull()
          .map((row) => row == null ? null : _map(row));
  @override
  Future<List<RemoteDownloadTask>> getAll() async =>
      (await _db.select(_db.remoteDownloadTasks).get()).map(_map).toList();
  @override
  Future<RemoteDownloadTask?> getById(String id) =>
      (_db.select(_db.remoteDownloadTasks)..where((t) => t.id.equals(id)))
          .getSingleOrNull()
          .then((r) => r == null ? null : _map(r));
  @override
  Future<RemoteDownloadTask?> findActiveByIdentity(
    String s,
    String p,
    String u,
  ) =>
      (_db.select(_db.remoteDownloadTasks)..where(
            (t) =>
                t.sourceId.equals(s) &
                t.publicationRemoteId.equals(p) &
                t.acquisitionUri.equals(u) &
                t.state.isIn(
                  RemoteDownloadTaskState.values
                      .where((x) => x != RemoteDownloadTaskState.deleted)
                      .map((x) => x.name),
                ),
          ))
          .getSingleOrNull()
          .then((r) => r == null ? null : _map(r));
  @override
  Future<void> create(RemoteDownloadTask x) =>
      _db.into(_db.remoteDownloadTasks).insert(_companion(x));
  @override
  Future<void> updateProgress(
    String id,
    int attempt,
    int bytes,
    int? total,
  ) async {
    final old = await getById(id);
    if (old == null ||
        old.attemptId != attempt ||
        old.state != RemoteDownloadTaskState.downloading) {
      return;
    }
    await (_db.update(
      _db.remoteDownloadTasks,
    )..where((t) => t.id.equals(id))).write(
      db.RemoteDownloadTasksCompanion(
        downloadedBytes: Value(
          bytes.clamp(old.downloadedBytes, total ?? bytes),
        ),
        totalBytes: Value(total),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> transition(
    String id,
    RemoteDownloadTaskState to, {
    int? attemptId,
    String? temporaryFilePath,
    String? sha256,
    String? importedBookId,
    RemoteDownloadFailureCategory? failure,
    int? downloadedBytes,
    int? totalBytes,
  }) async {
    final old = await getById(id);
    if (old == null ||
        (attemptId != null && old.attemptId != attemptId) ||
        !isLegalDownloadTaskTransition(old.state, to)) {
      throw StateError('Illegal download task transition');
    }
    final now = DateTime.now();
    final retrying = to == RemoteDownloadTaskState.queued && old.canRetry;
    await (_db.update(
      _db.remoteDownloadTasks,
    )..where((t) => t.id.equals(id))).write(
      db.RemoteDownloadTasksCompanion(
        state: Value(to.name),
        temporaryFilePath: retrying
            ? const Value(null)
            : temporaryFilePath == null
            ? const Value.absent()
            : Value(temporaryFilePath),
        sha256: retrying
            ? const Value(null)
            : sha256 == null
            ? const Value.absent()
            : Value(sha256),
        importedBookId:
            retrying || to == RemoteDownloadTaskState.completedTemporary
            ? const Value(null)
            : importedBookId == null
            ? const Value.absent()
            : Value(importedBookId),
        failureCategory: Value(failure?.name),
        downloadedBytes: Value(
          retrying ? 0 : downloadedBytes ?? old.downloadedBytes,
        ),
        totalBytes: retrying
            ? const Value(null)
            : Value(totalBytes ?? old.totalBytes),
        updatedAt: Value(now),
        startedAt: retrying
            ? const Value(null)
            : to == RemoteDownloadTaskState.downloading
            ? Value(now)
            : const Value.absent(),
        completedAt: retrying
            ? const Value(null)
            : (to == RemoteDownloadTaskState.completedTemporary ||
                  to == RemoteDownloadTaskState.imported ||
                  to == RemoteDownloadTaskState.duplicate)
            ? Value(now)
            : const Value.absent(),
        retryCount: retrying ? Value(old.retryCount + 1) : const Value.absent(),
        attemptId: retrying ? Value(old.attemptId + 1) : const Value.absent(),
      ),
    );
  }

  @override
  Future<void> recoverInterrupted() async {
    final now = DateTime.now();
    await (_db.update(_db.remoteDownloadTasks)..where(
          (t) => t.state.equals(RemoteDownloadTaskState.downloading.name),
        ))
        .write(
          db.RemoteDownloadTasksCompanion(
            state: Value(RemoteDownloadTaskState.pausedByAppRestart.name),
            failureCategory: Value(
              RemoteDownloadFailureCategory.interruptedByRestart.name,
            ),
            updatedAt: Value(now),
          ),
        );
    await (_db.update(
          _db.remoteDownloadTasks,
        )..where((t) => t.state.equals(RemoteDownloadTaskState.importing.name)))
        .write(
          db.RemoteDownloadTasksCompanion(
            state: Value(RemoteDownloadTaskState.failed.name),
            failureCategory: Value(
              RemoteDownloadFailureCategory.importFailure.name,
            ),
            updatedAt: Value(now),
          ),
        );
  }

  db.RemoteDownloadTasksCompanion _companion(RemoteDownloadTask x) =>
      db.RemoteDownloadTasksCompanion.insert(
        id: x.id,
        sourceId: x.sourceId,
        publicationRemoteId: x.publicationRemoteId,
        title: x.title,
        authorsJson: jsonEncode(x.authors),
        acquisitionUri: x.acquisitionUri,
        suggestedFilename: x.suggestedFilename,
        state: x.state.name,
        createdAt: x.createdAt,
        updatedAt: x.updatedAt,
        declaredMediaType: Value(x.declaredMediaType),
        expectedFinalMediaType: Value(x.expectedFinalMediaType),
        expectedSizeBytes: Value(x.expectedSizeBytes),
        downloadedBytes: Value(x.downloadedBytes),
        totalBytes: Value(x.totalBytes),
        temporaryFilePath: Value(x.temporaryFilePath),
        sha256: Value(x.sha256),
        failureCategory: Value(x.failure?.name),
        startedAt: Value(x.startedAt),
        completedAt: Value(x.completedAt),
        importedBookId: Value(x.importedBookId),
        retryCount: Value(x.retryCount),
        attemptId: Value(x.attemptId),
        remoteMetadataJson: Value(
          x.remoteMetadata == null
              ? null
              : encodeTrustedRemoteMetadataSnapshot(x.remoteMetadata!),
        ),
      );
  RemoteDownloadTask _map(db.RemoteDownloadTask row) => RemoteDownloadTask(
    id: row.id,
    sourceId: row.sourceId,
    publicationRemoteId: row.publicationRemoteId,
    title: row.title,
    authors: (jsonDecode(row.authorsJson) as List).cast<String>(),
    acquisitionUri: row.acquisitionUri,
    suggestedFilename: row.suggestedFilename,
    state: RemoteDownloadTaskState.values.byName(row.state),
    downloadedBytes: row.downloadedBytes,
    retryCount: row.retryCount,
    attemptId: row.attemptId,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    declaredMediaType: row.declaredMediaType,
    expectedFinalMediaType: row.expectedFinalMediaType,
    expectedSizeBytes: row.expectedSizeBytes,
    totalBytes: row.totalBytes,
    temporaryFilePath: row.temporaryFilePath,
    sha256: row.sha256,
    failure: row.failureCategory == null
        ? null
        : RemoteDownloadFailureCategory.values.byName(row.failureCategory!),
    startedAt: row.startedAt,
    completedAt: row.completedAt,
    importedBookId: row.importedBookId,
    remoteMetadata: decodeTrustedRemoteMetadataSnapshot(row.remoteMetadataJson),
  );
}

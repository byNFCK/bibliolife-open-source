import 'package:bibliolife/features/catalog_sources/domain/remote_download_task.dart';

abstract interface class RemoteDownloadTaskRepository {
  Stream<List<RemoteDownloadTask>> watchAll();
  Stream<RemoteDownloadTask?> watchById(String id);
  Stream<RemoteDownloadTask?> watchByIdentity(
    String sourceId,
    String publicationId,
    String acquisitionUri,
  );
  Future<List<RemoteDownloadTask>> getAll();
  Future<RemoteDownloadTask?> getById(String id);
  Future<RemoteDownloadTask?> findActiveByIdentity(
    String sourceId,
    String publicationId,
    String acquisitionUri,
  );
  Future<void> create(RemoteDownloadTask task);
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
  });
  Future<void> updateProgress(
    String id,
    int attemptId,
    int downloadedBytes,
    int? totalBytes,
  );
  Future<void> recoverInterrupted();
}

import 'package:bibliolife/features/metadata/domain/entities/trusted_remote_book_metadata.dart';

enum RemoteDownloadTaskState {
  queued,
  downloading,
  pausedByAppRestart,
  completedTemporary,
  importing,
  imported,
  duplicate,
  failed,
  cancelled,
  deleted,
}

enum RemoteDownloadFailureCategory {
  accessDenied,
  timeout,
  transport,
  httpStatus,
  authenticationRequired,
  notFound,
  tooLarge,
  invalidEpub,
  storage,
  cancelled,
  interruptedByRestart,
  importFailure,
}

/// Immutable persisted download-history record. It deliberately contains no
/// clients, streams, cancellation objects or exception text.
class RemoteDownloadTask {
  const RemoteDownloadTask({
    required this.id,
    required this.sourceId,
    required this.publicationRemoteId,
    required this.title,
    required this.authors,
    required this.acquisitionUri,
    required this.suggestedFilename,
    required this.state,
    required this.downloadedBytes,
    required this.retryCount,
    required this.createdAt,
    required this.updatedAt,
    this.declaredMediaType,
    this.expectedFinalMediaType,
    this.expectedSizeBytes,
    this.totalBytes,
    this.temporaryFilePath,
    this.sha256,
    this.failure,
    this.startedAt,
    this.completedAt,
    this.importedBookId,
    this.attemptId = 0,
    this.remoteMetadata,
  });

  final String id, sourceId, publicationRemoteId, title, acquisitionUri;
  final List<String> authors;
  final String suggestedFilename;
  final RemoteDownloadTaskState state;
  final String? declaredMediaType,
      expectedFinalMediaType,
      temporaryFilePath,
      sha256;
  final int? expectedSizeBytes, totalBytes;
  final int downloadedBytes, retryCount, attemptId;
  final RemoteDownloadFailureCategory? failure;
  final DateTime createdAt, updatedAt;
  final DateTime? startedAt, completedAt;
  final String? importedBookId;
  final TrustedRemoteBookMetadata? remoteMetadata;

  bool get isActive =>
      state == RemoteDownloadTaskState.queued ||
      state == RemoteDownloadTaskState.downloading ||
      state == RemoteDownloadTaskState.importing;
  bool get canRetry =>
      state == RemoteDownloadTaskState.failed ||
      state == RemoteDownloadTaskState.cancelled ||
      state == RemoteDownloadTaskState.pausedByAppRestart;
}

bool isLegalDownloadTaskTransition(
  RemoteDownloadTaskState from,
  RemoteDownloadTaskState to,
) => switch (from) {
  RemoteDownloadTaskState.queued =>
    to == RemoteDownloadTaskState.downloading ||
        to == RemoteDownloadTaskState.cancelled,
  RemoteDownloadTaskState.downloading =>
    to == RemoteDownloadTaskState.completedTemporary ||
        to == RemoteDownloadTaskState.failed ||
        to == RemoteDownloadTaskState.cancelled ||
        to == RemoteDownloadTaskState.pausedByAppRestart,
  RemoteDownloadTaskState.pausedByAppRestart ||
  RemoteDownloadTaskState.cancelled =>
    to == RemoteDownloadTaskState.queued ||
        to == RemoteDownloadTaskState.deleted,
  RemoteDownloadTaskState.failed =>
    to == RemoteDownloadTaskState.queued ||
        to == RemoteDownloadTaskState.importing ||
        to == RemoteDownloadTaskState.deleted,
  RemoteDownloadTaskState.completedTemporary =>
    to == RemoteDownloadTaskState.importing ||
        to == RemoteDownloadTaskState.failed ||
        to == RemoteDownloadTaskState.deleted,
  RemoteDownloadTaskState.importing =>
    to == RemoteDownloadTaskState.imported ||
        to == RemoteDownloadTaskState.duplicate ||
        to == RemoteDownloadTaskState.failed,
  RemoteDownloadTaskState.imported || RemoteDownloadTaskState.duplicate =>
    to == RemoteDownloadTaskState.completedTemporary ||
        to == RemoteDownloadTaskState.deleted,
  RemoteDownloadTaskState.deleted => false,
};

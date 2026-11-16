import 'dart:async';

import 'package:bibliolife/features/catalog_sources/domain/remote_book_download_plan.dart';
import 'package:bibliolife/features/metadata/domain/entities/trusted_remote_book_metadata.dart';

enum RemoteBookDownloadFailure {
  unsupportedPlan,
  indirectAcquisition,
  authenticationRequired,
  unsupportedMediaType,
  missingLocation,
  insecureLocation,
  unsafeFilename,
  missingIdentity,
  accessDenied,
  authenticationFailed,
  notFound,
  serverError,
  httpStatus,
  insecureRedirect,
  timeout,
  transport,
  emptyBody,
  tooLarge,
  invalidContentLength,
  wrongMediaType,
  invalidZip,
  notEpub,
  interrupted,
  fileSystem,
  cancelled,
}

enum RemoteBookDownloadPhase {
  idle,
  downloading,
  validating,
  succeeded,
  failed,
  cancelled,
}

class RemoteBookDownloadProgress {
  const RemoteBookDownloadProgress({
    required this.phase,
    this.bytesReceived = 0,
    this.totalBytes,
    this.failure,
  });

  final RemoteBookDownloadPhase phase;
  final int bytesReceived;
  final int? totalBytes;
  final RemoteBookDownloadFailure? failure;

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (bytesReceived / total).clamp(0, 1);
  }
}

class RemoteBookDownloadResult {
  const RemoteBookDownloadResult({
    required this.temporaryFilePath,
    required this.byteCount,
    required this.declaredMediaType,
    required this.effectiveUri,
    required this.suggestedFilename,
    required this.sourceId,
    required this.publicationRemoteId,
    this.checksum,
    this.remoteMetadata,
  });

  final String temporaryFilePath;
  final int byteCount;
  final String declaredMediaType;
  final Uri effectiveUri;
  final String? checksum;
  final String suggestedFilename;
  final String sourceId;
  final String publicationRemoteId;
  final TrustedRemoteBookMetadata? remoteMetadata;
}

class RemoteBookDownloadException implements Exception {
  const RemoteBookDownloadException(this.failure);
  final RemoteBookDownloadFailure failure;
}

class RemoteBookDownloadCancellation {
  bool _cancelled = false;
  final _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  void onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }
}

abstract interface class RemoteBookDownloader {
  Future<RemoteBookDownloadResult> download({
    required RemoteBookDownloadPlan plan,
    required RemoteBookDownloadCancellation cancellation,
    required void Function(RemoteBookDownloadProgress progress) onProgress,
  });
}

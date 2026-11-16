import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download_plan.dart';
import 'package:bibliolife/features/connectivity/application/network_access_policy.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

const remoteEpubMediaType = 'application/epub+zip';

abstract interface class RemoteEpubDownloadTransport {
  Future<RemoteEpubTransportResult> download({
    required Uri uri,
    required File destination,
    required Duration timeout,
    required int maximumBytes,
    required int maximumRedirects,
    required RemoteBookDownloadCancellation cancellation,
    required void Function(int bytes, int? total) onProgress,
  });
}

class RemoteEpubTransportResult {
  const RemoteEpubTransportResult({
    required this.effectiveUri,
    required this.byteCount,
    required this.contentType,
  });
  final Uri effectiveUri;
  final int byteCount;
  final String? contentType;
}

class ForegroundRemoteBookDownloader implements RemoteBookDownloader {
  ForegroundRemoteBookDownloader(
    this._policy,
    this._transport,
    this._temporaryDirectory, {
    String Function()? uniqueId,
    this.timeout = const Duration(seconds: 30),
    this.maximumBytes = 100 * 1024 * 1024,
    this.maximumRedirects = 5,
  }) : _uniqueId = uniqueId ?? _defaultUniqueId;

  final NetworkAccessPolicy _policy;
  final RemoteEpubDownloadTransport _transport;
  final Future<Directory> Function() _temporaryDirectory;
  final String Function() _uniqueId;
  final Duration timeout;
  final int maximumBytes;
  final int maximumRedirects;

  @override
  Future<RemoteBookDownloadResult> download({
    required RemoteBookDownloadPlan plan,
    required RemoteBookDownloadCancellation cancellation,
    required void Function(RemoteBookDownloadProgress progress) onProgress,
  }) async {
    _validatePlan(plan);
    _log(
      'ACQUISITION_DOWNLOAD_STARTED sourceId=${plan.sourceId} remoteId=${plan.publicationRemoteId} url=${_safeUri(plan.acquisitionUri!)}',
    );
    try {
      _policy.requireOnlineAccess('remote_epub_download');
    } on OfflineModeException {
      throw const RemoteBookDownloadException(
        RemoteBookDownloadFailure.accessDenied,
      );
    }
    if (cancellation.isCancelled) {
      throw const RemoteBookDownloadException(
        RemoteBookDownloadFailure.cancelled,
      );
    }

    Directory? workingDirectory;
    File? partial;
    try {
      final root = Directory(
        path.join((await _temporaryDirectory()).path, 'remote-downloads'),
      );
      workingDirectory = Directory(path.join(root.path, _uniqueId()));
      await workingDirectory.create(recursive: true);
      partial = File(
        path.join(workingDirectory.path, '${plan.suggestedFilename}.part'),
      );
      final finalFile = File(
        path.join(workingDirectory.path, plan.suggestedFilename),
      );
      if (await partial.exists() || await finalFile.exists()) {
        throw const RemoteBookDownloadException(
          RemoteBookDownloadFailure.fileSystem,
        );
      }

      var lastBytes = 0;
      final response = await _transport.download(
        uri: plan.acquisitionUri!,
        destination: partial,
        timeout: timeout,
        maximumBytes: maximumBytes,
        maximumRedirects: maximumRedirects,
        cancellation: cancellation,
        onProgress: (bytes, total) {
          if (bytes < lastBytes) return;
          lastBytes = bytes;
          onProgress(
            RemoteBookDownloadProgress(
              phase: RemoteBookDownloadPhase.downloading,
              bytesReceived: bytes,
              totalBytes: total,
            ),
          );
        },
      );
      _log(
        'ACQUISITION_BODY_COMPLETED sourceId=${plan.sourceId} remoteId=${plan.publicationRemoteId} bytes=${response.byteCount}',
      );
      if (cancellation.isCancelled) {
        throw const RemoteBookDownloadException(
          RemoteBookDownloadFailure.cancelled,
        );
      }
      if (response.byteCount <= 0) {
        throw const RemoteBookDownloadException(
          RemoteBookDownloadFailure.emptyBody,
        );
      }
      _validateResponseMediaType(response.contentType);
      _log(
        'ACQUISITION_VALIDATION_STARTED sourceId=${plan.sourceId} remoteId=${plan.publicationRemoteId}',
      );
      onProgress(
        RemoteBookDownloadProgress(
          phase: RemoteBookDownloadPhase.validating,
          bytesReceived: response.byteCount,
          totalBytes: response.byteCount,
        ),
      );
      const EpubPackageValidator().validate(partial);
      _log(
        'ACQUISITION_DOWNLOAD_VALIDATED sourceId=${plan.sourceId} remoteId=${plan.publicationRemoteId} bytes=${response.byteCount}',
      );
      final checksum = (await sha256.bind(partial.openRead()).first).toString();
      await partial.rename(finalFile.path);
      _log(
        'ACQUISITION_TEMPORARY_FILE_FINALIZED sourceId=${plan.sourceId} remoteId=${plan.publicationRemoteId}',
      );
      onProgress(
        RemoteBookDownloadProgress(
          phase: RemoteBookDownloadPhase.succeeded,
          bytesReceived: response.byteCount,
          totalBytes: response.byteCount,
        ),
      );
      return RemoteBookDownloadResult(
        temporaryFilePath: finalFile.path,
        byteCount: response.byteCount,
        declaredMediaType: remoteEpubMediaType,
        effectiveUri: response.effectiveUri,
        checksum: checksum,
        suggestedFilename: plan.suggestedFilename,
        sourceId: plan.sourceId,
        publicationRemoteId: plan.publicationRemoteId,
        remoteMetadata: plan.remoteMetadata,
      );
    } on RemoteBookDownloadException {
      rethrow;
    } on TimeoutException {
      throw const RemoteBookDownloadException(
        RemoteBookDownloadFailure.timeout,
      );
    } on FileSystemException {
      throw const RemoteBookDownloadException(
        RemoteBookDownloadFailure.fileSystem,
      );
    } catch (_) {
      throw const RemoteBookDownloadException(
        RemoteBookDownloadFailure.transport,
      );
    } finally {
      if (partial != null && await partial.exists()) await partial.delete();
      if (workingDirectory != null &&
          await workingDirectory.exists() &&
          (await workingDirectory.list().isEmpty)) {
        await workingDirectory.delete();
      }
    }
  }

  void _validatePlan(RemoteBookDownloadPlan plan) {
    if (!plan.supported) {
      throw const RemoteBookDownloadException(
        RemoteBookDownloadFailure.unsupportedPlan,
      );
    }
    if (plan.isIndirect) {
      throw const RemoteBookDownloadException(
        RemoteBookDownloadFailure.indirectAcquisition,
      );
    }
    if (plan.requiresAuthentication) {
      throw const RemoteBookDownloadException(
        RemoteBookDownloadFailure.authenticationRequired,
      );
    }
    if (plan.declaredMediaType?.toLowerCase() != remoteEpubMediaType) {
      throw const RemoteBookDownloadException(
        RemoteBookDownloadFailure.unsupportedMediaType,
      );
    }
    final uri = plan.acquisitionUri;
    if (uri == null || uri.host.isEmpty) {
      throw const RemoteBookDownloadException(
        RemoteBookDownloadFailure.missingLocation,
      );
    }
    if (uri.scheme.toLowerCase() != 'https') {
      throw const RemoteBookDownloadException(
        RemoteBookDownloadFailure.insecureLocation,
      );
    }
    if (plan.sourceId.trim().isEmpty ||
        plan.publicationRemoteId.trim().isEmpty) {
      throw const RemoteBookDownloadException(
        RemoteBookDownloadFailure.missingIdentity,
      );
    }
    if (!_safeFilename(plan.suggestedFilename)) {
      throw const RemoteBookDownloadException(
        RemoteBookDownloadFailure.unsafeFilename,
      );
    }
  }

  bool _safeFilename(String value) =>
      value.isNotEmpty &&
      value.toLowerCase().endsWith('.epub') &&
      path.basename(value) == value &&
      !value.contains('..') &&
      !RegExp(r'[<>:"/\\|?*\x00-\x1F]').hasMatch(value);

  void _validateResponseMediaType(String? value) {
    final normalized = value?.split(';').first.trim().toLowerCase();
    if (normalized == remoteEpubMediaType ||
        normalized == 'application/octet-stream') {
      return;
    }
    throw const RemoteBookDownloadException(
      RemoteBookDownloadFailure.wrongMediaType,
    );
  }

  String _safeUri(Uri uri) => '${uri.scheme}://${uri.host}${uri.path}';

  void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }
}

class EpubPackageValidator {
  const EpubPackageValidator();

  void validate(File file) {
    try {
      final input = InputFileStream(file.path);
      try {
        final archive = ZipDecoder().decodeStream(input);
        final entry = archive.files.where((item) => item.name == 'mimetype');
        if (entry.isEmpty) {
          throw const RemoteBookDownloadException(
            RemoteBookDownloadFailure.notEpub,
          );
        }
        final content = entry.first.readBytes();
        if (content == null) {
          throw const RemoteBookDownloadException(
            RemoteBookDownloadFailure.notEpub,
          );
        }
        final value = String.fromCharCodes(content);
        if (value != remoteEpubMediaType) {
          throw const RemoteBookDownloadException(
            RemoteBookDownloadFailure.notEpub,
          );
        }
        if (!archive.files.any(
          (item) => item.name == 'META-INF/container.xml',
        )) {
          throw const RemoteBookDownloadException(
            RemoteBookDownloadFailure.notEpub,
          );
        }
      } finally {
        input.close();
      }
    } on RemoteBookDownloadException {
      rethrow;
    } catch (_) {
      throw const RemoteBookDownloadException(
        RemoteBookDownloadFailure.invalidZip,
      );
    }
  }
}

String _defaultUniqueId() => DateTime.now().microsecondsSinceEpoch.toString();

class IoRemoteEpubDownloadTransport implements RemoteEpubDownloadTransport {
  @override
  Future<RemoteEpubTransportResult> download({
    required Uri uri,
    required File destination,
    required Duration timeout,
    required int maximumBytes,
    required int maximumRedirects,
    required RemoteBookDownloadCancellation cancellation,
    required void Function(int bytes, int? total) onProgress,
  }) async {
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = timeout;
    cancellation.onCancel(() => client.close(force: true));
    IOSink? sink;
    try {
      var current = uri;
      for (var redirects = 0; ; redirects++) {
        if (cancellation.isCancelled) {
          throw const RemoteBookDownloadException(
            RemoteBookDownloadFailure.cancelled,
          );
        }
        final request = await client.getUrl(current).timeout(timeout);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, remoteEpubMediaType);
        final response = await request.close().timeout(timeout);
        final total = response.contentLength;
        final validTotal = total > 0 ? total : null;
        _log(
          'ACQUISITION_HEADERS_RECEIVED host=${current.host} status=${response.statusCode} contentLength=${validTotal ?? 'unknown'}',
        );
        if (response.isRedirect) {
          if (redirects >= maximumRedirects) {
            throw const RemoteBookDownloadException(
              RemoteBookDownloadFailure.httpStatus,
            );
          }
          final location = response.headers.value(HttpHeaders.locationHeader);
          final next = location == null ? null : current.resolve(location);
          if (next == null ||
              next.scheme.toLowerCase() != 'https' ||
              _isNonFileRedirect(next)) {
            throw const RemoteBookDownloadException(
              RemoteBookDownloadFailure.insecureRedirect,
            );
          }
          await response.drain<void>();
          current = next;
          continue;
        }
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw const RemoteBookDownloadException(
            RemoteBookDownloadFailure.authenticationFailed,
          );
        }
        if (response.statusCode == 404) {
          throw const RemoteBookDownloadException(
            RemoteBookDownloadFailure.notFound,
          );
        }
        if (response.statusCode >= 500) {
          throw const RemoteBookDownloadException(
            RemoteBookDownloadFailure.serverError,
          );
        }
        if (response.statusCode != 200) {
          throw const RemoteBookDownloadException(
            RemoteBookDownloadFailure.httpStatus,
          );
        }
        if (validTotal != null && validTotal > maximumBytes) {
          throw const RemoteBookDownloadException(
            RemoteBookDownloadFailure.tooLarge,
          );
        }
        sink = destination.openWrite(mode: FileMode.writeOnly);
        var bytes = 0;
        await for (final chunk in response.timeout(timeout)) {
          if (cancellation.isCancelled) {
            throw const RemoteBookDownloadException(
              RemoteBookDownloadFailure.cancelled,
            );
          }
          if (bytes == 0) {
            _log('ACQUISITION_FIRST_BYTES_RECEIVED host=${current.host}');
          }
          bytes += chunk.length;
          if (bytes > maximumBytes) {
            throw const RemoteBookDownloadException(
              RemoteBookDownloadFailure.tooLarge,
            );
          }
          sink.add(chunk);
          onProgress(bytes, validTotal);
        }
        await sink.flush();
        await sink.close();
        sink = null;
        if (validTotal != null && bytes != validTotal) {
          throw const RemoteBookDownloadException(
            RemoteBookDownloadFailure.interrupted,
          );
        }
        return RemoteEpubTransportResult(
          effectiveUri: current,
          byteCount: bytes,
          contentType: response.headers.value(HttpHeaders.contentTypeHeader),
        );
      }
    } on RemoteBookDownloadException {
      rethrow;
    } on TimeoutException {
      throw const RemoteBookDownloadException(
        RemoteBookDownloadFailure.timeout,
      );
    } on SocketException {
      throw const RemoteBookDownloadException(
        RemoteBookDownloadFailure.transport,
      );
    } finally {
      await sink?.close();
      client.close(force: true);
    }
  }

  bool _isNonFileRedirect(Uri uri) {
    final value = '${uri.host}${uri.path}'.toLowerCase();
    return const [
      'login',
      'signin',
      'preview',
      'sample',
      'purchase',
      'buy',
      'consent',
      'error',
    ].any(value.contains);
  }

  void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }
}

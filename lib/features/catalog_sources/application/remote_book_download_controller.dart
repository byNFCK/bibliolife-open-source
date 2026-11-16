import 'dart:io';

import 'package:bibliolife/features/catalog_sources/domain/remote_book_download.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download_plan.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

class RemoteBookDownloadState {
  const RemoteBookDownloadState({
    this.progress = const RemoteBookDownloadProgress(
      phase: RemoteBookDownloadPhase.idle,
    ),
    this.result,
  });
  final RemoteBookDownloadProgress progress;
  final RemoteBookDownloadResult? result;
  bool get isActive =>
      progress.phase == RemoteBookDownloadPhase.downloading ||
      progress.phase == RemoteBookDownloadPhase.validating;
}

@Deprecated(
  'Legacy isolated helper. The persistent queue is the only production '
  'download lifecycle owner.',
)
class RemoteBookDownloadController extends ChangeNotifier {
  RemoteBookDownloadController(
    this._downloader,
    this._plan, [
    this._temporaryDirectory,
  ]);

  final RemoteBookDownloader _downloader;
  final RemoteBookDownloadPlan _plan;
  final Future<Directory> Function()? _temporaryDirectory;
  RemoteBookDownloadCancellation? _cancellation;
  var _disposed = false;
  RemoteBookDownloadState _state = const RemoteBookDownloadState();

  RemoteBookDownloadState get state => _state;

  Future<void> start() async {
    if (_state.isActive) return;
    final cancellation = RemoteBookDownloadCancellation();
    _cancellation = cancellation;
    _set(
      const RemoteBookDownloadState(
        progress: RemoteBookDownloadProgress(
          phase: RemoteBookDownloadPhase.downloading,
        ),
      ),
    );
    try {
      final result = await _downloader.download(
        plan: _plan,
        cancellation: cancellation,
        onProgress: (progress) {
          if (!_disposed && identical(_cancellation, cancellation)) {
            _set(RemoteBookDownloadState(progress: progress));
          }
        },
      );
      if (!_disposed && identical(_cancellation, cancellation)) {
        _set(
          RemoteBookDownloadState(
            progress: RemoteBookDownloadProgress(
              phase: RemoteBookDownloadPhase.succeeded,
              bytesReceived: result.byteCount,
              totalBytes: result.byteCount,
            ),
            result: result,
          ),
        );
      }
    } on RemoteBookDownloadException catch (error) {
      if (!_disposed && identical(_cancellation, cancellation)) {
        final cancelled = error.failure == RemoteBookDownloadFailure.cancelled;
        _set(
          RemoteBookDownloadState(
            progress: RemoteBookDownloadProgress(
              phase: cancelled
                  ? RemoteBookDownloadPhase.cancelled
                  : RemoteBookDownloadPhase.failed,
              failure: error.failure,
            ),
          ),
        );
      }
    } finally {
      if (identical(_cancellation, cancellation)) _cancellation = null;
    }
  }

  void cancel() => _cancellation?.cancel();

  Future<void> deleteTemporaryFile() async {
    final result = _state.result;
    final temporaryDirectory = _temporaryDirectory;
    if (result == null || temporaryDirectory == null) return;
    final file = File(result.temporaryFilePath);
    final rootPath = path.normalize(
      path.absolute(
        path.join((await temporaryDirectory()).path, 'remote-downloads'),
      ),
    );
    final filePath = path.normalize(path.absolute(file.path));
    if (!path.isWithin(rootPath, filePath)) return;
    if (await file.exists()) await file.delete();
    final parent = file.parent;
    if (await parent.exists() && await parent.list().isEmpty) {
      await parent.delete();
    }
    if (!_disposed) _set(const RemoteBookDownloadState());
  }

  void _set(RemoteBookDownloadState value) {
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancellation?.cancel();
    super.dispose();
  }
}

import 'dart:async';
import 'dart:io';

import 'package:bibliolife/features/catalog_sources/application/remote_book_download_controller.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  test('duplicate activation starts exactly one download', () async {
    final downloader = _Downloader();
    final controller = RemoteBookDownloadController(downloader, _plan());
    addTearDown(controller.dispose);
    final first = controller.start();
    final second = controller.start();
    expect(downloader.calls, 1);
    downloader.completeSuccess();
    await Future.wait([first, second]);
    expect(controller.state.result?.byteCount, 3);
  });

  test('cancellation emits one cancelled terminal state', () async {
    final downloader = _Downloader();
    final controller = RemoteBookDownloadController(downloader, _plan());
    addTearDown(controller.dispose);
    final terminals = <RemoteBookDownloadPhase>[];
    controller.addListener(() {
      final phase = controller.state.progress.phase;
      if (phase == RemoteBookDownloadPhase.cancelled ||
          phase == RemoteBookDownloadPhase.failed ||
          phase == RemoteBookDownloadPhase.succeeded) {
        terminals.add(phase);
      }
    });
    final pending = controller.start();
    controller.cancel();
    await pending;
    expect(terminals, [RemoteBookDownloadPhase.cancelled]);
  });

  test('failure permits explicit retry', () async {
    final downloader = _Downloader();
    final controller = RemoteBookDownloadController(downloader, _plan());
    addTearDown(controller.dispose);
    final first = controller.start();
    downloader.completeFailure(RemoteBookDownloadFailure.timeout);
    await first;
    expect(controller.state.progress.phase, RemoteBookDownloadPhase.failed);

    final second = controller.start();
    downloader.completeSuccess();
    await second;
    expect(downloader.calls, 2);
    expect(controller.state.progress.phase, RemoteBookDownloadPhase.succeeded);
  });

  test('disposal cancels and ignores late progress and completion', () async {
    final downloader = _Downloader();
    final controller = RemoteBookDownloadController(downloader, _plan());
    final pending = controller.start();
    controller.dispose();
    expect(downloader.cancellation?.isCancelled, isTrue);
    await pending;
  });

  test(
    'delete removes only a controlled temp file and its empty folder',
    () async {
      final root = await Directory.systemTemp.createTemp('download-delete-');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final controlledDirectory = Directory(
        path.join(root.path, 'remote-downloads', 'selected'),
      );
      await controlledDirectory.create(recursive: true);
      final controlled = File(path.join(controlledDirectory.path, 'book.epub'));
      await controlled.writeAsBytes([1, 2, 3]);
      final downloader = _Downloader();
      final controller = RemoteBookDownloadController(
        downloader,
        _plan(),
        () async => root,
      );
      addTearDown(controller.dispose);
      final pending = controller.start();
      downloader.completeSuccess(path: controlled.path);
      await pending;

      await controller.deleteTemporaryFile();

      expect(await controlled.exists(), isFalse);
      expect(await controlledDirectory.exists(), isFalse);
      expect(controller.state.result, isNull);

      final outside = File(path.join(root.path, 'outside.epub'));
      await outside.writeAsBytes([1, 2, 3]);
      final outsideDownloader = _Downloader();
      final outsideController = RemoteBookDownloadController(
        outsideDownloader,
        _plan(),
        () async => root,
      );
      addTearDown(outsideController.dispose);
      final outsidePending = outsideController.start();
      outsideDownloader.completeSuccess(path: outside.path);
      await outsidePending;

      await outsideController.deleteTemporaryFile();

      expect(await outside.exists(), isTrue);
      expect(outsideController.state.result, isNotNull);
    },
  );
}

RemoteBookDownloadPlan _plan() => RemoteBookDownloadPlan(
  sourceId: 'source',
  publicationRemoteId: 'book',
  publicationTitle: 'Book',
  authors: const [],
  acquisitionUri: Uri.parse('https://catalog.example/book.epub'),
  declaredMediaType: 'application/epub+zip',
  acquisitionRelation: 'http://opds-spec.org/acquisition',
  isIndirect: false,
  expectedFinalMediaType: 'application/epub+zip',
  expectedSizeBytes: null,
  suggestedFilename: 'Book.epub',
  requiresAuthentication: false,
  supported: true,
  unsupportedReason: null,
);

class _Downloader implements RemoteBookDownloader {
  Completer<RemoteBookDownloadResult>? _pending;
  RemoteBookDownloadCancellation? cancellation;
  int calls = 0;

  @override
  Future<RemoteBookDownloadResult> download({
    required RemoteBookDownloadPlan plan,
    required RemoteBookDownloadCancellation cancellation,
    required void Function(RemoteBookDownloadProgress progress) onProgress,
  }) {
    calls++;
    this.cancellation = cancellation;
    final pending = Completer<RemoteBookDownloadResult>();
    _pending = pending;
    cancellation.onCancel(() {
      if (!pending.isCompleted) {
        pending.completeError(
          const RemoteBookDownloadException(
            RemoteBookDownloadFailure.cancelled,
          ),
        );
      }
    });
    return pending.future;
  }

  void completeSuccess({String path = 'Book.epub'}) {
    _pending!.complete(
      RemoteBookDownloadResult(
        temporaryFilePath: path,
        byteCount: 3,
        declaredMediaType: 'application/epub+zip',
        effectiveUri: Uri.parse('https://catalog.example/book.epub'),
        suggestedFilename: 'Book.epub',
        sourceId: 'source',
        publicationRemoteId: 'book',
      ),
    );
  }

  void completeFailure(RemoteBookDownloadFailure failure) {
    _pending!.completeError(RemoteBookDownloadException(failure));
  }
}

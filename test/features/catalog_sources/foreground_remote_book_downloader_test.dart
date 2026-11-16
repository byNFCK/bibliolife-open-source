import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bibliolife/features/catalog_sources/data/foreground_remote_book_downloader.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download_plan.dart';
import 'package:bibliolife/features/connectivity/application/network_access_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('bibliolife-download-');
  });
  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test(
    'valid EPUB streams to part then atomically becomes one final file',
    () async {
      final policy = _Policy();
      final transport = _Transport(bytes: _validEpub());
      final progress = <RemoteBookDownloadProgress>[];
      final result = await _downloader(policy, transport, temporary).download(
        plan: _plan(),
        cancellation: RemoteBookDownloadCancellation(),
        onProgress: progress.add,
      );

      expect(policy.calls, 1);
      expect(transport.calls, 1);
      expect(result.byteCount, transport.bytes.length);
      expect(result.effectiveUri.scheme, 'https');
      expect(await File(result.temporaryFilePath).exists(), isTrue);
      expect(result.temporaryFilePath, endsWith('Book.epub'));
      expect(
        Directory(result.temporaryFilePath).parent
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.part')),
        isEmpty,
      );
      expect(result.checksum, hasLength(64));
      expect(progress.last.phase, RemoteBookDownloadPhase.succeeded);
    },
  );

  test(
    'Offline checks policy once, makes zero HTTP and creates no files',
    () async {
      final policy = _Policy(allowed: false);
      final transport = _Transport(bytes: _validEpub());
      await expectLater(
        _downloader(policy, transport, temporary).download(
          plan: _plan(),
          cancellation: RemoteBookDownloadCancellation(),
          onProgress: (_) {},
        ),
        _failure(RemoteBookDownloadFailure.accessDenied),
      );
      expect(policy.calls, 1);
      expect(transport.calls, 0);
      expect(temporary.listSync(), isEmpty);
    },
  );

  test('local eligibility failures make zero policy and HTTP calls', () async {
    final cases = <RemoteBookDownloadPlan>[
      _plan(supported: false),
      _plan(indirect: true),
      _plan(authentication: true),
      _plan(mediaType: 'application/pdf'),
      _plan(uri: 'http://catalog.example/book.epub'),
      _plan(uri: null),
      _plan(filename: '../Book.epub'),
      _plan(sourceId: ''),
    ];
    for (final plan in cases) {
      final policy = _Policy();
      final transport = _Transport(bytes: _validEpub());
      await expectLater(
        _downloader(policy, transport, temporary).download(
          plan: plan,
          cancellation: RemoteBookDownloadCancellation(),
          onProgress: (_) {},
        ),
        throwsA(isA<RemoteBookDownloadException>()),
      );
      expect(policy.calls, 0);
      expect(transport.calls, 0);
    }
  });

  test('generic binary succeeds only after EPUB package validation', () async {
    final result =
        await _downloader(
          _Policy(),
          _Transport(
            bytes: _validEpub(),
            contentType: 'application/octet-stream',
          ),
          temporary,
        ).download(
          plan: _plan(),
          cancellation: RemoteBookDownloadCancellation(),
          onProgress: (_) {},
        );
    expect(await File(result.temporaryFilePath).exists(), isTrue);
  });

  test(
    'wrong media type malformed ZIP and non-EPUB ZIP clean partials',
    () async {
      final cases = [
        _Transport(bytes: _validEpub(), contentType: 'text/html'),
        _Transport(bytes: [1, 2, 3]),
        _Transport(bytes: _zip('other', 'value')),
      ];
      for (final transport in cases) {
        await expectLater(
          _downloader(_Policy(), transport, temporary).download(
            plan: _plan(),
            cancellation: RemoteBookDownloadCancellation(),
            onProgress: (_) {},
          ),
          throwsA(isA<RemoteBookDownloadException>()),
        );
      }
      expect(
        temporary
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.part')),
        isEmpty,
      );
      expect(
        temporary
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.epub')),
        isEmpty,
      );
    },
  );

  test('transport typed failures propagate and clean partial files', () async {
    for (final failure in [
      RemoteBookDownloadFailure.timeout,
      RemoteBookDownloadFailure.transport,
      RemoteBookDownloadFailure.authenticationFailed,
      RemoteBookDownloadFailure.notFound,
      RemoteBookDownloadFailure.serverError,
      RemoteBookDownloadFailure.insecureRedirect,
      RemoteBookDownloadFailure.tooLarge,
      RemoteBookDownloadFailure.interrupted,
    ]) {
      final transport = _Transport(
        bytes: _validEpub(),
        failure: failure,
        writeBeforeFailure: true,
      );
      await expectLater(
        _downloader(_Policy(), transport, temporary).download(
          plan: _plan(),
          cancellation: RemoteBookDownloadCancellation(),
          onProgress: (_) {},
        ),
        _failure(failure),
      );
    }
    expect(temporary.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test(
    'progress is monotonic, bounded and indeterminate without total',
    () async {
      final progress = <RemoteBookDownloadProgress>[];
      await _downloader(
        _Policy(),
        _Transport(bytes: _validEpub(), omitTotal: true),
        temporary,
      ).download(
        plan: _plan(),
        cancellation: RemoteBookDownloadCancellation(),
        onProgress: progress.add,
      );
      final bytes = progress.map((value) => value.bytesReceived).toList();
      expect(bytes, orderedEquals([...bytes]..sort()));
      expect(
        progress
            .where(
              (value) => value.phase == RemoteBookDownloadPhase.downloading,
            )
            .every((value) => value.fraction == null),
        isTrue,
      );
      expect(progress.last.fraction, 1);
    },
  );

  test(
    'cancellation during streaming deletes partial and emits typed result',
    () async {
      final cancellation = RemoteBookDownloadCancellation();
      final transport = _Transport(
        bytes: _validEpub(),
        cancelAfterFirstChunk: cancellation,
      );
      await expectLater(
        _downloader(_Policy(), transport, temporary).download(
          plan: _plan(),
          cancellation: cancellation,
          onProgress: (_) {},
        ),
        _failure(RemoteBookDownloadFailure.cancelled),
      );
      expect(temporary.listSync(recursive: true).whereType<File>(), isEmpty);
    },
  );
}

ForegroundRemoteBookDownloader _downloader(
  _Policy policy,
  _Transport transport,
  Directory directory,
) => ForegroundRemoteBookDownloader(
  policy,
  transport,
  () async => directory,
  uniqueId: () => 'work-${transport.calls}',
  maximumBytes: 1024 * 1024,
);

RemoteBookDownloadPlan _plan({
  bool supported = true,
  bool indirect = false,
  bool authentication = false,
  String mediaType = remoteEpubMediaType,
  String? uri = 'https://catalog.example/book.epub',
  String filename = 'Book.epub',
  String sourceId = 'source',
}) => RemoteBookDownloadPlan(
  sourceId: sourceId,
  publicationRemoteId: 'book',
  publicationTitle: 'Book',
  authors: const ['Author'],
  acquisitionUri: uri == null ? null : Uri.parse(uri),
  declaredMediaType: mediaType,
  acquisitionRelation: 'http://opds-spec.org/acquisition',
  isIndirect: indirect,
  expectedFinalMediaType: remoteEpubMediaType,
  expectedSizeBytes: null,
  suggestedFilename: filename,
  requiresAuthentication: authentication,
  supported: supported,
  unsupportedReason: null,
);

List<int> _validEpub() {
  final archive = Archive()
    ..addFile(ArchiveFile.string('mimetype', remoteEpubMediaType))
    ..addFile(
      ArchiveFile.string(
        'META-INF/container.xml',
        '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"/>',
      ),
    );
  return ZipEncoder().encode(archive);
}

List<int> _zip(String name, String content) {
  final archive = Archive()..addFile(ArchiveFile.string(name, content));
  return ZipEncoder().encode(archive);
}

Matcher _failure(RemoteBookDownloadFailure failure) => throwsA(
  isA<RemoteBookDownloadException>().having(
    (error) => error.failure,
    'failure',
    failure,
  ),
);

class _Policy implements NetworkAccessPolicy {
  _Policy({this.allowed = true});
  final bool allowed;
  int calls = 0;
  @override
  bool get isOnlineAccessAllowed => allowed;
  @override
  void requireOnlineAccess(String operation) {
    calls++;
    if (!allowed) throw OfflineModeException(operation);
  }
}

class _Transport implements RemoteEpubDownloadTransport {
  _Transport({
    required this.bytes,
    this.contentType = remoteEpubMediaType,
    this.failure,
    this.writeBeforeFailure = false,
    this.omitTotal = false,
    this.cancelAfterFirstChunk,
  });

  final List<int> bytes;
  final String contentType;
  final RemoteBookDownloadFailure? failure;
  final bool writeBeforeFailure;
  final bool omitTotal;
  final RemoteBookDownloadCancellation? cancelAfterFirstChunk;
  int calls = 0;

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
    calls++;
    if (writeBeforeFailure) {
      await destination.writeAsBytes(bytes.take(4).toList());
    }
    if (failure != null) throw RemoteBookDownloadException(failure!);
    final sink = destination.openWrite();
    final split = bytes.length ~/ 2;
    final chunks = [bytes.take(split).toList(), bytes.skip(split).toList()];
    var received = 0;
    for (final chunk in chunks) {
      if (cancellation.isCancelled) {
        await sink.close();
        throw const RemoteBookDownloadException(
          RemoteBookDownloadFailure.cancelled,
        );
      }
      sink.add(chunk);
      received += chunk.length;
      onProgress(received, omitTotal ? null : bytes.length);
      if (received == chunks.first.length) cancelAfterFirstChunk?.cancel();
    }
    await sink.close();
    if (cancellation.isCancelled) {
      throw const RemoteBookDownloadException(
        RemoteBookDownloadFailure.cancelled,
      );
    }
    return RemoteEpubTransportResult(
      effectiveUri: uri,
      byteCount: bytes.length,
      contentType: contentType,
    );
  }
}

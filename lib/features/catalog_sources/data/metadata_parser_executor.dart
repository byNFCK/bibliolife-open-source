import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:bibliolife/core/network/request_cancellation.dart';
import 'package:bibliolife/features/catalog_sources/data/google_books_payload_parser.dart';
import 'package:bibliolife/features/catalog_sources/data/internet_archive_metadata_parser.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_parsing_policy.dart';
import 'package:bibliolife/features/catalog_sources/data/open_library_payload_parser.dart';
import 'package:bibliolife/features/catalog_sources/data/open_search_description_parser.dart';
import 'package:bibliolife/features/catalog_sources/data/opds1_atom_parser.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';

enum MetadataParserPriority {
  activeSearch,
  details,
  pagination,
  acquisition,
  enrichment,
  prefetch,
}

enum MetadataParserFailure { cancelled, disposed, overloaded, execution }

class MetadataParserException implements Exception {
  const MetadataParserException(this.failure);
  final MetadataParserFailure failure;
}

class MetadataParserJob {
  const MetadataParserJob({
    required this.id,
    required this.type,
    required this.bytes,
    required this.sourceId,
    this.sessionId,
    this.baseUri,
    this.details = false,
    this.priority = MetadataParserPriority.activeSearch,
  });
  final String id;
  final MetadataParserType type;
  final Uint8List bytes;
  final String sourceId;
  final String? sessionId;
  final String? baseUri;
  final bool details;
  final MetadataParserPriority priority;
}

class MetadataParserExecutor {
  MetadataParserExecutor({this.maximumActive = 2, this.maximumQueued = 16});
  final int maximumActive;
  final int maximumQueued;
  final List<_QueuedJob> _queued = [];
  final Map<String, _ActiveJob> _active = {};
  var _sequence = 0;
  var _disposed = false;

  int get activeCount => _active.length;
  int get queuedCount => _queued.length;

  Future<Object> submit(MetadataParserJob job, CancellationToken token) {
    if (_disposed) {
      return Future.error(
        const MetadataParserException(MetadataParserFailure.disposed),
      );
    }
    if (token.isCancelled) {
      return Future.error(
        const MetadataParserException(MetadataParserFailure.cancelled),
      );
    }
    if (_queued.length >= maximumQueued && _active.length >= maximumActive) {
      return Future.error(
        const MetadataParserException(MetadataParserFailure.overloaded),
      );
    }
    final queued = _QueuedJob(job, token, _sequence++);
    _queued.add(queued);
    queued.removeCancellation = token.addListener((_) {
      if (_queued.remove(queued)) {
        queued.completeError(
          const MetadataParserException(MetadataParserFailure.cancelled),
        );
        queued.dispose();
      }
    });
    _pump();
    return queued.completer.future;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final queued in List<_QueuedJob>.from(_queued)) {
      _queued.remove(queued);
      queued.completeError(
        const MetadataParserException(MetadataParserFailure.disposed),
      );
      queued.dispose();
    }
    for (final active in List<_ActiveJob>.from(_active.values)) {
      active.cancel(MetadataParserFailure.disposed);
    }
  }

  void _pump() {
    while (!_disposed && _active.length < maximumActive && _queued.isNotEmpty) {
      _queued.sort((a, b) {
        final priority = a.job.priority.index.compareTo(b.job.priority.index);
        return priority == 0 ? a.sequence.compareTo(b.sequence) : priority;
      });
      final queued = _queued.removeAt(0);
      if (queued.token.isCancelled) {
        queued.completeError(
          const MetadataParserException(MetadataParserFailure.cancelled),
        );
        queued.dispose();
        continue;
      }
      _start(queued);
    }
  }

  Future<void> _start(_QueuedJob queued) async {
    final receive = ReceivePort();
    final active = _ActiveJob(queued, receive, () {
      _active.remove(queued.job.id);
      _pump();
    });
    _active[queued.job.id] = active;
    queued.removeCancellation?.call();
    queued.removeCancellation = queued.token.addListener(
      (_) => active.cancel(MetadataParserFailure.cancelled),
    );
    receive.listen((message) {
      if (message is _ParserReply && !active.done) {
        if (message.error != null) {
          active.completeError(message.error!);
        } else {
          active.complete(message.value!);
        }
      }
    });
    try {
      active.isolate = await Isolate.spawn<_ParserRequest>(
        _metadataParserIsolateEntryPoint,
        _ParserRequest(
          queued.job.type,
          TransferableTypedData.fromList([queued.job.bytes]),
          queued.job.baseUri,
          queued.job.details,
          receive.sendPort,
        ),
        errorsAreFatal: true,
      );
    } on Object {
      active.completeError(
        const MetadataParserException(MetadataParserFailure.execution),
      );
    }
  }
}

class _QueuedJob {
  _QueuedJob(this.job, this.token, this.sequence);
  final MetadataParserJob job;
  final CancellationToken token;
  final int sequence;
  final completer = Completer<Object>();
  void Function()? removeCancellation;
  void completeError(Object error) {
    if (!completer.isCompleted) completer.completeError(error);
  }

  void dispose() => removeCancellation?.call();
}

class _ActiveJob {
  _ActiveJob(this.queued, this.port, this.onDone);
  final _QueuedJob queued;
  final ReceivePort port;
  final void Function() onDone;
  Isolate? isolate;
  var done = false;
  void complete(Object value) {
    if (done) {
      return;
    }
    done = true;
    _finish();
    queued.completer.complete(value);
  }

  void completeError(Object error) {
    if (done) {
      return;
    }
    done = true;
    _finish();
    queued.completeError(error);
  }

  void cancel(MetadataParserFailure failure) {
    if (done) {
      return;
    }
    isolate?.kill(priority: Isolate.immediate);
    completeError(MetadataParserException(failure));
  }

  void _finish() {
    isolate?.kill(priority: Isolate.beforeNextEvent);
    port.close();
    queued.dispose();
    onDone();
  }
}

class _ParserRequest {
  const _ParserRequest(
    this.type,
    this.bytes,
    this.baseUri,
    this.details,
    this.replyTo,
  );
  final MetadataParserType type;
  final TransferableTypedData bytes;
  final String? baseUri;
  final bool details;
  final SendPort replyTo;
}

class _ParserReply {
  const _ParserReply.value(this.value) : error = null;
  const _ParserReply.error(this.error) : value = null;
  final Object? value;
  final Object? error;
}

void _metadataParserIsolateEntryPoint(_ParserRequest request) {
  try {
    final bytes = request.bytes.materialize().asUint8List();
    final value = switch (request.type) {
      MetadataParserType.googleBooks => parseGoogleBooksPayload(
        bytes,
        details: request.details,
      ),
      MetadataParserType.openLibrary => parseOpenLibraryPayload(bytes),
      MetadataParserType.internetArchive => parseInternetArchiveMetadata(bytes),
      MetadataParserType.openSearch => parseOpenSearchDescriptionPayload(
        bytes,
        baseUri: request.baseUri!,
      ),
      MetadataParserType.opds => const Opds1AtomParser().parseBytes(
        sourceId: 'background',
        location: RemoteCatalogLocation.parse(request.baseUri!),
        bytes: bytes,
      ),
    };
    request.replyTo.send(_ParserReply.value(value));
  } on Object {
    request.replyTo.send(
      const _ParserReply.error(
        MetadataParserException(MetadataParserFailure.execution),
      ),
    );
  }
}

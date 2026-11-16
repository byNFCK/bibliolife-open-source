import 'dart:async';

import 'package:crypto/crypto.dart';

import 'package:bibliolife/core/network/request_cancellation.dart';
import 'package:bibliolife/core/performance/online_pipeline_performance.dart';
import 'package:bibliolife/features/catalog_sources/data/http_opds_remote_catalog_transport.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:flutter/foundation.dart';

/// Bounded, cancellable coordination for small catalog metadata GET requests.
/// EPUB downloads and image loading deliberately do not use this component.
class MetadataRequestCoordinator implements HttpCatalogClient {
  MetadataRequestCoordinator(
    this._transport, {
    this.maximumConcurrentRequests = 4,
    this.maximumConcurrentRequestsPerHost = 2,
    this.maximumQueuedRequests = 48,
  });

  final HttpCatalogClient _transport;
  final int maximumConcurrentRequests;
  final int maximumConcurrentRequestsPerHost;
  final int maximumQueuedRequests;
  final List<_CoordinatedGet> _queued = [];
  final Map<String, _CoordinatedGet> _inFlight = {};
  final Map<String, int> _activeHosts = {};
  var _active = 0;
  var _sequence = 0;

  void dispose() {
    for (final request in [..._queued, ..._inFlight.values]) {
      request.operation.cancel(RequestCancellationReason.controllerDisposed);
      request.completeError(
        const RequestCancelledException(
          RequestCancellationReason.controllerDisposed,
        ),
        StackTrace.current,
      );
      _remove(request);
    }
    _queued.clear();
    _inFlight.clear();
  }

  @override
  Future<HttpCatalogResponse> get({
    required RemoteCatalogLocation location,
    required Map<String, String> headers,
    required Duration timeout,
    required int maximumResponseBytes,
    required int maximumRedirects,
  }) {
    final context = MetadataRequestScope.current;
    if (context == null) {
      return _transport.get(
        location: location,
        headers: headers,
        timeout: timeout,
        maximumResponseBytes: maximumResponseBytes,
        maximumRedirects: maximumRedirects,
      );
    }
    if (context.token.isCancelled) {
      return Future.error(RequestCancelledException(context.token.reason!));
    }
    final fingerprint = _privateFingerprint(location, headers);
    final publicFingerprint = _fingerprint(location, headers);
    final coalescible = _isSafeToCoalesce(location, headers);
    var request = coalescible ? _inFlight[fingerprint] : null;
    if (request != null) {
      OnlinePerformanceScope.session?.recordCoordinatorEvent('coalesced');
      _log(
        'REQUEST_COORDINATOR_COALESCED',
        request,
        subscribers: request.subscribers.length + 1,
      );
      return request.addSubscriber(context);
    }
    if (_queued.length + _active >= maximumQueuedRequests) {
      return Future.error(StateError('Metadata request queue is full.'));
    }
    request = _CoordinatedGet(
      coordinator: this,
      fingerprint: coalescible ? fingerprint : '$fingerprint#${_sequence++}',
      publicFingerprint: publicFingerprint,
      host: location.uri.host.toLowerCase(),
      location: location,
      headers: headers,
      timeout: timeout,
      maximumResponseBytes: maximumResponseBytes,
      maximumRedirects: maximumRedirects,
      context: context,
      coalescible: coalescible,
    );
    if (coalescible) _inFlight[request.fingerprint] = request;
    _queued.add(request);
    OnlinePerformanceScope.session?.recordCoordinatorEvent('queued');
    _log('REQUEST_COORDINATOR_ENQUEUED', request, subscribers: 1);
    final future = request.addSubscriber(context);
    _pump();
    return future;
  }

  void _pump() {
    while (_active < maximumConcurrentRequests) {
      var index = -1;
      for (var candidate = 0; candidate < _queued.length; candidate++) {
        final request = _queued[candidate];
        if ((_activeHosts[request.host] ?? 0) >=
            maximumConcurrentRequestsPerHost) {
          continue;
        }
        if (index < 0 ||
            request.context.priority.index <
                _queued[index].context.priority.index) {
          index = candidate;
        }
      }
      if (index < 0) return;
      final request = _queued.removeAt(index);
      if (request.subscribers.isEmpty) {
        _remove(request);
        continue;
      }
      _active++;
      _activeHosts[request.host] = (_activeHosts[request.host] ?? 0) + 1;
      request.start();
    }
  }

  Future<void> _execute(_CoordinatedGet request) async {
    try {
      final response = await MetadataRequestScope.run(
        MetadataRequestContext(
          token: request.operation.token,
          sourceId: request.context.sourceId,
          priority: request.context.priority,
          sessionId: request.context.sessionId,
        ),
        () => _transport.get(
          location: request.location,
          headers: request.headers,
          timeout: request.timeout,
          maximumResponseBytes: request.maximumResponseBytes,
          maximumRedirects: request.maximumRedirects,
        ),
      );
      request.complete(response);
      _log('REQUEST_COORDINATOR_COMPLETED', request);
    } on Object catch (error, stackTrace) {
      request.completeError(error, stackTrace);
      _log(
        error is RequestCancelledException
            ? 'REQUEST_COORDINATOR_CANCELLED'
            : 'REQUEST_COORDINATOR_COMPLETED',
        request,
        reason: error.runtimeType.toString(),
      );
    } finally {
      _active--;
      final remaining = (_activeHosts[request.host] ?? 1) - 1;
      if (remaining <= 0) {
        _activeHosts.remove(request.host);
      } else {
        _activeHosts[request.host] = remaining;
      }
      _remove(request);
      _pump();
    }
  }

  void _cancelSubscriber(
    _CoordinatedGet request,
    _RequestSubscriber subscriber,
  ) {
    if (!request.subscribers.remove(subscriber)) return;
    subscriber.cancel();
    if (request.subscribers.isNotEmpty) return;
    request.operation.cancel(RequestCancellationReason.parentCancelled);
    _queued.remove(request);
    if (!request.started) {
      _remove(request);
      _log('REQUEST_COORDINATOR_CANCELLED', request, reason: 'queued');
      _pump();
    }
  }

  void _remove(_CoordinatedGet request) {
    _inFlight.remove(request.fingerprint);
    request.dispose();
  }

  String _fingerprint(
    RemoteCatalogLocation location,
    Map<String, String> headers,
  ) {
    final semanticHeaders =
        headers.entries
            .where(
              (entry) => const {
                'accept',
                'accept-language',
                'user-agent',
              }.contains(entry.key.toLowerCase()),
            )
            .map((entry) => '${entry.key.toLowerCase()}=${entry.value}')
            .toList()
          ..sort();
    return '${sanitizedRequestFingerprint(sourceId: MetadataRequestScope.current!.sourceId, method: 'GET', uri: location.uri)}|${semanticHeaders.join('&')}';
  }

  String _privateFingerprint(
    RemoteCatalogLocation location,
    Map<String, String> headers,
  ) {
    final credentialParts = <String>[];
    for (final entry in location.uri.queryParametersAll.entries) {
      if (entry.key.toLowerCase() == 'key') {
        credentialParts.add('query:${entry.key}=${entry.value.join(',')}');
      }
    }
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'authorization') {
        credentialParts.add('header:${entry.key}=${entry.value}');
      }
    }
    final digest = sha256
        .convert(credentialParts.join('\u0000').codeUnits)
        .toString();
    return '${_fingerprint(location, headers)}|credential=$digest';
  }

  bool _isSafeToCoalesce(
    RemoteCatalogLocation location,
    Map<String, String> headers,
  ) =>
      !location.uri.queryParameters.keys.any(
        (name) => _sensitive(name) && name.toLowerCase() != 'key',
      ) &&
      !headers.keys.any(_sensitive);

  bool _sensitive(String name) {
    final key = name.toLowerCase();
    return key == 'key' ||
        key.contains('token') ||
        key.contains('authorization') ||
        key.contains('cookie') ||
        key.contains('signature') ||
        key == 'sig' ||
        key.startsWith('x-amz-');
  }

  void _log(
    String event,
    _CoordinatedGet request, {
    int? subscribers,
    String? reason,
  }) {
    switch (event) {
      case 'REQUEST_COORDINATOR_STARTED':
        OnlinePerformanceScope.session?.recordCoordinatorEvent('started');
        break;
      case 'REQUEST_COORDINATOR_CANCELLED':
        if (reason == 'queued') {
          OnlinePerformanceScope.session?.recordCoordinatorEvent(
            'queuedCancelled',
          );
        }
        break;
      default:
        break;
    }
    if (!biblioLifeNetPerfVerboseLogsEnabled) return;
    final context = request.context;
    // The fingerprint is sanitized and the location omits query parameters.
    // This protects API keys and signed URLs in production diagnostics.
    debugPrint(
      '$event session=${context.sessionId ?? 'none'} source=${context.sourceId} fingerprint=${request.publicFingerprint} host=${request.location.uri.host}${request.location.uri.path} priority=${context.priority.name} active=$_active hostActive=${_activeHosts[request.host] ?? 0} subscribers=${subscribers ?? request.subscribers.length} reason=${reason ?? 'none'}',
    );
  }
}

class _CoordinatedGet {
  _CoordinatedGet({
    required this.coordinator,
    required this.fingerprint,
    required this.publicFingerprint,
    required this.host,
    required this.location,
    required this.headers,
    required this.timeout,
    required this.maximumResponseBytes,
    required this.maximumRedirects,
    required this.context,
    required this.coalescible,
  });

  final MetadataRequestCoordinator coordinator;
  final String fingerprint;
  final String publicFingerprint;
  final String host;
  final RemoteCatalogLocation location;
  final Map<String, String> headers;
  final Duration timeout;
  final int maximumResponseBytes;
  final int maximumRedirects;
  final MetadataRequestContext context;
  final bool coalescible;
  final operation = CancellationTokenSource();
  final List<_RequestSubscriber> subscribers = [];
  var started = false;
  var _disposed = false;

  Future<HttpCatalogResponse> addSubscriber(MetadataRequestContext context) {
    final subscriber = _RequestSubscriber(context, this);
    subscribers.add(subscriber);
    subscriber.install();
    return subscriber.completer.future;
  }

  void start() {
    if (started || subscribers.isEmpty) return;
    started = true;
    coordinator._log('REQUEST_COORDINATOR_STARTED', this);
    unawaited(coordinator._execute(this));
  }

  void complete(HttpCatalogResponse response) {
    for (final subscriber in [...subscribers]) {
      subscriber.complete(response);
    }
  }

  void completeError(Object error, StackTrace stackTrace) {
    for (final subscriber in [...subscribers]) {
      subscriber.completeError(error, stackTrace);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    operation.dispose();
    for (final subscriber in subscribers) {
      subscriber.dispose();
    }
    subscribers.clear();
  }
}

class _RequestSubscriber {
  _RequestSubscriber(this.context, this.request)
    : _removeCancellationListener = (() {});

  final MetadataRequestContext context;
  final _CoordinatedGet request;
  final completer = Completer<HttpCatalogResponse>();
  late void Function() _removeCancellationListener;
  var _done = false;

  void install() {
    _removeCancellationListener = context.token.addListener((reason) {
      request.coordinator._cancelSubscriber(request, this);
      completeError(RequestCancelledException(reason), StackTrace.current);
    });
  }

  void complete(HttpCatalogResponse value) {
    if (_done) return;
    _done = true;
    _removeCancellationListener();
    completer.complete(value);
  }

  void completeError(Object error, StackTrace stackTrace) {
    if (_done) return;
    _done = true;
    _removeCancellationListener();
    completer.completeError(error, stackTrace);
  }

  void cancel() => completeError(
    RequestCancelledException(
      context.token.reason ?? RequestCancellationReason.parentCancelled,
    ),
    StackTrace.current,
  );

  void dispose() => _removeCancellationListener();
}

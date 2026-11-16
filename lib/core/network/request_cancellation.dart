import 'dart:async';

/// Why a metadata operation stopped before it could produce a result.
enum RequestCancellationReason {
  queryReplaced,
  controllerDisposed,
  screenClosed,
  sourceDisabled,
  paginationSuperseded,
  retrySuperseded,
  explicitUserRetry,
  requestTimeout,
  parentCancelled,
}

class RequestCancelledException implements Exception {
  const RequestCancelledException(this.reason);

  final RequestCancellationReason reason;

  @override
  String toString() => 'RequestCancelledException(${reason.name})';
}

class CancellationToken {
  bool get isCancelled => _reason != null;
  RequestCancellationReason? get reason => _reason;
  Future<RequestCancellationReason> get whenCancelled => _cancelled.future;

  final _cancelled = Completer<RequestCancellationReason>();
  final Map<int, void Function(RequestCancellationReason)> _listeners = {};
  RequestCancellationReason? _reason;
  var _nextListenerId = 0;

  /// Registers once and returns a removal callback. Late listeners run
  /// immediately, which makes races with request completion deterministic.
  void Function() addListener(
    void Function(RequestCancellationReason) listener,
  ) {
    final reason = _reason;
    if (reason != null) {
      listener(reason);
      return () {};
    }
    final id = _nextListenerId++;
    _listeners[id] = listener;
    return () => _listeners.remove(id);
  }

  bool _cancel(RequestCancellationReason reason) {
    if (_reason != null) return false;
    _reason = reason;
    _cancelled.complete(reason);
    final listeners = _listeners.values.toList(growable: false);
    _listeners.clear();
    for (final listener in listeners) {
      listener(reason);
    }
    return true;
  }
}

class CancellationTokenSource {
  CancellationTokenSource({CancellationToken? parent})
    : token = CancellationToken() {
    _removeParentListener = parent?.addListener(
      (_) => cancel(RequestCancellationReason.parentCancelled),
    );
  }

  final CancellationToken token;
  void Function()? _removeParentListener;

  bool cancel(RequestCancellationReason reason) {
    final cancelled = token._cancel(reason);
    if (cancelled) {
      _removeParentListener?.call();
      _removeParentListener = null;
    }
    return cancelled;
  }

  void dispose() => cancel(RequestCancellationReason.parentCancelled);
}

enum MetadataRequestPriority {
  activeSearch,
  details,
  pagination,
  enrichment,
  prefetch,
}

class MetadataRequestContext {
  const MetadataRequestContext({
    required this.token,
    required this.sourceId,
    required this.priority,
    this.sessionId,
  });

  final CancellationToken token;
  final String sourceId;
  final MetadataRequestPriority priority;
  final String? sessionId;
}

/// Carries request ownership through the existing gateway interfaces without
/// making parsers or catalog adapters depend on controller types.
class MetadataRequestScope {
  const MetadataRequestScope._();

  static final _contextKey = Object();

  static MetadataRequestContext? get current =>
      Zone.current[_contextKey] as MetadataRequestContext?;

  static Future<T> run<T>(
    MetadataRequestContext context,
    Future<T> Function() action,
  ) => runZoned(action, zoneValues: {_contextKey: context});
}

void throwIfMetadataRequestCancelled() {
  final token = MetadataRequestScope.current?.token;
  if (token?.isCancelled == true) {
    throw RequestCancelledException(token!.reason!);
  }
}

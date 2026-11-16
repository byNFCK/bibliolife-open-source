import 'dart:async';

import 'package:bibliolife/core/network/request_cancellation.dart';
import 'package:bibliolife/features/catalog_sources/data/http_opds_remote_catalog_transport.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_request_coordinator.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'identical safe GETs coalesce and one cancelled subscriber does not abort the other',
    () async {
      final transport = _ControlledClient();
      final coordinator = MetadataRequestCoordinator(transport);
      final first = CancellationTokenSource();
      final second = CancellationTokenSource();

      final firstFuture = _request(coordinator, first, '/search?q=romeo');
      final secondFuture = _request(coordinator, second, '/search?q=romeo');
      await Future<void>.delayed(Duration.zero);

      expect(transport.calls, 1);
      first.cancel(RequestCancellationReason.queryReplaced);
      await expectLater(firstFuture, throwsA(isA<RequestCancelledException>()));
      transport.completeNext();
      await expectLater(secondFuture, completion(isA<HttpCatalogResponse>()));
    },
  );

  test(
    'Google key is private coalescing context, not a public fingerprint',
    () async {
      final transport = _ControlledClient();
      final coordinator = MetadataRequestCoordinator(transport);
      final first = CancellationTokenSource();
      final sameCredential = CancellationTokenSource();
      final differentCredential = CancellationTokenSource();

      final one = _request(coordinator, first, '/volumes?q=romeo&key=alpha');
      final two = _request(
        coordinator,
        sameCredential,
        '/volumes?q=romeo&key=alpha',
      );
      final three = _request(
        coordinator,
        differentCredential,
        '/volumes?q=romeo&key=bravo',
      );
      await Future<void>.delayed(Duration.zero);

      expect(transport.calls, 2);
      transport.completeNext();
      transport.completeNext();
      await Future.wait([one, two, three]);
    },
  );

  test('cancelled queued request never starts and releases no slot', () async {
    final transport = _ControlledClient();
    final coordinator = MetadataRequestCoordinator(
      transport,
      maximumConcurrentRequests: 1,
    );
    final blocker = CancellationTokenSource();
    final queued = CancellationTokenSource();
    final blockerFuture = _request(coordinator, blocker, '/one');
    final queuedFuture = _request(coordinator, queued, '/two');
    await Future<void>.delayed(Duration.zero);

    queued.cancel(RequestCancellationReason.queryReplaced);
    await expectLater(queuedFuture, throwsA(isA<RequestCancelledException>()));
    transport.completeNext();
    await blockerFuture;
    await Future<void>.delayed(Duration.zero);

    expect(transport.calls, 1);
  });

  test('already cancelled caller does not start transport work', () async {
    final transport = _ControlledClient();
    final coordinator = MetadataRequestCoordinator(transport);
    final cancelled = CancellationTokenSource()
      ..cancel(RequestCancellationReason.queryReplaced);

    await expectLater(
      _request(coordinator, cancelled, '/cancelled'),
      throwsA(isA<RequestCancelledException>()),
    );

    expect(transport.calls, 0);
  });

  test(
    'all cancelled subscribers cancel the underlying request token',
    () async {
      final transport = _ControlledClient();
      final coordinator = MetadataRequestCoordinator(transport);
      final first = CancellationTokenSource();
      final second = CancellationTokenSource();
      final firstFuture = _request(coordinator, first, '/shared');
      final secondFuture = _request(coordinator, second, '/shared');
      await Future<void>.delayed(Duration.zero);

      first.cancel(RequestCancellationReason.queryReplaced);
      second.cancel(RequestCancellationReason.queryReplaced);
      await expectLater(firstFuture, throwsA(isA<RequestCancelledException>()));
      await expectLater(
        secondFuture,
        throwsA(isA<RequestCancelledException>()),
      );

      expect(transport.tokens.single.isCancelled, isTrue);
    },
  );

  test(
    'active search priority starts before queued background enrichment',
    () async {
      final transport = _ControlledClient();
      final coordinator = MetadataRequestCoordinator(
        transport,
        maximumConcurrentRequests: 1,
      );
      final blocker = _request(
        coordinator,
        CancellationTokenSource(),
        '/blocker',
      );
      final background = _request(
        coordinator,
        CancellationTokenSource(),
        '/background',
        priority: MetadataRequestPriority.enrichment,
      );
      final active = _request(
        coordinator,
        CancellationTokenSource(),
        '/active',
      );
      await Future<void>.delayed(Duration.zero);

      transport.completeNext();
      await blocker;
      await Future<void>.delayed(Duration.zero);

      expect(transport.locations[1].uri.path, '/active');
      transport.completeNext();
      await active;
      transport.completeNext();
      await background;
    },
  );
}

Future<HttpCatalogResponse> _request(
  MetadataRequestCoordinator coordinator,
  CancellationTokenSource source,
  String path, {
  MetadataRequestPriority priority = MetadataRequestPriority.activeSearch,
}) => MetadataRequestScope.run(
  MetadataRequestContext(
    token: source.token,
    sourceId: 'source',
    priority: priority,
    sessionId: 'test',
  ),
  () => coordinator.get(
    location: RemoteCatalogLocation.parse('https://catalog.example$path'),
    headers: const {'Accept': 'application/json'},
    timeout: const Duration(seconds: 10),
    maximumResponseBytes: 1024,
    maximumRedirects: 1,
  ),
);

class _ControlledClient implements HttpCatalogClient {
  final completers = <Completer<HttpCatalogResponse>>[];
  final locations = <RemoteCatalogLocation>[];
  final tokens = <CancellationToken>[];

  int get calls => completers.length;

  @override
  Future<HttpCatalogResponse> get({
    required RemoteCatalogLocation location,
    required Map<String, String> headers,
    required Duration timeout,
    required int maximumResponseBytes,
    required int maximumRedirects,
  }) {
    locations.add(location);
    tokens.add(MetadataRequestScope.current!.token);
    final completer = Completer<HttpCatalogResponse>();
    completers.add(completer);
    return completer.future;
  }

  void completeNext() {
    final completer = completers.firstWhere((item) => !item.isCompleted);
    completer.complete(
      HttpCatalogResponse(
        statusCode: 200,
        bodyBytes: const [],
        effectiveLocation: locations[completers.indexOf(completer)],
      ),
    );
  }
}

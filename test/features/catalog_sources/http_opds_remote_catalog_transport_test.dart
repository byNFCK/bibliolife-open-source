import 'dart:async';
import 'dart:convert';

import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway_provider.dart';
import 'package:bibliolife/features/catalog_sources/data/http_opds_remote_catalog_transport.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/connectivity/application/network_access_policy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('successful root sends Accept and parses effective location', () async {
    final client = _FakeClient()
      ..response = _response(location: 'https://cdn.example/catalog/root');
    final page = await HttpOpdsRemoteCatalogTransport(
      client: client,
    ).loadRoot(_source());

    expect(page.title, 'Catalog');
    expect(page.location.toString(), 'https://cdn.example/catalog/root');
    expect(client.calls, 1);
    expect(client.locations.single.toString(), 'https://catalog.example/root');
    expect(client.headers.single['Accept'], remoteCatalogAcceptHeader);
    expect(client.timeouts.single, const Duration(seconds: 15));
    expect(client.maximumBytes.single, 2 * 1024 * 1024);
    expect(client.redirectLimits.single, 5);
  });

  test('successful page uses requested opaque location once', () async {
    final client = _FakeClient()..response = _response();
    final location = RemoteCatalogLocation.parse(
      'https://catalog.example/page/2',
    );
    final page = await HttpOpdsRemoteCatalogTransport(
      client: client,
    ).loadPage(source: _source(), location: location);

    expect(page.sourceId, 'source');
    expect(client.calls, 1);
    expect(client.locations.single, location);
  });

  test('404 and 500 map to typed HTTP status failure', () async {
    for (final status in [404, 500]) {
      final client = _FakeClient()
        ..response = _response(statusCode: status, body: 'private response');
      await expectLater(
        HttpOpdsRemoteCatalogTransport(client: client).loadRoot(_source()),
        _throwsFailure(RemoteCatalogFailure.httpStatus),
      );
      expect(client.calls, 1);
    }
  });

  test('timeout and raw transport failures are typed', () async {
    final timeoutClient = _FakeClient()..error = TimeoutException('controlled');
    await expectLater(
      HttpOpdsRemoteCatalogTransport(client: timeoutClient).loadRoot(_source()),
      _throwsFailure(RemoteCatalogFailure.timeout),
    );

    final socketClient = _FakeClient()
      ..error = StateError('controlled socket failure');
    await expectLater(
      HttpOpdsRemoteCatalogTransport(client: socketClient).loadRoot(_source()),
      _throwsFailure(RemoteCatalogFailure.transport),
    );
    expect(timeoutClient.calls, 1);
    expect(socketClient.calls, 1);
  });

  test('redirect and response size violations are typed', () async {
    final redirectClient = _FakeClient()
      ..error = const HttpCatalogInsecureRedirectException();
    await expectLater(
      HttpOpdsRemoteCatalogTransport(
        client: redirectClient,
      ).loadRoot(_source()),
      _throwsFailure(RemoteCatalogFailure.insecureRedirect),
    );

    final largeClient = _FakeClient()
      ..error = const HttpCatalogResponseTooLargeException();
    await expectLater(
      HttpOpdsRemoteCatalogTransport(client: largeClient).loadRoot(_source()),
      _throwsFailure(RemoteCatalogFailure.responseTooLarge),
    );
  });

  test(
    'empty invalid UTF-8 malformed XML and unsupported format are typed',
    () async {
      final cases = <(List<int>, String?, RemoteCatalogFailure)>[
        (<int>[], 'application/atom+xml', RemoteCatalogFailure.emptyResponse),
        (
          [0xff],
          'application/atom+xml',
          RemoteCatalogFailure.malformedCatalogResponse,
        ),
        (
          utf8.encode('<feed>'),
          'application/atom+xml',
          RemoteCatalogFailure.malformedCatalogResponse,
        ),
        (
          utf8.encode('<html/>'),
          'text/html',
          RemoteCatalogFailure.unsupportedCatalogFormat,
        ),
      ];
      for (final (bytes, contentType, failure) in cases) {
        final client = _FakeClient()
          ..response = HttpCatalogResponse(
            statusCode: 200,
            bodyBytes: bytes,
            effectiveLocation: RemoteCatalogLocation.parse(
              'https://catalog.example/root',
            ),
            contentType: contentType,
          );
        await expectLater(
          HttpOpdsRemoteCatalogTransport(client: client).loadRoot(_source()),
          _throwsFailure(failure),
        );
      }
    },
  );

  test(
    'valid Atom accepts missing generic or incompatible content type',
    () async {
      for (final contentType in [
        null,
        'application/octet-stream',
        'text/html',
      ]) {
        final client = _FakeClient()
          ..response = _response(contentType: contentType);
        final page = await HttpOpdsRemoteCatalogTransport(
          client: client,
        ).loadRoot(_source());
        expect(page.title, 'Catalog');
      }
    },
  );

  test('offline policy checks once and makes zero HTTP calls', () async {
    final policy = _CountingPolicy(allowed: false);
    final client = _FakeClient()..response = _response();
    final gateway = PolicyAwareRemoteCatalogGateway(
      policy: policy,
      transport: HttpOpdsRemoteCatalogTransport(client: client),
    );

    await expectLater(
      gateway.loadRoot(_source()),
      _throwsFailure(RemoteCatalogFailure.accessDenied),
    );
    expect(policy.calls, 1);
    expect(client.calls, 0);
  });

  test('online policy and real adapter seam each run exactly once', () async {
    final policy = _CountingPolicy(allowed: true);
    final client = _FakeClient()..response = _response();
    final gateway = PolicyAwareRemoteCatalogGateway(
      policy: policy,
      transport: HttpOpdsRemoteCatalogTransport(client: client),
    );

    final page = await gateway.loadRoot(_source());
    expect(page.title, 'Catalog');
    expect(policy.calls, 1);
    expect(client.calls, 1);
  });

  test('provider creation and reads remain request-free', () {
    final policy = _CountingPolicy(allowed: true);
    final client = _FakeClient()..response = _response();
    final container = ProviderContainer(
      overrides: [
        networkAccessPolicyProvider.overrideWithValue(policy),
        remoteCatalogTransportProvider.overrideWithValue(
          HttpOpdsRemoteCatalogTransport(client: client),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(client.calls, 0);
    expect(
      container.read(remoteCatalogGatewayProvider),
      isA<RemoteCatalogGateway>(),
    );
    expect(client.calls, 0);
    expect(policy.calls, 0);
  });
}

CatalogSource _source() => CatalogSource(
  id: 'source',
  name: 'Source',
  baseUri: Uri.parse('https://catalog.example/root'),
  type: CatalogSourceType.unknownOpds,
  isBuiltIn: false,
  isEnabled: true,
  supportsSearch: false,
  supportsNavigation: true,
  supportsAcquisition: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

HttpCatalogResponse _response({
  int statusCode = 200,
  String body =
      '<feed xmlns="http://www.w3.org/2005/Atom"><title>Catalog</title></feed>',
  String location = 'https://catalog.example/root',
  String? contentType = 'application/atom+xml; charset=utf-8',
}) => HttpCatalogResponse(
  statusCode: statusCode,
  bodyBytes: utf8.encode(body),
  effectiveLocation: RemoteCatalogLocation.parse(location),
  contentType: contentType,
);

Matcher _throwsFailure(RemoteCatalogFailure failure) => throwsA(
  isA<RemoteCatalogException>().having(
    (error) => error.failure,
    'failure',
    failure,
  ),
);

class _FakeClient implements HttpCatalogClient {
  int calls = 0;
  final locations = <RemoteCatalogLocation>[];
  final headers = <Map<String, String>>[];
  final timeouts = <Duration>[];
  final maximumBytes = <int>[];
  final redirectLimits = <int>[];
  HttpCatalogResponse? response;
  Object? error;

  @override
  Future<HttpCatalogResponse> get({
    required RemoteCatalogLocation location,
    required Map<String, String> headers,
    required Duration timeout,
    required int maximumResponseBytes,
    required int maximumRedirects,
  }) async {
    calls++;
    locations.add(location);
    this.headers.add(headers);
    timeouts.add(timeout);
    maximumBytes.add(maximumResponseBytes);
    redirectLimits.add(maximumRedirects);
    if (error case final controlled?) throw controlled;
    return response!;
  }
}

class _CountingPolicy implements NetworkAccessPolicy {
  _CountingPolicy({required this.allowed});

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

import 'package:bibliolife/core/network/request_cancellation.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:bibliolife/features/connectivity/application/network_access_policy.dart';

class PolicyAwareRemoteCatalogGateway implements RemoteCatalogGateway {
  PolicyAwareRemoteCatalogGateway({
    required NetworkAccessPolicy policy,
    required this._transport,
  }) : _policyGateway = PolicyAwareRemoteGateway(policy);

  final PolicyAwareRemoteGateway _policyGateway;
  final RemoteCatalogTransport _transport;

  @override
  Future<RemoteCatalogPage> loadRoot(CatalogSource source) =>
      _run('catalog.root:${source.id}', () {
        _validateSource(source);
        return _transport.loadRoot(source);
      });

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) => _run('catalog.page:${source.id}', () {
    _validateSource(source);
    return _transport.loadPage(source: source, location: location);
  });

  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) => _run('catalog.search:${source.id}', () {
    _validateSource(source);
    if (!capability.isSupported) {
      throw const RemoteCatalogException.searchUnsupported();
    }
    return _transport.search(
      source: source,
      capability: capability,
      query: query,
    );
  });

  Future<T> _run<T>(
    String operation,
    Future<T> Function() transportCall,
  ) async {
    try {
      return await _policyGateway.run(operation, transportCall);
    } on OfflineModeException catch (error) {
      throw RemoteCatalogException.accessDenied(error.operation);
    } on RequestCancelledException {
      rethrow;
    } on RemoteCatalogException {
      rethrow;
    } catch (_) {
      throw const RemoteCatalogException.transport(
        'Remote catalog transport failed.',
      );
    }
  }

  void _validateSource(CatalogSource source) {
    if (source.id.trim().isEmpty) {
      throw const RemoteCatalogException.sourceNotFound();
    }
    if (!source.isEnabled) {
      throw const RemoteCatalogException.sourceDisabled();
    }
    try {
      RemoteCatalogLocation.fromUri(source.baseUri);
    } on FormatException {
      throw const RemoteCatalogException.invalidSourceOrLocation();
    }
  }
}

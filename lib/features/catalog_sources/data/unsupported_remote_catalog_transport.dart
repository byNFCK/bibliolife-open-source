import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';

class UnsupportedRemoteCatalogTransport implements RemoteCatalogTransport {
  const UnsupportedRemoteCatalogTransport();

  Never _unsupported() =>
      throw const RemoteCatalogException.transportUnavailable(
        'Remote catalog transport is not implemented.',
      );

  @override
  Future<RemoteCatalogPage> loadRoot(CatalogSource source) async =>
      _unsupported();

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) async => _unsupported();

  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) async => _unsupported();
}

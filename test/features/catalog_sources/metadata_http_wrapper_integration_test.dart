import 'package:bibliolife/features/catalog_sources/data/cached_retrying_http_catalog_client.dart';
import 'package:bibliolife/features/catalog_sources/data/google_books_remote_catalog_adapter.dart';
import 'package:bibliolife/features/catalog_sources/data/http_opds_remote_catalog_transport.dart';
import 'package:bibliolife/features/catalog_sources/data/internet_archive_acquisition_resolver.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_memory_cache.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_retry_policy.dart';
import 'package:bibliolife/features/catalog_sources/data/open_library_remote_catalog_adapter.dart';
import 'package:bibliolife/features/catalog_sources/data/source_aware_remote_catalog_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'all metadata source seams accept the same shared retry/cache client',
    () {
      final shared = CachedRetryingHttpCatalogClient(
        _NoNetworkClient(),
        MetadataMemoryCache(),
        const MetadataRetryPolicy(),
      );
      expect(
        GoogleBooksRemoteCatalogAdapter(client: shared, apiKey: 'test'),
        isNotNull,
      );
      expect(OpenLibraryRemoteCatalogAdapter(client: shared), isNotNull);
      expect(HttpOpdsRemoteCatalogTransport(client: shared), isNotNull);
      expect(HttpInternetArchiveAcquisitionResolver(client: shared), isNotNull);
      expect(SourceAwareRemoteCatalogTransport(client: shared), isNotNull);
    },
  );
}

class _NoNetworkClient implements HttpCatalogClient {
  @override
  Future<HttpCatalogResponse> get({
    required location,
    required headers,
    required timeout,
    required maximumResponseBytes,
    required maximumRedirects,
  }) => throw UnimplementedError();
}

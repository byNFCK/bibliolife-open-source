import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/data/http_opds_remote_catalog_transport.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_request_coordinator.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_parsing_policy.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_parser_executor.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_payload_parser_dispatcher.dart';
import 'package:bibliolife/features/catalog_sources/data/cached_retrying_http_catalog_client.dart';
import 'package:bibliolife/features/catalog_sources/data/internet_archive_acquisition_resolver.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_memory_cache.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_retry_policy.dart';
import 'package:bibliolife/features/catalog_sources/data/remote_cache_service.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_cache_settings_provider.dart';
import 'package:bibliolife/features/catalog_sources/data/source_aware_remote_catalog_transport.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/domain/internet_archive_acquisition.dart';
import 'package:bibliolife/features/connectivity/application/network_access_policy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final remoteCatalogHttpClientProvider = Provider<IoHttpCatalogClient>((ref) {
  final client = IoHttpCatalogClient();
  ref.onDispose(client.close);
  return client;
});

final metadataRequestCoordinatorProvider = Provider<HttpCatalogClient>((ref) {
  final coordinator = MetadataRequestCoordinator(
    ref.watch(remoteCatalogHttpClientProvider),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

final metadataParsingPolicyProvider = Provider<MetadataParsingPolicy>(
  (ref) => const MetadataParsingPolicy(),
);
final metadataRetryPolicyProvider = Provider<MetadataRetryPolicy>(
  (ref) => const MetadataRetryPolicy(),
);
final metadataMemoryCacheProvider = Provider<MetadataMemoryCache>(
  (ref) => MetadataMemoryCache(),
);
final remoteCacheServiceProvider = Provider<RemoteCacheService>((ref) {
  final repository = ref.watch(remoteCacheSettingsRepositoryProvider);
  final service = RemoteCacheService(initialBudget: repository.load());
  bindRemoteCacheBudget(ref, service.updateBudget);
  return service;
});
final cachedMetadataHttpClientProvider = Provider<HttpCatalogClient>(
  (ref) => CachedRetryingHttpCatalogClient(
    ref.watch(metadataRequestCoordinatorProvider),
    ref.watch(metadataMemoryCacheProvider),
    ref.watch(metadataRetryPolicyProvider),
    diskCache: ref.watch(remoteCacheServiceProvider),
  ),
);

final metadataParserExecutorProvider = Provider<MetadataParserExecutor>((ref) {
  final executor = MetadataParserExecutor();
  ref.onDispose(executor.dispose);
  return executor;
});

final metadataPayloadParserDispatcherProvider =
    Provider<MetadataPayloadParserDispatcher>(
      (ref) => MetadataPayloadParserDispatcher(
        ref.watch(metadataParsingPolicyProvider),
        ref.watch(metadataParserExecutorProvider),
      ),
    );

final remoteCatalogTransportProvider = Provider<RemoteCatalogTransport>(
  (ref) => SourceAwareRemoteCatalogTransport(
    client: ref.watch(cachedMetadataHttpClientProvider),
    parserDispatcher: ref.watch(metadataPayloadParserDispatcherProvider),
  ),
);

final remoteCatalogGatewayProvider = Provider<RemoteCatalogGateway>(
  (ref) => PolicyAwareRemoteCatalogGateway(
    policy: ref.watch(networkAccessPolicyProvider),
    transport: ref.watch(remoteCatalogTransportProvider),
  ),
);

final internetArchiveAcquisitionResolverProvider =
    Provider<InternetArchiveAcquisitionResolver>(
      (ref) => HttpInternetArchiveAcquisitionResolver(
        client: ref.watch(cachedMetadataHttpClientProvider),
        parserDispatcher: ref.watch(metadataPayloadParserDispatcherProvider),
      ),
    );

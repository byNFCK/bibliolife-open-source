import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/canonical_acquisition_resolver.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_publication_details_resolver.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final remotePublicationDetailsResolverProvider =
    Provider<RemotePublicationDetailsResolver>(
      (ref) => RemotePublicationDetailsResolver(
        ref.watch(catalogSourceRepositoryProvider),
        ref.watch(remoteCatalogGatewayProvider),
      ),
    );

final canonicalAcquisitionResolverProvider =
    Provider<CanonicalAcquisitionResolver>(
      (ref) => CanonicalAcquisitionResolver(
        ref.watch(catalogSourceRepositoryProvider),
        ref.watch(remoteCatalogGatewayProvider),
        ref.watch(internetArchiveAcquisitionResolverProvider),
      ),
    );

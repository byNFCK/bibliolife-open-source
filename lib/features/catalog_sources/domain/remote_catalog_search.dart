import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';

enum RemoteCatalogSearchCapabilityKind {
  unsupported,
  directTemplate,
  openSearchDescription,
}

class RemoteCatalogSearchCapability {
  const RemoteCatalogSearchCapability.unsupported()
    : kind = RemoteCatalogSearchCapabilityKind.unsupported,
      location = null;

  const RemoteCatalogSearchCapability._(this.kind, this.location);

  factory RemoteCatalogSearchCapability.directTemplate(
    RemoteCatalogLocation location,
  ) => RemoteCatalogSearchCapability._(
    RemoteCatalogSearchCapabilityKind.directTemplate,
    location,
  );

  factory RemoteCatalogSearchCapability.openSearchDescription(
    RemoteCatalogLocation location,
  ) => RemoteCatalogSearchCapability._(
    RemoteCatalogSearchCapabilityKind.openSearchDescription,
    location,
  );

  final RemoteCatalogSearchCapabilityKind kind;
  final RemoteCatalogLocation? location;

  bool get isSupported => kind != RemoteCatalogSearchCapabilityKind.unsupported;
}

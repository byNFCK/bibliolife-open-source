enum CatalogSourceType {
  opds1,
  opds2,
  openLibrary,
  internetArchive,
  googleBooks,
  standardEbooks,
  unknownOpds,
}

enum CatalogSourceHealth {
  unknown,
  available,
  unavailable,
  invalid,
  blockedOffline,
}

enum CatalogSourceFreeDownloadCapability {
  direct,
  providerEnrichment,
  metadataOnly,
  detailsOnly,
}

CatalogSourceFreeDownloadCapability catalogSourceFreeDownloadCapability(
  CatalogSource source,
) => switch (source.type) {
  CatalogSourceType.opds1 ||
  CatalogSourceType.opds2 => CatalogSourceFreeDownloadCapability.direct,
  CatalogSourceType.internetArchive =>
    CatalogSourceFreeDownloadCapability.direct,
  CatalogSourceType.openLibrary =>
    CatalogSourceFreeDownloadCapability.providerEnrichment,
  CatalogSourceType.googleBooks =>
    CatalogSourceFreeDownloadCapability.detailsOnly,
  CatalogSourceType.standardEbooks =>
    CatalogSourceFreeDownloadCapability.detailsOnly,
  CatalogSourceType.unknownOpds =>
    CatalogSourceFreeDownloadCapability.metadataOnly,
};

String catalogSourceFreeDownloadDescription(CatalogSource source) =>
    switch (catalogSourceFreeDownloadCapability(source)) {
      CatalogSourceFreeDownloadCapability.direct =>
        source.type == CatalogSourceType.internetArchive
            ? 'Public EPUB/PDF download provider'
            : 'Direct free EPUB downloads',
      CatalogSourceFreeDownloadCapability.providerEnrichment =>
        'Free files may be provided by Internet Archive',
      CatalogSourceFreeDownloadCapability.detailsOnly =>
        source.type == CatalogSourceType.googleBooks
            ? 'Only verified full public downloads qualify'
            : 'Availability is verified from source details',
      CatalogSourceFreeDownloadCapability.metadataOnly =>
        'Metadata/search only; free files are not proven at Search time',
    };

class CatalogSource {
  const CatalogSource({
    required this.id,
    required this.name,
    required this.baseUri,
    required this.type,
    required this.isBuiltIn,
    required this.isEnabled,
    required this.supportsSearch,
    required this.supportsNavigation,
    required this.supportsAcquisition,
    required this.createdAt,
    required this.updatedAt,
    this.lastSuccessfulAccessAt,
    this.lastCheckedAt,
    this.health,
    this.lastErrorCode,
  });
  final String id;
  final String name;
  final Uri baseUri;
  final CatalogSourceType type;
  final bool isBuiltIn;
  final bool isEnabled;
  final bool supportsSearch;
  final bool supportsNavigation;
  final bool supportsAcquisition;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastSuccessfulAccessAt;
  final DateTime? lastCheckedAt;
  final CatalogSourceHealth? health;
  final String? lastErrorCode;
  CatalogSource copyWith({
    String? name,
    Uri? baseUri,
    bool? isEnabled,
    DateTime? updatedAt,
    CatalogSourceHealth? health,
  }) => CatalogSource(
    id: id,
    name: name ?? this.name,
    baseUri: baseUri ?? this.baseUri,
    type: type,
    isBuiltIn: isBuiltIn,
    isEnabled: isEnabled ?? this.isEnabled,
    supportsSearch: supportsSearch,
    supportsNavigation: supportsNavigation,
    supportsAcquisition: supportsAcquisition,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    health: health ?? this.health,
  );
}

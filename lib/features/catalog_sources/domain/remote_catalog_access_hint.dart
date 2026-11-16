enum RemoteCatalogAccessType {
  directDownload,
  authenticatedDownload,
  preview,
  sample,
  purchase,
  externalRead,
  unavailable,
}

class RemoteCatalogAccessHint {
  const RemoteCatalogAccessHint({
    required this.type,
    this.uri,
    this.mediaType,
    this.isFullBook = false,
    this.requiresAuthentication = false,
    this.isDrmFree,
    this.country,
    this.providerId,
  });

  final RemoteCatalogAccessType type;
  final Uri? uri;
  final String? mediaType;
  final bool isFullBook;
  final bool requiresAuthentication;
  final bool? isDrmFree;
  final String? country;

  /// The download provider when it differs from the metadata source record.
  final String? providerId;
}

enum InternetArchiveAvailability {
  directEpub,
  directPdf,
  borrowingRequired,
  metadataOnly,
}

class InternetArchiveAcquisitionResult {
  const InternetArchiveAcquisitionResult._({
    required this.availability,
    this.identifier,
    this.uri,
    this.mediaType,
  });

  const InternetArchiveAcquisitionResult.directEpub({
    required String identifier,
    required Uri uri,
  }) : this._(
         availability: InternetArchiveAvailability.directEpub,
         identifier: identifier,
         uri: uri,
         mediaType: 'application/epub+zip',
       );

  const InternetArchiveAcquisitionResult.directPdf({
    required String identifier,
    required Uri uri,
  }) : this._(
         availability: InternetArchiveAvailability.directPdf,
         identifier: identifier,
         uri: uri,
         mediaType: 'application/pdf',
       );

  const InternetArchiveAcquisitionResult.borrowingRequired({
    required String identifier,
  }) : this._(
         availability: InternetArchiveAvailability.borrowingRequired,
         identifier: identifier,
       );

  const InternetArchiveAcquisitionResult.metadataOnly()
    : this._(availability: InternetArchiveAvailability.metadataOnly);

  final InternetArchiveAvailability availability;
  final String? identifier;
  final Uri? uri;
  final String? mediaType;
}

abstract interface class InternetArchiveAcquisitionResolver {
  Future<InternetArchiveAcquisitionResult> resolve(
    Iterable<String> identifiers,
  );
}

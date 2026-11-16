class TrustedRemoteBookMetadata {
  TrustedRemoteBookMetadata({
    required this.sourceId,
    required this.publicationId,
    required this.title,
    Iterable<String> authors = const [],
    this.description,
    this.publisher,
    this.language,
    this.publishedDate,
    Iterable<String> identifiers = const [],
    Iterable<String> subjects = const [],
    this.rights,
    this.publicationLocation,
    this.coverLocation,
    required this.acquisitionLocation,
  }) : authors = List.unmodifiable(authors),
       identifiers = List.unmodifiable(identifiers),
       subjects = List.unmodifiable(subjects);

  final String sourceId;
  final String publicationId;
  final String title;
  final List<String> authors;
  final String? description;
  final String? publisher;
  final String? language;
  final String? publishedDate;
  final List<String> identifiers;
  final List<String> subjects;
  final String? rights;
  final Uri? publicationLocation;

  /// Exact trusted catalog cover identity carried through download/import.
  final Uri? coverLocation;
  final Uri acquisitionLocation;
}

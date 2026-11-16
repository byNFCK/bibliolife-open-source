import 'dart:typed_data';

class ExtractedBookMetadata {
  const ExtractedBookMetadata({
    required this.title,
    required this.sortTitle,
    required this.authors,
    required this.description,
    required this.language,
    required this.publisher,
    required this.publishedDate,
    required this.isbn,
    required this.coverBytes,
    required this.coverExtension,
    required this.mediaType,
    this.contributors = const [],
    this.identifiers = const [],
    this.subjects = const [],
    this.rights,
    this.seriesName,
    this.seriesIndex,
    this.edition,
    this.source,
    this.coverage,
    this.type,
    this.modifiedDate,
    this.pageCount,
  });

  final String? title;
  final String? sortTitle;
  final List<String> authors;
  final String? description;
  final String? language;
  final String? publisher;
  final String? publishedDate;
  final String? isbn;
  final Uint8List? coverBytes;
  final String? coverExtension;
  final String? mediaType;
  final List<String> contributors;
  final List<String> identifiers;
  final List<String> subjects;
  final String? rights;
  final String? seriesName;
  final double? seriesIndex;
  final String? edition;
  final String? source;
  final String? coverage;
  final String? type;
  final String? modifiedDate;
  final int? pageCount;

  String? get authorDisplay => authors.isEmpty ? null : authors.join(', ');
}

import 'package:bibliolife/features/catalog_sources/domain/book_source_record.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_access_hint.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';

class BookIdentifiers {
  const BookIdentifiers({
    this.isbn13 = const [],
    this.isbn10 = const [],
    this.other = const [],
  });

  final List<String> isbn13;
  final List<String> isbn10;
  final List<String> other;
}

class MetadataValue<T> {
  const MetadataValue({required this.value, required this.sourceId});
  final T value;
  final String sourceId;
}

class BookSourceReference {
  const BookSourceReference({required this.sourceId, required this.remoteId});
  final String sourceId;
  final String remoteId;
}

class BookEditionReference {
  const BookEditionReference({
    required this.sourceId,
    required this.remoteId,
    this.workId,
    this.editionId,
    this.identifiers = const [],
  });

  final String sourceId;
  final String remoteId;
  final String? workId;
  final String? editionId;
  final List<String> identifiers;
}

class AcquisitionCandidate {
  const AcquisitionCandidate({
    required this.sourceId,
    required this.type,
    this.uri,
    this.mediaType,
    this.fullBook = false,
    this.requiresAuthentication = false,
  });
  final String sourceId;
  final RemoteCatalogAccessType type;
  final Uri? uri;
  final String? mediaType;
  final bool fullBook;
  final bool requiresAuthentication;
}

class CanonicalBook {
  CanonicalBook({
    required this.canonicalId,
    required this.primary,
    required Iterable<BookSourceRecord> sources,
    required this.identifiers,
    this.selectedCover,
    this.title,
    this.subtitle,
    this.authors = const [],
    this.description,
    this.publisher,
    this.publishedDate,
    this.pageCount,
    this.language,
    this.firstPublicationYear,
    this.categories = const [],
    this.acquisitionCandidates = const [],
    this.fieldProvenance = const {},
    this.identifierProvenance = const {},
    this.metadataCompleteness = 0,
  }) : sources = List.unmodifiable(sources);

  final String canonicalId;
  final BookSourceRecord primary;
  final List<BookSourceRecord> sources;
  final BookIdentifiers identifiers;
  final RemoteCatalogLocation? selectedCover;
  final String? title;
  final String? subtitle;
  final List<String> authors;
  final String? description;
  final String? publisher;
  final String? publishedDate;
  final int? pageCount;
  final String? language;
  final String? firstPublicationYear;
  final List<String> categories;
  final List<AcquisitionCandidate> acquisitionCandidates;
  final Map<String, String> fieldProvenance;
  final Map<String, List<String>> identifierProvenance;
  final int metadataCompleteness;

  List<BookSourceReference> get sourceReferences => [
    for (final source in sources)
      BookSourceReference(sourceId: source.sourceId, remoteId: source.remoteId),
  ];

  List<BookEditionReference> get editions => [
    for (final source in sources)
      BookEditionReference(
        sourceId: source.sourceId,
        remoteId: source.remoteId,
        workId: source.sourceMetadata['openLibrary.workKey'],
        editionId: source.sourceMetadata['openLibrary.coverEditionKey'],
        identifiers: source.identifiers,
      ),
  ];

  RemoteCatalogPublicationSummary get displayPublication =>
      RemoteCatalogPublicationSummary(
        remoteId: primary.remoteId,
        title: title ?? primary.publication.title,
        subtitle: subtitle,
        authors: authors.isEmpty ? primary.publication.authors : authors,
        coverLocation: selectedCover ?? primary.publication.coverLocation,
        imageCandidates: [
          ..._selectedCover(),
          ...primary.publication.imageCandidates,
        ],
        summary: description ?? primary.publication.summary,
        acquisitions: primary.publication.acquisitions,
        publisher: publisher ?? primary.publication.publisher,
        language: language ?? primary.publication.language,
        publishedDate: publishedDate ?? primary.publication.publishedDate,
        pageCount: pageCount ?? primary.publication.pageCount,
        identifiers: [
          ...identifiers.isbn13,
          ...identifiers.isbn10,
          ...identifiers.other,
        ],
        subjects: categories.isEmpty
            ? primary.publication.subjects
            : categories,
        rights: primary.publication.rights,
        detailsLocation: primary.publication.detailsLocation,
        accessHints: primary.publication.accessHints,
        accessMetadata: primary.publication.accessMetadata,
        sourceMetadata: primary.publication.sourceMetadata,
        sourceLists: primary.publication.sourceLists,
        sourceLinks: primary.publication.sourceLinks,
      );

  Iterable<RemoteCatalogLocation> _selectedCover() sync* {
    final cover = selectedCover;
    if (cover != null) yield cover;
  }
}

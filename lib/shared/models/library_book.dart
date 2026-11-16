import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/book_cover_provenance.dart';

class LibraryBook {
  const LibraryBook({
    required this.id,
    required this.title,
    required this.sortTitle,
    required this.author,
    required this.description,
    required this.filePath,
    this.originalFilePath,
    required this.fileName,
    required this.fileExtension,
    required this.format,
    required this.mediaType,
    required this.coverPath,
    this.coverProvenance = BookCoverProvenance.none,
    required this.language,
    required this.publisher,
    required this.publishedDate,
    required this.isbn,
    required this.pageCount,
    required this.fileSizeBytes,
    required this.dateAdded,
    required this.lastOpenedAt,
    required this.isFavorite,
    this.authors = const [],
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
    this.catalogSourceId,
    this.remotePublicationId,
    this.remotePublicationLocation,
    this.remoteAcquisitionLocation,
    this.metadataOrigins = const {},
    this.tocJson,
  });

  final String id;
  final String title;
  final String? sortTitle;
  final String? author;
  final String? description;
  final String filePath;
  final String? originalFilePath;
  final String fileName;
  final String fileExtension;
  final BookFormat format;
  final String? mediaType;
  final String? coverPath;
  final BookCoverProvenance coverProvenance;
  final String? language;
  final String? publisher;
  final String? publishedDate;
  final String? isbn;
  final int? pageCount;
  final int fileSizeBytes;
  final DateTime dateAdded;
  final DateTime? lastOpenedAt;
  final bool isFavorite;
  final List<String> authors;
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
  final String? catalogSourceId;
  final String? remotePublicationId;
  final String? remotePublicationLocation;
  final String? remoteAcquisitionLocation;
  final Map<String, String> metadataOrigins;
  final String? tocJson;

  LibraryBook withCover({
    required String? coverPath,
    required BookCoverProvenance provenance,
  }) => LibraryBook(
    id: id,
    title: title,
    sortTitle: sortTitle,
    author: author,
    description: description,
    filePath: filePath,
    originalFilePath: originalFilePath,
    fileName: fileName,
    fileExtension: fileExtension,
    format: format,
    mediaType: mediaType,
    coverPath: coverPath,
    coverProvenance: provenance,
    language: language,
    publisher: publisher,
    publishedDate: publishedDate,
    isbn: isbn,
    pageCount: pageCount,
    fileSizeBytes: fileSizeBytes,
    dateAdded: dateAdded,
    lastOpenedAt: lastOpenedAt,
    isFavorite: isFavorite,
    authors: authors,
    contributors: contributors,
    identifiers: identifiers,
    subjects: subjects,
    rights: rights,
    seriesName: seriesName,
    seriesIndex: seriesIndex,
    edition: edition,
    source: source,
    coverage: coverage,
    type: type,
    modifiedDate: modifiedDate,
    catalogSourceId: catalogSourceId,
    remotePublicationId: remotePublicationId,
    remotePublicationLocation: remotePublicationLocation,
    remoteAcquisitionLocation: remoteAcquisitionLocation,
    metadataOrigins: metadataOrigins,
    tocJson: tocJson,
  );
}

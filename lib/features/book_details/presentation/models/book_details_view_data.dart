import 'package:bibliolife/features/book_details/presentation/models/book_details_formatters.dart';
import 'package:bibliolife/features/book_details/presentation/models/book_classification.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download_plan.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/metadata/data/services/isbn_extractor.dart';
import 'package:bibliolife/features/metadata/data/services/book_description_sanitizer.dart';
import 'package:bibliolife/shared/models/library_book.dart';

class BookDetailsViewData {
  BookDetailsViewData({
    required this.title,
    required this.authors,
    this.description,
    this.language,
    this.publicationDate,
    this.file,
    this.isbn,
    this.subjects = const [],
    BookDetailsClassificationCache? classificationCache,
    this.bibliographicSource,
    this.identifiers = const [],
    this.modifiedDate,
    this.rights,
    this.metadataProvenance,
    this.downloadProvenance,
    this.localBookId,
    this.remotePublicationId,
  }) : _classificationCache =
           classificationCache ?? BookDetailsClassificationCache();

  final String title;
  final List<String> authors;
  final String? description;
  final String? language;
  final String? publicationDate;
  final String? file;
  final String? isbn;
  final List<String> subjects;
  final BookDetailsClassificationCache _classificationCache;

  /// Derived only when Book Details renders the corresponding metadata rows.
  /// The cache is keyed solely by effective raw subjects.
  late final BookClassification classification = _classificationCache.resolve(
    subjects,
  );
  final String? bibliographicSource;
  final List<String> identifiers;
  final String? modifiedDate;
  final String? rights;
  final String? metadataProvenance;
  final String? downloadProvenance;
  final String? localBookId;
  final String? remotePublicationId;
}

class LocalBookDetailsViewDataMapper {
  const LocalBookDetailsViewDataMapper({this.classificationCache});

  final BookDetailsClassificationCache? classificationCache;

  BookDetailsViewData map(LibraryBook book) {
    final origins = book.metadataOrigins.values.toSet();
    final hasRemote =
        origins.contains('remote') || origins.contains('epub+remote');
    final hasEpub = origins.contains('epub') || origins.contains('epub+remote');
    final remoteName = book.catalogSourceId == 'builtin-project-gutenberg'
        ? 'Project Gutenberg'
        : 'remote catalog';
    final provenance = hasRemote
        ? hasEpub
              ? 'EPUB and $remoteName'
              : remoteName == 'remote catalog'
              ? 'Remote catalog'
              : remoteName
        : hasEpub
        ? 'EPUB'
        : null;
    return BookDetailsViewData(
      title: normalizeBookDetailsText(book.title),
      authors: book.authors.isNotEmpty
          ? book.authors
          : [
              if (normalizeBookDetailsText(book.author).isNotEmpty)
                book.author!,
            ],
      description: book.description,
      language: book.language,
      publicationDate: book.publishedDate,
      file: formatBookFileSummary(book),
      isbn: book.isbn,
      subjects: book.subjects,
      classificationCache: classificationCache,
      bibliographicSource: book.source,
      identifiers: book.identifiers,
      modifiedDate: book.modifiedDate,
      rights: book.rights,
      metadataProvenance: provenance,
      localBookId: book.id,
      remotePublicationId: book.remotePublicationId,
    );
  }
}

class RemoteBookDetailsViewDataMapper {
  const RemoteBookDetailsViewDataMapper({this.classificationCache});

  final BookDetailsClassificationCache? classificationCache;

  BookDetailsViewData map({
    required RemoteCatalogPublicationSummary publication,
    required String sourceName,
    RemoteBookDownloadPlan? plan,
    String? downloadProviderName,
  }) {
    final identifiers = publication.identifiers;
    String? isbn;
    for (final identifier in identifiers) {
      isbn = IsbnExtractor.canonicalize(identifier);
      if (isbn != null) break;
    }
    final remainingIdentifiers = identifiers
        .where((value) => IsbnExtractor.canonicalize(value) != isbn)
        .toList(growable: false);
    final format = plan?.expectedFinalMediaType == 'application/epub+zip'
        ? [
            'EPUB',
            if (plan?.expectedSizeBytes case final size?) formatFileSize(size),
          ].whereType<String>().join(' · ')
        : null;
    return BookDetailsViewData(
      title: normalizeBookDetailsText(publication.title),
      authors: publication.authors,
      description: BookDescriptionSanitizer.sanitize(publication.summary),
      language: publication.language,
      publicationDate: publication.publishedDate,
      file: format,
      isbn: isbn,
      subjects: publication.subjects,
      classificationCache: classificationCache,
      bibliographicSource: publication.publisher ?? sourceName,
      identifiers: remainingIdentifiers,
      rights: publication.rights,
      metadataProvenance: sourceName,
      downloadProvenance: downloadProviderName,
      remotePublicationId: publication.remoteId,
    );
  }
}

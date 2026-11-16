import 'package:bibliolife/features/book_details/presentation/models/book_classification.dart';
import 'package:bibliolife/features/catalog_sources/domain/book_source_record.dart';
import 'package:bibliolife/features/catalog_sources/domain/canonical_book.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_access_hint.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_acquisition.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download_plan.dart';

enum CatalogSearchFileType { epub, pdf }

/// The complete, immutable search request.  Collections are normalized so it
/// is safe to use this object in generation, cache and coalescing identities.
class CatalogSearchFilters {
  factory CatalogSearchFilters.defaults() => CatalogSearchFilters();

  CatalogSearchFilters({
    Iterable<String> includedGenres = const [],
    Iterable<String> excludedGenres = const [],
    String author = '',
    this.editionYearFrom,
    this.editionYearTo,
    Iterable<String> languages = const [],
    Iterable<CatalogSearchFileType> fileTypes = const [],
    Iterable<String> selectedSourceIds = const [],
    this.onlyFreelyDownloadable = true,
  }) : includedGenres = _ordered(includedGenres.map(_genre)),
       excludedGenres = _ordered(
         excludedGenres
             .map(_genre)
             .where((genre) => !includedGenres.map(_genre).contains(genre)),
       ),
       author = _text(author),
       languages = _ordered(languages.map(_language)),
       fileTypes = List.unmodifiable(
         (fileTypes.toSet().toList()..sort((a, b) => a.name.compareTo(b.name))),
       ),
       selectedSourceIds = _ordered(selectedSourceIds.map(_text));

  final List<String> includedGenres;
  final List<String> excludedGenres;
  final String author;
  final int? editionYearFrom;
  final int? editionYearTo;
  final List<String> languages;
  final List<CatalogSearchFileType> fileTypes;
  final List<String> selectedSourceIds;
  final bool onlyFreelyDownloadable;

  bool get hasYearRange => editionYearFrom != null || editionYearTo != null;
  bool get hasMeaningfulSourceQuery =>
      author.isNotEmpty || includedGenres.isNotEmpty;
  bool get hasLocalCompatibleNarrowing =>
      author.isNotEmpty ||
      includedGenres.isNotEmpty ||
      excludedGenres.isNotEmpty ||
      languages.isNotEmpty ||
      hasYearRange ||
      fileTypes.isNotEmpty;
  bool get isDefault =>
      includedGenres.isEmpty &&
      excludedGenres.isEmpty &&
      author.isEmpty &&
      !hasYearRange &&
      languages.isEmpty &&
      fileTypes.isEmpty &&
      selectedSourceIds.isEmpty &&
      onlyFreelyDownloadable;
  bool get hasCustomFilters => !isDefault;
  bool get hasValidYearRange =>
      (editionYearFrom == null || editionYearFrom! >= 1) &&
      (editionYearTo == null || editionYearTo! >= 1) &&
      (editionYearFrom == null || editionYearFrom! <= DateTime.now().year) &&
      (editionYearTo == null || editionYearTo! <= DateTime.now().year) &&
      (editionYearFrom == null ||
          editionYearTo == null ||
          editionYearFrom! <= editionYearTo!);

  String get identity => [
    includedGenres.join(','),
    excludedGenres.join(','),
    author,
    editionYearFrom?.toString() ?? '',
    editionYearTo?.toString() ?? '',
    languages.join(','),
    fileTypes.map((e) => e.name).join(','),
    selectedSourceIds.join(','),
    onlyFreelyDownloadable ? 'free' : 'any',
  ].map((part) => '${part.length}:$part').join('|');

  CatalogSearchFilters copyWith({
    Iterable<String>? includedGenres,
    Iterable<String>? excludedGenres,
    String? author,
    int? editionYearFrom,
    int? editionYearTo,
    bool clearEditionYearFrom = false,
    bool clearEditionYearTo = false,
    Iterable<String>? languages,
    Iterable<CatalogSearchFileType>? fileTypes,
    Iterable<String>? selectedSourceIds,
    bool? onlyFreelyDownloadable,
  }) => CatalogSearchFilters(
    includedGenres: includedGenres ?? this.includedGenres,
    excludedGenres: excludedGenres ?? this.excludedGenres,
    author: author ?? this.author,
    editionYearFrom: clearEditionYearFrom
        ? null
        : editionYearFrom ?? this.editionYearFrom,
    editionYearTo: clearEditionYearTo
        ? null
        : editionYearTo ?? this.editionYearTo,
    languages: languages ?? this.languages,
    fileTypes: fileTypes ?? this.fileTypes,
    selectedSourceIds: selectedSourceIds ?? this.selectedSourceIds,
    onlyFreelyDownloadable:
        onlyFreelyDownloadable ?? this.onlyFreelyDownloadable,
  );

  @override
  bool operator ==(Object other) =>
      other is CatalogSearchFilters && identity == other.identity;
  @override
  int get hashCode => identity.hashCode;

  static List<String> _ordered(Iterable<String> values) => List.unmodifiable(
    values.where((value) => value.isNotEmpty).toSet().toList()..sort(),
  );
  static String _text(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  static String _genre(String value) =>
      BookClassificationClassifier.normalizeTaxonomyKey(value);
  static String _language(String value) => _text(value).replaceAll('_', '-');
}

class CatalogSearchPostFilter {
  const CatalogSearchPostFilter();

  /// Keeps matching source records, which makes the details route and the
  /// acquisition resolver stay on an edition that actually satisfied a filter.
  CanonicalBook? apply(CanonicalBook book, CatalogSearchFilters filters) {
    if (!filters.hasValidYearRange) {
      return null;
    }
    if (!_workMatches(book, filters)) {
      return null;
    }
    final matched = book.sources
        .where((record) => _editionMatches(record, filters))
        .toList();
    if (matched.isEmpty ||
        (filters.onlyFreelyDownloadable &&
            !matched.any(_hasVerifiedFreeDownload))) {
      return null;
    }
    final primary = matched.firstWhere(
      (record) =>
          record.remoteId == book.primary.remoteId &&
          record.sourceId == book.primary.sourceId,
      orElse: () => matched.first,
    );
    return CanonicalBook(
      canonicalId: book.canonicalId,
      primary: primary,
      sources: matched,
      identifiers: book.identifiers,
      selectedCover: book.selectedCover,
      title: book.title,
      subtitle: book.subtitle,
      authors: book.authors,
      description: book.description,
      publisher: book.publisher,
      publishedDate: book.publishedDate,
      pageCount: book.pageCount,
      language: book.language,
      firstPublicationYear: book.firstPublicationYear,
      categories: book.categories,
      acquisitionCandidates: book.acquisitionCandidates,
      fieldProvenance: book.fieldProvenance,
      identifierProvenance: book.identifierProvenance,
      metadataCompleteness: book.metadataCompleteness,
    );
  }

  bool _workMatches(CanonicalBook book, CatalogSearchFilters filters) {
    final classifier = const BookClassificationClassifier();
    final genres = classifier
        .classify([
          ...book.categories,
          for (final record in book.sources) ...record.publication.subjects,
        ])
        .genres
        .map(BookClassificationClassifier.normalizeTaxonomyKey)
        .toSet();
    if (filters.includedGenres.isNotEmpty &&
        !filters.includedGenres.any(genres.contains)) {
      return false;
    }
    if (filters.excludedGenres.any(genres.contains)) {
      return false;
    }
    if (filters.author.isNotEmpty &&
        !book.sources.any(
          (record) => record.publication.authors.any(
            (author) => _authorMatches(author, filters.author),
          ),
        )) {
      return false;
    }
    return true;
  }

  bool _editionMatches(BookSourceRecord record, CatalogSearchFilters filters) {
    if (filters.selectedSourceIds.isNotEmpty &&
        !filters.selectedSourceIds.contains(record.sourceId) &&
        !record.accessHints.any(
          (hint) =>
              hint.providerId != null &&
              filters.selectedSourceIds.contains(hint.providerId) &&
              hint.type == RemoteCatalogAccessType.directDownload &&
              hint.uri?.scheme == 'https' &&
              hint.isFullBook &&
              hint.isDrmFree == true &&
              !hint.requiresAuthentication,
        )) {
      return false;
    }
    if (filters.languages.isNotEmpty &&
        !_recordLanguages(record).any(filters.languages.contains)) {
      return false;
    }
    if (!filters.hasYearRange) return true;
    final year = _editionYear(record);
    return year != null &&
        (filters.editionYearFrom == null || year >= filters.editionYearFrom!) &&
        (filters.editionYearTo == null || year <= filters.editionYearTo!);
  }

  int? _editionYear(BookSourceRecord record) {
    final text = record.publication.publishedDate?.trim();
    final match = text == null
        ? null
        : RegExp(r'(?<!\d)(\d{1,4})(?!\d)').firstMatch(text);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  Iterable<String> _recordLanguages(BookSourceRecord record) sync* {
    final language = record.publication.language;
    if (language != null) {
      yield BookClassificationClassifier.normalizeTaxonomyKey(
        language,
      ).replaceAll('_', '-');
    }
    yield* (record.sourceLists['openLibrary.languages'] ?? const []).map(
      (value) => BookClassificationClassifier.normalizeTaxonomyKey(
        value,
      ).replaceAll('_', '-'),
    );
  }

  bool _hasVerifiedFreeDownload(BookSourceRecord record) {
    // Search stays offline: accept only an already-classified standard OPDS
    // public acquisition, or an adapter hint which explicitly verified DRM-free
    // direct availability. The planner is EPUB-only, so a verified direct PDF
    // is checked from the same source edition separately.
    final plan = const RemoteBookDownloadPlanner()
        .create(sourceId: record.sourceId, publication: record.publication)
        .plan;
    final planned =
        plan?.supported == true &&
        !plan!.isIndirect &&
        !plan.requiresAuthentication &&
        plan.acquisitionUri?.scheme == 'https' &&
        record.publication.acquisitions.any(
          (acquisition) =>
              acquisition.href == plan.acquisitionUri.toString() &&
              _isVerifiedPublicAcquisition(
                acquisition,
                mediaTypes: const {'application/epub+zip'},
              ),
        );
    final directPdf = record.publication.acquisitions.any(
      (acquisition) => _isVerifiedPublicAcquisition(
        acquisition,
        mediaTypes: const {'application/pdf'},
      ),
    );
    final hinted = record.publication.accessHints.any(
      (hint) =>
          hint.type == RemoteCatalogAccessType.directDownload &&
          hint.uri != null &&
          hint.isFullBook &&
          hint.isDrmFree == true &&
          !hint.requiresAuthentication &&
          const {
            'application/epub+zip',
            'application/pdf',
          }.contains(hint.mediaType?.toLowerCase()),
    );
    return planned || directPdf || hinted;
  }

  bool _isVerifiedPublicAcquisition(
    RemoteAcquisition acquisition, {
    required Set<String> mediaTypes,
  }) {
    final uri = Uri.tryParse(acquisition.href);
    return !acquisition.isIndirect &&
        acquisition.isSecure &&
        !acquisition.isMalformed &&
        !acquisition.requiresAuthentication &&
        uri?.scheme == 'https' &&
        mediaTypes.contains(acquisition.mediaType?.toLowerCase()) &&
        switch (acquisition.kind) {
          RemoteAcquisitionKind.generic ||
          RemoteAcquisitionKind.openAccess => true,
          _ => false,
        };
  }

  bool _authorMatches(String author, String filter) {
    final normalized = CatalogSearchFilters._text(author);
    if (normalized.contains(filter)) return true;
    final tokens = normalized
        .split(' ')
        .where((item) => item.isNotEmpty)
        .toSet();
    return filter
        .split(' ')
        .where((item) => item.isNotEmpty)
        .every(tokens.contains);
  }
}

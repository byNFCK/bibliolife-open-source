import 'package:bibliolife/features/catalog_sources/application/multi_catalog_search_controller.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_search_filters.dart';
import 'package:bibliolife/core/performance/online_pipeline_performance.dart';
import 'package:bibliolife/features/book_details/presentation/models/book_classification.dart';
import 'package:bibliolife/shared/models/library_book.dart';

enum LocalSearchMatchMethod {
  remoteIdentity,
  provenanceOrCanonicalAlias,
  isbn,
  titleAuthorLanguage,
}

/// A source record that is known to identify the same canonical remote edition.
///
/// These aliases come from the canonical remote merger; they are not inferred
/// from a filename or title-only similarity.
class LocalBookIdentityAlias {
  const LocalBookIdentityAlias({
    required this.sourceId,
    required this.remotePublicationId,
    this.publicationLocation,
    this.acquisitionLocations = const [],
  });

  final String sourceId;
  final String remotePublicationId;
  final String? publicationLocation;
  final Iterable<String> acquisitionLocations;
}

/// The remote identity to resolve against persisted local books.
class LocalBookIdentityTarget {
  const LocalBookIdentityTarget({
    required this.sourceId,
    required this.remotePublicationId,
    required this.title,
    required this.authors,
    required this.language,
    this.identifiers = const [],
    this.publishedDate,
    this.publicationLocation,
    this.acquisitionLocation,
    this.aliases = const [],
  });

  final String sourceId;
  final String remotePublicationId;
  final String title;
  final Iterable<String> authors;
  final String? language;
  final Iterable<String> identifiers;
  final String? publishedDate;
  final String? publicationLocation;
  final String? acquisitionLocation;
  final Iterable<LocalBookIdentityAlias> aliases;
}

class LocalBookIdentityMatch {
  const LocalBookIdentityMatch({required this.book, required this.method});

  final LibraryBook book;
  final LocalSearchMatchMethod method;
}

/// Shared local identity index for Search assembly and Download-time redirects.
///
/// Its fallbacks are deliberately conservative: it never uses filenames or a
/// title alone, and an otherwise matching title/author/language is rejected
/// when both sides contain conflicting ISBN or publication-date evidence.
class LocalBookIdentityIndex {
  LocalBookIdentityIndex(Iterable<LibraryBook> books)
    : _books = List.unmodifiable(books);

  final List<LibraryBook> _books;

  LocalBookIdentityMatch? match(LocalBookIdentityTarget target) {
    final exact = _firstWhere(
      (book) =>
          _sameNonEmpty(book.catalogSourceId, target.sourceId) &&
          _sameNonEmpty(book.remotePublicationId, target.remotePublicationId),
    );
    if (exact != null) {
      return LocalBookIdentityMatch(
        book: exact,
        method: LocalSearchMatchMethod.remoteIdentity,
      );
    }

    final aliases = target.aliases.toList(growable: false);
    final alias = _firstWhere(
      (book) => aliases.any(
        (candidate) =>
            _sameNonEmpty(book.catalogSourceId, candidate.sourceId) &&
            _sameNonEmpty(
              book.remotePublicationId,
              candidate.remotePublicationId,
            ) &&
            _matchesLocation(
              book,
              publicationLocation: candidate.publicationLocation,
              acquisitionLocations: candidate.acquisitionLocations,
            ),
      ),
    );
    if (alias != null) {
      return LocalBookIdentityMatch(
        book: alias,
        method: LocalSearchMatchMethod.provenanceOrCanonicalAlias,
      );
    }

    final provenance = _firstWhere(
      (book) => _matchesEditionProvenance(book, target, aliases),
    );
    if (provenance != null) {
      return LocalBookIdentityMatch(
        book: provenance,
        method: LocalSearchMatchMethod.provenanceOrCanonicalAlias,
      );
    }

    final targetIsbns = _isbns(target.identifiers);
    if (targetIsbns.isNotEmpty) {
      final isbn = _firstWhere(
        (book) => targetIsbns.intersection(_bookIsbns(book)).isNotEmpty,
      );
      if (isbn != null) {
        return LocalBookIdentityMatch(
          book: isbn,
          method: LocalSearchMatchMethod.isbn,
        );
      }
    }

    final targetTitle = _identityText(target.title);
    final targetAuthors = _authors(target.authors);
    final targetLanguage = _identityText(target.language);
    if (targetTitle.isEmpty ||
        targetAuthors.isEmpty ||
        targetLanguage.isEmpty) {
      return null;
    }
    final candidates = _books
        .where((book) {
          if (_identityText(book.title) != targetTitle ||
              _bookAuthors(book) != targetAuthors ||
              _identityText(book.language) != targetLanguage) {
            return false;
          }
          final bookIsbns = _bookIsbns(book);
          if (targetIsbns.isNotEmpty &&
              bookIsbns.isNotEmpty &&
              targetIsbns.intersection(bookIsbns).isEmpty) {
            return false;
          }
          return !_conflictingPublicationDate(
            book.publishedDate,
            target.publishedDate,
          );
        })
        .toList(growable: false);
    if (candidates.length != 1) return null;
    return LocalBookIdentityMatch(
      book: candidates.single,
      method: LocalSearchMatchMethod.titleAuthorLanguage,
    );
  }

  LibraryBook? _firstWhere(bool Function(LibraryBook book) predicate) {
    for (final book in _books) {
      if (predicate(book)) return book;
    }
    return null;
  }

  bool _matchesEditionProvenance(
    LibraryBook book,
    LocalBookIdentityTarget target,
    Iterable<LocalBookIdentityAlias> aliases,
  ) {
    if (_sameNonEmpty(book.catalogSourceId, target.sourceId) &&
        _matchesLocation(
          book,
          publicationLocation: target.publicationLocation,
          acquisitionLocations: [target.acquisitionLocation],
        )) {
      return true;
    }
    return aliases.any(
      (alias) =>
          _sameNonEmpty(book.catalogSourceId, alias.sourceId) &&
          _matchesLocation(
            book,
            publicationLocation: alias.publicationLocation,
            acquisitionLocations: alias.acquisitionLocations,
          ),
    );
  }

  bool _matchesLocation(
    LibraryBook book, {
    required String? publicationLocation,
    required Iterable<String?> acquisitionLocations,
  }) {
    final persistedPublication = _location(book.remotePublicationLocation);
    final persistedAcquisition = _location(book.remoteAcquisitionLocation);
    final expectedPublication = _location(publicationLocation);
    if (expectedPublication.isNotEmpty &&
        persistedPublication == expectedPublication) {
      return true;
    }
    final expectedAcquisitions = acquisitionLocations
        .map(_location)
        .where((location) => location.isNotEmpty)
        .toSet();
    return persistedAcquisition.isNotEmpty &&
        expectedAcquisitions.contains(persistedAcquisition);
  }
}

/// Compatibility helper for callers/tests that only need the matched book.
LibraryBook? matchLocalBook({
  required Iterable<LibraryBook> books,
  required String sourceId,
  required String remotePublicationId,
  required String title,
  required Iterable<String> authors,
  required String? language,
  Iterable<String> identifiers = const [],
}) => LocalBookIdentityIndex(books)
    .match(
      LocalBookIdentityTarget(
        sourceId: sourceId,
        remotePublicationId: remotePublicationId,
        title: title,
        authors: authors,
        language: language,
        identifiers: identifiers,
      ),
    )
    ?.book;

class LocalSearchResult {
  const LocalSearchResult({
    required this.remote,
    this.localBook,
    this.matchMethod,
  });

  final MultiCatalogSearchResult? remote;
  final LibraryBook? localBook;
  final LocalSearchMatchMethod? matchMethod;

  bool get isLocal => localBook != null;
  bool get isMerged => localBook != null && remote != null;
}

/// Precomputes the local fields Search may use. This keeps rebuilding the
/// unified result list cheap when the local repository changes, without
/// issuing another remote request or inspecting files on disk.
class LocalBookSearchIndex {
  LocalBookSearchIndex(
    Iterable<LibraryBook> books, {
    OnlineSearchPerformanceSession? performanceSession,
  }) : _books = List.unmodifiable(books) {
    performanceSession?.recordLocalIdentityIndexConstruction();
    _identities = LocalBookIdentityIndex(_books);
    _entries = List.unmodifiable(_books.map(_LocalSearchableBook.fromBook));
  }

  final List<LibraryBook> _books;
  late final LocalBookIdentityIndex _identities;
  late final List<_LocalSearchableBook> _entries;
  late final Map<String, _LocalSearchableBook> _entriesById = {
    for (final entry in _entries) entry.book.id: entry,
  };

  LocalBookIdentityMatch? match(LocalBookIdentityTarget target) =>
      _identities.match(target);

  _LocalSearchableBook? _entryFor(LibraryBook book) => _entriesById[book.id];

  Iterable<LibraryBook> localOnlyMatches({
    required String query,
    required CatalogSearchFilters filters,
    required Set<String> usedBookIds,
  }) {
    final normalizedQuery = _text(query);
    final normalizedIsbnQuery = _isbn(query);
    final validIsbnQuery = _isValidIsbn(normalizedIsbnQuery)
        ? normalizedIsbnQuery
        : '';
    final hasTextQuery = normalizedQuery.isNotEmpty;
    if (!hasTextQuery && !filters.hasLocalCompatibleNarrowing) {
      _logLocalRejections(
        total: _entries.length,
        noQueryOrNarrowing: _entries.length,
      );
      return const <LibraryBook>[];
    }
    if (filters.selectedSourceIds.isNotEmpty || !filters.hasValidYearRange) {
      // A local-only item has no retained remote provenance. It must not
      // appear merely because an online provider is selected.
      _logLocalRejections(
        total: _entries.length,
        sourceOrInvalidFilters: _entries.length,
      );
      return const <LibraryBook>[];
    }
    final accepted = <LibraryBook>[];
    var used = 0;
    var queryMismatch = 0;
    var filterMismatch = 0;
    for (final entry in _entries) {
      if (usedBookIds.contains(entry.book.id)) {
        used++;
        continue;
      }
      final fields = entry.queryFields(
        textQuery: normalizedQuery,
        isbnQuery: normalizedIsbnQuery,
        validIsbnQuery: validIsbnQuery,
      );
      if (hasTextQuery && !fields.matches) {
        queryMismatch++;
        continue;
      }
      if (!entry.matchesFilters(filters)) {
        filterMismatch++;
        continue;
      }
      accepted.add(entry.book);
      _logAcceptedLocal(
        entry,
        fields: fields,
        resultType: 'localOnly',
        queryNonEmpty: hasTextQuery,
        identityMethod: null,
        remoteCounterpartPresent: false,
        localFiltersPassed: true,
        finalReason: hasTextQuery ? 'localQueryAndFilters' : 'localFilters',
      );
    }
    _logLocalRejections(
      total: _entries.length,
      used: used,
      queryMismatch: queryMismatch,
      filterMismatch: filterMismatch,
    );
    return accepted;
  }
}

/// Keeps the expensive local identity index stable while remote search pages
/// and availability enrichment publish incremental changes.  The UI owns one
/// instance for the lifetime of a Search route, so scrolling and remote state
/// updates never rebuild local searchable fields for every visible card.
class LocalSearchResultAssembler {
  List<LibraryBook>? _books;
  LocalBookSearchIndex? _localIndex;

  List<LocalSearchResult> assemble({
    required List<MultiCatalogSearchResult> remote,
    required List<LibraryBook> local,
    required String query,
    CatalogSearchFilters? filters,
    OnlineSearchPerformanceSession? performanceSession,
  }) {
    performanceSession?.recordUnifiedAssemblerExecution();
    if (!identical(_books, local)) {
      _books = local;
      _localIndex = LocalBookSearchIndex(
        local,
        performanceSession: performanceSession,
      );
    }
    return _assembleLocalSearchResults(
      remote: remote,
      localIndex: _localIndex!,
      query: query,
      filters: filters,
    );
  }
}

class _LocalSearchableBook {
  _LocalSearchableBook.fromBook(this.book)
    : title = _text(book.title),
      authors = _localAuthors(
        book,
      ).map(_text).where((value) => value.isNotEmpty).toList(growable: false),
      isbns = _bookIsbns(book),
      language = _language(book.language),
      year = _year(book.publishedDate),
      genres = const BookClassificationClassifier()
          .classify(book.subjects)
          .genres
          .map(BookClassificationClassifier.normalizeTaxonomyKey)
          .toSet(),
      fileType = _fileType(book);

  final LibraryBook book;
  final String title;
  final List<String> authors;
  final Set<String> isbns;
  final String language;
  final int? year;
  final Set<String> genres;
  final CatalogSearchFileType? fileType;

  _LocalQueryFields queryFields({
    required String textQuery,
    required String isbnQuery,
    required String validIsbnQuery,
  }) => _LocalQueryFields(
    titleMatch: textQuery.isNotEmpty && title.contains(textQuery),
    authorMatch:
        textQuery.isNotEmpty &&
        authors.any((author) => author.contains(textQuery)),
    isbnQueryNonEmpty: isbnQuery.isNotEmpty,
    isbnMatch:
        validIsbnQuery.isNotEmpty &&
        isbns.any((isbn) => isbn.contains(validIsbnQuery)),
  );

  bool matchesFilters(CatalogSearchFilters filters) {
    if (filters.includedGenres.isNotEmpty &&
        !filters.includedGenres.any(genres.contains)) {
      return false;
    }
    if (filters.excludedGenres.any(genres.contains)) return false;
    if (filters.author.isNotEmpty &&
        !authors.any((author) => _authorMatches(author, filters.author))) {
      return false;
    }
    if (filters.languages.isNotEmpty && !filters.languages.contains(language)) {
      return false;
    }
    if (filters.hasYearRange &&
        (year == null ||
            (filters.editionYearFrom != null &&
                year! < filters.editionYearFrom!) ||
            (filters.editionYearTo != null &&
                year! > filters.editionYearTo!))) {
      return false;
    }
    return filters.fileTypes.isEmpty || filters.fileTypes.contains(fileType);
  }
}

class _LocalQueryFields {
  const _LocalQueryFields({
    required this.titleMatch,
    required this.authorMatch,
    required this.isbnQueryNonEmpty,
    required this.isbnMatch,
  });

  final bool titleMatch;
  final bool authorMatch;
  final bool isbnQueryNonEmpty;
  final bool isbnMatch;

  bool get matches => titleMatch || authorMatch || isbnMatch;
}

/// Pure, indexed local/remote merge used by the Search UI. It deliberately
/// avoids filename/title-only matching so separate local editions survive.
List<LocalSearchResult> assembleLocalSearchResults({
  required List<MultiCatalogSearchResult> remote,
  required List<LibraryBook> local,
  required String query,
  CatalogSearchFilters? filters,
}) {
  return _assembleLocalSearchResults(
    remote: remote,
    localIndex: LocalBookSearchIndex(local),
    query: query,
    filters: filters,
  );
}

List<LocalSearchResult> _assembleLocalSearchResults({
  required List<MultiCatalogSearchResult> remote,
  required LocalBookSearchIndex localIndex,
  required String query,
  CatalogSearchFilters? filters,
}) {
  final activeFilters = filters ?? CatalogSearchFilters.defaults();
  final used = <String>{};
  final output = <LocalSearchResult>[];
  for (final result in remote) {
    final publication = result.routePublication;
    final identityMatch = localIndex.match(
      LocalBookIdentityTarget(
        sourceId: result.source.id,
        remotePublicationId: publication.remoteId,
        title: publication.title,
        authors: publication.authors,
        language: publication.language,
        identifiers: publication.identifiers,
        publishedDate: publication.publishedDate,
        publicationLocation: publication.detailsLocation?.toString(),
        acquisitionLocation: publication.acquisitions
            .where((acquisition) => acquisition.isDirectSupportedEpub)
            .map((acquisition) => acquisition.href)
            .firstOrNull,
      ),
    );
    final match = identityMatch != null && used.add(identityMatch.book.id)
        ? identityMatch
        : null;
    if (match != null) {
      final fields = localIndex
          ._entryFor(match.book)
          ?.queryFields(
            textQuery: _text(query),
            isbnQuery: _isbn(query),
            validIsbnQuery: _isValidIsbn(_isbn(query)) ? _isbn(query) : '',
          );
      if (fields != null) {
        _logAcceptedLocal(
          localIndex._entryFor(match.book)!,
          fields: fields,
          resultType: 'merged',
          queryNonEmpty: _text(query).isNotEmpty,
          identityMethod: match.method.name,
          remoteCounterpartPresent: true,
          remoteId: _stableId(
            '${result.source.id}\u0000${publication.remoteId}',
          ),
          localFiltersPassed: localIndex
              ._entryFor(match.book)!
              .matchesFilters(activeFilters),
          finalReason: 'trustedIdentity',
        );
      }
    }
    output.add(
      LocalSearchResult(
        remote: result,
        localBook: match?.book,
        matchMethod: match?.method,
      ),
    );
  }
  for (final book in localIndex.localOnlyMatches(
    query: query,
    filters: activeFilters,
    usedBookIds: used,
  )) {
    output.add(LocalSearchResult(remote: null, localBook: book));
  }
  return output;
}

void _logAcceptedLocal(
  _LocalSearchableBook entry, {
  required _LocalQueryFields fields,
  required String resultType,
  required bool queryNonEmpty,
  required String? identityMethod,
  required bool remoteCounterpartPresent,
  String? remoteId,
  required bool localFiltersPassed,
  required String finalReason,
}) {
  if (!biblioLifeNetPerfVerboseLogsEnabled) return;
  onlinePerformanceMarker(
    'local_search_accept',
    fields: {
      'localId': _stableId(entry.book.id),
      'resultType': resultType,
      'queryNonEmpty': queryNonEmpty,
      'titleMatch': fields.titleMatch,
      'authorMatch': fields.authorMatch,
      'isbnQueryNonEmpty': fields.isbnQueryNonEmpty,
      'isbnMatch': fields.isbnMatch,
      'identityMethod': identityMethod,
      'remoteCounterpartPresent': remoteCounterpartPresent,
      'remoteId': remoteId,
      'localFiltersPassed': localFiltersPassed,
      'reason': finalReason,
    },
  );
}

void _logLocalRejections({
  required int total,
  int used = 0,
  int noQueryOrNarrowing = 0,
  int sourceOrInvalidFilters = 0,
  int queryMismatch = 0,
  int filterMismatch = 0,
}) {
  if (!biblioLifeNetPerfVerboseLogsEnabled) return;
  onlinePerformanceMarker(
    'local_search_rejections',
    fields: {
      'total': total,
      'used': used,
      'noQueryOrNarrowing': noQueryOrNarrowing,
      'sourceOrInvalidFilters': sourceOrInvalidFilters,
      'queryMismatch': queryMismatch,
      'filterMismatch': filterMismatch,
    },
  );
}

String _stableId(String value) {
  var hash = 0x811c9dc5;
  for (final codeUnit in value.codeUnits) {
    hash = (hash ^ codeUnit) * 0x01000193 & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

Iterable<String> _localAuthors(LibraryBook book) sync* {
  yield* book.authors;
  if (book.author case final author?) yield author;
}

CatalogSearchFileType? _fileType(LibraryBook book) =>
    switch (book.fileExtension.trim().toLowerCase()) {
      'epub' => CatalogSearchFileType.epub,
      'pdf' => CatalogSearchFileType.pdf,
      _ => null,
    };

String _language(String? value) => _text(value).replaceAll('_', '-');

int? _year(String? value) {
  final match = RegExp(r'(?<!\d)(\d{1,4})(?!\d)').firstMatch(value ?? '');
  return match == null ? null : int.tryParse(match.group(1)!);
}

bool _authorMatches(String author, String filter) {
  if (author.contains(filter)) return true;
  final tokens = author.split(' ').where((token) => token.isNotEmpty).toSet();
  return filter
      .split(' ')
      .where((token) => token.isNotEmpty)
      .every(tokens.contains);
}

bool _sameNonEmpty(String? left, String? right) {
  final normalizedLeft = _identityText(left);
  final normalizedRight = _identityText(right);
  return normalizedLeft.isNotEmpty && normalizedLeft == normalizedRight;
}

bool _conflictingPublicationDate(String? left, String? right) {
  final normalizedLeft = _identityText(left);
  final normalizedRight = _identityText(right);
  return normalizedLeft.isNotEmpty &&
      normalizedRight.isNotEmpty &&
      normalizedLeft != normalizedRight;
}

Set<String> _bookIsbns(LibraryBook book) =>
    _isbns([if (book.isbn != null) book.isbn!, ...book.identifiers]);

Set<String> _isbns(Iterable<String> values) =>
    values.map(_isbn).where(_isValidIsbn).toSet();

String _bookAuthors(LibraryBook book) =>
    _authors(book.authors.isNotEmpty ? book.authors : [book.author ?? '']);

String _authors(Iterable<String> values) {
  final normalized =
      values
          .expand((value) => value.split(';'))
          .map(_identityText)
          .where((value) => value.isNotEmpty)
          .toList()
        ..sort();
  return normalized.join('\u0000');
}

String _location(String? value) {
  final parsed = Uri.tryParse(value?.trim() ?? '');
  if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) return '';
  return Uri(
    scheme: parsed.scheme.toLowerCase(),
    host: parsed.host.toLowerCase(),
    port:
        parsed.hasPort &&
            !((parsed.scheme == 'https' && parsed.port == 443) ||
                (parsed.scheme == 'http' && parsed.port == 80))
        ? parsed.port
        : null,
    path: parsed.path.isEmpty ? '/' : parsed.path,
    query: parsed.hasQuery ? parsed.query : null,
  ).toString();
}

String _text(String? value) =>
    value?.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ') ?? '';

String _identityText(String? value) => _text(
  value,
).replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();

String _isbn(String? value) =>
    (value ?? '').replaceAll(RegExp(r'[^0-9Xx]'), '').toLowerCase();

bool _isValidIsbn(String value) {
  if (value.length == 13 && RegExp(r'^\d{13}$').hasMatch(value)) {
    final sum = value.codeUnits.take(12).indexed.fold<int>(0, (total, entry) {
      final digit = entry.$2 - 0x30;
      return total + digit * (entry.$1.isEven ? 1 : 3);
    });
    return (10 - sum % 10) % 10 == value.codeUnitAt(12) - 0x30;
  }
  if (value.length == 10 && RegExp(r'^\d{9}[\dx]$').hasMatch(value)) {
    final sum = value.codeUnits.indexed.fold<int>(0, (total, entry) {
      final digit = entry.$1 == 9 && entry.$2 == 0x78 ? 10 : entry.$2 - 0x30;
      return total + digit * (10 - entry.$1);
    });
    return sum % 11 == 0;
  }
  return false;
}

import 'package:bibliolife/features/catalog_sources/domain/book_source_record.dart';
import 'package:bibliolife/core/performance/online_pipeline_performance.dart';
import 'package:bibliolife/features/catalog_sources/domain/canonical_book.dart';
import 'package:bibliolife/features/catalog_sources/domain/canonical_book_normalization.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_access_hint.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_acquisition.dart';

class CanonicalBookMerger {
  const CanonicalBookMerger({this.performanceSession});

  final OnlineSearchPerformanceSession? performanceSession;

  List<CanonicalBook> merge(Iterable<BookSourceRecord> records) {
    final input = records.toList(growable: false);
    final performance = performanceSession;
    final stopwatch = performance == null ? null : (Stopwatch()..start());
    final result = <CanonicalBook>[];
    var comparisons = 0;
    var mergeCount = 0;
    var rejected = 0;
    for (final record in input) {
      final index = result.indexWhere((book) {
        comparisons++;
        return _matches(book, record);
      });
      if (index < 0) {
        final similarlyTitled = result.any(
          (book) => _normal(book.title) == _normal(record.publication.title),
        );
        if (similarlyTitled) {
          rejected++;
          _log(
            'CANONICAL_BOOK_MERGE_REJECTED sourceId=${record.sourceId} remoteId=${record.remoteId} reason=insufficientIdentity',
          );
        }
        final book = _create(record);
        _log(
          'CANONICAL_BOOK_CREATED canonicalId=${book.canonicalId} sourceIds=${record.sourceId}',
        );
        result.add(book);
      } else {
        mergeCount++;
        final merged = _merge(result[index], record);
        result[index] = merged;
        _log(
          'CANONICAL_BOOK_MERGED canonicalId=${merged.canonicalId} sourceIds=${merged.sources.map((item) => item.sourceId).join(',')}',
        );
      }
    }
    stopwatch?.stop();
    performance?.recordCanonical(
      inputRecordCount: input.length,
      resultCount: result.length,
      mergedCount: mergeCount,
      rejectedCount: rejected,
      comparisonCount: comparisons,
      normalizationCalls: 0,
      isbnConversions: 0,
      mergeDuration: stopwatch?.elapsed ?? Duration.zero,
    );
    return result;
  }

  bool _matches(CanonicalBook book, BookSourceRecord candidate) {
    final candidateIds = _identifiers(candidate);
    if (candidateIds.isbn13.any(book.identifiers.isbn13.contains) ||
        candidateIds.isbn10.any(book.identifiers.isbn10.contains)) {
      _log(
        'CANONICAL_MATCH_STRONG sourceId=${candidate.sourceId} remoteId=${candidate.remoteId} reason=isbn',
      );
      return true;
    }
    final existingHasStrong =
        book.identifiers.isbn13.isNotEmpty ||
        book.identifiers.isbn10.isNotEmpty;
    final candidateHasStrong =
        candidateIds.isbn13.isNotEmpty || candidateIds.isbn10.isNotEmpty;
    if (existingHasStrong || candidateHasStrong) {
      _log(
        'CANONICAL_MATCH_REJECTED sourceId=${candidate.sourceId} remoteId=${candidate.remoteId} reason=conflictingStrongIdentifier',
      );
      return false;
    }
    final titleMatches =
        _normal(book.title) == _normal(candidate.publication.title);
    final authorMatches = book.authors.any(
      (author) => candidate.publication.authors.any(
        (other) => _normal(author) == _normal(other),
      ),
    );
    final compatibleLanguage =
        book.language == null ||
        candidate.publication.language == null ||
        _normal(book.language) == _normal(candidate.publication.language);
    final compatibleType = !_isDifferentPublicationType(book, candidate);
    final match =
        titleMatches && authorMatches && compatibleLanguage && compatibleType;
    if (match) {
      _log(
        'CANONICAL_MATCH_MODERATE sourceId=${candidate.sourceId} remoteId=${candidate.remoteId} reason=titleAuthorLanguage',
      );
    }
    return match;
  }

  CanonicalBook _create(BookSourceRecord record) {
    final publication = record.publication;
    final identifiers = _identifiers(record);
    return CanonicalBook(
      canonicalId: _canonicalId(record, identifiers),
      primary: record,
      sources: [record],
      identifiers: identifiers,
      selectedCover: _bestCover([record]),
      title: publication.title,
      subtitle: publication.subtitle,
      authors: publication.authors,
      description: publication.summary,
      publisher: publication.publisher,
      publishedDate: publication.publishedDate,
      pageCount: publication.pageCount,
      language: publication.language,
      firstPublicationYear:
          record.sourceMetadata['openLibrary.firstPublishYear'],
      categories: publication.subjects,
      acquisitionCandidates: _candidates([record]),
      fieldProvenance: _provenance(record),
      identifierProvenance: _identifierProvenance([record]),
      metadataCompleteness: _completeness(
        title: publication.title,
        authors: publication.authors,
        description: publication.summary,
        publisher: publication.publisher,
        language: publication.language,
        pageCount: publication.pageCount,
        cover: _bestCover([record]),
      ),
    );
  }

  CanonicalBook _merge(CanonicalBook existing, BookSourceRecord incoming) {
    final sources = [...existing.sources, incoming];
    sources.sort((a, b) => a.sourcePriority.compareTo(b.sourcePriority));
    final primary = sources.first;
    final value = incoming.publication;
    T? choose<T>(
      T? current,
      T? next,
      String field,
      Map<String, String> provenance,
    ) {
      if (_present(next) &&
          (!_present(current) ||
              incoming.sourcePriority < existing.primary.sourcePriority)) {
        provenance[field] = incoming.sourceId;
        return next;
      }
      return current;
    }

    final provenance = {...existing.fieldProvenance};
    final title = choose(existing.title, value.title, 'title', provenance);
    final description = choose(
      existing.description,
      _usefulDescription(value.summary) ? value.summary : null,
      'description',
      provenance,
    );
    final publisher = choose(
      existing.publisher,
      value.publisher,
      'publisher',
      provenance,
    );
    final publishedDate = choose(
      existing.publishedDate,
      value.publishedDate,
      'publishedDate',
      provenance,
    );
    final pageCount = choose(
      existing.pageCount,
      value.pageCount,
      'pageCount',
      provenance,
    );
    final language = choose(
      existing.language,
      value.language,
      'language',
      provenance,
    );
    final subtitle = choose(
      existing.subtitle,
      value.subtitle,
      'subtitle',
      provenance,
    );
    final authors = existing.authors.isNotEmpty
        ? existing.authors
        : value.authors;
    if (existing.authors.isEmpty && value.authors.isNotEmpty) {
      provenance['authors'] = incoming.sourceId;
    }
    final identifiers = _combineIdentifiers(
      existing.identifiers,
      _identifiers(incoming),
    );
    final categories = _mergeCategories(existing.categories, value.subjects);
    final firstPublicationYear = choose(
      existing.firstPublicationYear,
      incoming.sourceMetadata['openLibrary.firstPublishYear'],
      'firstPublicationYear',
      provenance,
    );
    _log(
      'CANONICAL_RECORD_ENRICHED canonicalId=${existing.canonicalId} sourceId=${incoming.sourceId} fields=${provenance.keys.join(',')}',
    );
    return CanonicalBook(
      canonicalId: existing.canonicalId,
      primary: primary,
      sources: sources,
      identifiers: identifiers,
      selectedCover: _bestCover(sources),
      title: title,
      subtitle: subtitle,
      authors: authors,
      description: description,
      publisher: publisher,
      publishedDate: publishedDate,
      pageCount: pageCount,
      language: language,
      firstPublicationYear: firstPublicationYear,
      categories: categories,
      acquisitionCandidates: _candidates(sources),
      fieldProvenance: provenance,
      identifierProvenance: _identifierProvenance(sources),
      metadataCompleteness: _completeness(
        title: title,
        authors: authors,
        description: description,
        publisher: publisher,
        language: language,
        pageCount: pageCount,
        cover: _bestCover(sources),
      ),
    );
  }

  BookIdentifiers _identifiers(BookSourceRecord record) {
    final isbn13 = <String>[];
    final isbn10 = <String>[];
    final other = <String>[];
    for (final raw in record.identifiers) {
      final value = canonicalIsbn(raw.split(':').last);
      if (value?.length == 13) {
        isbn13.add(value!);
      } else if (value?.length == 10) {
        isbn10.add(value!);
        isbn13.add(isbn13FromIsbn10(value)!);
      } else if (raw.trim().isNotEmpty) {
        other.add(raw.trim());
      }
    }
    return BookIdentifiers(
      isbn13: _unique(isbn13),
      isbn10: _unique(isbn10),
      other: _unique(other),
    );
  }

  BookIdentifiers _combineIdentifiers(BookIdentifiers a, BookIdentifiers b) =>
      BookIdentifiers(
        isbn13: _unique([...a.isbn13, ...b.isbn13]),
        isbn10: _unique([...a.isbn10, ...b.isbn10]),
        other: _unique([...a.other, ...b.other]),
      );

  String _canonicalId(BookSourceRecord record, BookIdentifiers ids) {
    if (ids.isbn13.isNotEmpty) return 'isbn13:${ids.isbn13.first}';
    if (ids.isbn10.isNotEmpty) return 'isbn10:${ids.isbn10.first}';
    final author = record.publication.authors.firstOrNull ?? '';
    final language = record.publication.language ?? '';
    if (_normal(record.publication.title).isNotEmpty &&
        _normal(author).isNotEmpty) {
      return 'work:${_normal(record.publication.title)}|${_normal(author)}|${_normal(language)}';
    }
    return '${record.sourceId}:${record.remoteId}';
  }

  RemoteCatalogLocation? _bestCover(List<BookSourceRecord> records) {
    final candidates = <(RemoteCatalogLocation, int, int)>[];
    for (final record in records) {
      for (final image in record.imageCandidates) {
        final url = image.toString().toLowerCase();
        if (url.contains('placeholder') || url.contains('transparent')) {
          continue;
        }
        candidates.add((image, record.sourcePriority, _imageRank(url)));
      }
      if (record.publication.coverLocation case final cover?) {
        candidates.add((
          cover,
          record.sourcePriority,
          _imageRank(cover.toString()),
        ));
      }
    }
    candidates.sort((a, b) {
      final size = b.$3.compareTo(a.$3);
      return size != 0 ? size : a.$2.compareTo(b.$2);
    });
    final cover = candidates.firstOrNull?.$1;
    if (cover != null) {
      _log(
        'CANONICAL_COVER_UPDATED uri=${cover.uri.scheme}://${cover.uri.host}${cover.uri.path}',
      );
    }
    return cover;
  }

  int _imageRank(String url) => switch (url.contains('extralarge')) {
    true => 6,
    false when url.contains('large') => 5,
    false when url.contains('medium') => 4,
    false when url.contains('covers.openlibrary.org') && url.contains('-l.') =>
      5,
    false when url.contains('small') => 3,
    _ => 1,
  };

  List<AcquisitionCandidate> _candidates(List<BookSourceRecord> sources) => [
    for (final source in sources) ...[
      for (final acquisition in source.publication.acquisitions)
        ..._acquisitionCandidate(source.sourceId, acquisition),
      for (final hint in source.accessHints)
        AcquisitionCandidate(
          sourceId: hint.providerId ?? source.sourceId,
          type: hint.type,
          uri: hint.uri,
          mediaType: hint.mediaType,
          fullBook: hint.isFullBook,
          requiresAuthentication: hint.requiresAuthentication,
        ),
    ],
  ];

  List<AcquisitionCandidate> _acquisitionCandidate(
    String sourceId,
    RemoteAcquisition acquisition,
  ) {
    final uri = Uri.tryParse(acquisition.href);
    if (uri == null || uri.scheme != 'https') return const [];
    final type = switch (acquisition.kind) {
      RemoteAcquisitionKind.sample => RemoteCatalogAccessType.sample,
      RemoteAcquisitionKind.buy => RemoteCatalogAccessType.purchase,
      RemoteAcquisitionKind.borrow =>
        RemoteCatalogAccessType.authenticatedDownload,
      _ when acquisition.isDirectSupportedEpub =>
        RemoteCatalogAccessType.directDownload,
      _ => RemoteCatalogAccessType.unavailable,
    };
    return [
      AcquisitionCandidate(
        sourceId: sourceId,
        type: type,
        uri: uri,
        mediaType: acquisition.mediaType,
        fullBook: acquisition.isDirectSupportedEpub,
        requiresAuthentication: acquisition.requiresAuthentication,
      ),
    ];
  }

  Map<String, String> _provenance(BookSourceRecord record) => {
    'title': record.sourceId,
    if (record.publication.subtitle != null) 'subtitle': record.sourceId,
    if (record.publication.authors.isNotEmpty) 'authors': record.sourceId,
    if (record.publication.summary != null) 'description': record.sourceId,
    if (record.publication.publisher != null) 'publisher': record.sourceId,
    if (record.publication.language != null) 'language': record.sourceId,
    if (record.sourceMetadata['openLibrary.firstPublishYear'] != null)
      'firstPublicationYear': record.sourceId,
    if (record.publication.subjects.isNotEmpty) 'categories': record.sourceId,
  };

  Map<String, List<String>> _identifierProvenance(
    Iterable<BookSourceRecord> records,
  ) => {
    for (final record in records)
      for (final identifier in record.identifiers)
        identifier: [
          for (final source in records)
            if (source.identifiers.contains(identifier)) source.sourceId,
        ],
  };

  List<String> _mergeCategories(
    Iterable<String> current,
    Iterable<String> next,
  ) {
    final byNormalized = <String, String>{};
    for (final value in [...current, ...next]) {
      final key = canonicalText(value);
      if (key.isNotEmpty) byNormalized.putIfAbsent(key, () => value.trim());
      if (byNormalized.length == 24) break;
    }
    return byNormalized.values.toList(growable: false);
  }

  bool _usefulDescription(String? value) {
    final text = value?.trim() ?? '';
    return text.length >= 8 &&
        !RegExp(r'<[^>]+>').hasMatch(text) &&
        !text.toLowerCase().contains('no description available');
  }

  bool _isDifferentPublicationType(
    CanonicalBook book,
    BookSourceRecord candidate,
  ) {
    const markers = ['audiobook', 'study guide', 'summary', 'commentary'];
    final a = '${book.title} ${book.subtitle ?? ''}'.toLowerCase();
    final b =
        '${candidate.publication.title} ${candidate.publication.subtitle ?? ''}'
            .toLowerCase();
    return markers.any((marker) => a.contains(marker) != b.contains(marker));
  }

  int _completeness({
    required String? title,
    required Iterable<String> authors,
    required String? description,
    required String? publisher,
    required String? language,
    required int? pageCount,
    required RemoteCatalogLocation? cover,
  }) => [
    title,
    authors.isNotEmpty ? 'authors' : null,
    description,
    publisher,
    language,
    pageCount,
    cover,
  ].where(_present).length;

  bool _present(Object? value) => switch (value) {
    String text => text.trim().isNotEmpty,
    Iterable items => items.isNotEmpty,
    null => false,
    _ => true,
  };

  String _normal(String? value) => canonicalText(value);

  List<String> _unique(Iterable<String> values) =>
      values.toSet().toList()..sort();

  // Canonical identities and cover locations are data, not diagnostic fields.
  void _log(String _) {}
}

/// Session-scoped, incremental owner of canonical search records.
///
/// It intentionally delegates the actual merge policy to [CanonicalBookMerger]
/// so the existing conservative matching rules remain unchanged. Indices only
/// narrow the set of books to which those rules are applied.
class CanonicalSearchAccumulator {
  CanonicalSearchAccumulator({CanonicalBookMerger? merger})
    : _merger = merger ?? const CanonicalBookMerger();

  final CanonicalBookMerger _merger;
  final Map<String, CanonicalBook> _books = {};
  final Map<String, String> _sourceAliases = {};
  final Map<String, String> _presentationIds = {};
  final Map<String, String> _isbn13 = {};
  final Map<String, String> _isbn10 = {};
  final Map<String, Set<String>> _titleAuthor = {};

  int mergerExecutions = 0;
  int candidateLookups = 0;
  int fullScans = 0;
  int indexHits = 0;
  int indexMisses = 0;

  List<CanonicalBook> get books => List.unmodifiable(_books.values);
  Map<String, String> get sourceAliases => Map.unmodifiable(_sourceAliases);
  Map<String, String> get presentationIds => Map.unmodifiable(_presentationIds);

  CanonicalAccumulatorChange addPage(Iterable<BookSourceRecord> records) {
    var newBooks = 0;
    var enriched = 0;
    var rejected = 0;
    for (final record in records) {
      final sourceKey = _sourceKey(record);
      if (_sourceAliases.containsKey(sourceKey)) continue;
      final ids = _merger._identifiers(record);
      final candidates = _candidates(record, ids);
      CanonicalBook? matched;
      for (final id in candidates) {
        final existing = _books[id];
        if (existing == null) continue;
        candidateLookups++;
        if (_merger._matches(existing, record)) {
          matched = existing;
          break;
        }
        rejected++;
      }
      if (matched == null) {
        final created = _merger._create(record);
        _books[created.canonicalId] = created;
        _sourceAliases[sourceKey] = created.canonicalId;
        _index(created, presentationId: sourceKey);
        newBooks++;
      } else {
        final merged = _merger._merge(matched, record);
        _books[merged.canonicalId] = merged;
        _sourceAliases[sourceKey] = merged.canonicalId;
        final presentationId =
            matched.sources
                .map((source) => _presentationIds[_sourceKey(source)])
                .whereType<String>()
                .firstOrNull ??
            _sourceKey(matched.sources.first);
        _index(merged, presentationId: presentationId);
        enriched++;
      }
    }
    mergerExecutions++;
    return CanonicalAccumulatorChange(
      newCanonicalRecords: newBooks,
      enrichedCanonicalRecords: enriched,
      rejectedMatches: rejected,
    );
  }

  /// Rebuilds only the canonical record containing one source publication.
  /// Availability enrichment changes acquisition hints, not identity; keeping
  /// the existing canonical id preserves the Search tile's element identity.
  CanonicalBook? replacePublication({
    required String sourceId,
    required String remoteId,
    required RemoteCatalogPublicationSummary publication,
  }) {
    final sourceKey = '$sourceId\u0000$remoteId';
    final canonicalId = _sourceAliases[sourceKey];
    if (canonicalId == null) return null;
    final existing = _books[canonicalId];
    if (existing == null) return null;
    final records = [
      for (final record in existing.sources)
        if (record.sourceId == sourceId && record.remoteId == remoteId)
          BookSourceRecord.fromPublication(
            sourceId: record.sourceId,
            sourcePriority: record.sourcePriority,
            publication: publication,
          )
        else
          record,
    ];
    if (records.isEmpty) return null;
    var rebuilt = _merger._create(records.first);
    for (final record in records.skip(1)) {
      rebuilt = _merger._merge(rebuilt, record);
    }
    // Acquisition hints are presentation metadata. Preserve the existing
    // canonical identity even when source precedence would choose another
    // primary record while rebuilding this one canonical group.
    if (rebuilt.canonicalId != existing.canonicalId) {
      rebuilt = CanonicalBook(
        canonicalId: existing.canonicalId,
        primary: rebuilt.primary,
        sources: rebuilt.sources,
        identifiers: rebuilt.identifiers,
        selectedCover: rebuilt.selectedCover,
        title: rebuilt.title,
        subtitle: rebuilt.subtitle,
        authors: rebuilt.authors,
        description: rebuilt.description,
        publisher: rebuilt.publisher,
        publishedDate: rebuilt.publishedDate,
        pageCount: rebuilt.pageCount,
        language: rebuilt.language,
        firstPublicationYear: rebuilt.firstPublicationYear,
        categories: rebuilt.categories,
        acquisitionCandidates: rebuilt.acquisitionCandidates,
        fieldProvenance: rebuilt.fieldProvenance,
        identifierProvenance: rebuilt.identifierProvenance,
        metadataCompleteness: rebuilt.metadataCompleteness,
      );
    }
    _books[canonicalId] = rebuilt;
    _index(
      rebuilt,
      presentationId:
          _presentationIds[_sourceKey(existing.sources.first)] ?? sourceKey,
    );
    return rebuilt;
  }

  Set<String> _candidates(BookSourceRecord record, BookIdentifiers ids) {
    final result = <String>{};
    final sourceAlias = _sourceAliases[_sourceKey(record)];
    if (sourceAlias != null) result.add(sourceAlias);
    for (final id in ids.isbn13) {
      final canonical = _isbn13[id];
      if (canonical != null) result.add(canonical);
    }
    for (final id in ids.isbn10) {
      final canonical = _isbn10[id];
      if (canonical != null) result.add(canonical);
    }
    if (result.isNotEmpty) {
      indexHits++;
      return result;
    }
    if (ids.isbn13.isNotEmpty || ids.isbn10.isNotEmpty) {
      indexMisses++;
      return result;
    }
    for (final author in record.publication.authors) {
      result.addAll(
        _titleAuthor[_titleAuthorKey(record.publication.title, author)] ??
            const {},
      );
    }
    if (result.isEmpty) {
      indexMisses++;
    } else {
      indexHits++;
    }
    return result;
  }

  void _index(CanonicalBook book, {required String presentationId}) {
    for (final id in book.identifiers.isbn13) {
      _isbn13.putIfAbsent(id, () => book.canonicalId);
    }
    for (final id in book.identifiers.isbn10) {
      _isbn10.putIfAbsent(id, () => book.canonicalId);
    }
    for (final author in book.authors) {
      _titleAuthor
          .putIfAbsent(_titleAuthorKey(book.title, author), () => <String>{})
          .add(book.canonicalId);
    }
    for (final record in book.sources) {
      final key = _sourceKey(record);
      _sourceAliases[key] = book.canonicalId;
      _presentationIds.putIfAbsent(key, () => presentationId);
    }
  }

  String _sourceKey(BookSourceRecord record) =>
      '${record.sourceId}\u0000${record.remoteId}';

  String _titleAuthorKey(String? title, String? author) =>
      '${canonicalText(title)}\u0000${canonicalText(author)}';
}

class CanonicalAccumulatorChange {
  const CanonicalAccumulatorChange({
    required this.newCanonicalRecords,
    required this.enrichedCanonicalRecords,
    required this.rejectedMatches,
  });

  final int newCanonicalRecords;
  final int enrichedCanonicalRecords;
  final int rejectedMatches;

  bool get didChange =>
      newCanonicalRecords != 0 || enrichedCanonicalRecords != 0;
}

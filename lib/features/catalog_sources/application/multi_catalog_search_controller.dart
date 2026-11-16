import 'dart:async';
import 'dart:convert';

import 'package:bibliolife/core/network/request_cancellation.dart';
import 'package:bibliolife/core/performance/online_pipeline_performance.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/data/built_in_catalog_sources.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/canonical_book_merger.dart';
import 'package:bibliolife/features/catalog_sources/domain/book_source_record.dart';
import 'package:bibliolife/features/catalog_sources/domain/canonical_book.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_search_filters.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/google_books_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/internet_archive_acquisition.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_access_hint.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crypto/crypto.dart';

const multiCatalogSearchConcurrency = 3;
const _internetArchiveEnrichmentTimeout = Duration(seconds: 12);
const _internetArchiveEnrichmentConcurrency = 3;
const _internetArchiveEnrichmentBatchSize = 3;

String normalizeCatalogSearchQuery(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

String _queryKey(String value) =>
    normalizeCatalogSearchQuery(value).toLowerCase();

String _rankingText(String value) => normalizeCatalogSearchQuery(
  value,
).toLowerCase().replaceAll(RegExp(r'''[.,;:!?"'()\[\]{}]'''), '');

int catalogSearchRelevance(
  RemoteCatalogPublicationSummary publication,
  String query,
) {
  final normalizedQuery = _rankingText(query);
  if (normalizedQuery.isEmpty) return 7;
  final title = _rankingText(publication.title);
  final authors = publication.authors.map(_rankingText).toList(growable: false);
  if (title == normalizedQuery) return 1;
  if (authors.any((author) => author == normalizedQuery)) return 2;
  if (title.startsWith(normalizedQuery)) return 3;
  if (authors.any((author) => author.startsWith(normalizedQuery))) return 4;
  if (title.contains(normalizedQuery)) return 5;
  if (authors.any((author) => author.contains(normalizedQuery))) return 6;
  return 7;
}

final multiCatalogSearchControllerProvider =
    NotifierProvider.autoDispose<
      MultiCatalogSearchController,
      MultiCatalogSearchState
    >(MultiCatalogSearchController.new);

/// Shared applied snapshot for Home and the full Search route. Draft values
/// stay inside the sheet until Apply commits them here.
final catalogSearchFiltersProvider =
    NotifierProvider<CatalogSearchFiltersController, CatalogSearchFilters>(
      CatalogSearchFiltersController.new,
    );

class CatalogSearchFiltersController extends Notifier<CatalogSearchFilters> {
  @override
  CatalogSearchFilters build() => CatalogSearchFilters.defaults();
  void set(CatalogSearchFilters filters) => state = filters;
}

class MultiCatalogSearchResult {
  const MultiCatalogSearchResult({
    required this.source,
    required this.publication,
    required this.routePublication,
    required this.canonicalBook,
    required this.presentationIdentity,
    this.performanceSession,
  });

  final CatalogSource source;
  final RemoteCatalogPublicationSummary publication;
  final RemoteCatalogPublicationSummary routePublication;
  final CanonicalBook canonicalBook;
  final String presentationIdentity;
  final OnlineSearchPerformanceSession? performanceSession;

  String get identity => presentationIdentity;
}

class MultiCatalogSourceSearchState {
  const MultiCatalogSourceSearchState({
    required this.source,
    this.page,
    this.capability = const RemoteCatalogSearchCapability.unsupported(),
    this.loading = false,
    this.exhausted = false,
    this.failure,
    this.failureMessage,
  });

  final CatalogSource source;
  final RemoteCatalogPage? page;
  final RemoteCatalogSearchCapability capability;
  final bool loading;
  final bool exhausted;
  final RemoteCatalogFailure? failure;
  final String? failureMessage;

  bool get isRetryable =>
      failure != RemoteCatalogFailure.googleBooksApiKeyMissing &&
      failure != RemoteCatalogFailure.googleBooksConfigurationInvalid;

  MultiCatalogSourceSearchState copyWith({
    RemoteCatalogPage? page,
    RemoteCatalogSearchCapability? capability,
    bool? loading,
    bool? exhausted,
    RemoteCatalogFailure? failure,
    String? failureMessage,
    bool clearFailure = false,
  }) => MultiCatalogSourceSearchState(
    source: source,
    page: page ?? this.page,
    capability: capability ?? this.capability,
    loading: loading ?? this.loading,
    exhausted: exhausted ?? this.exhausted,
    failure: clearFailure ? null : failure ?? this.failure,
    failureMessage: clearFailure ? null : failureMessage ?? this.failureMessage,
  );
}

class MultiCatalogSearchState {
  MultiCatalogSearchState({
    this.query = '',
    CatalogSearchFilters? filters,
    this.generation = 0,
    this.sources = const {},
    this.presentationIds = const {},
    this.awaitingDebounce = false,
    this.enrichmentPending = 0,
    this.performanceSession,
    this.materializedResults,
  }) : filters = filters ?? CatalogSearchFilters.defaults();

  final String query;
  final CatalogSearchFilters filters;
  final int generation;
  final Map<String, MultiCatalogSourceSearchState> sources;

  /// Source-record aliases to a session-stable presentation identity.
  final Map<String, String> presentationIds;
  final bool awaitingDebounce;
  final int enrichmentPending;
  final OnlineSearchPerformanceSession? performanceSession;
  final List<MultiCatalogSearchResult>? materializedResults;

  List<MultiCatalogSearchResult> get results {
    final materialized = materializedResults;
    if (materialized != null) return materialized;
    final sourceById = {
      for (final source in sources.values) source.source.id: source.source,
    };
    final records = <BookSourceRecord>[
      for (final entry in sources.values)
        for (final publication in entry.page?.publications ?? const [])
          BookSourceRecord.fromPublication(
            sourceId: entry.source.id,
            sourcePriority: _sourcePriority(entry.source),
            publication: publication,
          ),
    ];
    final performance = performanceSession;
    final items = [
      for (final book
          in (performance == null
                  ? const CanonicalBookMerger()
                  : CanonicalBookMerger(performanceSession: performance))
              .merge(records))
        () {
          final route = book.sources.firstWhere(
            (record) =>
                sourceById[record.sourceId]?.supportsAcquisition == true,
            orElse: () => book.primary,
          );
          return MultiCatalogSearchResult(
            source: sourceById[route.sourceId]!,
            publication: book.displayPublication,
            routePublication: route.publication,
            canonicalBook: book,
            presentationIdentity: _presentationIdentity(book),
            performanceSession: performance,
          );
        }(),
    ];
    final indexed = items.indexed.toList(growable: false);
    final rankingStopwatch = performance == null
        ? null
        : (Stopwatch()..start());
    indexed.sort((a, b) {
      final relevance = catalogSearchRelevance(
        a.$2.publication,
        query,
      ).compareTo(catalogSearchRelevance(b.$2.publication, query));
      if (relevance != 0) return relevance;
      final aDownloadable = a.$2.source.supportsAcquisition;
      final bDownloadable = b.$2.source.supportsAcquisition;
      if (aDownloadable != bDownloadable) return aDownloadable ? -1 : 1;
      return a.$1.compareTo(b.$1);
    });
    rankingStopwatch?.stop();
    if (rankingStopwatch != null) {
      performance!.recordRanking(rankingStopwatch.elapsed);
    }
    return indexed.map((entry) => entry.$2).toList(growable: false);
  }

  String _presentationIdentity(CanonicalBook book) =>
      book.sources
          .map((source) => presentationIds[_sourceRecordKey(source)])
          .whereType<String>()
          .firstOrNull ??
      book.canonicalId;

  /// Remote source progress determines whether the result grid is loading.
  /// Availability enrichment is deliberately independent so a slow Internet
  /// Archive lookup cannot hold already-fetched results behind a spinner.
  bool get isLoading => sources.values.any((source) => source.loading);
  bool get isEnriching => enrichmentPending > 0;
  bool get hasNoSources =>
      (query.isNotEmpty || filters.hasMeaningfulSourceQuery) && sources.isEmpty;
  bool get hasAnyFailure =>
      sources.values.any((source) => source.failure != null);
  bool get allFailed =>
      sources.isNotEmpty &&
      sources.values.every((source) => source.failure != null);
  bool get hasMore => sources.values.any(
    (source) =>
        !source.loading &&
        source.failure == null &&
        !source.exhausted &&
        source.page?.nextPageLocation != null,
  );
  bool get hasPaginationFailure => sources.values.any(
    (source) => source.page != null && source.failure != null,
  );
  bool get hasRecoverableFailure => sources.values.any(
    (source) =>
        source.failure != null &&
        source.isRetryable &&
        source.failure != RemoteCatalogFailure.searchUnsupported,
  );

  String? get isolatedFailureMessage =>
      sources.length == 1 ? sources.values.single.failureMessage : null;
}

class _InternetArchiveEnrichmentStats {
  int candidates = 0;
  int scheduled = 0;
  int completed = 0;
  int completedSinceFlush = 0;
  int unavailable = 0;
  int failed = 0;
  int timedOut = 0;
  int cancelled = 0;
  int verifiedAttached = 0;
  int retainedEditions = 0;
  int visibleResults = 0;
}

List<MultiCatalogSearchResult> materializeCanonicalSearchResults({
  required Iterable<CanonicalBook> books,
  required Map<String, MultiCatalogSourceSearchState> sources,
  required Map<String, String> presentationIds,
  required String query,
  CatalogSearchFilters? filters,
  OnlineSearchPerformanceSession? performanceSession,
}) {
  performanceSession?.recordCanonicalMaterialization();
  final sourceById = {
    for (final entry in sources.values) entry.source.id: entry.source,
  };
  final items = [
    for (final original in books)
      if (const CatalogSearchPostFilter().apply(
            original,
            filters ?? CatalogSearchFilters.defaults(),
          )
          case final book?)
        () {
          final identity =
              book.sources
                  .map((record) => presentationIds[_sourceRecordKey(record)])
                  .whereType<String>()
                  .firstOrNull ??
              book.canonicalId;
          return _resultFromCanonical(
            book: book,
            sourceById: sourceById,
            presentationIds: presentationIds,
            performanceSession: performanceSession,
            identity: identity,
          );
        }(),
  ];
  final indexed = items.indexed.toList(growable: false);
  final stopwatch = performanceSession == null ? null : (Stopwatch()..start());
  indexed.sort((a, b) {
    final relevance = catalogSearchRelevance(
      a.$2.publication,
      query,
    ).compareTo(catalogSearchRelevance(b.$2.publication, query));
    if (relevance != 0) return relevance;
    final aDownloadable = a.$2.source.supportsAcquisition;
    final bDownloadable = b.$2.source.supportsAcquisition;
    if (aDownloadable != bDownloadable) return aDownloadable ? -1 : 1;
    return a.$1.compareTo(b.$1);
  });
  stopwatch?.stop();
  if (stopwatch != null) performanceSession!.recordRanking(stopwatch.elapsed);
  return List.unmodifiable(indexed.map((entry) => entry.$2));
}

MultiCatalogSearchResult _resultFromCanonical({
  required CanonicalBook book,
  required Map<String, CatalogSource> sourceById,
  required Map<String, String> presentationIds,
  required OnlineSearchPerformanceSession? performanceSession,
  String? identity,
}) {
  final route = book.sources.firstWhere(
    (record) => sourceById[record.sourceId]?.supportsAcquisition == true,
    orElse: () => book.primary,
  );
  final presentationIdentity =
      identity ??
      book.sources
          .map((record) => presentationIds[_sourceRecordKey(record)])
          .whereType<String>()
          .firstOrNull ??
      book.canonicalId;
  return MultiCatalogSearchResult(
    source: sourceById[route.sourceId]!,
    publication: book.displayPublication,
    routePublication: route.publication,
    canonicalBook: book,
    presentationIdentity: presentationIdentity,
    performanceSession: performanceSession,
  );
}

int _sourcePriority(CatalogSource source) => switch (source.type) {
  CatalogSourceType.googleBooks => 1,
  CatalogSourceType.openLibrary => 2,
  CatalogSourceType.opds1 when source.id == 'builtin-project-gutenberg' => 3,
  _ => 4,
};

class MultiCatalogSearchController extends Notifier<MultiCatalogSearchState> {
  var _generation = 0;
  var _disposed = false;
  OnlineSearchPerformanceSession? _activePerformanceSession;
  CanonicalSearchAccumulator? _canonicalAccumulator;
  CancellationTokenSource? _searchSession;
  final Map<String, CancellationTokenSource> _sourceTasks = {};
  final Map<String, CancellationTokenSource> _paginationTasks = {};
  final Set<CancellationTokenSource> _enrichmentTasks = {};
  final Map<int, int> _enrichmentPending = {};
  final Map<int, _InternetArchiveEnrichmentStats> _enrichmentStats = {};
  final Map<int, Map<String, Map<String, RemoteCatalogPublicationSummary>>>
  _queuedEnrichments = {};

  @override
  MultiCatalogSearchState build() {
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      _cancelSearch(RequestCancellationReason.controllerDisposed);
      _finishPerformanceSession('controllerDisposed');
    });
    return MultiCatalogSearchState(
      filters: ref.read(catalogSearchFiltersProvider),
    );
  }

  /// Invalidates in-flight requests as soon as the text changes, before the
  /// presentation layer's debounce schedules a replacement request.
  void setQuery(String value) {
    final query = normalizeCatalogSearchQuery(value);
    if (_queryKey(query) == _queryKey(state.query)) return;
    _activePerformanceSession?.recordCancellationRequested();
    _cancelSearch(RequestCancellationReason.queryReplaced);
    _finishPerformanceSession('queryReplaced');
    _canonicalAccumulator = null;
    final generation = ++_generation;
    _log('MULTI_SEARCH_QUERY_CHANGED query=$query generation=$generation');
    _emit(
      MultiCatalogSearchState(
        query: query,
        filters: state.filters,
        generation: generation,
        awaitingDebounce: query.isNotEmpty,
      ),
    );
  }

  Future<void> applyFilters(CatalogSearchFilters filters) async {
    if (filters == state.filters) return;
    _activePerformanceSession?.recordCancellationRequested();
    _cancelSearch(RequestCancellationReason.queryReplaced);
    _finishPerformanceSession('filtersReplaced');
    _canonicalAccumulator = null;
    ref.read(catalogSearchFiltersProvider.notifier).set(filters);
    _emit(
      MultiCatalogSearchState(
        query: state.query,
        filters: filters,
        generation: ++_generation,
      ),
    );
    if (state.query.isNotEmpty || filters.hasMeaningfulSourceQuery) {
      await submit(state.query);
    }
  }

  Future<void> submit(String value) async {
    final query = normalizeCatalogSearchQuery(value);
    if (query.isEmpty && !state.filters.hasMeaningfulSourceQuery) {
      setQuery(query);
      return;
    }
    if (query != state.query) setQuery(query);
    if (state.isLoading || state.sources.isNotEmpty) {
      _log('MULTI_SEARCH_DUPLICATE_IGNORED query=$query');
      _activePerformanceSession?.duplicateRequestCount++;
      return;
    }
    final generation = ++_generation;
    final performanceId = biblioLifeNetPerfLogsEnabled
        ? _newPerformanceSessionId(generation)
        : null;
    if (performanceId != null) {
      searchPerformanceHealth(
        'session_start',
        fields: {'generationHash': performanceId},
      );
    }
    final performance = performanceId == null
        ? null
        : OnlineSearchPerformanceSession(id: performanceId);
    _activePerformanceSession = performance;
    _searchSession = CancellationTokenSource();
    _canonicalAccumulator = CanonicalSearchAccumulator(
      merger: CanonicalBookMerger(performanceSession: performance),
    );
    _log('MULTI_SEARCH_SUBMITTED query=$query generation=$generation');
    final searchable =
        (await ref.read(catalogSourceRepositoryProvider).getAll())
            .where((source) => source.isEnabled && source.supportsSearch)
            .toList();
    final requestedSourceIds = state.filters.selectedSourceIds.toSet();
    final selectedSearchIds = requestedSourceIds
        .where((id) => searchable.any((source) => source.id == id))
        .toSet();
    // Internet Archive is an acquisition provider, not a text-search API. An
    // IA-only filter therefore searches Open Library as its metadata carrier.
    if (requestedSourceIds.contains(internetArchiveCatalogSourceId)) {
      selectedSearchIds.addAll(
        searchable
            .where((source) => source.type == CatalogSourceType.openLibrary)
            .map((source) => source.id),
      );
    }
    final enabled = requestedSourceIds.isEmpty
        ? searchable
        : searchable
              .where((source) => selectedSearchIds.contains(source.id))
              .toList();
    if (!_current(generation)) {
      _log('MULTI_SEARCH_STALE_IGNORED query=$query generation=$generation');
      return;
    }
    performance?.configureSources(enabled.length);
    _log(
      'MULTI_SEARCH_STARTED query=$query generation=$generation sourceCount=${enabled.length}',
    );
    final initial = {
      for (final source in enabled)
        source.id: MultiCatalogSourceSearchState(source: source, loading: true),
    };
    _emit(
      MultiCatalogSearchState(
        query: query,
        filters: state.filters,
        generation: generation,
        sources: initial,
        awaitingDebounce: false,
        performanceSession: performance,
        materializedResults: const [],
      ),
      wholeListReplacement: true,
    );
    await _runLimited(
      enabled,
      generation,
      (source) => _runSearchSource(source, _sourceQuery(query), generation),
    );
    _finishPerformanceSessionIfTerminal();
  }

  String _sourceQuery(String query) {
    if (query.isNotEmpty) return query;
    final filters = state.filters;
    return filters.author.isNotEmpty
        ? filters.author
        : filters.includedGenres.join(' ');
  }

  Future<void> loadMore() async {
    final generation = state.generation;
    final eligible = state.sources.values
        .where(
          (entry) =>
              !entry.loading &&
              entry.failure == null &&
              !entry.exhausted &&
              entry.page?.nextPageLocation != null,
        )
        .toList();
    if (eligible.isEmpty) {
      onlinePerformanceMarker(
        'pagination_unavailable',
        fields: {
          'generation': generation,
          'sources': state.sources.length,
          'exhausted': state.sources.values
              .where((entry) => entry.exhausted)
              .length,
        },
      );
      return;
    }
    onlinePerformanceMarker(
      'pagination_requested',
      fields: {'generation': generation, 'sources': eligible.length},
    );
    await _runLimited(
      eligible,
      generation,
      (entry) => _runPagination(entry, generation),
    );
    _finishPerformanceSessionIfTerminal();
  }

  Future<void> retryFailed() async {
    final generation = state.generation;
    final query = state.query;
    if (query.isEmpty) return;
    final retryable = state.sources.values
        .where(
          (entry) =>
              entry.failure != null &&
              entry.isRetryable &&
              entry.failure != RemoteCatalogFailure.searchUnsupported,
        )
        .toList(growable: false);
    if (retryable.isEmpty) return;
    _log(
      'MULTI_SEARCH_RETRY query=$query generation=$generation sourceCount=${retryable.length}',
    );
    await _runLimited(retryable, generation, (entry) {
      if (entry.page == null) {
        _update(
          entry.source.id,
          generation,
          (current) => current.copyWith(loading: true, clearFailure: true),
        );
        return _runSearchSource(entry.source, _sourceQuery(query), generation);
      }
      _update(
        entry.source.id,
        generation,
        (current) => current.copyWith(loading: false, clearFailure: true),
      );
      return _runPagination(entry, generation);
    });
  }

  Future<void> retrySource(String sourceId) async {
    final entry = state.sources[sourceId];
    if (entry == null || entry.failure == null || !entry.isRetryable) return;
    final generation = state.generation;
    final query = state.query;
    if (entry.page == null) {
      _update(
        sourceId,
        generation,
        (current) => current.copyWith(loading: true, clearFailure: true),
      );
      await _runSearchSource(entry.source, _sourceQuery(query), generation);
      return;
    }
    _update(
      sourceId,
      generation,
      (current) => current.copyWith(clearFailure: true),
    );
    await _runPagination(entry, generation);
  }

  Future<void> _runLimited<T>(
    List<T> items,
    int generation,
    Future<void> Function(T item) action, {
    int concurrency = multiCatalogSearchConcurrency,
  }) async {
    var next = 0;
    Future<void> worker() async {
      while (_current(generation) && next < items.length) {
        final item = items[next++];
        await action(item);
      }
    }

    await Future.wait([
      for (var index = 0; index < concurrency && index < items.length; index++)
        worker(),
    ]);
  }

  Future<void> _runSearchSource(
    CatalogSource source,
    String query,
    int generation,
  ) {
    _sourceTasks
        .remove(source.id)
        ?.cancel(RequestCancellationReason.retrySuperseded);
    final session = _searchSession;
    if (session == null) return Future.value();
    final task = CancellationTokenSource(parent: session.token);
    _sourceTasks[source.id] = task;
    return MetadataRequestScope.run(
      MetadataRequestContext(
        token: task.token,
        sourceId: source.id,
        priority: MetadataRequestPriority.activeSearch,
        sessionId: _activePerformanceSession?.id,
      ),
      () => OnlinePerformanceScope.run(
        state.performanceSession,
        source.id,
        () => _searchSource(source, query, generation),
      ),
    );
  }

  Future<void> _runPagination(
    MultiCatalogSourceSearchState entry,
    int generation,
  ) {
    final next = entry.page?.nextPageLocation;
    if (next == null) return Future.value();
    final key = '${entry.source.id}\u0000$next';
    if (_paginationTasks.containsKey(key)) {
      state.performanceSession?.recordPaginationRequest(
        entry.source.id,
        duplicate: true,
      );
      return Future.value();
    }
    final session = _searchSession;
    if (session == null) return Future.value();
    final task = CancellationTokenSource(parent: session.token);
    state.performanceSession?.recordPaginationRequest(entry.source.id);
    _paginationTasks[key] = task;
    return MetadataRequestScope.run(
      MetadataRequestContext(
        token: task.token,
        sourceId: entry.source.id,
        priority: MetadataRequestPriority.pagination,
        sessionId: _activePerformanceSession?.id,
      ),
      () => OnlinePerformanceScope.run(
        state.performanceSession,
        entry.source.id,
        () => _loadNext(entry, generation),
      ),
    ).whenComplete(() => _paginationTasks.remove(key));
  }

  void _cancelSearch(RequestCancellationReason reason) {
    _searchSession?.cancel(reason);
    _searchSession = null;
    for (final task in _sourceTasks.values) {
      task.cancel(reason);
    }
    _sourceTasks.clear();
    for (final task in _paginationTasks.values) {
      task.cancel(reason);
    }
    _paginationTasks.clear();
    for (final task in _enrichmentTasks) {
      task.cancel(reason);
    }
    _enrichmentTasks.clear();
    _enrichmentPending.clear();
    _enrichmentStats.clear();
    _queuedEnrichments.clear();
  }

  Future<void> _searchSource(
    CatalogSource source,
    String query,
    int generation,
  ) async {
    try {
      OnlinePerformanceScope.session?.sourceStarted(source.id);
      _log('MULTI_SEARCH_SOURCE_STARTED libraryId=${source.id}');
      final root = await ref
          .read(remoteCatalogGatewayProvider)
          .loadRoot(source);
      if (!_current(generation)) {
        OnlinePerformanceScope.session?.recordStaleResponse();
        _log(
          'MULTI_SEARCH_STALE_IGNORED query=$query generation=$generation libraryId=${source.id} stage=root',
        );
        return;
      }
      final capability = root.searchCapability;
      if (!capability.isSupported) {
        _update(
          source.id,
          generation,
          (entry) => entry.copyWith(
            capability: capability,
            loading: false,
            exhausted: true,
            failure: RemoteCatalogFailure.searchUnsupported,
          ),
        );
        OnlinePerformanceScope.session?.sourceFinished(
          source.id,
          recordCount: 0,
        );
        return;
      }
      final fetchedPage = await ref
          .read(remoteCatalogGatewayProvider)
          .search(source: source, capability: capability, query: query);
      if (!_current(generation)) {
        OnlinePerformanceScope.session?.recordStaleResponse();
        _log(
          'MULTI_SEARCH_STALE_IGNORED query=$query generation=$generation libraryId=${source.id} stage=response',
        );
        return;
      }
      _applySourcePage(
        sourceId: source.id,
        generation: generation,
        page: fetchedPage,
        capability: capability,
      );
      unawaited(
        _scheduleInternetArchiveEnrichment(source, fetchedPage, generation),
      );
      final performance = OnlinePerformanceScope.session;
      performance?.sourceFinished(
        source.id,
        recordCount: fetchedPage.publications.length,
      );
      if (fetchedPage.publications.isNotEmpty) {
        performance?.recordFirstVisibleResultCandidate();
      }
      _log(
        'MULTI_SEARCH_SOURCE_COMPLETED query=$query generation=$generation libraryId=${source.id} resultCount=${fetchedPage.publications.length}',
      );
    } on RequestCancelledException {
      // Cancellation is intentional and must not create retryable UI state.
      return;
    } on RemoteCatalogException catch (error) {
      OnlinePerformanceScope.session?.sourceFailed(source.id);
      _log(
        'MULTI_SEARCH_SOURCE_FAILED query=$query generation=$generation libraryId=${source.id} reason=${error.failure.name} detail=${error.message ?? 'none'}',
      );
      _update(
        source.id,
        generation,
        (entry) => entry.copyWith(
          loading: false,
          exhausted: true,
          failure: error.failure,
          failureMessage: error is GoogleBooksRequestException
              ? error.userMessage
              : null,
        ),
      );
    }
  }

  Future<void> _loadNext(
    MultiCatalogSourceSearchState entry,
    int generation,
  ) async {
    final next = entry.page?.nextPageLocation;
    if (next == null) return;
    final query = state.query;
    _log(
      'MULTI_SEARCH_PAGE_STARTED query=$query generation=$generation libraryId=${entry.source.id} cursor=$next',
    );
    _update(
      entry.source.id,
      generation,
      (current) => current.copyWith(loading: true),
    );
    try {
      OnlinePerformanceScope.session?.sourceStarted(entry.source.id);
      final fetchedPage = await ref
          .read(remoteCatalogGatewayProvider)
          .loadPage(source: entry.source, location: next);
      if (!_current(generation)) {
        OnlinePerformanceScope.session?.recordStaleResponse();
        _log(
          'MULTI_SEARCH_STALE_IGNORED query=$query generation=$generation libraryId=${entry.source.id} stage=page',
        );
        return;
      }
      _applySourcePage(
        sourceId: entry.source.id,
        generation: generation,
        page: fetchedPage,
        append: true,
      );
      unawaited(
        _scheduleInternetArchiveEnrichment(
          entry.source,
          fetchedPage,
          generation,
        ),
      );
      OnlinePerformanceScope.session?.sourceFinished(
        entry.source.id,
        recordCount: fetchedPage.publications.length,
      );
      _log(
        'MULTI_SEARCH_PAGE_COMPLETED query=$query generation=$generation libraryId=${entry.source.id} cursor=$next resultCount=${fetchedPage.publications.length}',
      );
      onlinePerformanceMarker(
        'pagination_completed',
        fields: {
          'generation': generation,
          'source': entry.source.id,
          'records': fetchedPage.publications.length,
          'totalRecords':
              state.sources[entry.source.id]?.page?.publications.length,
          'cursor': fetchedPage.nextPageLocation == null ? 'none' : 'present',
          'exhausted': fetchedPage.nextPageLocation == null,
        },
      );
    } on RequestCancelledException {
      // The parent session or cursor task owns this cancellation.
      onlinePerformanceMarker(
        'pagination_cancelled',
        fields: {'generation': generation, 'source': entry.source.id},
      );
      return;
    } on RemoteCatalogException catch (error) {
      OnlinePerformanceScope.session?.sourceFailed(entry.source.id);
      _log(
        'MULTI_SEARCH_PAGE_FAILED query=$query generation=$generation libraryId=${entry.source.id} cursor=$next reason=${error.failure.name}',
      );
      _update(
        entry.source.id,
        generation,
        (current) => current.copyWith(
          loading: false,
          failure: error.failure,
          failureMessage: error is GoogleBooksRequestException
              ? error.userMessage
              : null,
        ),
      );
    }
  }

  void _update(
    String sourceId,
    int generation,
    MultiCatalogSourceSearchState Function(MultiCatalogSourceSearchState)
    update,
  ) {
    if (!_current(generation)) return;
    final current = state.sources[sourceId];
    if (current == null) return;
    final updated = update(current);
    _emit(
      MultiCatalogSearchState(
        query: state.query,
        filters: state.filters,
        generation: state.generation,
        sources: {...state.sources, sourceId: updated},
        presentationIds: state.presentationIds,
        enrichmentPending: state.enrichmentPending,
        performanceSession: state.performanceSession,
        materializedResults: state.materializedResults,
      ),
      wholeListReplacement: true,
    );
  }

  void _applySourcePage({
    required String sourceId,
    required int generation,
    required RemoteCatalogPage page,
    RemoteCatalogSearchCapability? capability,
    bool append = false,
  }) {
    if (!_current(generation)) return;
    final current = state.sources[sourceId];
    if (current == null) return;
    final mergedPage = append ? _append(current.page!, page) : page;
    if (append) state.performanceSession?.recordPaginationBatchAppended();
    final updated = current.copyWith(
      capability: capability,
      page: mergedPage,
      loading: false,
      exhausted: page.nextPageLocation == null,
      clearFailure: true,
    );
    onlinePerformanceMarker(
      'source_page_state',
      fields: {
        'source': sourceId,
        'phase': append ? 'pagination' : 'initial',
        'records': page.publications.length,
        'totalRecords': mergedPage.publications.length,
        'cursor': page.nextPageLocation == null ? 'none' : 'present',
        'exhausted': page.nextPageLocation == null,
      },
    );
    final sources = {...state.sources, sourceId: updated};
    final accumulator = _canonicalAccumulator;
    if (accumulator == null) {
      _emit(
        MultiCatalogSearchState(
          query: state.query,
          filters: state.filters,
          generation: state.generation,
          sources: sources,
          presentationIds: state.presentationIds,
          enrichmentPending: state.enrichmentPending,
          performanceSession: state.performanceSession,
          materializedResults: state.materializedResults,
        ),
        wholeListReplacement: true,
      );
      return;
    }

    final previousCandidateLookups = accumulator.candidateLookups;
    final stopwatch = Stopwatch()..start();
    final change = accumulator.addPage(
      page.publications.map(
        (publication) => BookSourceRecord.fromPublication(
          sourceId: current.source.id,
          sourcePriority: _sourcePriority(current.source),
          publication: publication,
        ),
      ),
    );
    stopwatch.stop();
    state.performanceSession?.recordCanonical(
      inputRecordCount: page.publications.length,
      resultCount: accumulator.books.length,
      mergedCount: change.enrichedCanonicalRecords,
      rejectedCount: change.rejectedMatches,
      comparisonCount: accumulator.candidateLookups - previousCandidateLookups,
      normalizationCalls: 0,
      isbnConversions: 0,
      mergeDuration: stopwatch.elapsed,
    );
    if (!change.didChange) {
      _emit(
        MultiCatalogSearchState(
          query: state.query,
          filters: state.filters,
          generation: state.generation,
          sources: sources,
          presentationIds: accumulator.presentationIds,
          enrichmentPending: state.enrichmentPending,
          performanceSession: state.performanceSession,
          materializedResults: state.materializedResults,
        ),
      );
      return;
    }
    final materialized = materializeCanonicalSearchResults(
      books: accumulator.books,
      sources: sources,
      presentationIds: accumulator.presentationIds,
      query: state.query,
      filters: state.filters,
      performanceSession: state.performanceSession,
    );
    _emit(
      MultiCatalogSearchState(
        query: state.query,
        filters: state.filters,
        generation: state.generation,
        sources: sources,
        presentationIds: accumulator.presentationIds,
        enrichmentPending: state.enrichmentPending,
        performanceSession: state.performanceSession,
        materializedResults: materialized,
      ),
      wholeListReplacement: true,
    );
  }

  Future<void> _scheduleInternetArchiveEnrichment(
    CatalogSource source,
    RemoteCatalogPage page,
    int generation,
  ) async {
    if (source.type != CatalogSourceType.openLibrary) {
      return;
    }
    final candidates = <(RemoteCatalogPublicationSummary, Iterable<String>)>[
      for (final publication in page.publications)
        if (publication.sourceLists['openLibrary.internetArchiveIds']
            case final identifiers? when identifiers.isNotEmpty)
          (publication, identifiers),
    ];
    if (candidates.isEmpty) return;
    final stats = _enrichmentStats.putIfAbsent(
      generation,
      _InternetArchiveEnrichmentStats.new,
    );
    stats.candidates += candidates.length;
    stats.scheduled += candidates.length;
    onlinePerformanceMarker(
      'ia_enrichment_queued',
      fields: {
        'generation': generation,
        'source': source.id,
        'records': candidates.length,
        'concurrency': _internetArchiveEnrichmentConcurrency,
      },
    );
    await _runLimited(
      candidates,
      generation,
      (candidate) => _runInternetArchiveEnrichment(
        source: source,
        publication: candidate.$1,
        identifiers: candidate.$2,
        generation: generation,
      ),
      concurrency: _internetArchiveEnrichmentConcurrency,
    );
  }

  Future<void> _runInternetArchiveEnrichment({
    required CatalogSource source,
    required RemoteCatalogPublicationSummary publication,
    required Iterable<String> identifiers,
    required int generation,
  }) async {
    final parent = _searchSession;
    if (parent == null || !_current(generation)) return;
    final task = CancellationTokenSource(parent: parent.token);
    _enrichmentTasks.add(task);
    _enrichmentPending[generation] = (_enrichmentPending[generation] ?? 0) + 1;
    _syncEnrichmentPending(generation);
    onlinePerformanceMarker('ia_enrichment_started');
    try {
      final archive = await ref
          .read(catalogSourceRepositoryProvider)
          .getById(internetArchiveCatalogSourceId);
      if (archive?.isEnabled != true) {
        _statsFor(generation).unavailable++;
        onlinePerformanceMarker('ia_enrichment_unavailable');
        return;
      }
      final resolver = ref.read(internetArchiveAcquisitionResolverProvider);
      final result = await MetadataRequestScope.run(
        MetadataRequestContext(
          token: task.token,
          sourceId: internetArchiveCatalogSourceId,
          priority: MetadataRequestPriority.enrichment,
          sessionId: _activePerformanceSession?.id,
        ),
        () => resolver
            .resolve(identifiers)
            .timeout(
              _internetArchiveEnrichmentTimeout,
              onTimeout: () {
                task.cancel(RequestCancellationReason.requestTimeout);
                throw TimeoutException(
                  'Internet Archive enrichment timed out.',
                );
              },
            ),
      );
      if ((result.availability != InternetArchiveAvailability.directEpub &&
              result.availability != InternetArchiveAvailability.directPdf) ||
          result.uri == null ||
          !_current(generation)) {
        _statsFor(generation).unavailable++;
        onlinePerformanceMarker('ia_enrichment_unavailable');
        return;
      }
      _statsFor(generation).verifiedAttached++;
      _queueEnrichedPublication(
        sourceId: source.id,
        remoteId: publication.remoteId,
        generation: generation,
        publication: publication.copyWith(
          accessHints: [
            ...publication.accessHints,
            RemoteCatalogAccessHint(
              type: RemoteCatalogAccessType.directDownload,
              uri: result.uri,
              mediaType: result.mediaType,
              isFullBook: true,
              isDrmFree: true,
              providerId: internetArchiveCatalogSourceId,
            ),
          ],
        ),
      );
      onlinePerformanceMarker('ia_enrichment_completed');
    } on TimeoutException {
      _statsFor(generation).timedOut++;
      onlinePerformanceMarker('ia_enrichment_timed_out');
    } on RequestCancelledException {
      _statsFor(generation).cancelled++;
      onlinePerformanceMarker('ia_enrichment_cancelled');
    } on Object {
      _statsFor(generation).failed++;
      onlinePerformanceMarker('ia_enrichment_failed');
    } finally {
      task.dispose();
      _enrichmentTasks.remove(task);
      final stats = _statsFor(generation);
      stats.completed++;
      stats.completedSinceFlush++;
      final remaining = (_enrichmentPending[generation] ?? 1) - 1;
      if (remaining <= 0) {
        _enrichmentPending.remove(generation);
        if (_current(generation)) {
          _flushQueuedEnrichments(generation);
          onlinePerformanceMarker(
            'ia_enrichment_summary',
            fields: {
              'generation': generation,
              'candidates': stats.candidates,
              'scheduled': stats.scheduled,
              'completed': stats.completed,
              'unavailable': stats.unavailable,
              'failed': stats.failed,
              'timedOut': stats.timedOut,
              'cancelled': stats.cancelled,
              'verifiedAttached': stats.verifiedAttached,
              'retainedEditions': stats.retainedEditions,
              'visible': stats.visibleResults,
              'active': true,
            },
          );
          _enrichmentStats.remove(generation);
          onlinePerformanceMarker(
            'ia_enrichment_generation_finished',
            fields: const {'pending': 0},
          );
        }
      } else {
        _enrichmentPending[generation] = remaining;
        if (stats.completedSinceFlush >= _internetArchiveEnrichmentBatchSize) {
          _flushQueuedEnrichments(generation);
          stats.completedSinceFlush = 0;
        }
      }
      _syncEnrichmentPending(generation);
      _finishPerformanceSessionIfTerminal();
    }
  }

  void _queueEnrichedPublication({
    required String sourceId,
    required String remoteId,
    required int generation,
    required RemoteCatalogPublicationSummary publication,
  }) {
    if (!_current(generation)) return;
    final bySource = _queuedEnrichments.putIfAbsent(generation, () => {});
    final replacements = bySource.putIfAbsent(sourceId, () => {});
    replacements[remoteId] = publication;
  }

  _InternetArchiveEnrichmentStats _statsFor(int generation) => _enrichmentStats
      .putIfAbsent(generation, _InternetArchiveEnrichmentStats.new);

  void _flushQueuedEnrichments(int generation) {
    if (!_current(generation)) return;
    final pending = _queuedEnrichments.remove(generation);
    if (pending == null || pending.isEmpty) return;
    final sources = <String, MultiCatalogSourceSearchState>{
      for (final entry in state.sources.entries)
        entry.key: _replaceQueuedPublications(entry.value, pending[entry.key]),
    };
    final accumulator = _canonicalAccumulator;
    if (accumulator == null) return;
    final replacements = <String, CanonicalBook>{};
    for (final sourceEntry in pending.entries) {
      for (final entry in sourceEntry.value.entries) {
        final replacement = accumulator.replacePublication(
          sourceId: sourceEntry.key,
          remoteId: entry.key,
          publication: entry.value,
        );
        if (replacement != null) {
          replacements[replacement.canonicalId] = replacement;
        }
      }
    }
    final replacementResults = materializeCanonicalSearchResults(
      books: replacements.values,
      sources: sources,
      presentationIds: accumulator.presentationIds,
      query: state.query,
      filters: state.filters,
      performanceSession: state.performanceSession,
    );
    final materialized =
        <MultiCatalogSearchResult>[
          for (final existing in state.materializedResults ?? const [])
            if (!replacements.containsKey(existing.canonicalBook.canonicalId))
              existing,
          ...replacementResults,
        ]..sort((left, right) {
          final relevance = catalogSearchRelevance(
            left.publication,
            state.query,
          ).compareTo(catalogSearchRelevance(right.publication, state.query));
          if (relevance != 0) return relevance;
          final leftDownloadable = left.source.supportsAcquisition;
          final rightDownloadable = right.source.supportsAcquisition;
          if (leftDownloadable != rightDownloadable) {
            return leftDownloadable ? -1 : 1;
          }
          return left.presentationIdentity.compareTo(
            right.presentationIdentity,
          );
        });
    state.performanceSession?.recordIndividualItemReplacement(
      replacements.length,
    );
    final stats = _enrichmentStats[generation];
    if (stats != null) {
      stats.visibleResults = materialized.length;
      stats.retainedEditions = materialized.fold<int>(
        0,
        (total, result) => total + result.canonicalBook.sources.length,
      );
    }
    onlinePerformanceMarker(
      'ia_enrichment_batch_applied',
      fields: {
        'generation': generation,
        'sources': pending.length,
        'records': pending.values.fold<int>(
          0,
          (total, replacements) => total + replacements.length,
        ),
        'visible': materialized.length,
      },
    );
    _emit(
      MultiCatalogSearchState(
        query: state.query,
        filters: state.filters,
        generation: state.generation,
        sources: sources,
        presentationIds: accumulator.presentationIds,
        enrichmentPending: _enrichmentPending[generation] ?? 0,
        performanceSession: state.performanceSession,
        materializedResults: List.unmodifiable(materialized),
      ),
      wholeListReplacement: false,
    );
  }

  MultiCatalogSourceSearchState _replaceQueuedPublications(
    MultiCatalogSourceSearchState entry,
    Map<String, RemoteCatalogPublicationSummary>? replacements,
  ) {
    final page = entry.page;
    if (page == null || replacements == null || replacements.isEmpty) {
      return entry;
    }
    return entry.copyWith(
      page: RemoteCatalogPage(
        sourceId: page.sourceId,
        location: page.location,
        title: page.title,
        navigation: page.navigation,
        publications: [
          for (final publication in page.publications)
            replacements[publication.remoteId] ?? publication,
        ],
        nextPageLocation: page.nextPageLocation,
        searchCapability: page.searchCapability,
      ),
    );
  }

  void _syncEnrichmentPending(int generation) {
    if (!_current(generation)) return;
    _emit(
      MultiCatalogSearchState(
        query: state.query,
        filters: state.filters,
        generation: state.generation,
        sources: state.sources,
        presentationIds: state.presentationIds,
        enrichmentPending: _enrichmentPending[generation] ?? 0,
        performanceSession: state.performanceSession,
        materializedResults: state.materializedResults,
      ),
    );
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  void _finishPerformanceSessionIfTerminal() {
    final current = state;
    if (_activePerformanceSession == null ||
        current.awaitingDebounce ||
        current.isLoading ||
        current.isEnriching ||
        current.hasMore) {
      return;
    }
    _finishPerformanceSession('completed');
  }

  /// Stops an active session without changing the visible search state.
  /// The route calls this only when it is disposed or backgrounded.
  void stopPerformanceForRouteDisposal() {
    _finishPerformanceSession('routeDisposed');
  }

  void stopPerformanceForLifecyclePause() {
    _finishPerformanceSession('lifecyclePaused');
  }

  String _newPerformanceSessionId(int generation) {
    final seed =
        '$generation:${DateTime.now().microsecondsSinceEpoch}:'
        '${identityHashCode(this)}';
    return sha256.convert(utf8.encode(seed)).toString().substring(0, 16);
  }

  void _emit(
    MultiCatalogSearchState next, {
    bool wholeListReplacement = false,
  }) {
    _activePerformanceSession?.recordStateEmission(
      wholeListReplacement: wholeListReplacement,
    );
    onlinePerformanceMarker(
      'search_state_emitted',
      fields: {
        'generation': next.generation,
        'results': next.materializedResults?.length ?? 0,
        'wholeList': wholeListReplacement,
      },
    );
    state = next;
  }

  void _finishPerformanceSession(String reason) {
    final performance = _activePerformanceSession;
    _activePerformanceSession = null;
    if (performance == null) return;
    if (reason == 'completed') {
      searchPerformanceHealth('terminal_detected');
    }
    searchPerformanceHealth('session_stop', fields: {'reason': reason});
    performance.finish(reason: reason);
  }

  // Search diagnostics are emitted exclusively through the aggregate,
  // credential-safe performance markers. Do not print query text or cursors.
  void _log(String _) {}

  RemoteCatalogPage _append(RemoteCatalogPage current, RemoteCatalogPage next) {
    final ids = current.publications.map((item) => item.remoteId).toSet();
    return RemoteCatalogPage(
      sourceId: current.sourceId,
      location: current.location,
      title: current.title,
      publications: [
        ...current.publications,
        ...next.publications.where((item) => ids.add(item.remoteId)),
      ],
      nextPageLocation: next.nextPageLocation,
      searchCapability: current.searchCapability,
    );
  }
}

String _sourceRecordKey(BookSourceRecord record) =>
    '${record.sourceId}\u0000${record.remoteId}';

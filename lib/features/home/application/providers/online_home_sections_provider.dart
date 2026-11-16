import 'dart:async';

import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway_provider.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:bibliolife/features/connectivity/application/app_connectivity_mode_provider.dart';
import 'package:bibliolife/features/home/application/providers/home_publication_page_cache.dart';
import 'package:bibliolife/features/home/domain/models/online_home_section.dart';
import 'package:bibliolife/features/home/domain/models/remote_home_publication_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const homeCatalogSourceId = 'builtin-project-gutenberg';

final onlineHomeSectionsProvider =
    NotifierProvider<
      OnlineHomeSectionsController,
      AsyncValue<List<OnlineHomeSection>>
    >(OnlineHomeSectionsController.new);

/// The Home catalog is scoped to one configured online library.  The family
/// identity is deliberately the stable library id, so changing Home's selected
/// library disposes the previous listener and makes late responses harmless.
final onlineHomeSectionsForLibraryProvider = NotifierProvider.autoDispose
    .family<
      OnlineHomeSectionsController,
      AsyncValue<List<OnlineHomeSection>>,
      String
    >(OnlineHomeSectionsController.forLibrary);

class OnlineHomeSectionsController
    extends Notifier<AsyncValue<List<OnlineHomeSection>>> {
  OnlineHomeSectionsController([this._sourceId = homeCatalogSourceId])
    : _reactToSourceEdits = false;

  OnlineHomeSectionsController.forLibrary(String sourceId)
    : _sourceId = sourceId,
      _reactToSourceEdits = true;

  static const _batchSize = 12;
  static const _inspectionLimit = 96;
  static const subsectionConcurrency = 4;
  static const _rootRetryDelay = Duration(milliseconds: 150);
  var _requestToken = 0;
  var _loadingMore = false;
  Future<void>? _initialLoad;
  CatalogSource? _source;
  RemoteCatalogPage? _sectionPage;
  _HomeContinuation _continuation = const _HomeContinuation();
  List<OnlineHomeSlot> _slots = const [];
  List<int> _reusableSlotIds = const [];
  var _nextSlotId = 0;
  var _nextSourceIndex = 0;
  final String _sourceId;
  final bool _reactToSourceEdits;

  @override
  AsyncValue<List<OnlineHomeSection>> build() {
    // A tab may be offstage while another Home tab is selected. Keep its
    // completed page state alive until the user hides that tab explicitly.
    if (_reactToSourceEdits) ref.keepAlive();
    final online = ref.watch(onlineAccessAllowedProvider);
    // The configured-library stream remains the source of truth.  A change to
    // this selected source rebuilds only its active family instance.
    if (_reactToSourceEdits) ref.watch(catalogSourcesProvider);
    ref.onDispose(() => _requestToken++);
    if (!online) {
      _requestToken++;
      _initialLoad = null;
      return const AsyncData([]);
    }
    unawaited(Future<void>.microtask(retry));
    return const AsyncLoading();
  }

  Future<void> retry() {
    final active = _initialLoad;
    if (active != null) return active;
    final operation = _load();
    _initialLoad = operation;
    return operation.whenComplete(() {
      if (identical(_initialLoad, operation)) _initialLoad = null;
    });
  }

  Future<void> loadMore() async {
    final sections = state.asData?.value;
    if (_loadingMore ||
        sections == null ||
        sections.isEmpty ||
        !sections.first.hasMore ||
        !ref.read(onlineAccessAllowedProvider)) {
      return;
    }
    _loadingMore = true;
    _log('automatic lookahead started: target=$subsectionConcurrency');
    final token = _requestToken;
    final current = sections.first;
    final continuationBeforeLoad = _continuation;
    final slotsBeforeLoad = _slots;
    final reusableSlotIdsBeforeLoad = _reusableSlotIds;
    final nextSlotIdBeforeLoad = _nextSlotId;
    final nextSourceIndexBeforeLoad = _nextSourceIndex;
    state = AsyncData([
      current.copyWith(isLoadingMore: true, loadMoreFailed: false),
    ]);
    try {
      final seen = current.books
          .map(
            (book) => RemoteHomePublicationIdentity.canonical(
              sourceId: book.sourceId,
              publication: book.publication,
            ),
          )
          .whereType<String>()
          .toSet();
      final additions = await _nextBatch(
        seen,
        token: token,
        targetSize: subsectionConcurrency,
        reserveSlots: true,
        onProgress: (partial) {
          if (token != _requestToken) return;
          state = AsyncData([
            current.copyWith(
              books: _slots.isEmpty
                  ? List.unmodifiable([
                      ...current.books,
                      ...partial.map(_toHomeBook),
                    ])
                  : _loadedSlotBooks(),
              isLoadingMore: true,
              loadMoreFailed: false,
              hasMore: true,
              slots: _slots,
            ),
          ]);
        },
      );
      if (token != _requestToken || state.asData?.value.isEmpty != false) {
        return;
      }
      final appended = additions.map(_toHomeBook).toList(growable: false);
      state = AsyncData([
        current.copyWith(
          books: _slots.isEmpty
              ? List.unmodifiable([...current.books, ...appended])
              : _loadedSlotBooks(),
          isLoadingMore: false,
          loadMoreFailed: false,
          hasMore: _continuation.hasMore,
          slots: _slots,
        ),
      ]);
      assert(_hasUniqueIdentities(state.requireValue.first.books));
    } catch (_) {
      if (token != _requestToken || state.asData?.value.isEmpty != false) {
        return;
      }
      _requestToken++;
      // A recoverable continuation failure must be transactional: keep the
      // visible page and retry exactly the same continuation later.
      _continuation = continuationBeforeLoad;
      _slots = slotsBeforeLoad;
      _reusableSlotIds = reusableSlotIdsBeforeLoad;
      _nextSlotId = nextSlotIdBeforeLoad;
      _nextSourceIndex = nextSourceIndexBeforeLoad;
      state = AsyncData([
        current.copyWith(
          isLoadingMore: false,
          loadMoreFailed: true,
          hasMore: true,
        ),
      ]);
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> _load() async {
    if (!ref.read(onlineAccessAllowedProvider)) return;
    final token = ++_requestToken;
    _source = null;
    _sectionPage = null;
    _continuation = const _HomeContinuation();
    _slots = const [];
    _reusableSlotIds = const [];
    _nextSlotId = 0;
    _nextSourceIndex = 0;
    state = const AsyncLoading();
    final elapsed = Stopwatch()..start();
    try {
      _log('initial load started t=0ms');
      final repository = ref.read(catalogSourceRepositoryProvider);
      final source =
          await repository.getById(_sourceId) ??
          (!_reactToSourceEdits
              ? (await repository.getAll()).firstOrNull
              : null);
      if (token != _requestToken) return;
      if (source == null) {
        throw const RemoteCatalogException(RemoteCatalogFailure.sourceNotFound);
      }
      // isEnabled is the existing Search/acquisition selection. Home
      // discovery has its own persisted preference, so it must not be blocked
      // merely because this provider was switched off in Search settings.
      final homeSource = source.isEnabled
          ? source
          : source.copyWith(isEnabled: true);
      _source = homeSource;
      _log('source resolved: ${source.id} t=${elapsed.elapsedMilliseconds}ms');
      final initialReusableSlotIds = [
        for (var index = 0; index < subsectionConcurrency; index++)
          _reserveVisualSlot(null).slotId,
      ];
      _emitInitialPendingSection(homeSource);
      _log('pending slots emitted: count=${initialReusableSlotIds.length}');
      // Give Flutter an event-loop turn to schedule a frame for the immutable
      // pending snapshot before starting the root network request. This is not
      // a visible delay and cached responses are still consumed immediately.
      await Future<void>.delayed(Duration.zero);
      if (token != _requestToken) return;
      final rootStartedAt = elapsed.elapsedMilliseconds;
      final page = await _loadRootWithRetry(homeSource, token);
      if (token != _requestToken) return;
      _sectionPage = page;
      _log(
        'root loaded: publications=${page.publications.length}, '
        'navigation=${page.navigation.length}, next=${page.nextPageLocation != null}, '
        'duration=${elapsed.elapsedMilliseconds - rootStartedAt}ms, '
        't=${elapsed.elapsedMilliseconds}ms',
      );
      _continuation = _HomeContinuation(
        pendingPublications: _usable(page.publications).toList(growable: false),
        pendingNavigation: page.navigation,
        nextPage: page.nextPageLocation,
        visitedPages: {page.location.toString()},
      );
      final publications = await _nextBatch(
        <String>{},
        skipNavigationFailures: true,
        token: token,
        reserveSlots: true,
        reusableSlotIds: initialReusableSlotIds,
        onProgress: (partial) {
          if (token != _requestToken || partial.isEmpty) return;
          _emitInitialSection(
            source: homeSource,
            page: page,
            publications: partial,
            isResolving: true,
          );
          _log(
            'initial progress: publications=${partial.length}, '
            't=${elapsed.elapsedMilliseconds}ms',
          );
        },
      );
      if (token != _requestToken) return;
      _log(
        'initial batch loaded: publications=${publications.length}, '
        'hasMore=${_continuation.hasMore}, '
        'cacheHits=${ref.read(homePublicationPageCacheProvider).hits}, '
        't=${elapsed.elapsedMilliseconds}ms',
      );
      _emitInitialSection(
        source: homeSource,
        page: page,
        publications: publications,
        isResolving: false,
      );
    } catch (error, stackTrace) {
      if (token == _requestToken) {
        _logFailure('initial load failed', error, stackTrace);
        state = AsyncError(error, stackTrace);
      }
    }
  }

  Future<RemoteCatalogPage> _loadRootWithRetry(
    CatalogSource source,
    int token,
  ) async {
    try {
      return await ref.read(remoteCatalogGatewayProvider).loadRoot(source);
    } on RemoteCatalogException catch (error) {
      if (!_isTransientRoot(error) || token != _requestToken) rethrow;
      _log('root transient failure: ${error.failure.name}; retry=1');
      await Future<void>.delayed(_rootRetryDelay);
      if (token != _requestToken) rethrow;
      return ref.read(remoteCatalogGatewayProvider).loadRoot(source);
    }
  }

  bool _isTransientRoot(RemoteCatalogException error) {
    if (error.failure == RemoteCatalogFailure.timeout) return true;
    if (error.failure != RemoteCatalogFailure.httpStatus) return false;
    final message = error.message ?? '';
    return RegExp(r'HTTP (?:502|503|504)\b').hasMatch(message);
  }

  void _emitInitialSection({
    required CatalogSource source,
    required RemoteCatalogPage page,
    required List<RemoteCatalogPublicationSummary> publications,
    required bool isResolving,
  }) {
    state = AsyncData([
      OnlineHomeSection(
        id: source.id,
        title: source.name,
        searchCapability: page.searchCapability,
        ranking: page.homeRanking,
        books: _slots.isEmpty
            ? publications.map(_toHomeBook).toList(growable: false)
            : _loadedSlotBooks(),
        hasMore: _continuation.hasMore,
        isInitialResolving: isResolving,
        slots: _slots,
      ),
    ]);
  }

  void _emitInitialPendingSection(CatalogSource source) {
    state = AsyncData([
      OnlineHomeSection(
        id: source.id,
        title: source.name,
        searchCapability: const RemoteCatalogSearchCapability.unsupported(),
        ranking: null,
        books: const [],
        hasMore: true,
        isInitialResolving: true,
        slots: _slots,
      ),
    ]);
  }

  OnlineHomeBook _toHomeBook(RemoteCatalogPublicationSummary publication) {
    final source = _source!;
    return OnlineHomeBook(
      sourceId: source.id,
      sourceName: source.name,
      publication: publication,
    );
  }

  Future<List<RemoteCatalogPublicationSummary>> _nextBatch(
    Set<String> existingIdentities, {
    bool skipNavigationFailures = false,
    required int token,
    int targetSize = _batchSize,
    bool reserveSlots = false,
    List<int> reusableSlotIds = const [],
    void Function(List<RemoteCatalogPublicationSummary>)? onProgress,
  }) async {
    final source = _source!;
    final result = <RemoteCatalogPublicationSummary>[];
    final progress = _ProgressEmitter<List<RemoteCatalogPublicationSummary>>(
      onProgress,
    );
    Object? firstNavigationError;
    StackTrace? firstNavigationStackTrace;
    var inspected = 0;
    final availableReusableSlotIds = [
      ...reusableSlotIds,
      ..._reusableSlotIds.where((id) => !reusableSlotIds.contains(id)),
    ];
    while (result.length < targetSize &&
        _continuation.hasMore &&
        inspected < _inspectionLimit) {
      if (_continuation.pendingPublications.isNotEmpty) {
        final publication = _continuation.pendingPublications.first;
        _continuation = _continuation.copyWith(
          pendingPublications: _continuation.pendingPublications.skip(1),
        );
        inspected++;
        final identity = RemoteHomePublicationIdentity.canonical(
          sourceId: source.id,
          publication: publication,
        );
        if (identity != null && existingIdentities.add(identity)) {
          if (reserveSlots) {
            final attempt = _reserveVisualSlot(
              availableReusableSlotIds.isEmpty
                  ? null
                  : availableReusableSlotIds.removeAt(0),
            );
            final index = _slots.indexWhere(
              (slot) =>
                  slot.slotId == attempt.slotId &&
                  slot.attempt == attempt.attempt,
            );
            final updated = [..._slots]
              ..[index] = _slots[index].fill(_toHomeBook(publication));
            _slots = List.unmodifiable(updated);
            _emitSlotSnapshot();
          }
          result.add(publication);
          progress.add(List.unmodifiable(result));
        }
        continue;
      }
      if (_continuation.pendingNavigation.isNotEmpty) {
        final remaining = targetSize - result.length;
        final windowSize = remaining < subsectionConcurrency
            ? remaining
            : subsectionConcurrency;
        final window = _continuation.pendingNavigation
            .take(windowSize)
            .toList(growable: false);
        _continuation = _continuation.copyWith(
          pendingNavigation: _continuation.pendingNavigation.skip(
            window.length,
          ),
        );
        final attempts = <_VisualSlotAttempt?>[
          for (var index = 0; index < window.length; index++)
            reserveSlots
                ? _reserveVisualSlot(
                    availableReusableSlotIds.isEmpty
                        ? null
                        : availableReusableSlotIds.removeAt(0),
                  )
                : null,
        ];
        if (reserveSlots) {
          _emitSlotSnapshot();
          _log(
            'pending slots emitted: count=${_slots.where((slot) => slot.isPending).length}',
          );
        }
        final requests = [
          for (var index = 0; index < window.length; index++)
            _loadNavigationPage(source, window[index].location)
                .then(
                  _NavigationResult.success,
                  onError: (Object error, StackTrace stackTrace) =>
                      _NavigationResult.failure(error, stackTrace),
                )
                .then((resolved) {
                  final attempt = attempts[index];
                  if (attempt != null) {
                    _completeVisualSlot(attempt, resolved, token);
                  }
                  return resolved;
                }),
        ];
        for (var index = 0; index < requests.length; index++) {
          if (token != _requestToken) return result;
          final resolved = await requests[index];
          final page = resolved.page;
          if (page != null) {
            _continuation = _continuation.copyWith(
              pendingPublications: [
                ..._continuation.pendingPublications,
                ..._usable(page.publications),
              ],
            );
          } else {
            final attempt = attempts[index];
            if (attempt != null) availableReusableSlotIds.add(attempt.slotId);
            final error = resolved.error!;
            final stackTrace = resolved.stackTrace!;
            if (!skipNavigationFailures &&
                (error is! RemoteCatalogException ||
                    !_isSkippableOptional(error.failure))) {
              _continuation = _continuation.copyWith(
                pendingNavigation: [
                  window[index],
                  ...window.skip(index + 1),
                  ..._continuation.pendingNavigation,
                ],
              );
              Error.throwWithStackTrace(error, stackTrace);
            }
            firstNavigationError ??= error;
            firstNavigationStackTrace ??= stackTrace;
            _logFailure('optional navigation page skipped', error, stackTrace);
          }
          inspected++;
          while (result.length < targetSize &&
              _continuation.pendingPublications.isNotEmpty) {
            final publication = _continuation.pendingPublications.first;
            _continuation = _continuation.copyWith(
              pendingPublications: _continuation.pendingPublications.skip(1),
            );
            final identity = RemoteHomePublicationIdentity.canonical(
              sourceId: source.id,
              publication: publication,
            );
            if (identity != null && existingIdentities.add(identity)) {
              result.add(publication);
              progress.add(List.unmodifiable(result));
            }
          }
          if (result.length >= targetSize) {
            _continuation = _continuation.copyWith(
              pendingNavigation: [
                ...window.skip(index + 1),
                ..._continuation.pendingNavigation,
              ],
            );
            break;
          }
        }
        continue;
      }
      final next = _continuation.nextPage;
      if (next == null) break;
      final identity = next.toString();
      if (_continuation.visitedPages.contains(identity)) {
        _continuation = _continuation.copyWith(clearNextPage: true);
        continue;
      }
      final page = await ref
          .read(remoteCatalogGatewayProvider)
          .loadPage(source: source, location: next);
      _continuation = _continuation.copyWith(
        pendingPublications: _usable(page.publications),
        pendingNavigation: page.navigation,
        nextPage: page.nextPageLocation,
        clearNextPage: page.nextPageLocation == null,
        visitedPages: {..._continuation.visitedPages, identity},
      );
      inspected++;
    }
    if (result.isEmpty &&
        !_continuation.hasMore &&
        firstNavigationError != null) {
      Error.throwWithStackTrace(
        firstNavigationError,
        firstNavigationStackTrace ?? StackTrace.current,
      );
    }
    await progress.flush();
    if (reserveSlots) {
      if (_continuation.hasMore) {
        _reusableSlotIds = List.unmodifiable(availableReusableSlotIds);
      } else {
        _reusableSlotIds = const [];
        _slots = List.unmodifiable(_slots.where((slot) => !slot.isPending));
        _emitSlotSnapshot();
      }
    }
    return result;
  }

  _VisualSlotAttempt _reserveVisualSlot(int? reusableSlotId) {
    if (reusableSlotId == null) {
      final slot = OnlineHomeSlot.pending(
        slotId: _nextSlotId++,
        sourceIndex: _nextSourceIndex++,
        attempt: 0,
      );
      _slots = List.unmodifiable([..._slots, slot]);
      _log(
        'slot reserved: id=${slot.slotId}, source=${slot.sourceIndex}, '
        'attempt=${slot.attempt}',
      );
      return _VisualSlotAttempt(slot.slotId, slot.attempt);
    }
    final index = _slots.indexWhere((slot) => slot.slotId == reusableSlotId);
    final reassigned = _slots[index].reassign(_nextSourceIndex++);
    final updated = [..._slots]..[index] = reassigned;
    _slots = List.unmodifiable(updated);
    _log(
      'slot reassigned: id=${reassigned.slotId}, '
      'source=${reassigned.sourceIndex}, attempt=${reassigned.attempt}',
    );
    return _VisualSlotAttempt(reassigned.slotId, reassigned.attempt);
  }

  void _completeVisualSlot(
    _VisualSlotAttempt attempt,
    _NavigationResult resolved,
    int token,
  ) {
    if (token != _requestToken || resolved.page == null) return;
    final index = _slots.indexWhere(
      (slot) =>
          slot.slotId == attempt.slotId && slot.attempt == attempt.attempt,
    );
    if (index < 0) return;
    final publication = _usable(resolved.page!.publications).firstOrNull;
    if (publication == null) return;
    final identity = RemoteHomePublicationIdentity.canonical(
      sourceId: _source!.id,
      publication: publication,
    );
    final duplicate = _slots.any((slot) {
      final book = slot.book;
      return book != null &&
          RemoteHomePublicationIdentity.canonical(
                sourceId: book.sourceId,
                publication: book.publication,
              ) ==
              identity;
    });
    if (identity == null || duplicate) return;
    final updated = [..._slots]
      ..[index] = _slots[index].fill(_toHomeBook(publication));
    _slots = List.unmodifiable(updated);
    _log(
      'slot filled: id=${attempt.slotId}, attempt=${attempt.attempt}, '
      'loaded=${_slots.where((slot) => !slot.isPending).length}',
    );
    _emitSlotSnapshot();
  }

  void _emitSlotSnapshot() {
    final page = _sectionPage;
    final source = _source;
    if (page == null || source == null) return;
    final current = state.asData?.value.firstOrNull;
    final books = _loadedSlotBooks();
    state = AsyncData([
      OnlineHomeSection(
        id: source.id,
        title: source.name,
        searchCapability: page.searchCapability,
        ranking: page.homeRanking,
        books: books,
        slots: _slots,
        isInitialResolving: current?.isInitialResolving ?? true,
        isLoadingMore: current?.isLoadingMore ?? false,
        loadMoreFailed: current?.loadMoreFailed ?? false,
        hasMore: true,
      ),
    ]);
  }

  List<OnlineHomeBook> _loadedSlotBooks() => _slots
      .map((slot) => slot.book)
      .whereType<OnlineHomeBook>()
      .toList(growable: false);

  Future<RemoteCatalogPage> _loadNavigationPage(
    CatalogSource source,
    RemoteCatalogLocation location,
  ) async {
    final cache = ref.read(homePublicationPageCacheProvider);
    final cached = cache.read(location);
    if (cached != null) return cached;
    final page = await ref
        .read(remoteCatalogGatewayProvider)
        .loadPage(source: source, location: location);
    cache.write(location, page);
    return page;
  }

  void _log(String message) {
    if (!kReleaseMode) {
      debugPrint('[HomeOnlineCatalog] $message');
    }
  }

  bool _isSkippableOptional(RemoteCatalogFailure failure) =>
      failure == RemoteCatalogFailure.emptyResponse ||
      failure == RemoteCatalogFailure.unsupportedCatalogFormat ||
      failure == RemoteCatalogFailure.malformedCatalogResponse;

  void _logFailure(String boundary, Object error, StackTrace stackTrace) {
    if (kReleaseMode) return;
    final category = error is RemoteCatalogException
        ? error.failure.name
        : error.runtimeType.toString();
    debugPrint('[HomeOnlineCatalog] $boundary: $category');
    debugPrintStack(
      label: '[HomeOnlineCatalog] stack',
      stackTrace: stackTrace,
      maxFrames: 12,
    );
  }

  bool _hasUniqueIdentities(List<OnlineHomeBook> books) {
    final identities = books
        .map(
          (book) => RemoteHomePublicationIdentity.canonical(
            sourceId: book.sourceId,
            publication: book.publication,
          ),
        )
        .whereType<String>()
        .toList(growable: false);
    return identities.length == identities.toSet().length;
  }

  Iterable<RemoteCatalogPublicationSummary> _usable(
    Iterable<RemoteCatalogPublicationSummary> publications,
  ) => publications.where(
    (publication) =>
        publication.title.trim().isNotEmpty &&
        (publication.detailsLocation != null ||
            publication.acquisitions.isNotEmpty) &&
        RemoteHomePublicationIdentity.canonical(
              sourceId: _source!.id,
              publication: publication,
            ) !=
            null,
  );
}

class _HomeContinuation {
  const _HomeContinuation({
    this.pendingPublications = const [],
    this.pendingNavigation = const [],
    this.nextPage,
    this.visitedPages = const {},
  });

  final List<RemoteCatalogPublicationSummary> pendingPublications;
  final List<RemoteCatalogNavigationLink> pendingNavigation;
  final RemoteCatalogLocation? nextPage;
  final Set<String> visitedPages;

  bool get hasMore =>
      pendingPublications.isNotEmpty ||
      pendingNavigation.isNotEmpty ||
      nextPage != null;

  _HomeContinuation copyWith({
    Iterable<RemoteCatalogPublicationSummary>? pendingPublications,
    Iterable<RemoteCatalogNavigationLink>? pendingNavigation,
    RemoteCatalogLocation? nextPage,
    bool clearNextPage = false,
    Iterable<String>? visitedPages,
  }) => _HomeContinuation(
    pendingPublications: List.unmodifiable(
      pendingPublications ?? this.pendingPublications,
    ),
    pendingNavigation: List.unmodifiable(
      pendingNavigation ?? this.pendingNavigation,
    ),
    nextPage: clearNextPage ? null : nextPage ?? this.nextPage,
    visitedPages: Set.unmodifiable(visitedPages ?? this.visitedPages),
  );
}

class _NavigationResult {
  const _NavigationResult.success(this.page) : error = null, stackTrace = null;

  const _NavigationResult.failure(this.error, this.stackTrace) : page = null;

  final RemoteCatalogPage? page;
  final Object? error;
  final StackTrace? stackTrace;
}

class _VisualSlotAttempt {
  const _VisualSlotAttempt(this.slotId, this.attempt);

  final int slotId;
  final int attempt;
}

class _ProgressEmitter<T> {
  _ProgressEmitter(this._emit);

  final void Function(T value)? _emit;
  T? _pending;
  Completer<void>? _scheduled;

  void add(T value) {
    if (_emit == null) return;
    _pending = value;
    if (_scheduled != null) return;
    final scheduled = Completer<void>();
    _scheduled = scheduled;
    scheduleMicrotask(() {
      final pending = _pending;
      _pending = null;
      _scheduled = null;
      if (pending != null) _emit(pending);
      scheduled.complete();
    });
  }

  Future<void> flush() => _scheduled?.future ?? Future<void>.value();
}

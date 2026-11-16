import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway_provider.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const maximumCatalogSearchQueryLength = 200;

final catalogSearchControllerProvider = NotifierProvider.autoDispose
    .family<CatalogSearchController, CatalogSearchState, String>(
      CatalogSearchController.new,
    );

enum CatalogSearchLoading { idle, searching, nextPage }

class CatalogSearchState {
  const CatalogSearchState({
    required this.sourceId,
    this.sourceName,
    this.query = '',
    this.lastSuccessfulQuery,
    this.capability = const RemoteCatalogSearchCapability.unsupported(),
    this.initialized = false,
    this.page,
    this.loading = CatalogSearchLoading.idle,
    this.failure,
    this.validationMessage,
  });

  final String sourceId;
  final String? sourceName;
  final String query;
  final String? lastSuccessfulQuery;
  final RemoteCatalogSearchCapability capability;
  final bool initialized;
  final RemoteCatalogPage? page;
  final CatalogSearchLoading loading;
  final RemoteCatalogFailure? failure;
  final String? validationMessage;

  bool get isLoading => loading != CatalogSearchLoading.idle;
  bool get isSupported => capability.isSupported;
  bool get hasNextPage => page?.nextPageLocation != null;

  CatalogSearchState copyWith({
    String? sourceName,
    String? query,
    String? lastSuccessfulQuery,
    RemoteCatalogSearchCapability? capability,
    bool? initialized,
    RemoteCatalogPage? page,
    bool clearPage = false,
    CatalogSearchLoading? loading,
    RemoteCatalogFailure? failure,
    bool clearFailure = false,
    String? validationMessage,
    bool clearValidation = false,
  }) => CatalogSearchState(
    sourceId: sourceId,
    sourceName: sourceName ?? this.sourceName,
    query: query ?? this.query,
    lastSuccessfulQuery: lastSuccessfulQuery ?? this.lastSuccessfulQuery,
    capability: capability ?? this.capability,
    initialized: initialized ?? this.initialized,
    page: clearPage ? null : page ?? this.page,
    loading: loading ?? this.loading,
    failure: clearFailure ? null : failure ?? this.failure,
    validationMessage: clearValidation
        ? null
        : validationMessage ?? this.validationMessage,
  );
}

class CatalogSearchController extends Notifier<CatalogSearchState> {
  CatalogSearchController(this._sourceId);
  final String _sourceId;
  var _token = 0;
  var _disposed = false;
  String? _pendingQuery;
  bool _retryNext = false;

  @override
  CatalogSearchState build() {
    ref.onDispose(() {
      _disposed = true;
      _token++;
    });
    return CatalogSearchState(sourceId: _sourceId);
  }

  Future<void> initialize(RemoteCatalogSearchCapability capability) async {
    if (state.initialized) return;
    final source = await _source();
    if (_disposed) return;
    state = state.copyWith(
      sourceName: source?.name,
      capability: capability,
      initialized: true,
      failure: source == null ? RemoteCatalogFailure.sourceNotFound : null,
      clearFailure: source != null,
    );
  }

  void setQuery(String value) {
    state = state.copyWith(query: value, clearValidation: true);
  }

  Future<void> submit([String? value]) async {
    final query = (value ?? state.query).trim();
    state = state.copyWith(query: query, clearValidation: true);
    if (query.isEmpty) {
      state = state.copyWith(validationMessage: 'Enter a search query.');
      return;
    }
    if (query.length > maximumCatalogSearchQueryLength) {
      state = state.copyWith(
        validationMessage:
            'Search queries must be $maximumCatalogSearchQueryLength characters or fewer.',
      );
      return;
    }
    if (!state.isSupported) {
      state = state.copyWith(failure: RemoteCatalogFailure.searchUnsupported);
      return;
    }
    if (_pendingQuery == query) return;
    final source = await _source();
    if (source == null) return;
    final token = ++_token;
    _pendingQuery = query;
    _retryNext = false;
    state = state.copyWith(
      loading: CatalogSearchLoading.searching,
      clearFailure: true,
    );
    try {
      final page = await ref
          .read(remoteCatalogGatewayProvider)
          .search(source: source, capability: state.capability, query: query);
      if (!_current(token)) return;
      state = state.copyWith(
        page: page,
        lastSuccessfulQuery: query,
        loading: CatalogSearchLoading.idle,
        clearFailure: true,
      );
    } on RemoteCatalogException catch (error) {
      if (_current(token)) {
        state = state.copyWith(
          failure: error.failure,
          loading: CatalogSearchLoading.idle,
        );
      }
    } finally {
      if (_current(token)) _pendingQuery = null;
    }
  }

  Future<void> loadNextPage() async {
    final next = state.page?.nextPageLocation;
    final query = state.lastSuccessfulQuery;
    if (next == null || query == null || _pendingQuery == query) return;
    final source = await _source();
    if (source == null) return;
    final token = ++_token;
    _pendingQuery = query;
    _retryNext = true;
    state = state.copyWith(
      loading: CatalogSearchLoading.nextPage,
      clearFailure: true,
    );
    try {
      final nextPage = await ref
          .read(remoteCatalogGatewayProvider)
          .loadPage(source: source, location: next);
      if (!_current(token)) return;
      state = state.copyWith(
        page: _append(state.page!, nextPage),
        loading: CatalogSearchLoading.idle,
        clearFailure: true,
      );
    } on RemoteCatalogException catch (error) {
      if (_current(token)) {
        state = state.copyWith(
          failure: error.failure,
          loading: CatalogSearchLoading.idle,
        );
      }
    } finally {
      if (_current(token)) _pendingQuery = null;
    }
  }

  Future<void> retry() => _retryNext ? loadNextPage() : submit(state.query);

  void clear() {
    _token++;
    _pendingQuery = null;
    state = CatalogSearchState(
      sourceId: state.sourceId,
      sourceName: state.sourceName,
      capability: state.capability,
      initialized: state.initialized,
    );
  }

  Future<CatalogSource?> _source() async {
    final source = await ref
        .read(catalogSourceRepositoryProvider)
        .getById(state.sourceId);
    if (source == null) {
      state = state.copyWith(failure: RemoteCatalogFailure.sourceNotFound);
    } else if (!source.isEnabled) {
      state = state.copyWith(failure: RemoteCatalogFailure.sourceDisabled);
      return null;
    }
    return source;
  }

  bool _current(int token) => !_disposed && token == _token;

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

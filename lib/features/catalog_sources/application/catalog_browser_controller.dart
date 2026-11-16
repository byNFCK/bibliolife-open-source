import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway_provider.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final catalogBrowserControllerProvider = NotifierProvider.autoDispose
    .family<CatalogBrowserController, CatalogBrowserState, String>(
      CatalogBrowserController.new,
    );

enum CatalogBrowserLoading { idle, initial, navigation, nextPage, refresh }

enum _RetryOperation { current, nextPage }

class CatalogBrowserState {
  const CatalogBrowserState({
    required this.sourceId,
    this.sourceName,
    this.location,
    this.page,
    this.loading = CatalogBrowserLoading.idle,
    this.failure,
    this.history = const [],
  });

  final String sourceId;
  final String? sourceName;
  final RemoteCatalogLocation? location;
  final RemoteCatalogPage? page;
  final CatalogBrowserLoading loading;
  final RemoteCatalogFailure? failure;
  final List<RemoteCatalogPage> history;

  bool get isLoading => loading != CatalogBrowserLoading.idle;
  bool get canGoBack => history.isNotEmpty;
  bool get hasNextPage => page?.nextPageLocation != null;

  CatalogBrowserState copyWith({
    String? sourceName,
    RemoteCatalogLocation? location,
    RemoteCatalogPage? page,
    CatalogBrowserLoading? loading,
    RemoteCatalogFailure? failure,
    bool clearFailure = false,
    List<RemoteCatalogPage>? history,
  }) => CatalogBrowserState(
    sourceId: sourceId,
    sourceName: sourceName ?? this.sourceName,
    location: location ?? this.location,
    page: page ?? this.page,
    loading: loading ?? this.loading,
    failure: clearFailure ? null : failure ?? this.failure,
    history: List.unmodifiable(history ?? this.history),
  );
}

class CatalogBrowserController extends Notifier<CatalogBrowserState> {
  CatalogBrowserController(this._sourceId);

  final String _sourceId;
  var _requestToken = 0;
  var _disposed = false;
  RemoteCatalogLocation? _pendingLocation;
  _RetryOperation _retryOperation = _RetryOperation.current;

  @override
  CatalogBrowserState build() {
    ref.onDispose(() {
      _disposed = true;
      _requestToken++;
    });
    return CatalogBrowserState(sourceId: _sourceId);
  }

  Future<void> openRoot() async {
    if (state.loading == CatalogBrowserLoading.initial) return;
    final token = ++_requestToken;
    state = state.copyWith(
      loading: CatalogBrowserLoading.initial,
      clearFailure: true,
    );
    final source = await ref
        .read(catalogSourceRepositoryProvider)
        .getById(state.sourceId);
    if (!_isCurrent(token)) return;
    if (source == null) {
      _fail(RemoteCatalogFailure.sourceNotFound);
      return;
    }
    state = state.copyWith(sourceName: source.name);
    if (!source.isEnabled) {
      _fail(RemoteCatalogFailure.sourceDisabled);
      return;
    }
    final location = _sourceLocation(source);
    if (location == null) {
      _fail(RemoteCatalogFailure.invalidSourceOrLocation);
      return;
    }
    await _request(
      source: source,
      location: location,
      loading: CatalogBrowserLoading.initial,
      token: token,
      root: true,
    );
  }

  Future<void> openNavigation(RemoteCatalogLocation location) async {
    if (_isDuplicate(location)) return;
    _pendingLocation = location;
    final source = await _validatedSource();
    if (source == null) {
      _pendingLocation = null;
      return;
    }
    final token = ++_requestToken;
    await _request(
      source: source,
      location: location,
      loading: CatalogBrowserLoading.navigation,
      token: token,
      pushCurrentPage: true,
    );
  }

  Future<void> refresh() async {
    final location = state.location;
    if (location == null || _isDuplicate(location)) return;
    _pendingLocation = location;
    final source = await _validatedSource();
    if (source == null) {
      _pendingLocation = null;
      return;
    }
    final token = ++_requestToken;
    await _request(
      source: source,
      location: location,
      loading: CatalogBrowserLoading.refresh,
      token: token,
    );
  }

  Future<void> loadNextPage() async {
    final next = state.page?.nextPageLocation;
    if (next == null || _isDuplicate(next)) return;
    _pendingLocation = next;
    final source = await _validatedSource();
    if (source == null) {
      _pendingLocation = null;
      return;
    }
    final token = ++_requestToken;
    _retryOperation = _RetryOperation.nextPage;
    _pendingLocation = next;
    state = state.copyWith(
      loading: CatalogBrowserLoading.nextPage,
      clearFailure: true,
    );
    try {
      final page = await ref
          .read(remoteCatalogGatewayProvider)
          .loadPage(source: source, location: next);
      if (!_isCurrent(token)) return;
      state = state.copyWith(
        location: page.location,
        page: _append(state.page!, page),
        loading: CatalogBrowserLoading.idle,
        clearFailure: true,
      );
    } on RemoteCatalogException catch (error) {
      if (_isCurrent(token)) _fail(error.failure);
    } finally {
      if (_isCurrent(token)) _pendingLocation = null;
    }
  }

  Future<void> retry() {
    if (_retryOperation == _RetryOperation.nextPage) return loadNextPage();
    return state.location == null ? openRoot() : refresh();
  }

  void goBack() {
    if (state.history.isEmpty) return;
    _requestToken++;
    _pendingLocation = null;
    final history = [...state.history];
    final previous = history.removeLast();
    state = state.copyWith(
      location: previous.location,
      page: previous,
      loading: CatalogBrowserLoading.idle,
      clearFailure: true,
      history: history,
    );
  }

  Future<void> _request({
    required CatalogSource source,
    required RemoteCatalogLocation location,
    required CatalogBrowserLoading loading,
    required int token,
    bool root = false,
    bool pushCurrentPage = false,
  }) async {
    _retryOperation = _RetryOperation.current;
    _pendingLocation = location;
    state = state.copyWith(loading: loading, clearFailure: true);
    try {
      final page = root
          ? await ref.read(remoteCatalogGatewayProvider).loadRoot(source)
          : await ref
                .read(remoteCatalogGatewayProvider)
                .loadPage(source: source, location: location);
      if (!_isCurrent(token)) return;
      final history = pushCurrentPage && state.page != null
          ? [...state.history, state.page!]
          : state.history;
      state = state.copyWith(
        sourceName: source.name,
        location: page.location,
        page: page,
        loading: CatalogBrowserLoading.idle,
        clearFailure: true,
        history: history,
      );
    } on RemoteCatalogException catch (error) {
      if (_isCurrent(token)) _fail(error.failure);
    } finally {
      if (_isCurrent(token)) _pendingLocation = null;
    }
  }

  Future<CatalogSource?> _validatedSource() async {
    final source = await ref
        .read(catalogSourceRepositoryProvider)
        .getById(state.sourceId);
    if (source == null) {
      _fail(RemoteCatalogFailure.sourceNotFound);
      return null;
    }
    if (!source.isEnabled) {
      _fail(RemoteCatalogFailure.sourceDisabled);
      return null;
    }
    if (_sourceLocation(source) == null) {
      _fail(RemoteCatalogFailure.invalidSourceOrLocation);
      return null;
    }
    return source;
  }

  RemoteCatalogLocation? _sourceLocation(CatalogSource source) {
    try {
      return RemoteCatalogLocation.fromUri(source.baseUri);
    } on FormatException {
      return null;
    }
  }

  bool _isDuplicate(RemoteCatalogLocation location) =>
      _pendingLocation == location;

  bool _isCurrent(int token) => !_disposed && token == _requestToken;

  void _fail(RemoteCatalogFailure failure) {
    state = state.copyWith(
      loading: CatalogBrowserLoading.idle,
      failure: failure,
    );
  }

  RemoteCatalogPage _append(RemoteCatalogPage current, RemoteCatalogPage next) {
    final publicationIds = current.publications
        .map((item) => item.remoteId)
        .toSet();
    final navigationLocations = current.navigation
        .map((item) => item.location)
        .toSet();
    return RemoteCatalogPage(
      sourceId: current.sourceId,
      location: current.location,
      title: current.title,
      navigation: [
        ...current.navigation,
        ...next.navigation.where(
          (item) => navigationLocations.add(item.location),
        ),
      ],
      publications: [
        ...current.publications,
        ...next.publications.where((item) => publicationIds.add(item.remoteId)),
      ],
      nextPageLocation: next.nextPageLocation,
    );
  }
}

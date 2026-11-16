import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_search_controller.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:bibliolife/features/catalog_sources/presentation/widgets/remote_catalog_publication_sliver.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/remote_publication_details_screen.dart';
import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CatalogSearchScreen extends ConsumerStatefulWidget {
  const CatalogSearchScreen({
    required this.sourceId,
    required this.capability,
    super.key,
  });
  final String sourceId;
  final RemoteCatalogSearchCapability capability;

  @override
  ConsumerState<CatalogSearchScreen> createState() =>
      _CatalogSearchScreenState();
}

class _CatalogSearchScreenState extends ConsumerState<CatalogSearchScreen> {
  final _query = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(catalogSearchControllerProvider(widget.sourceId).notifier)
            .initialize(widget.capability);
      }
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = catalogSearchControllerProvider(widget.sourceId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final showResults =
        state.isSupported &&
        state.loading != CatalogSearchLoading.searching &&
        state.failure == null &&
        state.page != null &&
        state.page!.publications.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text('Search ${state.sourceName ?? 'library'}')),
      body: SafeArea(
        child: _CatalogSearchScrollView(
          key: ValueKey(widget.sourceId),
          sourceId: widget.sourceId,
          successfulQuery: state.lastSuccessfulQuery,
          page: state.page,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Semantics(
                        container: true,
                        explicitChildNodes: true,
                        liveRegion: true,
                        label: showResults
                            ? '${state.page!.publications.length} search results'
                            : null,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SearchBar(
                              controller: _query,
                              focusNode: _focusNode,
                              hintText: 'Search this library',
                              onChanged: controller.setQuery,
                              onSubmitted: controller.submit,
                              trailing: [
                                IconButton(
                                  tooltip: 'Submit catalog search',
                                  onPressed: state.isLoading
                                      ? null
                                      : () => controller.submit(_query.text),
                                  icon: const Icon(Icons.search),
                                ),
                                if (_query.text.isNotEmpty)
                                  IconButton(
                                    tooltip: 'Clear search',
                                    onPressed: () {
                                      _query.clear();
                                      controller.clear();
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.clear),
                                  ),
                              ],
                            ),
                            if (state.validationMessage
                                case final message?) ...[
                              const SizedBox(height: 8),
                              Text(
                                message,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            if (!state.isSupported && state.initialized)
                              Semantics(
                                liveRegion: true,
                                child: const Text(
                                  'Search is not available for this library.',
                                ),
                              )
                            else if (state.loading ==
                                CatalogSearchLoading.searching)
                              Semantics(
                                label: 'Searching catalog',
                                liveRegion: true,
                                child: const LinearProgressIndicator(),
                              )
                            else if (state.failure != null)
                              _SearchFailure(
                                failure: state.failure!,
                                onRetry: controller.retry,
                              )
                            else if (state.page == null)
                              const Text('Enter a query and select Search.')
                            else if (state.page!.publications.isEmpty)
                              Semantics(
                                liveRegion: true,
                                child: const Text('No results found.'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (showResults) ...[
                    _SearchPublications(
                      publications: state.page!.publications,
                      sourceId: widget.sourceId,
                      onOpen: (item) {
                        // Returning from Details must not refocus the search
                        // field and auto-scroll a scrolled result list to it.
                        _focusNode.unfocus();
                        context.pushNamed(
                          AppRoutes.publicationOnlineLibraryName,
                          pathParameters: {'sourceId': widget.sourceId},
                          extra: RemotePublicationDetailsRequest(
                            sourceId: widget.sourceId,
                            sourceName: state.sourceName ?? 'Online library',
                            publication: item,
                          ),
                        );
                      },
                    ),
                    if (state.hasNextPage)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: FilledButton.tonal(
                            onPressed: state.isLoading
                                ? null
                                : controller.loadNextPage,
                            child: Text(
                              state.loading == CatalogSearchLoading.nextPage
                                  ? 'Loading more'
                                  : 'Load more',
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// This is the only layout watcher. SearchBar and business controller do not
// rebuild or reinitialize when the global preference alone changes.
class _SearchPublications extends ConsumerWidget {
  const _SearchPublications({
    required this.publications,
    required this.sourceId,
    required this.onOpen,
  });
  final List<RemoteCatalogPublicationSummary> publications;
  final String sourceId;
  final ValueChanged<RemoteCatalogPublicationSummary> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(libraryViewModeProvider);
    return SliverPadding(
      padding: mode == LibraryViewMode.grid
          ? const EdgeInsets.symmetric(horizontal: 16)
          : EdgeInsets.zero,
      sliver: RemoteCatalogPublicationSliver(
        publications: publications,
        sourceId: sourceId,
        onOpen: onOpen,
        mode: mode,
        gridKey: const Key('catalog-search-publication-grid'),
        listKey: const Key('catalog-search-publication-list'),
        itemKeyPrefix: 'catalog-search-publication',
      ),
    );
  }
}

class _CatalogSearchScrollView extends ConsumerStatefulWidget {
  const _CatalogSearchScrollView({
    required this.sourceId,
    required this.successfulQuery,
    required this.page,
    required this.slivers,
    super.key,
  });
  final String sourceId;
  final String? successfulQuery;
  final RemoteCatalogPage? page;
  final List<Widget> slivers;
  @override
  ConsumerState<_CatalogSearchScrollView> createState() =>
      _CatalogSearchScrollViewState();
}

class _CatalogSearchScrollViewState
    extends ConsumerState<_CatalogSearchScrollView> {
  final _controller = ScrollController(keepScrollOffset: false);
  late LibraryViewMode _mode;
  PageStorageBucket? _bucket;
  int _queryRevision = 0;
  int _restoreRevision = 0;
  double? _pendingOffset;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _mode = ref.read(libraryViewModeProvider);
  }

  ValueKey<Object> _storageKey() => ValueKey((
    widget.sourceId,
    widget.successfulQuery,
    _queryRevision,
    _mode,
  ));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bucket = PageStorage.maybeOf(context);
    if (!_initialized) {
      _initialized = true;
      final stored = _bucket?.readState(context, identifier: _storageKey());
      _restoreAfterLayout(stored is double ? stored : 0);
    }
  }

  void _savePosition() {
    if (_pendingOffset != null || !_controller.hasClients) return;
    _bucket?.writeState(context, _controller.offset, identifier: _storageKey());
  }

  void _switchMode(LibraryViewMode next) {
    if (_mode == next) return;
    _savePosition();
    _mode = next;
    final stored = _bucket?.readState(context, identifier: _storageKey());
    _restoreAfterLayout(stored is double ? stored : 0);
  }

  void _restoreAfterLayout(double offset) {
    _pendingOffset = offset;
    final revision = ++_restoreRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _restoreRevision || !_controller.hasClients) {
        return;
      }
      final position = _controller.position;
      final target = offset
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      _pendingOffset = null;
      if ((position.pixels - target).abs() > .5) _controller.jumpTo(target);
      _savePosition();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didUpdateWidget(covariant _CatalogSearchScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.successfulQuery != widget.successfulQuery) {
      // New successful searches (including a return to an earlier query) get
      // fresh mode offsets. Pagination cursors never participate in identity.
      _queryRevision++;
      _restoreAfterLayout(0);
    } else if (oldWidget.page != widget.page) {
      _restoreAfterLayout(
        _pendingOffset ?? (_controller.hasClients ? _controller.offset : 0),
      );
    }
  }

  @override
  void dispose() {
    _savePosition();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(libraryViewModeProvider, (_, next) => _switchMode(next));
    return CustomScrollView(
      key: const Key('catalog-search-scroll'),
      controller: _controller,
      slivers: widget.slivers,
    );
  }
}

class _SearchFailure extends StatelessWidget {
  const _SearchFailure({required this.failure, required this.onRetry});
  final RemoteCatalogFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final offline = failure == RemoteCatalogFailure.accessDenied;
    return Semantics(
      liveRegion: true,
      label: offline ? 'Search unavailable while Offline' : _message,
      child: Column(
        children: [
          Text(_message),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
              if (offline)
                TextButton(
                  onPressed: () => context.pushNamed(AppRoutes.settingsName),
                  child: const Text('Connectivity settings'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String get _message => switch (failure) {
    RemoteCatalogFailure.accessDenied =>
      'Online access is disabled. Enable it in connectivity settings.',
    RemoteCatalogFailure.searchUnsupported =>
      'Search is not available for this library.',
    RemoteCatalogFailure.malformedSearchDescription =>
      'The library returned an invalid search description.',
    RemoteCatalogFailure.unsupportedSearchTemplate =>
      'This library uses an unsupported search format.',
    RemoteCatalogFailure.timeout => 'The search request timed out.',
    RemoteCatalogFailure.httpStatus =>
      'The catalog server could not complete the search.',
    RemoteCatalogFailure.malformedCatalogResponse =>
      'The catalog returned invalid search results.',
    RemoteCatalogFailure.sourceDisabled => 'This library source is disabled.',
    RemoteCatalogFailure.sourceNotFound => 'This library source was not found.',
    _ => 'The catalog search could not be completed.',
  };
}

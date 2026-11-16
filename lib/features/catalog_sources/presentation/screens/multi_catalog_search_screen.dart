import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_book_tile.dart';
import 'package:bibliolife/features/catalog_sources/presentation/widgets/remote_catalog_book_tile.dart';
import 'dart:async';

import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:bibliolife/core/performance/online_pipeline_performance.dart';
import 'package:bibliolife/features/catalog_sources/application/multi_catalog_search_controller.dart';
import 'package:bibliolife/features/catalog_sources/application/local_search_result_assembler.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway_provider.dart';
import 'package:bibliolife/features/catalog_sources/data/remote_cache_service.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_search_filters.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/book_details/presentation/models/book_classification_taxonomy.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/remote_publication_details_screen.dart';
import 'package:bibliolife/features/catalog_sources/presentation/widgets/remote_catalog_book_card.dart';
import 'package:bibliolife/features/library/application/providers/library_providers.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_book_card.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MultiCatalogSearchScreen extends ConsumerStatefulWidget {
  const MultiCatalogSearchScreen({super.key});

  @override
  ConsumerState<MultiCatalogSearchScreen> createState() =>
      _MultiCatalogSearchScreenState();
}

class _MultiCatalogSearchScreenState
    extends ConsumerState<MultiCatalogSearchScreen>
    with WidgetsBindingObserver {
  final _query = TextEditingController();
  final _queryFocusNode = FocusNode();
  final _scrollController = ScrollController(keepScrollOffset: false);
  late LibraryViewMode _layoutMode;
  final _layoutOffsets = <LibraryViewMode, double>{};
  int _layoutRevision = 0;
  bool _restoringLayout = false;
  (String, CatalogSearchFilters)? _layoutQuery;
  Timer? _debounce;
  bool _nearEndDemandSent = false;
  late final MultiCatalogSearchController _searchController;

  @override
  void initState() {
    super.initState();
    _layoutMode = ref.read(libraryViewModeProvider);
    _searchController = ref.read(multiCatalogSearchControllerProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    searchPerformanceHealth('route_mounted');
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.stopPerformanceForRouteDisposal();
    _debounce?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _queryFocusNode.dispose();
    _query.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _searchController.stopPerformanceForLifecyclePause();
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _nearEndDemandSent = false;
    final controller = ref.read(multiCatalogSearchControllerProvider.notifier);
    controller.setQuery(value);
    if (value.trim().isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 400), _submit);
  }

  void _restoreLayout(LibraryViewMode next, {bool newQuery = false}) {
    if (_scrollController.hasClients && !_restoringLayout && !newQuery) {
      _layoutOffsets[_layoutMode] = _scrollController.offset;
    }
    if (newQuery) _layoutOffsets.clear();
    _layoutMode = next;
    final offset = _layoutOffsets[next] ?? 0;
    final revision = ++_layoutRevision;
    _restoringLayout = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          revision != _layoutRevision ||
          !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      _scrollController.jumpTo(
        offset
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble(),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && revision == _layoutRevision) _restoringLayout = false;
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _onScroll() {
    if (_restoringLayout) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.extentAfter > position.viewportDimension * 2.5) {
      _nearEndDemandSent = false;
      return;
    }
    if (position.extentAfter < position.viewportDimension * 1.5 &&
        !_nearEndDemandSent) {
      _nearEndDemandSent = true;
      ref.read(multiCatalogSearchControllerProvider.notifier).loadMore();
    }
  }

  Future<void> _submit() async {
    _debounce?.cancel();
    final query = _query.text.trim();
    final filters = ref.read(multiCatalogSearchControllerProvider).filters;
    if (query.isEmpty && !filters.hasMeaningfulSourceQuery) return;
    await ref.read(multiCatalogSearchControllerProvider.notifier).submit(query);
  }

  Future<void> _openFilters(CatalogSearchFilters applied) async {
    final sources = (await ref.read(catalogSourceRepositoryProvider).getAll())
        .where(
          (source) =>
              source.isEnabled &&
              (source.supportsSearch ||
                  source.type == CatalogSourceType.internetArchive),
        )
        .toList(growable: false);
    if (!mounted) return;
    final result = await showModalBottomSheet<CatalogSearchFilters>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          CatalogSearchFiltersSheet(applied: applied, enabledSources: sources),
    );
    if (result != null && mounted) {
      _nearEndDemandSent = false;
      await ref
          .read(multiCatalogSearchControllerProvider.notifier)
          .applyFilters(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(multiCatalogSearchControllerProvider);
    ref.listen(libraryViewModeProvider, (_, next) => _restoreLayout(next));
    final layoutQuery = (state.query, state.filters);
    if (_layoutQuery != layoutQuery) {
      if (_layoutQuery != null) _restoreLayout(_layoutMode, newQuery: true);
      _layoutQuery = layoutQuery;
    }
    // Start the local-library stream with the route, without making the
    // loading/footer subtree rebuild for every library mutation. The grid
    // selectively watches the actual book list when it is visible.
    ref.watch(allBooksProvider.select((_) => 0));
    final results = state.results;
    return Scaffold(
      appBar: AppBar(title: const Text('Search online libraries')),
      body: SafeArea(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverToBoxAdapter(
                child: SearchBar(
                  controller: _query,
                  focusNode: _queryFocusNode,
                  hintText: 'Search books',
                  textInputAction: TextInputAction.search,
                  onChanged: _onQueryChanged,
                  onSubmitted: (_) => _submit(),
                  trailing: [
                    if (state.filters.hasCustomFilters)
                      IconButton(
                        tooltip: 'Reset filters',
                        onPressed: () => ref
                            .read(multiCatalogSearchControllerProvider.notifier)
                            .applyFilters(CatalogSearchFilters.defaults()),
                        icon: const Icon(Icons.filter_alt_off_outlined),
                      ),
                    IconButton(
                      tooltip: 'Search filters',
                      onPressed: () => _openFilters(state.filters),
                      icon: const Icon(Icons.filter_alt_outlined),
                    ),
                    IconButton(
                      tooltip: 'Submit catalog search',
                      onPressed: _submit,
                      icon: const Icon(Icons.search),
                    ),
                  ],
                ),
              ),
            ),
            if (state.query.isEmpty && !state.filters.hasMeaningfulSourceQuery)
              const SliverToBoxAdapter(
                child: Center(child: Text('Enter a query and select Search.')),
              )
            else if ((state.awaitingDebounce ||
                    state.isLoading ||
                    state.isEnriching) &&
                results.isEmpty)
              const SliverToBoxAdapter(child: LinearProgressIndicator())
            else if (state.hasNoSources)
              const SliverToBoxAdapter(
                child: Center(child: Text('No online libraries configured.')),
              )
            else if (results.isEmpty && state.allFailed)
              SliverToBoxAdapter(
                child: Center(
                  child: Text(
                    state.isolatedFailureMessage ??
                        'The catalog search could not be completed.',
                  ),
                ),
              )
            else if (results.isEmpty && !state.isLoading)
              SliverToBoxAdapter(
                child: Center(
                  child: Text(
                    state.filters.onlyFreelyDownloadable
                        ? 'No verified free downloads were found for the selected sources.'
                        : 'No results found.',
                  ),
                ),
              )
            else
              const _SearchResultsGrid(),
            if (results.isNotEmpty && state.hasRecoverableFailure)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Some libraries could not be searched.'),
                      for (final entry in state.sources.values)
                        if (entry.failure != null)
                          TextButton(
                            onPressed: state.isLoading || !entry.isRetryable
                                ? null
                                : () => ref
                                      .read(
                                        multiCatalogSearchControllerProvider
                                            .notifier,
                                      )
                                      .retrySource(entry.source.id),
                            child: Text('Retry ${entry.source.name}'),
                          ),
                      TextButton(
                        onPressed:
                            state.isLoading ||
                                !state.sources.values.any(
                                  (entry) =>
                                      entry.failure != null &&
                                      entry.isRetryable,
                                )
                            ? null
                            : () => ref
                                  .read(
                                    multiCatalogSearchControllerProvider
                                        .notifier,
                                  )
                                  .retryFailed(),
                        child: const Text('Retry all'),
                      ),
                    ],
                  ),
                ),
              ),
            if (state.hasPaginationFailure)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: FilledButton.tonal(
                      onPressed: state.isLoading
                          ? null
                          : () => ref
                                .read(
                                  multiCatalogSearchControllerProvider.notifier,
                                )
                                .retryFailed(),
                      child: const Text('Retry loading more results'),
                    ),
                  ),
                ),
              )
            else if (results.isEmpty && state.allFailed)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: FilledButton.tonal(
                      onPressed: () => ref
                          .read(multiCatalogSearchControllerProvider.notifier)
                          .retryFailed(),
                      child: const Text('Retry search'),
                    ),
                  ),
                ),
              )
            else if (state.isLoading || state.isEnriching || state.hasMore)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: state.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : state.isEnriching
                      ? const Center(
                          child: Text(
                            'Checking Internet Archive availability…',
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static double _searchCardExtent(BuildContext context, double width) {
    final textTheme = Theme.of(context).textTheme;
    final textScaler = MediaQuery.textScalerOf(context);
    // Both card variants use these bounded title/author sections. Local and
    // merged cards also have an interactive status footer, whose minimum tap
    // target must be part of every fixed grid tile's extent.
    return width / context.appTokens.bookCardAspectRatio +
        8 +
        _textHeight(context, textTheme.titleSmall, textScaler, lines: 2) +
        _textHeight(context, textTheme.bodySmall, textScaler, lines: 1) +
        _searchCardFooterHeight(context);
  }

  static double _searchCardFooterHeight(BuildContext context) {
    final textHeight = _textHeight(
      context,
      Theme.of(context).textTheme.bodyMedium,
      MediaQuery.textScalerOf(context),
      lines: 1,
    );
    return (textHeight + 16)
        .clamp(kMinInteractiveDimension, double.infinity)
        .toDouble();
  }

  static double _textHeight(
    BuildContext context,
    TextStyle? style,
    TextScaler textScaler, {
    required int lines,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: List.filled(lines, 'A').join('\n'), style: style),
      textDirection: Directionality.of(context),
      textScaler: textScaler,
    )..layout();
    return painter.height;
  }
}

/// Isolates the lazy grid from loading/footer state. Source loading changes
/// keep the same materialized result list, so they no longer rebuild every
/// visible card or the local identity index.
class _SearchResultsGrid extends ConsumerStatefulWidget {
  const _SearchResultsGrid();

  @override
  ConsumerState<_SearchResultsGrid> createState() => _SearchResultsGridState();
}

class _SearchResultsGridState extends ConsumerState<_SearchResultsGrid> {
  final _assembler = LocalSearchResultAssembler();

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(libraryViewModeProvider);
    final results = ref.watch(
      multiCatalogSearchControllerProvider.select((state) => state.results),
    );
    final query = ref.watch(
      multiCatalogSearchControllerProvider.select((state) => state.query),
    );
    final filters = ref.watch(
      multiCatalogSearchControllerProvider.select((state) => state.filters),
    );
    final performance = ref.watch(
      multiCatalogSearchControllerProvider.select(
        (state) => state.performanceSession,
      ),
    );
    final localBooks =
        ref.watch(allBooksProvider).asData?.value ?? const <LibraryBook>[];
    final remoteCache = ref.read(remoteCacheServiceProvider);
    final assembled = _assembler.assemble(
      remote: results,
      local: localBooks,
      query: query,
      filters: filters,
      performanceSession: performance,
    );
    final indexByKey = <String, int>{
      for (final entry in assembled.indexed) _tileIdentity(entry.$2): entry.$1,
    };
    if (biblioLifeNetPerfVerboseLogsEnabled) {
      onlinePerformanceMarker(
        'local_search_assembler_input',
        fields: {
          'remoteCount': results.length,
          'localCount': localBooks.length,
          'assembledCount': assembled.length,
        },
      );
    }
    if (mode == LibraryViewMode.list) {
      return SliverPadding(
        padding: EdgeInsets.zero,
        sliver: SliverList.builder(
          key: const Key('multi-search-book-list'),
          itemCount: assembled.length,
          addAutomaticKeepAlives: false,
          findChildIndexCallback: (key) => switch (key) {
            ValueKey<String>(:final value) => indexByKey[value],
            _ => null,
          },
          itemBuilder: (context, index) =>
              _buildListTile(context, assembled[index], remoteCache),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final count = switch (constraints.crossAxisExtent) {
            < 600 => 2,
            < 900 => 3,
            _ => 4,
          };
          final gap = context.appTokens.bookCardGridGap;
          final tileWidth =
              (constraints.crossAxisExtent - gap * (count - 1)) / count;
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: count,
              crossAxisSpacing: gap,
              mainAxisSpacing: gap,
              mainAxisExtent: _MultiCatalogSearchScreenState._searchCardExtent(
                context,
                tileWidth,
              ),
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  _buildTile(context, assembled[index], remoteCache),
              childCount: assembled.length,
              findChildIndexCallback: (key) => switch (key) {
                ValueKey<String>(:final value) => indexByKey[value],
                _ => null,
              },
              addAutomaticKeepAlives: false,
            ),
          );
        },
      ),
    );
  }

  Widget _buildTile(
    BuildContext context,
    LocalSearchResult item,
    RemoteCacheService remoteCache,
  ) {
    item.remote?.performanceSession?.recordVisibleCardBuild();
    final localBook = item.localBook;
    final identity = _tileIdentity(item);
    if (localBook != null) {
      return RepaintBoundary(
        key: ValueKey(identity),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LibraryBookCard(
                book: localBook,
                onOpen: (bookId) {
                  FocusManager.instance.primaryFocus?.unfocus();
                  context.pushNamed(
                    AppRoutes.bookDetailsName,
                    pathParameters: {'bookId': bookId},
                  );
                },
              ),
            ),
            SizedBox(
              height: _MultiCatalogSearchScreenState._searchCardFooterHeight(
                context,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.isMerged ? 'Downloaded' : 'In library',
                      key: const Key('local-search-status'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    key: const Key('local-search-open'),
                    onPressed: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      context.pushNamed(
                        AppRoutes.bookDetailsName,
                        pathParameters: {'bookId': localBook.id},
                      );
                    },
                    child: const Text('Open'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final remote = item.remote!;
    return RepaintBoundary(
      key: ValueKey(identity),
      child: RemoteCatalogBookCard(
        key: ValueKey('catalog-search-publication-${remote.identity}'),
        publication: remote.publication,
        onOpen: () {
          FocusManager.instance.primaryFocus?.unfocus();
          context.pushNamed(
            AppRoutes.publicationOnlineLibraryName,
            pathParameters: {'sourceId': remote.source.id},
            extra: RemotePublicationDetailsRequest(
              sourceId: remote.source.id,
              sourceName: remote.source.name,
              publication: remote.routePublication,
              canonicalBook: remote.canonicalBook,
            ),
          );
        },
        sourceId: remote.source.id,
        canonicalId: remote.canonicalBook.canonicalId,
        performanceSession: remote.performanceSession,
        remoteCache: remoteCache,
      ),
    );
  }

  Widget _buildListTile(
    BuildContext context,
    LocalSearchResult item,
    RemoteCacheService remoteCache,
  ) {
    item.remote?.performanceSession?.recordVisibleCardBuild();
    final local = item.localBook;
    if (local != null) {
      void open() {
        FocusManager.instance.primaryFocus?.unfocus();
        context.pushNamed(
          AppRoutes.bookDetailsName,
          pathParameters: {'bookId': local.id},
        );
      }

      return RepaintBoundary(
        key: ValueKey(_tileIdentity(item)),
        child: LibraryBookTile(
          book: local,
          onOpen: open,
          status: Text(
            item.isMerged ? 'Downloaded' : 'In library',
            key: const Key('local-search-status'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          includeOpenAction: true,
        ),
      );
    }
    final remote = item.remote!;
    return RepaintBoundary(
      key: ValueKey(_tileIdentity(item)),
      child: RemoteCatalogBookTile(
        key: ValueKey('catalog-search-publication-${remote.identity}'),
        publication: remote.publication,
        statusPublication: remote.routePublication,
        sourceId: remote.source.id,
        canonicalId: remote.canonicalBook.canonicalId,
        performanceSession: remote.performanceSession,
        remoteCache: remoteCache,
        onOpen: () {
          FocusManager.instance.primaryFocus?.unfocus();
          context.pushNamed(
            AppRoutes.publicationOnlineLibraryName,
            pathParameters: {'sourceId': remote.source.id},
            extra: RemotePublicationDetailsRequest(
              sourceId: remote.source.id,
              sourceName: remote.source.name,
              publication: remote.routePublication,
              canonicalBook: remote.canonicalBook,
            ),
          );
        },
      ),
    );
  }

  String _tileIdentity(LocalSearchResult item) =>
      item.remote?.identity ?? 'local-${item.localBook!.id}';
}

class CatalogSearchFiltersSheet extends StatefulWidget {
  const CatalogSearchFiltersSheet({
    required this.applied,
    required this.enabledSources,
    super.key,
  });
  final CatalogSearchFilters applied;
  final List<CatalogSource> enabledSources;
  @override
  State<CatalogSearchFiltersSheet> createState() =>
      _CatalogSearchFiltersSheetState();
}

class _CatalogSearchFiltersSheetState extends State<CatalogSearchFiltersSheet> {
  late CatalogSearchFilters _draft = widget.applied;
  late final TextEditingController _author = TextEditingController(
    text: _draft.author,
  );
  late final TextEditingController _from = TextEditingController(
    text: _draft.editionYearFrom?.toString() ?? '',
  );
  late final TextEditingController _to = TextEditingController(
    text: _draft.editionYearTo?.toString() ?? '',
  );
  @override
  void dispose() {
    _author.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _cycleGenre(String genre) {
    final key = genre.toLowerCase();
    final included = _draft.includedGenres.toSet();
    final excluded = _draft.excludedGenres.toSet();
    if (included.remove(key)) {
      excluded.add(key);
    } else if (!excluded.remove(key)) {
      included.add(key);
    }
    setState(
      () => _draft = _draft.copyWith(
        includedGenres: included,
        excludedGenres: excluded,
      ),
    );
  }

  void _apply() {
    final now = DateTime.now().year;
    final from = int.tryParse(_from.text.trim());
    final to = int.tryParse(_to.text.trim());
    final next = _draft.copyWith(
      author: _author.text,
      editionYearFrom: from,
      editionYearTo: to,
      clearEditionYearFrom: _from.text.trim().isEmpty,
      clearEditionYearTo: _to.text.trim().isEmpty,
    );
    if (!next.hasValidYearRange ||
        (from != null && from > now) ||
        (to != null && to > now)) {
      return;
    }
    Navigator.pop(context, next);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .78,
        maxChildSize: .92,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Search filters',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _draft = CatalogSearchFilters.defaults();
                    _author.clear();
                    _from.clear();
                    _to.clear();
                  }),
                  child: const Text('Reset'),
                ),
              ],
            ),
            TextField(
              controller: _author,
              decoration: const InputDecoration(labelText: 'Author'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _from,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Edition year from',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _to,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Edition year to',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _GenreSection(
              included: _draft.includedGenres,
              excluded: _draft.excludedGenres,
              onCycle: _cycleGenre,
            ),
            _LanguageSection(
              selected: _draft.languages,
              onToggle: (language) {
                final selected = _draft.languages.toSet();
                selected.contains(language.$1)
                    ? selected.remove(language.$1)
                    : selected.add(language.$1);
                setState(() => _draft = _draft.copyWith(languages: selected));
              },
            ),
            const ListTile(
              title: Text('File type — Coming soon'),
              enabled: false,
            ),
            SwitchListTile(
              title: const Text('Only freely downloadable'),
              value: _draft.onlyFreelyDownloadable,
              onChanged: (value) => setState(
                () => _draft = _draft.copyWith(onlyFreelyDownloadable: value),
              ),
            ),
            const Text('Sources'),
            for (final source in widget.enabledSources)
              CheckboxListTile(
                title: Text(source.name),
                value:
                    _draft.selectedSourceIds.isEmpty ||
                    _draft.selectedSourceIds.contains(source.id),
                onChanged: (checked) {
                  final selected = _draft.selectedSourceIds.isEmpty
                      ? widget.enabledSources.map((item) => item.id).toSet()
                      : _draft.selectedSourceIds.toSet();
                  checked == true
                      ? selected.add(source.id)
                      : selected.remove(source.id);
                  if (selected.isEmpty) return;
                  setState(
                    () => _draft = _draft.copyWith(
                      selectedSourceIds:
                          selected.length == widget.enabledSources.length
                          ? const []
                          : selected,
                    ),
                  );
                },
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _apply,
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _GenreSection extends StatelessWidget {
  const _GenreSection({
    required this.included,
    required this.excluded,
    required this.onCycle,
  });
  final List<String> included;
  final List<String> excluded;
  final ValueChanged<String> onCycle;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('Genres'),
    children: [
      Wrap(
        spacing: 8,
        children: [
          for (final entry in bookGenreTaxonomy)
            _GenreChip(
              label: Text(entry.canonical),
              state: included.contains(entry.canonical.toLowerCase())
                  ? _GenreChipState.included
                  : excluded.contains(entry.canonical.toLowerCase())
                  ? _GenreChipState.excluded
                  : _GenreChipState.neutral,
              onPressed: () => onCycle(entry.canonical),
            ),
        ],
      ),
    ],
  );
}

enum _GenreChipState { neutral, included, excluded }

class _GenreChip extends StatelessWidget {
  const _GenreChip({
    required this.label,
    required this.state,
    required this.onPressed,
  });
  final Widget label;
  final _GenreChipState state;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => FilterChip(
    label: label,
    selected: state == _GenreChipState.included,
    avatar: state == _GenreChipState.included
        ? const Icon(Icons.check, size: 18)
        : state == _GenreChipState.excluded
        ? const Icon(Icons.remove, size: 18)
        : null,
    selectedColor: state == _GenreChipState.excluded
        ? Theme.of(context).colorScheme.errorContainer
        : null,
    onSelected: (_) => onPressed(),
  );
}

class _LanguageSection extends StatelessWidget {
  const _LanguageSection({required this.selected, required this.onToggle});
  final List<String> selected;
  final ValueChanged<(String, String)> onToggle;
  static const _languages = <(String, String)>[
    ('en', 'English'),
    ('uk', 'Ukrainian'),
    ('de', 'German'),
    ('fr', 'French'),
    ('es', 'Spanish'),
    ('it', 'Italian'),
  ];
  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('Languages'),
    children: [
      Wrap(
        spacing: 8,
        children: [
          for (final language in _languages)
            FilterChip(
              label: Text(language.$2),
              selected: selected.contains(language.$1),
              onSelected: (_) => onToggle(language),
            ),
        ],
      ),
    ],
  );
}

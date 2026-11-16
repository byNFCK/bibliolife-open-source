import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_search_filters.dart';
import 'package:bibliolife/features/catalog_sources/application/multi_catalog_search_controller.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/multi_catalog_search_screen.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:bibliolife/features/connectivity/application/app_connectivity_mode_provider.dart';
import 'package:bibliolife/features/home/application/providers/online_home_sections_provider.dart';
import 'package:bibliolife/features/catalog_sources/domain/google_books_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/home/application/providers/home_online_tab_settings_provider.dart';
import 'package:bibliolife/features/home/application/providers/home_default_carousel_provider.dart';
import 'package:bibliolife/features/home/domain/models/book_reading_progress.dart';
import 'package:bibliolife/features/home/domain/models/home_feed_ranking.dart';
import 'package:bibliolife/features/home/presentation/widgets/home_book_card.dart';
import 'package:bibliolife/features/home/presentation/widgets/home_local_book_carousel.dart';
import 'package:bibliolife/features/home/presentation/widgets/home_online_catalog_grid.dart';
import 'package:bibliolife/features/home/presentation/widgets/home_online_library_tabs.dart';
import 'package:bibliolife/features/home/presentation/widgets/home_ranking_subtitle.dart';
import 'package:bibliolife/features/home/presentation/widgets/home_search_entry.dart';
import 'package:bibliolife/features/home/presentation/widgets/home_section_header.dart';
import 'package:bibliolife/features/library/application/providers/library_providers.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_providers.dart';
import 'package:bibliolife/features/reader/domain/models/reading_progress.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final ScrollController _scrollController;
  var _nearEndDemandSent = false;
  String? _selectedLibraryId;
  String? _activeCatalogLibraryId;
  String? _offsetSourceId;
  late LibraryViewMode _layoutMode;
  final _layoutOffsets = <(String?, LibraryViewMode), double>{};
  bool _restoringLayout = false;
  int _layoutRevision = 0;
  PageStorageBucket? _layoutBucket;

  @override
  void initState() {
    super.initState();
    _layoutMode = ref.read(libraryViewModeProvider);
    _scrollController = ScrollController(keepScrollOffset: false)
      ..addListener(_onScroll);
  }

  @override
  void dispose() {
    _saveLayoutOffset();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _layoutBucket = PageStorage.maybeOf(context);
  }

  void _saveLayoutOffset() {
    if (_restoringLayout || !_scrollController.hasClients) return;
    final key = (_offsetSourceId, _layoutMode);
    _layoutOffsets[key] = _scrollController.offset;
    _layoutBucket?.writeState(
      context,
      _scrollController.offset,
      identifier: ('home-online-offset', key),
    );
  }

  void _switchLayoutScope(String? sourceId, LibraryViewMode mode) {
    if (sourceId == _offsetSourceId && mode == _layoutMode) return;
    if (_offsetSourceId == null && sourceId != null && _layoutOffsets.isEmpty) {
      _offsetSourceId = sourceId;
      _layoutMode = mode;
      return;
    }
    final fallback =
        sourceId != _offsetSourceId &&
            mode == _layoutMode &&
            _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    _saveLayoutOffset();
    _offsetSourceId = sourceId;
    _layoutMode = mode;
    final key = (sourceId, mode);
    final stored =
        _layoutOffsets[key] ??
        _layoutBucket?.readState(
          context,
          identifier: ('home-online-offset', key),
        );
    final offset = stored is double ? stored : fallback;
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
      // Ignore corrections caused by reflow/restoration, never feed demand.
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
    if (!position.hasContentDimensions || position.viewportDimension <= 0) {
      return;
    }
    final nearEnd = position.extentAfter <= position.viewportDimension * 2.5;
    if (!nearEnd) {
      _nearEndDemandSent = false;
      return;
    }
    if (_nearEndDemandSent) return;
    if (!ref.read(onlineAccessAllowedProvider)) return;
    final libraryId = _activeCatalogLibraryId;
    if (libraryId == null) return;
    final section = ref
        .read(onlineHomeSectionsForLibraryProvider(libraryId))
        .asData
        ?.value
        .firstOrNull;
    if (section == null ||
        section.isInitialResolving ||
        section.isLoadingMore ||
        section.loadMoreFailed ||
        !section.hasMore ||
        section.presentationSlots.where((slot) => slot.isPending).length >=
            OnlineHomeSectionsController.subsectionConcurrency) {
      return;
    }
    _nearEndDemandSent = true;
    ref
        .read(onlineHomeSectionsForLibraryProvider(libraryId).notifier)
        .loadMore();
  }

  void _selectLibrary(String? libraryId) {
    if (_selectedLibraryId == libraryId) return;
    _nearEndDemandSent = false;
    _activeCatalogLibraryId = libraryId;
    if (mounted) {
      setState(() => _selectedLibraryId = libraryId);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      libraryViewModeProvider,
      (_, next) => _switchLayoutScope(_offsetSourceId, next),
    );
    final onlineAllowed = ref.watch(onlineAccessAllowedProvider);
    final configuredLibraries = ref.watch(visibleHomeCatalogSourcesProvider);
    final filters = ref.watch(catalogSearchFiltersProvider);
    final selectedLibrary =
        configuredLibraries
            .where((source) => source.id == _selectedLibraryId)
            .firstOrNull ??
        configuredLibraries.firstOrNull;
    if (_selectedLibraryId != null &&
        selectedLibrary != null &&
        _selectedLibraryId != selectedLibrary.id) {
      final hiddenId = _selectedLibraryId!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _selectedLibraryId != hiddenId) return;
        ref.invalidate(onlineHomeSectionsForLibraryProvider(hiddenId));
        _selectLibrary(selectedLibrary.id);
      });
    }
    _switchLayoutScope(selectedLibrary?.id, _layoutMode);
    _activeCatalogLibraryId = selectedLibrary?.id;
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          key: const PageStorageKey('home-scroll'),
          controller: _scrollController,
          slivers: [
            const _HomeLocalCarouselSliver(),
            SliverToBoxAdapter(
              child: HomeSearchEntry(
                hasCustomFilters: filters.hasCustomFilters,
                onResetFilters: () => ref
                    .read(catalogSearchFiltersProvider.notifier)
                    .set(CatalogSearchFilters.defaults()),
                onFilters: () async {
                  final sources =
                      (await ref.read(catalogSourceRepositoryProvider).getAll())
                          .where(
                            (source) =>
                                source.isEnabled && source.supportsSearch,
                          )
                          .toList(growable: false);
                  if (!context.mounted) return;
                  final next = await showModalBottomSheet<CatalogSearchFilters>(
                    context: context,
                    useRootNavigator: true,
                    isScrollControlled: true,
                    builder: (_) => CatalogSearchFiltersSheet(
                      applied: filters,
                      enabledSources: sources,
                    ),
                  );
                  if (next != null && context.mounted) {
                    ref.read(catalogSearchFiltersProvider.notifier).set(next);
                  }
                },
                onTap: () {
                  final library = selectedLibrary;
                  if (library == null) return;
                  final capability =
                      ref
                          .read(
                            onlineHomeSectionsForLibraryProvider(library.id),
                          )
                          .asData
                          ?.value
                          .firstOrNull
                          ?.searchCapability ??
                      const RemoteCatalogSearchCapability.unsupported();
                  context.pushNamed(
                    AppRoutes.searchOnlineLibraryName,
                    pathParameters: {'sourceId': library.id},
                    queryParameters: const {'all': 'true'},
                    extra: capability,
                  );
                },
              ),
            ),
            ..._onlineSlivers(
              context,
              onlineAllowed,
              configuredLibraries,
              selectedLibrary,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _onlineSlivers(
    BuildContext context,
    bool onlineAllowed,
    List<CatalogSource> libraries,
    CatalogSource? selectedLibrary,
  ) {
    final onlineHeader = SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.only(
          top: context.appTokens.sectionSpacing,
          bottom: 16,
        ),
        child: const HomeSectionHeader(title: 'Online libraries'),
      ),
    );
    if (!onlineAllowed) {
      return [
        onlineHeader,
        const SliverToBoxAdapter(
          child: _OnlineMessage('Go online to explore free books'),
        ),
      ];
    }
    if (libraries.isEmpty) {
      return [
        onlineHeader,
        SliverToBoxAdapter(
          child: _HomeOnlineTabsHidden(
            onOpenSettings: () =>
                context.pushNamed(AppRoutes.onlineLibrariesName),
          ),
        ),
      ];
    }
    final library = selectedLibrary!;
    return [
      onlineHeader,
      SliverToBoxAdapter(
        child: HomeOnlineLibraryTabs(
          libraries: libraries,
          selectedLibraryId: library.id,
          onSelected: _selectLibrary,
        ),
      ),
      Consumer(
        builder: (context, ref, _) {
          final provider = onlineHomeSectionsForLibraryProvider(library.id);
          final online = ref.watch(provider);
          return SliverMainAxisGroup(
            slivers: online.when(
              loading: () => const [
                SliverToBoxAdapter(child: _OnlineLoading()),
              ],
              error: (error, _) => [
                if (error is GoogleBooksRequestException)
                  const SliverToBoxAdapter(
                    child: HomeRankingSubtitle(
                      ranking: HomeFeedRanking.googleRelevance(),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: _OnlineFailure(
                    error: error,
                    onRetry: () => ref.read(provider.notifier).retry(),
                  ),
                ),
              ],
              data: (sections) {
                if (sections.isEmpty) {
                  return const [
                    SliverToBoxAdapter(
                      child: _OnlineMessage('No online books are available.'),
                    ),
                  ];
                }
                final books = sections
                    .expand((section) => section.books)
                    .toList();
                final section = sections.first;
                if (books.isEmpty && section.presentationSlots.isEmpty) {
                  return const [
                    SliverToBoxAdapter(
                      child: _OnlineMessage('No online books are available.'),
                    ),
                  ];
                }
                return [
                  if (section.ranking case final ranking?)
                    SliverToBoxAdapter(
                      child: HomeRankingSubtitle(ranking: ranking),
                    ),
                  HomeOnlineCatalogGrid(
                    mode: ref.watch(libraryViewModeProvider),
                    books: books,
                    slots: section.presentationSlots,
                  ),
                  if (section.isInitialResolving)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Center(
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    ),
                  if (section.loadMoreFailed)
                    SliverToBoxAdapter(
                      child: _OnlineFailure(
                        message: 'Could not load more books.',
                        onRetry: () => ref.read(provider.notifier).loadMore(),
                      ),
                    ),
                  if (section.isLoadingMore)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 20, bottom: 8),
                        child: Center(
                          child: Semantics(
                            label: 'Loading more books',
                            child: const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                      ),
                    ),
                ];
              },
            ),
          );
        },
      ),
    ];
  }
}

class _HomeLocalCarouselSliver extends ConsumerWidget {
  const _HomeLocalCarouselSliver();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defaultCarousel =
        ref.watch(defaultHomeCarouselProvider).asData?.value ??
        HomeDefaultCarousel.recentlyOpened;
    final localSection = switch (defaultCarousel) {
      HomeDefaultCarousel.recentlyOpened => (
        books: ref.watch(recentlyOpenedBooksProvider),
        title: AppStrings.recentlyOpened,
      ),
      HomeDefaultCarousel.favorites => (
        books: ref.watch(favoriteBooksProvider),
        title: AppStrings.favorites,
      ),
    };
    final allProgress = ref.watch(allReadingProgressProvider);
    final progressByBook = {
      for (final progress in allProgress.asData?.value ?? <ReadingProgress>[])
        progress.bookId: BookReadingProgress.fromProgression(
          progress.progression,
        ),
    };
    final items = (localSection.books.asData?.value ?? const <LibraryBook>[])
        .take(12)
        .toList(growable: false);
    if (items.isEmpty) return const SliverToBoxAdapter();
    return SliverToBoxAdapter(
      child: HomeLocalBookCarousel(
        title: localSection.title,
        books: items,
        itemCount: items.length,
        itemBuilder: (context, index) {
          final book = items[index];
          return HomeBookCard(
            key: ValueKey('home-book-${book.id}'),
            book: book,
            progress: progressByBook[book.id],
          );
        },
      ),
    );
  }
}

class _OnlineLoading extends StatelessWidget {
  const _OnlineLoading();

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: 12),
    child: Center(
      child: Semantics(
        label: 'Loading online books',
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    ),
  );
}

class _OnlineMessage extends StatelessWidget {
  const _OnlineMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: context.appTokens.pagePadding),
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _OnlineFailure extends StatelessWidget {
  const _OnlineFailure({
    required this.onRetry,
    this.message = 'Could not load online books.',
    this.error,
  });

  final VoidCallback onRetry;
  final String message;
  final Object? error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: context.appTokens.pagePadding),
    child: Row(
      children: [
        Expanded(child: Text(_messageFor(error) ?? message)),
        TextButton(
          key: const Key('home-online-retry'),
          onPressed: onRetry,
          child: const Text('Retry'),
        ),
      ],
    ),
  );

  String? _messageFor(Object? error) => switch (error) {
    GoogleBooksRequestException failure => failure.userMessage,
    RemoteCatalogException failure
        when failure.message?.trim().isNotEmpty == true =>
      failure.message,
    _ => null,
  };
}

class _HomeOnlineTabsHidden extends StatelessWidget {
  const _HomeOnlineTabsHidden({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: context.appTokens.pagePadding),
    child: Semantics(
      container: true,
      label: 'All Home online libraries are hidden',
      child: Column(
        key: const Key('home-online-tabs-hidden'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Online Home sections are hidden.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          TextButton(
            key: const Key('home-online-tabs-open-settings'),
            onPressed: onOpenSettings,
            child: const Text('Open online library settings'),
          ),
        ],
      ),
    ),
  );
}

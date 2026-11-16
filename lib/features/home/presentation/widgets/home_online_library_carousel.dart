import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:bibliolife/app/theme/app_spacing.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

class HomeOnlineLibraryCarousel extends StatefulWidget {
  const HomeOnlineLibraryCarousel({
    required this.libraries,
    required this.selectedLibraryId,
    required this.onSelected,
    super.key,
  });

  const HomeOnlineLibraryCarousel.empty({super.key})
    : libraries = const [],
      selectedLibraryId = null,
      onSelected = _ignore;

  final List<CatalogSource> libraries;
  final String? selectedLibraryId;
  final ValueChanged<String> onSelected;

  static const _cycleAnchor = 1000000;
  static const _recenterBoundary = 10000;
  static const viewportFraction = 0.66;
  static const peekZoneWidth = 36.0;
  static const _peekGap = 16.0;
  static const selectionAnimationDuration = Duration(milliseconds: 280);
  static const selectionAnimationCurve = Curves.easeOutCubic;

  static void _ignore(String _) {}

  /// Maps virtual pages onto the configured-library list without duplicating
  /// configuration or creating synthetic library items.
  static int libraryIndexForPage(int page, int libraryCount) =>
      libraryCount == 0
      ? 0
      : ((page % libraryCount) + libraryCount) % libraryCount;

  static int centeredPageFor(int libraryIndex, int libraryCount) {
    if (libraryCount < 2) return 0;
    return _cycleAnchor - (_cycleAnchor % libraryCount) + libraryIndex;
  }

  static bool shouldRecenter(int page) =>
      page < _recenterBoundary || page > 0x7fffffff - _recenterBoundary;

  static int recenteredPageFor(int page, int libraryCount) =>
      centeredPageFor(libraryIndexForPage(page, libraryCount), libraryCount);

  static int nearestPageForLibrary({
    required int libraryIndex,
    required int currentPage,
    required int libraryCount,
  }) {
    final pageInCycle = libraryIndexForPage(currentPage, libraryCount);
    final base = currentPage - pageInCycle + libraryIndex;
    final candidates = [base - libraryCount, base, base + libraryCount];
    candidates.sort(
      (first, second) =>
          (first - currentPage).abs().compareTo((second - currentPage).abs()),
    );
    return candidates.first;
  }

  @override
  State<HomeOnlineLibraryCarousel> createState() =>
      _HomeOnlineLibraryCarouselState();
}

class _HomeOnlineLibraryCarouselState extends State<HomeOnlineLibraryCarousel> {
  late final PageController _controller;
  var _lastPage = 0;
  int? _pendingRecenterPage;
  var _suppressSelectionCallbacks = false;

  @override
  void initState() {
    super.initState();
    _lastPage = _pageForSelected(anchor: true);
    _controller = PageController(
      initialPage: _lastPage,
      viewportFraction: HomeOnlineLibraryCarousel.viewportFraction,
    );
  }

  @override
  void didUpdateWidget(covariant HomeOnlineLibraryCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final librariesChanged = !_sameLibraries(
      oldWidget.libraries,
      widget.libraries,
    );
    if (librariesChanged) {
      _alignForLibraryListChange(oldWidget.libraries);
      return;
    }
    if (widget.libraries.length < 2) return;
    final currentLibraryId = widget
        .libraries[HomeOnlineLibraryCarousel.libraryIndexForPage(
          _lastPage,
          widget.libraries.length,
        )]
        .id;
    if (oldWidget.selectedLibraryId != widget.selectedLibraryId &&
        widget.selectedLibraryId != currentLibraryId) {
      final nextPage = _pageForSelected();
      _lastPage = nextPage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) {
          _controller.animateToPage(
            nextPage,
            duration: HomeOnlineLibraryCarousel.selectionAnimationDuration,
            curve: HomeOnlineLibraryCarousel.selectionAnimationCurve,
          );
        }
      });
    }
  }

  void _alignForLibraryListChange(List<CatalogSource> previousLibraries) {
    if (widget.libraries.length < 2) return;
    final previousId = previousLibraries.isEmpty
        ? null
        : previousLibraries[HomeOnlineLibraryCarousel.libraryIndexForPage(
                _lastPage,
                previousLibraries.length,
              )]
              .id;
    final targetId = widget.libraries.any((library) => library.id == previousId)
        ? previousId
        : widget.selectedLibraryId;
    final targetIndex = widget.libraries.indexWhere(
      (library) => library.id == targetId,
    );
    final nextPage = HomeOnlineLibraryCarousel.nearestPageForLibrary(
      libraryIndex: targetIndex < 0 ? 0 : targetIndex,
      currentPage: _lastPage,
      libraryCount: widget.libraries.length,
    );
    if (nextPage == _lastPage) return;
    _lastPage = nextPage;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.hasClients) {
        _jumpSilentlyTo(nextPage);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _sameLibraries(List<CatalogSource> previous, List<CatalogSource> next) {
    if (previous.length != next.length) return false;
    for (var index = 0; index < previous.length; index++) {
      if (previous[index].id != next[index].id) return false;
    }
    return true;
  }

  int _pageForSelected({bool anchor = false}) {
    final index = widget.libraries.indexWhere(
      (library) => library.id == widget.selectedLibraryId,
    );
    if (!anchor && widget.libraries.length >= 2) {
      return HomeOnlineLibraryCarousel.nearestPageForLibrary(
        libraryIndex: index < 0 ? 0 : index,
        currentPage: _lastPage,
        libraryCount: widget.libraries.length,
      );
    }
    return HomeOnlineLibraryCarousel.centeredPageFor(
      index < 0 ? 0 : index,
      widget.libraries.length,
    );
  }

  void _onPageChanged(int page) {
    _lastPage = page;
    final count = widget.libraries.length;
    if (count < 2 || _suppressSelectionCallbacks) return;
    widget.onSelected(
      widget
          .libraries[HomeOnlineLibraryCarousel.libraryIndexForPage(page, count)]
          .id,
    );
    if (HomeOnlineLibraryCarousel.shouldRecenter(page)) {
      _pendingRecenterPage = page;
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is! ScrollEndNotification) return false;
    final page = _pendingRecenterPage;
    final count = widget.libraries.length;
    if (page == null || page != _lastPage || count < 2) return false;
    _pendingRecenterPage = null;
    _jumpSilentlyTo(HomeOnlineLibraryCarousel.recenteredPageFor(page, count));
    return false;
  }

  void _jumpSilentlyTo(int page) {
    _suppressSelectionCallbacks = true;
    _lastPage = page;
    _controller.jumpToPage(page);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _suppressSelectionCallbacks = false;
    });
  }

  void _animateToLibrary(String libraryId) {
    final index = widget.libraries.indexWhere(
      (library) => library.id == libraryId,
    );
    if (index < 0 || widget.libraries.length < 2) return;
    final targetPage = HomeOnlineLibraryCarousel.nearestPageForLibrary(
      libraryIndex: index,
      currentPage: _currentVirtualPage.round(),
      libraryCount: widget.libraries.length,
    );
    if (targetPage == _currentVirtualPage.round()) return;
    _controller.animateToPage(
      targetPage,
      duration: HomeOnlineLibraryCarousel.selectionAnimationDuration,
      curve: HomeOnlineLibraryCarousel.selectionAnimationCurve,
    );
  }

  double get _currentVirtualPage => _controller.hasClients
      ? _controller.page ?? _lastPage.toDouble()
      : _lastPage.toDouble();

  @override
  Widget build(BuildContext context) {
    final libraries = widget.libraries;
    final tokens = context.appTokens;
    if (libraries.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          tokens.pagePadding,
          tokens.sectionSpacing,
          tokens.pagePadding,
          0,
        ),
        child: const _OnlineLibrariesEmptyState(),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.pagePadding),
            child: SizedBox(
              height: 40,
              child: libraries.length == 1
                  ? Center(
                      child: _LibraryItem(
                        library: libraries.single,
                        selected: true,
                        onTap: () => widget.onSelected(libraries.single.id),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final selectedMaxWidth =
                            constraints.maxWidth -
                            2 *
                                (HomeOnlineLibraryCarousel.peekZoneWidth +
                                    HomeOnlineLibraryCarousel._peekGap);
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            NotificationListener<ScrollNotification>(
                              onNotification: _onScrollNotification,
                              child: PageView.builder(
                                key: const Key('home-online-library-carousel'),
                                controller: _controller,
                                allowImplicitScrolling: true,
                                scrollCacheExtent: ScrollCacheExtent.viewport(
                                  2,
                                ),
                                onPageChanged: _onPageChanged,
                                itemBuilder: (context, virtualPage) {
                                  final index =
                                      HomeOnlineLibraryCarousel.libraryIndexForPage(
                                        virtualPage,
                                        libraries.length,
                                      );
                                  final library = libraries[index];
                                  return GestureDetector(
                                    key: ValueKey(
                                      'home-online-library-page-$virtualPage',
                                    ),
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => _animateToLibrary(library.id),
                                  );
                                },
                              ),
                            ),
                            AnimatedBuilder(
                              animation: _controller,
                              builder: (context, _) => _CarouselVisualState(
                                libraries: libraries,
                                virtualPage: _currentVirtualPage,
                                selectedMaxWidth: selectedMaxWidth,
                                onTapLibrary: _animateToLibrary,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryItem extends StatelessWidget {
  const _LibraryItem({
    required this.library,
    required this.selected,
    required this.onTap,
    this.capsuleOpacity = 1,
    this.capsuleScale = 1,
    this.selectedTextOpacity = 1,
  });

  final CatalogSource library;
  final bool selected;
  final VoidCallback onTap;
  final double capsuleOpacity;
  final double capsuleScale;
  final double selectedTextOpacity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
      color: scheme.onSecondaryContainer,
      fontWeight: FontWeight.w600,
    );
    final unselectedStyle = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(color: scheme.onSurfaceVariant);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Select ${library.name}',
      child: Opacity(
        opacity: capsuleOpacity,
        child: Transform.scale(
          scale: capsuleScale,
          child: Center(
            child: GestureDetector(
              key: ValueKey('home-online-library-${library.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: selected
                    ? const EdgeInsets.symmetric(horizontal: 14, vertical: 5)
                    : EdgeInsets.zero,
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.secondaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  style: selected ? selectedStyle! : unselectedStyle!,
                  child: Opacity(
                    opacity: selected ? selectedTextOpacity : 1,
                    child: Text(
                      library.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CarouselVisualState extends StatelessWidget {
  const _CarouselVisualState({
    required this.libraries,
    required this.virtualPage,
    required this.selectedMaxWidth,
    required this.onTapLibrary,
  });

  final List<CatalogSource> libraries;
  final double virtualPage;
  final double selectedMaxWidth;
  final ValueChanged<String> onTapLibrary;

  @override
  Widget build(BuildContext context) {
    final centeredPage = virtualPage.round();
    final currentIndex = HomeOnlineLibraryCarousel.libraryIndexForPage(
      centeredPage,
      libraries.length,
    );
    final previous =
        libraries[(currentIndex - 1 + libraries.length) % libraries.length];
    final next = libraries[(currentIndex + 1) % libraries.length];
    final capsulePages = <int>{virtualPage.floor(), virtualPage.ceil()};
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: _peekOpacity((centeredPage - 1 - virtualPage).abs()),
          child: _LibraryPeek(
            key: const Key('home-online-library-peek-left'),
            library: previous,
            left: true,
            onTap: () => onTapLibrary(previous.id),
          ),
        ),
        Opacity(
          opacity: _peekOpacity((centeredPage + 1 - virtualPage).abs()),
          child: _LibraryPeek(
            key: const Key('home-online-library-peek-right'),
            library: next,
            left: false,
            onTap: () => onTapLibrary(next.id),
          ),
        ),
        for (final page in capsulePages)
          IgnorePointer(
            child: _CapsuleForVirtualPage(
              libraries: libraries,
              virtualPage: page,
              distance: (page - virtualPage).abs(),
              selectedMaxWidth: selectedMaxWidth,
            ),
          ),
      ],
    );
  }

  double _peekOpacity(double distance) =>
      (0.65 - distance.clamp(0.0, 1.0) * 0.2).clamp(0.45, 0.65);
}

class _CapsuleForVirtualPage extends StatelessWidget {
  const _CapsuleForVirtualPage({
    required this.libraries,
    required this.virtualPage,
    required this.distance,
    required this.selectedMaxWidth,
  });

  final List<CatalogSource> libraries;
  final int virtualPage;
  final double distance;
  final double selectedMaxWidth;

  @override
  Widget build(BuildContext context) {
    final progress = (1 - distance).clamp(0.0, 1.0);
    final library =
        libraries[HomeOnlineLibraryCarousel.libraryIndexForPage(
          virtualPage,
          libraries.length,
        )];
    return KeyedSubtree(
      key: ValueKey('home-online-library-capsule-$virtualPage'),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: selectedMaxWidth),
          child: _LibraryItem(
            library: library,
            selected: true,
            onTap: () {},
            capsuleOpacity: progress,
            capsuleScale: 0.96 + progress * 0.04,
            selectedTextOpacity: 0.65 + progress * 0.35,
          ),
        ),
      ),
    );
  }
}

class _LibraryPeek extends StatelessWidget {
  const _LibraryPeek({
    required this.library,
    required this.left,
    this.onTap,
    super.key,
  });

  final CatalogSource library;
  final bool left;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Align(
    alignment: left ? Alignment.centerLeft : Alignment.centerRight,
    child: SizedBox(
      key: Key('home-online-library-peek-${left ? 'left' : 'right'}-zone'),
      width: HomeOnlineLibraryCarousel.peekZoneWidth,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ClipRect(
          key: Key('home-online-library-peek-${left ? 'left' : 'right'}-clip'),
          child: Align(
            alignment: left ? Alignment.centerRight : Alignment.centerLeft,
            child: OverflowBox(
              minWidth: 0,
              maxWidth: double.infinity,
              alignment: left ? Alignment.centerRight : Alignment.centerLeft,
              child: Text(
                library.name,
                key: Key(
                  'home-online-library-peek-${left ? 'left' : 'right'}-text',
                ),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _OnlineLibrariesEmptyState extends StatelessWidget {
  const _OnlineLibrariesEmptyState();

  @override
  Widget build(BuildContext context) => Text(
    'No online libraries configured.',
    key: const Key('home-online-libraries-empty'),
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

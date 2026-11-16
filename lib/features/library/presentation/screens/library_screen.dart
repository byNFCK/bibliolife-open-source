import 'dart:async';

import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/core/performance/library_image_performance.dart';
import 'package:bibliolife/features/collections/presentation/widgets/collections_body.dart';
import 'package:bibliolife/features/import/application/providers/book_import_provider.dart';
import 'package:bibliolife/features/import/domain/entities/import_result.dart';
import 'package:bibliolife/features/library/application/providers/library_providers.dart';
import 'package:bibliolife/features/library/application/providers/library_section_provider.dart';
import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_book_section.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defaultSection = ref.watch(defaultLibrarySectionProvider);
    return switch (defaultSection) {
      AsyncData(:final value) => _LibraryScreenBody(initialSection: value),
      AsyncError() => const _LibraryScreenBody(
        initialSection: LibrarySection.allBooks,
      ),
      _ => const Scaffold(body: SizedBox.expand()),
    };
  }
}

class _LibraryScreenBody extends ConsumerStatefulWidget {
  const _LibraryScreenBody({required this.initialSection});

  final LibrarySection initialSection;

  @override
  ConsumerState<_LibraryScreenBody> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<_LibraryScreenBody> {
  late final PageController _pageController;
  late final ValueNotifier<int> _visiblePage;
  final _frameTimings = LibraryFrameTimingObserver();
  ({int target, Future<void> completion})? _pageTransition;
  int? _transitionStartIndex;
  bool _transitionFinishScheduled = false;

  static const _pageAnimationDuration = Duration(milliseconds: 260);

  @override
  void initState() {
    super.initState();
    final sectionNotifier = ref.read(librarySectionProvider.notifier);
    final initialSection = sectionNotifier.isInitialized
        ? ref.read(librarySectionProvider)
        : widget.initialSection;
    _pageController = PageController(initialPage: initialSection.index);
    _visiblePage = ValueNotifier(initialSection.index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      sectionNotifier.initializeFromDefault(widget.initialSection);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _visiblePage.dispose();
    _frameTimings.dispose();
    super.dispose();
  }

  void _selectPage(int index) {
    final section = LibrarySection.values[index];
    if (ref.read(librarySectionProvider) != section) {
      ref.read(librarySectionProvider.notifier).select(section);
    }
  }

  void _onPageChanged(int index) {
    _visiblePage.value = index;
    final transition = libraryTransitionName(
      _transitionStartIndex ?? index,
      index,
    );
    _frameTimings.setTransition(transition);
    // A tap can animate past a third section. Keep the requested selection
    // until the animation arrives or the user takes over with a drag.
    final target = _pageTransition?.target;
    if (target == null || target == index) {
      _selectPage(index);
    }
    _finishFrameTimingAfterPresentedFrames();
  }

  void _syncPageController(LibrarySection section) {
    if (!_pageController.hasClients) return;
    final currentPage = _pageController.page?.round();
    if (currentPage == section.index && _pageTransition == null) return;
    final from = currentPage ?? _pageController.initialPage;
    _transitionStartIndex = from;
    _frameTimings.start(libraryTransitionName(from, section.index));
    final completion = _pageController.animateToPage(
      section.index,
      duration: _pageAnimationDuration,
      curve: Curves.easeOutCubic,
    );
    _pageTransition = (target: section.index, completion: completion);
    unawaited(
      completion.whenComplete(() {
        if (!mounted || _pageTransition?.completion != completion) return;
        _pageTransition = null;
        final page = _pageController.hasClients ? _pageController.page : null;
        if (page != null) _selectPage(page.round());
      }),
    );
  }

  void _onHorizontalScrollStart(bool userDrag) {
    if (userDrag) _pageTransition = null;
    final current =
        _pageController.page?.round() ?? _pageController.initialPage;
    _transitionStartIndex = current;
    if (!_frameTimings.isRunning) {
      _frameTimings.start(libraryTransitionName(current, current));
    }
  }

  void _onHorizontalScrollEnd() {
    final index = _pageController.page?.round() ?? _pageController.initialPage;
    if (_pageTransition == null) _selectPage(index);
    if (!_frameTimings.isRunning) return;
    _frameTimings.setTransition(
      libraryTransitionName(_transitionStartIndex ?? index, index),
    );
    _finishFrameTimingAfterPresentedFrames();
  }

  void _finishFrameTimingAfterPresentedFrames() {
    if (!_frameTimings.isRunning || _transitionFinishScheduled) return;
    _transitionFinishScheduled = true;
    var framesRemaining = 2;

    void finish(Duration _) {
      if (!mounted || !_frameTimings.isRunning) {
        _transitionFinishScheduled = false;
        return;
      }
      framesRemaining -= 1;
      if (framesRemaining == 0) {
        _transitionFinishScheduled = false;
        _frameTimings.stop();
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback(finish);
    }

    WidgetsBinding.instance.addPostFrameCallback(finish);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<LibrarySection>(
      librarySectionProvider,
      (_, next) => _syncPageController(next),
    );
    ref.listen(bookImportProvider, (previous, next) {
      next.when(
        loading: () {},
        error: (error, stackTrace) {},
        data: (result) {
          if (result == null ||
              result is ImportCancelled ||
              result is ImportSuccess) {
            return;
          }
          final message = switch (result) {
            ImportUnsupportedFormat() => 'This file format is not supported.',
            ImportDuplicate() => 'This book has already been imported.',
            ImportCopyFailed() => 'The book file could not be copied.',
            ImportUnreadableFile() =>
              'This file is damaged, encrypted, or cannot be read.',
            ImportDatabaseFailed() =>
              'The book could not be added to your library.',
            ImportUnknownFailure() => 'The book could not be imported.',
            _ => null,
          };
          if (message != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(message)));
          }
        },
      );
    });

    return Scaffold(
      body: SafeArea(
        child: NestedScrollView(
          floatHeaderSlivers: true,
          headerSliverBuilder: (context, _) => LibraryHeader.slivers(
            initialSection: widget.initialSection,
            overlapHandle: NestedScrollView.sliverOverlapAbsorberHandleFor(
              context,
            ),
          ),
          body: _LibraryPageView(
            controller: _pageController,
            visiblePage: _visiblePage,
            onPageChanged: _onPageChanged,
            onHorizontalScrollStart: _onHorizontalScrollStart,
            onHorizontalScrollEnd: _onHorizontalScrollEnd,
          ),
        ),
      ),
    );
  }
}

class _LibraryPageView extends StatelessWidget {
  const _LibraryPageView({
    required this.controller,
    required this.visiblePage,
    required this.onPageChanged,
    required this.onHorizontalScrollStart,
    required this.onHorizontalScrollEnd,
  });

  final PageController controller;
  final ValueNotifier<int> visiblePage;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<bool> onHorizontalScrollStart;
  final VoidCallback onHorizontalScrollEnd;

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth != 0 ||
              notification.metrics.axis != Axis.horizontal) {
            return false;
          }
          if (notification is ScrollStartNotification) {
            onHorizontalScrollStart(notification.dragDetails != null);
          } else if (notification is ScrollEndNotification) {
            onHorizontalScrollEnd();
          }
          return false;
        },
        child: PageView(
          key: const Key('library-page-view'),
          controller: controller,
          onPageChanged: onPageChanged,
          children: [
            _LibraryPageScroll(
              visiblePage: visiblePage,
              index: LibrarySection.collection.index,
              child: CollectionsBody(
                key: const PageStorageKey('library-collection-page'),
                scrollKey: const PageStorageKey('library-collection'),
                padding: const EdgeInsets.only(bottom: 96),
                overlapHandle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                  context,
                ),
              ),
            ),
            _LibraryPageScroll(
              visiblePage: visiblePage,
              index: LibrarySection.follow.index,
              child: const _FollowSection(key: ValueKey('library-follow-page')),
            ),
            _LibraryPageScroll(
              visiblePage: visiblePage,
              index: LibrarySection.allBooks.index,
              child: const _AllBooksSection(
                key: ValueKey('library-all-books-page'),
              ),
            ),
          ],
        ),
      );
}

class _LibraryPageScroll extends StatefulWidget {
  const _LibraryPageScroll({
    required this.visiblePage,
    required this.index,
    required this.child,
  });

  final ValueNotifier<int> visiblePage;
  final int index;
  final Widget child;

  @override
  State<_LibraryPageScroll> createState() => _LibraryPageScrollState();
}

class _LibraryPageScrollState extends State<_LibraryPageScroll> {
  late final _controller = _LibraryPageScrollController(
    PrimaryScrollController.of(context),
    widget.visiblePage.value == widget.index,
  );

  @override
  void initState() {
    super.initState();
    widget.visiblePage.addListener(_updateActivePage);
  }

  void _updateActivePage() =>
      _controller.active = widget.visiblePage.value == widget.index;

  @override
  void dispose() {
    widget.visiblePage.removeListener(_updateActivePage);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PrimaryScrollController(
    controller: _controller,
    automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
    child: widget.child,
  );
}

// NestedScrollView applies vertical deltas to every attached inner position.
// Keep each page's native position alive, but coordinate only the visible page.
class _LibraryPageScrollController extends ScrollController {
  _LibraryPageScrollController(this._nested, this._active);

  final ScrollController _nested;
  bool _active;

  set active(bool value) {
    if (value == _active) return;
    _active = value;
    for (final position in positions) {
      if (value) {
        _nested.attach(position);
      } else {
        if (position.isScrollingNotifier.value) {
          position.hold(() {});
        }
        _nested.detach(position);
      }
    }
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    final storageContext = context.storageContext;
    final storage = PageStorage.maybeOf(storageContext);
    final savedOffset = oldPosition == null
        ? storage?.readState(storageContext)
        : null;
    final position = _nested.createScrollPosition(
      physics,
      context,
      oldPosition,
    );
    // The nested position skips restoration while the outer header is open.
    // Grid and list can still restore their own PageStorage offsets.
    if (savedOffset is double && position.pixels != savedOffset) {
      position.correctPixels(savedOffset);
      storage!.writeState(storageContext, savedOffset);
    }
    return position;
  }

  @override
  void attach(ScrollPosition position) {
    super.attach(position);
    if (_active) _nested.attach(position);
  }

  @override
  void detach(ScrollPosition position) {
    if (_active) _nested.detach(position);
    super.detach(position);
  }
}

class _FollowSection extends ConsumerStatefulWidget {
  const _FollowSection({super.key});

  @override
  ConsumerState<_FollowSection> createState() => _FollowSectionState();
}

class _FollowSectionState extends ConsumerState<_FollowSection>
    with AutomaticKeepAliveClientMixin<_FollowSection> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LibraryBookSection(
      books: ref.watch(favoriteBooksProvider),
      viewMode: ref.watch(libraryViewModeProvider),
      storageKey: 'library-follow',
      emptyTitle: 'No followed books',
      emptyMessage: 'Books you favorite will appear here.',
      emptyIcon: Icons.favorite_border,
      onRetry: () => ref.invalidate(favoriteBooksProvider),
    );
  }
}

class _AllBooksSection extends ConsumerStatefulWidget {
  const _AllBooksSection({super.key});

  @override
  ConsumerState<_AllBooksSection> createState() => _AllBooksSectionState();
}

class _AllBooksSectionState extends ConsumerState<_AllBooksSection>
    with AutomaticKeepAliveClientMixin<_AllBooksSection> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LibraryBookSection(
      books: ref.watch(allBooksProvider),
      viewMode: ref.watch(libraryViewModeProvider),
      storageKey: 'library-all-books',
      emptyTitle: AppStrings.noBooksInLibrary,
      emptyMessage: AppStrings.emptyLibraryMessage,
      emptyIcon: Icons.inbox_outlined,
      onRetry: () => ref.invalidate(allBooksProvider),
    );
  }
}

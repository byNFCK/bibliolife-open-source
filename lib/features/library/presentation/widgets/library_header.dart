import 'dart:async';

import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/app/theme/app_spacing.dart';
import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:bibliolife/features/import/application/providers/book_import_provider.dart';
import 'package:bibliolife/features/library/application/providers/library_section_provider.dart';
import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_section_tabs.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_view_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// Move part of the search row's bottom padding into the pinned row.
// The expanded layout keeps the same spacing between the two rows.
const _pinnedTabsTopGap = 12.0;

abstract final class LibraryHeader {
  static List<Widget> slivers({
    required LibrarySection initialSection,
    required SliverOverlapAbsorberHandle overlapHandle,
  }) {
    final backdrop = _HeaderBackdropGeometry();
    return [
      // The outer NestedScrollView prioritizes revealing this row on reverse
      // scroll, even while the active page's inner offset is away from zero.
      _HeaderBackdrop(
        geometry: backdrop,
        isPinned: false,
        sliver: SliverToBoxAdapter(
          child: _SearchActions(initialSection: initialSection),
        ),
      ),
      SliverOverlapAbsorber(
        handle: overlapHandle,
        sliver: _HeaderBackdrop(
          geometry: backdrop,
          isPinned: true,
          sliver: PinnedHeaderSliver(
            child: _PinnedTabs(initialSection: initialSection),
          ),
        ),
      ),
    ];
  }
}

class _SearchActions extends ConsumerWidget {
  const _SearchActions({required this.initialSection});

  final LibrarySection initialSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = ref.watch(librarySectionProvider);
    final section = ref.read(librarySectionProvider.notifier).isInitialized
        ? selected
        : initialSection;
    final isCollection = section == LibrarySection.collection;
    final importing = ref.watch(
      bookImportProvider.select((value) => value.isLoading),
    );

    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: EdgeInsets.only(
          left: context.appTokens.pagePadding,
          top: AppSpacing.md,
          right: context.appTokens.pagePadding,
          bottom: AppSpacing.md - _pinnedTabsTopGap,
        ),
        child: Row(
          children: [
            Expanded(
              child: Material(
                color: colors.surface,
                shape: StadiumBorder(
                  side: BorderSide(color: colors.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const Key('library-search'),
                  onTap: () => context.pushNamed(AppRoutes.searchName),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    child: SizedBox(
                      height: 54,
                      child: Row(
                        children: [
                          const Icon(Icons.search, size: 22),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              AppStrings.searchBooks,
                              style: theme.textTheme.bodyMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            SizedBox.square(
              dimension: kMinInteractiveDimension,
              child: IconButton(
                tooltip: isCollection ? AppStrings.createCollection : 'Add',
                onPressed: importing
                    ? null
                    : () {
                        if (isCollection) {
                          unawaited(
                            context.pushNamed(AppRoutes.createCollectionName),
                          );
                        } else {
                          unawaited(
                            ref.read(bookImportProvider.notifier).importFile(),
                          );
                        }
                      },
                icon: const Icon(Icons.add),
              ),
            ),
            SizedBox.square(
              dimension: kMinInteractiveDimension,
              // Keep search and Add in place when Collection hides the toggle.
              child: isCollection
                  ? null
                  : LibraryViewToggle(
                      viewMode: ref.watch(libraryViewModeProvider),
                      onPressed: () async {
                        try {
                          await ref
                              .read(libraryViewModeProvider.notifier)
                              .toggle();
                        } catch (_) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                AppStrings.libraryPreferenceSaveError,
                              ),
                            ),
                          );
                        }
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinnedTabs extends ConsumerWidget {
  const _PinnedTabs({required this.initialSection});

  final LibrarySection initialSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(librarySectionProvider);
    return Padding(
      padding: EdgeInsets.only(
        left: context.appTokens.pagePadding,
        top: _pinnedTabsTopGap,
        right: context.appTokens.pagePadding,
        bottom: AppSpacing.md,
      ),
      child: LibrarySectionTabs(
        selected: ref.read(librarySectionProvider.notifier).isInitialized
            ? selected
            : initialSection,
        onSelected: ref.read(librarySectionProvider.notifier).select,
      ),
    );
  }
}

class _HeaderBackdrop extends SingleChildRenderObjectWidget {
  const _HeaderBackdrop({
    required this.geometry,
    required this.isPinned,
    required Widget sliver,
  }) : super(child: sliver);

  final _HeaderBackdropGeometry geometry;
  final bool isPinned;

  @override
  RenderLibraryHeaderBackdrop createRenderObject(BuildContext context) =>
      RenderLibraryHeaderBackdrop._(
        geometry,
        isPinned,
        Theme.of(context).scaffoldBackgroundColor,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLibraryHeaderBackdrop renderObject,
  ) =>
      renderObject._update(geometry, Theme.of(context).scaffoldBackgroundColor);
}

// Both slivers use the same shader coordinates, but paint only their own region.
// This avoids cross-sliver overpainting and keeps the search controls above it.
class _HeaderBackdropGeometry {
  late RenderLibraryHeaderBackdrop pinned;
}

/// Coordinated header background; never changes sliver layout or hit testing.
class RenderLibraryHeaderBackdrop extends RenderProxySliver {
  RenderLibraryHeaderBackdrop._(this._header, this.isPinned, this._surface) {
    if (isPinned) _header.pinned = this;
  }

  _HeaderBackdropGeometry _header;
  final bool isPinned;
  Color _surface;

  void _update(_HeaderBackdropGeometry header, Color surface) {
    _header = header;
    _surface = surface;
    if (isPinned) _header.pinned = this;
    markNeedsPaint();
  }

  double get _visibleSearchExtent =>
      _header.pinned.constraints.viewportMainAxisExtent -
      _header.pinned.constraints.remainingPaintExtent;

  double get _fadeExtent =>
      _header.pinned.child!.geometry!.scrollExtent - AppSpacing.md;

  Rect get gradientBounds {
    final top = isPinned ? -_visibleSearchExtent : 0.0;
    return Rect.fromLTRB(
      0,
      top,
      constraints.crossAxisExtent,
      top + _visibleSearchExtent + _fadeExtent,
    );
  }

  LinearGradient get gradient {
    final height = _visibleSearchExtent + _fadeExtent;
    // Hold the page background through the search viewport boundary. A cubic
    // smoothstep has zero slope at both ends, so neither edge forms a seam.
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        _surface,
        for (var i = 0; i <= 24; i++)
          _surface.withValues(alpha: 1 - _smoothstep(i / 24)),
      ],
      stops: [
        0,
        for (var i = 0; i <= 24; i++)
          (_visibleSearchExtent + _fadeExtent * i / 24) / height,
      ],
    );
  }

  static double _smoothstep(double t) => t * t * (3 - 2 * t);

  @override
  void paint(PaintingContext context, Offset offset) {
    final bounds = gradientBounds.shift(offset);
    final region = Rect.fromLTWH(
      offset.dx,
      offset.dy,
      constraints.crossAxisExtent,
      isPinned ? _fadeExtent : geometry!.paintExtent,
    );
    context.canvas.drawRect(
      region,
      Paint()..shader = gradient.createShader(bounds),
    );
    super.paint(context, offset);
  }
}

import 'dart:async';

import 'package:bibliolife/features/bookmarks/domain/models/library_bookmark.dart';
import 'package:bibliolife/features/bookmarks/presentation/widgets/bookmark_edit_dialog.dart';
import 'package:bibliolife/features/reader/application/services/readium_epub_annotation_coordinator.dart';
import 'package:bibliolife/features/reader/domain/models/reader_annotation.dart';
import 'package:bibliolife/features/reader/presentation/models/reader_ui_controller.dart';
import 'package:bibliolife/features/reader/presentation/screens/book_annotations_screen.dart';
import 'package:bibliolife/features/reader/presentation/widgets/reader_annotation_editor_sheet.dart';
import 'package:bibliolife/features/reader/presentation/widgets/reader_stable_components.dart';
import 'package:bibliolife/features/reader/performance/reader_performance.dart';
import 'package:bibliolife/shared/presentation/widgets/biblio_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

final _readerSavedItemWhitespace = RegExp(r'\s+');

/// Stable reader saved-items presentation: Bookmarks then Annotations.
enum ReaderSavedItemsTab { bookmarks, annotations }

class ReaderSavedItemsTabController extends ChangeNotifier {
  ReaderSavedItemsTab _selected = ReaderSavedItemsTab.bookmarks;

  ReaderSavedItemsTab get selected => _selected;

  void select(ReaderSavedItemsTab value) {
    if (_selected == value) return;
    _selected = value;
    notifyListeners();
  }
}

Future<T?> showReaderSavedItemsMenu<T>({
  required BuildContext context,
  required ReaderUiController controller,
}) async {
  if (!controller.capabilities.supportsBookmarks) return null;
  final annotationsSupported =
      controller.capabilities.supportsHighlights &&
      controller.annotationMenuController != null;
  final tabs = ReaderSavedItemsTabController();
  try {
    return await showReaderMenu<T>(
      context: context,
      title: 'Bookmarks and annotations',
      headerExtension: annotationsSupported
          ? _StableSavedItemsSelector(
              key: const Key('reader-saved-items-header-segmented-control'),
              tabController: tabs,
            )
          : null,
      footer: const ReaderMenuSingleActionFooter(),
      child: ReaderSavedItemsSheet(
        controller: controller,
        tabController: tabs,
        showAnnotations: annotationsSupported,
      ),
    );
  } finally {
    tabs.dispose();
  }
}

class ReaderSavedItemsSheet extends StatefulWidget {
  const ReaderSavedItemsSheet({
    required this.controller,
    this.tabController,
    this.showAnnotations = true,
    super.key,
  });

  final ReaderUiController controller;
  final ReaderSavedItemsTabController? tabController;
  final bool showAnnotations;

  @override
  State<ReaderSavedItemsSheet> createState() => _ReaderSavedItemsSheetState();
}

class _ReaderSavedItemsSheetState extends State<ReaderSavedItemsSheet> {
  late final ReaderSavedItemsTabController _ownedTabController;
  late final Listenable _updates;

  ReaderSavedItemsTabController get _tabController =>
      widget.tabController ?? _ownedTabController;

  @override
  void initState() {
    super.initState();
    _ownedTabController = ReaderSavedItemsTabController();
    _updates = Listenable.merge([
      _tabController,
      if (widget.controller.bookmarkCoordinator
          case final Listenable bookmarkUpdates)
        bookmarkUpdates,
      if (widget.controller.annotationMenuController
          case final Listenable annotationUpdates)
        annotationUpdates,
    ]);
  }

  @override
  void dispose() {
    _ownedTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _updates,
    builder: (context, _) {
      final annotationsSelected =
          widget.showAnnotations &&
          _tabController.selected == ReaderSavedItemsTab.annotations;
      return Column(
        children: [
          if (widget.tabController == null && widget.showAnnotations) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _StableSavedItemsSelector(
                key: const Key('reader-saved-items-switcher'),
                tabController: _tabController,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: KeyedSubtree(
              key: const Key('reader-saved-items-scroll-body'),
              // Keep both lazy list subtrees mounted. This preserves each
              // ScrollPosition and avoids destroying/recreating a whole list on
              // a tab tap; IndexedStack has no full-list opacity transition.
              child: IndexedStack(
                index: annotationsSelected ? 1 : 0,
                children: [
                  TickerMode(
                    enabled: !annotationsSelected,
                    child: _BookmarksTab(
                      key: const PageStorageKey('reader-saved-bookmarks'),
                      controller: widget.controller,
                    ),
                  ),
                  if (widget.showAnnotations)
                    TickerMode(
                      enabled: annotationsSelected,
                      child: _AnnotationsTab(
                        key: const PageStorageKey('reader-saved-annotations'),
                        controller: widget.controller,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _StableSavedItemsSelector extends StatelessWidget {
  const _StableSavedItemsSelector({required this.tabController, super.key});

  final ReaderSavedItemsTabController tabController;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: tabController,
    builder: (context, _) => Semantics(
      label: 'Bookmarks and annotations tabs',
      child: BiblioTabs<ReaderSavedItemsTab>(
        key: const Key('reader-saved-items-segmented-control'),
        items: const [
          BiblioTabItem(
            id: ReaderSavedItemsTab.bookmarks,
            label: 'Bookmarks',
            key: Key('reader-saved-bookmarks-tab'),
          ),
          BiblioTabItem(
            id: ReaderSavedItemsTab.annotations,
            label: 'Annotations',
            key: Key('reader-saved-annotations-tab'),
          ),
        ],
        selectedId: tabController.selected,
        onSelected: tabController.select,
      ),
    ),
  );
}

class _BookmarksTab extends StatelessWidget {
  const _BookmarksTab({required this.controller, super.key});

  final ReaderUiController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.bookmarkState;
    if (state.isLoading) return const ReaderMenuLoading();
    if (state.error != null && state.bookmarks.isEmpty) {
      return ReaderMenuError(
        title: 'Could not load bookmarks.',
        onRetry: controller.bookmarkCoordinator?.reload,
      );
    }
    if (state.bookmarks.isEmpty) {
      return const ReaderMenuEmpty(
        asset: 'assets/readium/stable/ic_reader_bookmark.svg',
        title: 'No bookmarks yet.',
        message: 'Bookmarks you add in this book will appear here.',
      );
    }
    return ListView.separated(
      key: const Key('reader-saved-bookmarks-list'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      itemCount: state.bookmarks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        ReaderMenuPerformanceScope.recordRowBuild(context);
        return _BookmarkCard(
          bookmark: state.bookmarks[index],
          controller: controller,
        );
      },
    );
  }
}

class _AnnotationsTab extends StatelessWidget {
  const _AnnotationsTab({required this.controller, super.key});

  final ReaderUiController controller;

  @override
  Widget build(BuildContext context) {
    final menu = controller.annotationMenuController;
    final state = menu?.annotationMenuState;
    if (menu == null) {
      return const ReaderMenuEmpty(
        asset: 'assets/readium/stable/ic_reader_annotations.svg',
        title: 'No annotations yet.',
        message: 'Highlights you create in this book will appear here.',
      );
    }
    if (state!.isLoading) return const ReaderMenuLoading();
    if (state.error != null && state.annotations.isEmpty) {
      return const ReaderMenuError(title: 'Could not load annotations.');
    }
    final valid = state.annotations
        .where((value) => value.locatorJson.trim().isNotEmpty)
        .toList(growable: false);
    if (valid.isEmpty) {
      return const ReaderMenuEmpty(
        asset: 'assets/readium/stable/ic_reader_annotations.svg',
        title: 'No annotations yet.',
        message: 'Highlights you create in this book will appear here.',
      );
    }
    return ListView.separated(
      key: const Key('reader-saved-annotations-list'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      itemCount: valid.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        ReaderMenuPerformanceScope.recordRowBuild(context);
        return _AnnotationCard(annotation: valid[index], menu: menu);
      },
    );
  }
}

class _BookmarkCard extends StatelessWidget {
  const _BookmarkCard({required this.bookmark, required this.controller});
  final LibraryBookmark bookmark;
  final ReaderUiController controller;

  String get _label =>
      bookmark.title ?? bookmark.chapterTitle ?? 'Saved location';

  @override
  Widget build(BuildContext context) => ReaderMenuCard(
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => unawaited(_open(context)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _label,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _metadata(context),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              children: [
                _StableAssetButton(
                  tooltip: 'Edit bookmark',
                  asset: 'assets/readium/stable/ic_edit_outline.svg',
                  onPressed: () => _edit(context),
                ),
                const SizedBox(height: 4),
                _StableAssetButton(
                  tooltip: 'Delete bookmark',
                  asset: 'assets/readium/stable/ic_delete_highlight.svg',
                  onPressed: () => unawaited(_delete(context)),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  String _metadata(BuildContext context) => [
    if (bookmark.chapterTitle != null && bookmark.chapterTitle != _label)
      bookmark.chapterTitle!,
    if (bookmark.progression != null)
      '${(bookmark.progression!.clamp(0, 1) * 100).round()}%',
    if (bookmark.note?.trim().isNotEmpty == true) bookmark.note!.trim(),
    formatAnnotationDate(context, bookmark.updatedAt),
  ].join(' • ');

  Future<void> _open(BuildContext context) async {
    final result = await controller.goToBookmark(bookmark);
    if (!context.mounted) return;
    if (result.isSuccess) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this bookmark.')),
      );
    }
  }

  Future<void> _edit(BuildContext context) async {
    final coordinator = controller.bookmarkCoordinator;
    if (coordinator == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => BookmarkEditDialog(
        bookmark: bookmark,
        onSave: (update) => coordinator.updateBookmark(bookmark, update),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final result = await controller.deleteBookmark(bookmark);
    if (!context.mounted || result.isSuccess) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not delete this bookmark.')),
    );
  }
}

class _AnnotationCard extends StatelessWidget {
  const _AnnotationCard({required this.annotation, required this.menu});
  final ReaderAnnotation annotation;
  final ReaderAnnotationMenuController menu;

  @override
  Widget build(BuildContext context) {
    final excerpt = annotation.selectedText
        .replaceAll(_readerSavedItemWhitespace, ' ')
        .trim();
    return ReaderMenuCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => unawaited(_goToLocation(context)),
        onLongPress: () => unawaited(_edit(context)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      excerpt.isEmpty ? 'Annotation' : excerpt,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      formatAnnotationDate(context, annotation.createdAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  AnnotationColorIndicator(color: annotation.color),
                  const SizedBox(height: 4),
                  _StableAssetButton(
                    tooltip: 'Delete highlight',
                    asset: 'assets/readium/stable/ic_delete_highlight.svg',
                    onPressed: () => unawaited(_delete(context)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _goToLocation(BuildContext context) async {
    final opened = await menu.openAnnotation(annotation);
    if (!context.mounted) return;
    if (opened) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open this highlight location.'),
        ),
      );
    }
  }

  Future<void> _edit(BuildContext context) => showReaderMenu<void>(
    context: context,
    title: 'Edit annotation',
    child: ReaderAnnotationEditorSheet(
      annotation: annotation,
      onSave: (note, style, color) => menu.updateAnnotation(
        id: annotation.id,
        note: note,
        style: style,
        color: color,
      ),
      onDelete: () => menu.deleteAnnotation(annotation.id),
    ),
  );

  Future<void> _delete(BuildContext context) async {
    if (await menu.deleteAnnotation(annotation.id) || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not delete this highlight.')),
    );
  }
}

class _StableAssetButton extends StatelessWidget {
  const _StableAssetButton({
    required this.tooltip,
    required this.asset,
    required this.onPressed,
  });
  final String tooltip;
  final String asset;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 48,
    height: 48,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: SvgPicture.asset(
        asset,
        width: 24,
        height: 24,
        colorFilter: ColorFilter.mode(
          Theme.of(context).colorScheme.onSurfaceVariant,
          BlendMode.srcIn,
        ),
      ),
    ),
  );
}

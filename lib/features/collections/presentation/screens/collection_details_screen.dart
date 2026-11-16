import 'package:bibliolife/features/collections/presentation/system_collection_colors.dart';
import 'package:bibliolife/features/collections/domain/models/system_collection.dart';
import 'package:bibliolife/shared/presentation/widgets/app_context_menu.dart';
import 'dart:async';

import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/app/theme/app_spacing.dart';
import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:bibliolife/core/utils/date_time_formatter.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_description_panel.dart';
import 'package:bibliolife/features/collections/application/providers/collection_providers.dart';
import 'package:bibliolife/features/collections/application/providers/collection_repository_provider.dart';
import 'package:bibliolife/features/collections/domain/models/library_collection.dart';
import 'package:bibliolife/features/collections/domain/repositories/collection_repository.dart';
import 'package:bibliolife/features/collections/presentation/widgets/collection_overview_cover.dart';
import 'package:bibliolife/features/collections/presentation/widgets/collection_book_selector_sheet.dart';
import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_grid.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_list.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CollectionDetailsScreen extends ConsumerStatefulWidget {
  const CollectionDetailsScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  ConsumerState<CollectionDetailsScreen> createState() =>
      _CollectionDetailsScreenState();
}

class _CollectionDetailsScreenState
    extends ConsumerState<CollectionDetailsScreen> {
  bool _managingBooks = false;

  Future<void> _manageBooks(List<LibraryBook> books) async {
    if (_managingBooks) return;
    _managingBooks = true;
    final collectionId = widget.collectionId;
    final accentScheme = systemCollectionColorScheme(
      collectionId,
      Theme.of(context).brightness,
    );
    final initial = books.map((book) => book.id).toSet();
    try {
      final selected = await showModalBottomSheet<Set<String>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => CollectionBookSelectorSheet(
          initialSelectedBookIds: initial,
          accentScheme: accentScheme,
        ),
      );
      if (!mounted || widget.collectionId != collectionId || selected == null) {
        return;
      }
      final repository = ref.read(collectionRepositoryProvider);
      for (final id in selected.difference(initial)) {
        await repository.addBook(collectionId, id);
      }
      for (final id in initial.difference(selected)) {
        await repository.removeBook(collectionId, id);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update collection books.')),
        );
      }
    } finally {
      _managingBooks = false;
    }
  }

  Future<void> _showDeleteConfirmation(String collectionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.deleteCollectionTitle),
        content: const Text(AppStrings.deleteCollectionBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStrings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(collectionRepositoryProvider).delete(collectionId);
      if (mounted) Navigator.of(context).pop();
    } on CollectionRepositoryFailure {
      if (mounted) _showDeleteError();
    } on Object {
      if (mounted) _showDeleteError();
    }
  }

  void _showDeleteError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(AppStrings.collectionDeleteError)),
    );
  }

  Future<void> _openEdit(String collectionId) async {
    await context.pushNamed(
      AppRoutes.editCollectionName,
      pathParameters: {'collectionId': collectionId},
    );
    if (!mounted) return;
    ref.invalidate(collectionByIdProvider(collectionId));
    ref.invalidate(booksInCollectionProvider(collectionId));
  }

  void _onMenuSelected(String value, String collectionId) {
    switch (value) {
      case 'edit':
        unawaited(_openEdit(collectionId));
      case 'delete':
        _showDeleteConfirmation(collectionId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final collection = ref.watch(collectionByIdProvider(widget.collectionId));
    return collection.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const Scaffold(
        body: Center(child: Text(AppStrings.collectionLoadError)),
      ),
      data: (item) {
        if (item == null) {
          return const Scaffold(
            body: Center(child: Text(AppStrings.collectionNotFound)),
          );
        }
        final books = ref.watch(booksInCollectionProvider(widget.collectionId));
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: books.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const Center(
                child: Text(AppStrings.collectionBooksLoadError),
              ),
              data: (items) => _buildOverview(context, item.name, item, items),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverview(
    BuildContext context,
    String collectionName,
    LibraryCollection collection,
    List<LibraryBook> books,
  ) {
    final tokens = context.appTokens;
    final description = collection.description;
    final hasDescription = description?.trim().isNotEmpty ?? false;
    return _CollectionDetailsScrollView(
      key: ValueKey(widget.collectionId),
      collectionId: widget.collectionId,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              tokens.pagePadding,
              AppSpacing.sm,
              tokens.pagePadding,
              0,
            ),
            child: SystemCollectionTheme(
              collectionId: collection.id,
              child: _CollectionOverviewHeader(
                collectionId: widget.collectionId,
                collectionName: collectionName,
                createdAt: collection.createdAt,
                customCoverPath: collection.customCoverPath,
                books: books,
                onMenuSelected: _onMenuSelected,
                isSystem: isSystemCollection(collection.id),
              ),
            ),
          ),
        ),
        if (hasDescription)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                tokens.pagePadding,
                AppSpacing.xl,
                tokens.pagePadding,
                0,
              ),
              child: BookDescriptionPanel(description: description),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              tokens.pagePadding,
              hasDescription ? tokens.sectionSpacing : AppSpacing.xl,
              tokens.pagePadding,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Divider(
                  key: const Key('collection-details-books-divider'),
                  color: Theme.of(context).colorScheme.outlineVariant,
                  height: 1,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  '${AppStrings.books} · ${books.length}',
                  key: const Key('collection-details-books-header'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        ),
        if (books.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: SystemCollectionTheme(
              collectionId: collection.id,
              child: _EmptyCollectionBooks(
                onAddBooks: isSystemCollection(collection.id)
                    ? () => _manageBooks(books)
                    : () => context.pushNamed(
                        AppRoutes.editCollectionName,
                        pathParameters: {'collectionId': widget.collectionId},
                      ),
              ),
            ),
          )
        else
          _CollectionBooks(books: books),
      ],
    );
  }
}

// Only this sliver rebuilds its presentation when the global mode changes.
class _CollectionBooks extends ConsumerWidget {
  const _CollectionBooks({required this.books});

  final List<LibraryBook> books;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(libraryViewModeProvider);
    final tokens = context.appTokens;
    final padding = EdgeInsets.fromLTRB(
      tokens.pagePadding,
      0,
      tokens.pagePadding,
      MediaQuery.viewPaddingOf(context).bottom + AppSpacing.xxl,
    );
    if (mode == LibraryViewMode.list) {
      return LibraryList(
        books: books,
        padding: padding.copyWith(left: 0, right: 0),
        sliverKey: const Key('collection-details-book-list'),
        itemKeyPrefix: 'collection-details-book',
      );
    }
    return SliverLayoutBuilder(
      builder: (context, constraints) => LibraryGrid(
        books: books,
        width: constraints.crossAxisExtent,
        padding: padding,
        sliverKey: const Key('collection-details-book-grid'),
        itemKeyPrefix: 'collection-details-book',
      ),
    );
  }
}

// Keep the scrollable and overview widgets mounted across layout changes.
// PageStorage holds pixels per collection/mode, not another layout preference.
class _CollectionDetailsScrollView extends ConsumerStatefulWidget {
  const _CollectionDetailsScrollView({
    required this.collectionId,
    required this.slivers,
    super.key,
  });

  final String collectionId;
  final List<Widget> slivers;

  @override
  ConsumerState<_CollectionDetailsScrollView> createState() =>
      _CollectionDetailsScrollViewState();
}

class _CollectionDetailsScrollViewState
    extends ConsumerState<_CollectionDetailsScrollView> {
  late final ScrollController _controller;
  late LibraryViewMode _mode;
  PageStorageBucket? _bucket;
  double? _pendingOffset;
  int _restoreRevision = 0;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _mode = ref.read(libraryViewModeProvider);
    _controller = ScrollController(keepScrollOffset: false);
  }

  ValueKey<String> _storageKey(LibraryViewMode mode) =>
      ValueKey('collection-details-${widget.collectionId}-${mode.name}');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bucket = PageStorage.maybeOf(context);
    if (!_initialized) {
      _initialized = true;
      final stored = _bucket?.readState(
        context,
        identifier: _storageKey(_mode),
      );
      _restoreAfterLayout(stored is double ? stored : 0);
    }
  }

  void _savePosition() {
    if (_pendingOffset != null || !_controller.hasClients) return;
    _bucket?.writeState(
      context,
      _controller.offset,
      identifier: _storageKey(_mode),
    );
  }

  void _switchMode(LibraryViewMode next) {
    if (next == _mode) return;
    _savePosition();
    final current =
        _pendingOffset ?? (_controller.hasClients ? _controller.offset : 0.0);
    _mode = next;
    final stored = _bucket?.readState(context, identifier: _storageKey(next));
    // On the first visit to a mode retain reasonable pixels, without trying
    // to convert the viewport to the same book. Later visits restore that mode.
    _restoreAfterLayout(stored is double ? stored : current);
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
      if ((position.pixels - target).abs() > 0.5) _controller.jumpTo(target);
      _savePosition();
    });
  }

  @override
  void didUpdateWidget(covariant _CollectionDetailsScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Data changes can shorten the collection while an old offset is saved.
    _restoreAfterLayout(
      _pendingOffset ?? (_controller.hasClients ? _controller.offset : 0),
    );
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
      key: const Key('collection-details-scroll'),
      controller: _controller,
      slivers: widget.slivers,
    );
  }
}

class _CollectionOverviewHeader extends StatelessWidget {
  const _CollectionOverviewHeader({
    required this.collectionId,
    required this.collectionName,
    required this.createdAt,
    required this.customCoverPath,
    required this.books,
    required this.onMenuSelected,
    required this.isSystem,
  });

  final String collectionId;
  final String collectionName;
  final DateTime createdAt;
  final String? customCoverPath;
  final List<LibraryBook> books;
  final void Function(String value, String collectionId) onMenuSelected;
  final bool isSystem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            key: const Key('collection-details-back'),
            tooltip: AppStrings.back,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        CollectionOverviewCover(
          collectionId: collectionId,
          customCoverPath: customCoverPath,
          books: books,
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    collectionName,
                    key: const Key('collection-details-title'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  if (!isSystem)
                    Text(
                      '${AppStrings.created} ${DateTimeFormatter.shortDateLabel(createdAt)}',
                      key: const Key('collection-details-created-date'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            AppContextMenuButton<String>(
              key: const Key('collection-details-overflow'),
              tooltip: AppStrings.more,
              onSelected: (value) => onMenuSelected(value, collectionId),
              actions: [
                AppContextMenuAction(
                  value: 'edit',
                  label: AppStrings.editCollection,
                  semanticLabel:
                      '${AppStrings.editCollection}, $collectionName',
                  icon: Icons.edit_outlined,
                ),
                if (!isSystem)
                  AppContextMenuAction(
                    value: 'delete',
                    label: AppStrings.deleteCollection,
                    semanticLabel:
                        '${AppStrings.deleteCollection}, $collectionName',
                    icon: Icons.delete_outline,
                    destructive: true,
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _EmptyCollectionBooks extends StatelessWidget {
  const _EmptyCollectionBooks({required this.onAddBooks});

  final VoidCallback onAddBooks;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppStrings.noBooksInCollection),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              key: const Key('collection-details-add-books'),
              onPressed: onAddBooks,
              icon: const Icon(Icons.add),
              label: const Text(AppStrings.addBooks),
            ),
          ],
        ),
      ),
    );
  }
}

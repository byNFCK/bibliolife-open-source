import 'package:bibliolife/features/library/presentation/widgets/library_error_state.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_grid.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_list.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_section_empty_state.dart';
import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LibraryBookSection extends StatelessWidget {
  const LibraryBookSection({
    required this.books,
    required this.viewMode,
    required this.storageKey,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.emptyIcon,
    required this.onRetry,
    super.key,
  });

  final AsyncValue<List<LibraryBook>> books;
  final LibraryViewMode viewMode;
  final String storageKey;
  final String emptyTitle;
  final String emptyMessage;
  final IconData emptyIcon;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final items = books.when(
      data: (items) => items,
      loading: () => null,
      error: (_, _) => null,
    );
    final hasBooks = items != null && items.isNotEmpty;
    final isGrid = viewMode == LibraryViewMode.grid;

    return LayoutBuilder(
      builder: (context, constraints) => CustomScrollView(
        key: PageStorageKey('$storageKey-${isGrid ? 'grid' : 'list'}'),
        semanticChildCount: items?.length,
        slivers: [
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
          if (hasBooks)
            if (isGrid)
              LibraryGrid(books: items, width: constraints.maxWidth)
            else
              LibraryList(books: items)
          else
            SliverFillRemaining(
              hasScrollBody: false,
              child: books.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) =>
                    LibraryErrorState(onRetry: onRetry),
                data: (_) => LibrarySectionEmptyState(
                  title: emptyTitle,
                  message: emptyMessage,
                  icon: emptyIcon,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

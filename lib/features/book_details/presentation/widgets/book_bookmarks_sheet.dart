import 'package:bibliolife/features/bookmarks/application/providers/bookmark_providers.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_modal_card.dart';
import 'package:bibliolife/features/bookmarks/domain/models/library_bookmark.dart';
import 'package:bibliolife/features/bookmarks/presentation/widgets/bookmark_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BookBookmarksSheet extends ConsumerWidget {
  const BookBookmarksSheet({
    required this.bookId,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final String bookId;
  final ValueChanged<LibraryBookmark> onOpen;
  final Future<void> Function(LibraryBookmark) onEdit;
  final Future<void> Function(LibraryBookmark) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarks = ref.watch(bookmarksForBookProvider(bookId));
    return bookmarks.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(
        child: TextButton(
          onPressed: () => ref.invalidate(bookmarksForBookProvider(bookId)),
          child: const Text('Could not load bookmarks. Retry'),
        ),
      ),
      data: (items) => items.isEmpty
          ? const Center(child: Text('No bookmarks yet.'))
          : ListView.separated(
              shrinkWrap: true,
              key: const Key('bookmarks-list'),
              padding: const EdgeInsets.symmetric(
                vertical: BookDetailsModalCardMetrics.listVerticalPadding,
              ),
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: BookDetailsModalCardMetrics.cardGap),
              itemBuilder: (context, index) {
                final bookmark = items[index];
                return BookmarkListTile(
                  bookmark: bookmark,
                  onOpen: () {
                    Navigator.pop(context);
                    onOpen(bookmark);
                  },
                  onEdit: () => onEdit(bookmark),
                  onDelete: () => onDelete(bookmark),
                );
              },
            ),
    );
  }
}

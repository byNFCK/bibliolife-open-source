import 'package:bibliolife/shared/presentation/presenters/book_reading_progress_availability.dart';
import 'package:bibliolife/shared/presentation/presenters/book_list_status_presenter.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_book_card.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:bibliolife/shared/presentation/widgets/app_book_card.dart';
import 'package:bibliolife/shared/presentation/widgets/app_book_list_tile.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_render_profile.dart';
import 'package:flutter/material.dart';

/// Draft-only presentation. Callers own selection/removal; no book navigation.
class CollectionDraftBooksSliver extends StatelessWidget {
  const CollectionDraftBooksSliver({
    required this.books,
    required this.mode,
    required this.itemPrefix,
    required this.actionBuilder,
    this.onSelect,
    super.key,
  });

  final List<LibraryBook> books;
  final LibraryViewMode mode;
  final String itemPrefix;
  final Widget Function(LibraryBook) actionBuilder;
  final ValueChanged<LibraryBook>? onSelect;

  Widget _item(LibraryBook book) {
    final open = onSelect == null ? null : () => onSelect!(book);
    final action = actionBuilder(book);
    if (mode == LibraryViewMode.list) {
      return Consumer(
        key: ValueKey('$itemPrefix-identity-${book.id}'),
        builder: (context, ref, _) {
          final progress = ref
              .watch(readingProgressProvider(book.id))
              .asData
              ?.value;
          return AppBookListTile(
            progressPercent: availableBookReadingProgress(
              ref,
              book,
              progress == null ? null : (progress.progression * 100).round(),
            ),
            key: ValueKey('$itemPrefix-row-${book.id}'),
            title: book.title,
            bookStatus: BookListStatusPresenter.local(book),
            metadata: book.author,
            onOpen: open,
            cover: LibraryBookCover(
              book: book,
              profile: BookCoverRenderProfile.localLibraryList,
            ),
            actions: [action],
          );
        },
      );
    }
    return Consumer(
      builder: (context, ref, _) {
        return AppBookCard(
          progressPercent: availableBookReadingProgress(ref, book, 0),
          key: ValueKey('$itemPrefix-card-${book.id}'),
          title: book.title,
          author: book.author,
          cover: LibraryBookCover(book: book),
          onOpen: open,
          status: Align(alignment: Alignment.centerRight, child: action),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (mode == LibraryViewMode.list) {
      return SliverList.builder(
        key: ValueKey('$itemPrefix-list'),
        itemCount: books.length,
        addAutomaticKeepAlives: false,
        itemBuilder: (_, index) => _item(books[index]),
      );
    }
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final count = switch (constraints.crossAxisExtent) {
          < 600 => 2,
          < 900 => 3,
          _ => 4,
        };
        final gap = context.appTokens.bookCardGridGap;
        final width = (constraints.crossAxisExtent - gap * (count - 1)) / count;
        return SliverList.separated(
          key: ValueKey('$itemPrefix-grid'),
          itemCount: (books.length / count).ceil(),
          addAutomaticKeepAlives: false,
          itemBuilder: (_, row) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (
                var col = 0;
                col < count && row * count + col < books.length;
                col++
              ) ...[
                if (col > 0) SizedBox(width: gap),
                SizedBox(width: width, child: _item(books[row * count + col])),
              ],
            ],
          ),
          separatorBuilder: (_, _) => SizedBox(height: gap),
        );
      },
    );
  }
}

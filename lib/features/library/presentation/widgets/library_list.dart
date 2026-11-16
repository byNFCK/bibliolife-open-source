import 'package:bibliolife/features/library/presentation/widgets/library_book_tile.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';

class LibraryList extends StatelessWidget {
  const LibraryList({
    required this.books,
    this.padding,
    this.allowDeleteBook = true,
    this.sliverKey,
    this.itemKeyPrefix = 'library-book-tile',
    super.key,
  });

  final List<LibraryBook> books;
  final EdgeInsets? padding;
  final bool allowDeleteBook;
  final Key? sliverKey;
  final String itemKeyPrefix;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding:
          padding ??
          EdgeInsets.only(
            bottom: MediaQuery.viewPaddingOf(context).bottom + 96,
          ),
      sliver: SliverList.builder(
        key: sliverKey,
        itemCount: books.length,
        addAutomaticKeepAlives: false,
        itemBuilder: (context, index) {
          final book = books[index];
          return LibraryBookTile(
            key: ValueKey('$itemKeyPrefix-${book.id}'),
            book: book,
            allowDeleteBook: allowDeleteBook,
          );
        },
      ),
    );
  }
}

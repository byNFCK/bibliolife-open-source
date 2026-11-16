import 'package:bibliolife/features/book_details/presentation/widgets/book_details_modal_sheet_scaffold.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_bookmarks_sheet.dart';
import 'package:bibliolife/features/bookmarks/domain/models/library_bookmark.dart';
import 'package:bibliolife/features/reader/presentation/screens/book_annotations_screen.dart';
import 'package:bibliolife/shared/presentation/widgets/app_modal_sheet_scaffold.dart';
import 'package:bibliolife/shared/presentation/widgets/biblio_tabs.dart';
import 'package:flutter/material.dart';

enum _BookSavedItemsSection { bookmarks, annotations }

Future<void> showBookBookmarksAndAnnotationsSheet({
  required BuildContext context,
  required String bookId,
  required ValueChanged<LibraryBookmark> onOpenBookmark,
  required Future<void> Function(LibraryBookmark) onEditBookmark,
  required Future<void> Function(LibraryBookmark) onDeleteBookmark,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: false,
  enableDrag: true,
  backgroundColor: Colors.transparent,
  sheetAnimationStyle: appModalSheetAnimation,
  builder: (_) => BookBookmarksAndAnnotationsSheet(
    bookId: bookId,
    onOpenBookmark: onOpenBookmark,
    onEditBookmark: onEditBookmark,
    onDeleteBookmark: onDeleteBookmark,
  ),
);

class BookBookmarksAndAnnotationsSheet extends StatefulWidget {
  const BookBookmarksAndAnnotationsSheet({
    required this.bookId,
    required this.onOpenBookmark,
    required this.onEditBookmark,
    required this.onDeleteBookmark,
    super.key,
  });

  final String bookId;
  final ValueChanged<LibraryBookmark> onOpenBookmark;
  final Future<void> Function(LibraryBookmark) onEditBookmark;
  final Future<void> Function(LibraryBookmark) onDeleteBookmark;

  @override
  State<BookBookmarksAndAnnotationsSheet> createState() =>
      _BookBookmarksAndAnnotationsSheetState();
}

class _BookBookmarksAndAnnotationsSheetState
    extends State<BookBookmarksAndAnnotationsSheet> {
  var _selectedSection = _BookSavedItemsSection.bookmarks;

  @override
  Widget build(BuildContext context) => BookDetailsModalSheetScaffold(
    title: 'Bookmarks and annotations',
    headerExtension: BiblioTabs<_BookSavedItemsSection>(
      key: const Key('book-saved-items-switcher'),
      items: const [
        BiblioTabItem(id: _BookSavedItemsSection.bookmarks, label: 'Bookmarks'),
        BiblioTabItem(
          id: _BookSavedItemsSection.annotations,
          label: 'Annotations',
        ),
      ],
      selectedId: _selectedSection,
      onSelected: (section) {
        if (section != _selectedSection) {
          setState(() => _selectedSection = section);
        }
      },
    ),
    content: SizedBox(
      height: double.infinity,
      child: IndexedStack(
        index: _selectedSection.index,
        children: [
          BookBookmarksSheet(
            bookId: widget.bookId,
            onOpen: widget.onOpenBookmark,
            onEdit: widget.onEditBookmark,
            onDelete: widget.onDeleteBookmark,
          ),
          BookAnnotationsBottomSheet(bookId: widget.bookId),
        ],
      ),
    ),
  );
}

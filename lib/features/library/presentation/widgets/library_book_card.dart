import 'package:bibliolife/shared/presentation/presenters/book_reading_progress_availability.dart';
import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/features/library/application/providers/library_use_case_providers.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_providers.dart';
import 'package:bibliolife/shared/models/book_cover_reference.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:bibliolife/shared/presentation/widgets/app_book_card.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_image.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_render_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Local-book adapter for the shared [AppBookCard] presentation.
class LibraryBookCard extends ConsumerStatefulWidget {
  const LibraryBookCard({
    required this.book,
    this.progressPercent,
    this.onOpen,
    this.coverKey,
    super.key,
  });

  final LibraryBook book;
  final int? progressPercent;
  final ValueChanged<String>? onOpen;
  final Key? coverKey;

  @override
  ConsumerState<LibraryBookCard> createState() => _LibraryBookCardState();
}

class _LibraryBookCardState extends ConsumerState<LibraryBookCard> {
  var _isUpdatingFavorite = false;

  Future<void> _toggleFavorite() async {
    if (_isUpdatingFavorite) return;
    setState(() => _isUpdatingFavorite = true);
    try {
      await ref.read(setBookFavoriteProvider)(
        widget.book.id,
        !widget.book.isFavorite,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update favorite status.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingFavorite = false);
    }
  }

  void _open() {
    final callback = widget.onOpen;
    if (callback != null) return callback(widget.book.id);
    context.pushNamed(
      AppRoutes.bookDetailsName,
      pathParameters: {'bookId': widget.book.id},
    );
  }

  @override
  Widget build(BuildContext context) {
    final persisted = widget.progressPercent == null
        ? ref.watch(readingProgressProvider(widget.book.id)).value
        : null;
    final percent =
        (widget.progressPercent ??
                ((persisted?.progression ?? 0) * 100).round())
            .clamp(0, 100);
    return AppBookCard(
      key: const Key('local-book-card'),
      title: widget.book.title,
      author: widget.book.author,
      cover: LibraryBookCover(key: widget.coverKey, book: widget.book),
      progressPercent: availableBookReadingProgress(ref, widget.book, percent),
      isFavorite: widget.book.isFavorite,
      favoriteAvailable: true,
      favoriteEnabled: !_isUpdatingFavorite,
      onFavorite: _toggleFavorite,
      onOpen: _open,
    );
  }
}

class LibraryBookCover extends StatelessWidget {
  const LibraryBookCover({
    required this.book,
    this.profile = BookCoverRenderProfile.localLibraryGrid,
    super.key,
  });

  final LibraryBook book;
  final BookCoverRenderProfile profile;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Center(
        child: Icon(
          Icons.menu_book_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
    final coverPath = book.coverPath;
    return SizedBox.expand(
      child: BookCoverImage(
        cover: coverPath == null
            ? const BookCoverReference.missing()
            : BookCoverReference.local(coverPath),
        title: book.title,
        placeholder: placeholder,
        profile: profile,
        diagnosticSourceType: 'local-book',
        diagnosticId: 'book:${book.id}',
      ),
    );
  }
}

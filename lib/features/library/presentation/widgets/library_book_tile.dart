import 'package:bibliolife/features/book_details/presentation/local_book_actions.dart';
import 'package:bibliolife/shared/presentation/presenters/book_reading_progress_availability.dart';
import 'package:bibliolife/shared/presentation/widgets/app_context_menu.dart';
import 'package:bibliolife/shared/presentation/presenters/book_list_status_presenter.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_providers.dart';
import 'package:bibliolife/shared/presentation/widgets/app_book_list_tile.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_book_card.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_render_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bibliolife/app/router/app_routes.dart';

class LibraryBookTile extends ConsumerStatefulWidget {
  const LibraryBookTile({
    required this.book,
    this.allowDeleteBook = true,
    this.onOpen,
    this.status,
    this.includeOpenAction = false,
    super.key,
  });

  final LibraryBook book;
  final bool allowDeleteBook;
  final VoidCallback? onOpen;
  final Widget? status;
  final bool includeOpenAction;

  @override
  ConsumerState<LibraryBookTile> createState() => _LibraryBookTileState();
}

class _LibraryBookTileState extends ConsumerState<LibraryBookTile> {
  bool _fileAvailable = false;
  var _fileCheckGeneration = 0;
  LibraryBook? _fileCheckedBook;

  Future<void> _checkFile(LocalBookActions actions) async {
    final generation = ++_fileCheckGeneration;
    setState(() {
      _fileAvailable = false;
      _fileCheckedBook = actions.book;
    });
    final available = await actions.canSave();
    if (mounted &&
        generation == _fileCheckGeneration &&
        LocalBookActions.sameFileSource(actions.book, widget.book)) {
      setState(() => _fileAvailable = available);
    }
  }

  void _open() {
    final open = widget.onOpen;
    if (open != null) {
      open();
    } else {
      context.pushNamed(
        AppRoutes.bookDetailsName,
        pathParameters: {'bookId': widget.book.id},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final actions = LocalBookActions(context, ref, book);
    final busy = ref.watch(
      localBookActionStateProvider.select((state) => state[book.id]),
    );
    final progress = ref.watch(readingProgressProvider(book.id)).asData?.value;

    return AppBookListTile(
      onOpen: _open,
      cover: LibraryBookCover(
        book: book,
        profile: BookCoverRenderProfile.localLibraryList,
      ),
      title: book.title,
      metadata: book.author,
      progressPercent: availableBookReadingProgress(
        ref,
        book,
        progress == null ? null : (progress.progression * 100).round(),
      ),
      bookStatus: BookListStatusPresenter.local(book),
      status: widget.status,
      actions: [
        AppContextMenuButton<String>(
          tooltip: 'More options for ${book.title}',
          onOpen: () => _checkFile(actions),
          onSelected: (value) {
            if (value == 'open') {
              _open();
            } else {
              actions.run(LocalBookAction.values.byName(value));
            }
          },
          actions: [
            if (widget.includeOpenAction)
              const AppContextMenuAction(
                value: 'open',
                key: Key('local-search-open'),
                label: 'Open',
                icon: Icons.open_in_new,
              ),
            for (final item in actions.items(
              busy: busy,
              fileAvailable:
                  _fileAvailable &&
                  LocalBookActions.sameFileSource(book, _fileCheckedBook),
              allowDelete: widget.allowDeleteBook,
            ))
              AppContextMenuAction(
                value: item.value.name,
                label: item.label,
                icon: item.icon,
                enabled: item.enabled,
                busy: item.busy,
                destructive: item.destructive,
                semanticLabel: item.semanticLabel,
              ),
          ],
        ),
      ],
    );
  }
}

import 'package:bibliolife/features/book_details/presentation/local_book_actions.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_status_bar.dart';
import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:bibliolife/features/book_details/application/providers/book_details_providers.dart';
import 'package:bibliolife/features/book_details/presentation/models/book_classification.dart';
import 'package:bibliolife/features/book_details/presentation/models/book_details_view_data.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_bookmarks_and_annotations_sheet.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_action_row.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_cover.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_progress.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_layout.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_float_menu.dart';
import 'package:bibliolife/features/book_details/domain/models/book_toc_snapshot.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_toc_sheet.dart';
import 'package:bibliolife/features/bookmarks/application/providers/bookmark_providers.dart';
import 'package:bibliolife/features/bookmarks/application/providers/bookmark_repository_provider.dart';
import 'package:bibliolife/features/bookmarks/domain/models/library_bookmark.dart';
import 'package:bibliolife/features/bookmarks/presentation/widgets/bookmark_edit_dialog.dart';
import 'package:bibliolife/features/library/application/providers/library_providers.dart';
import 'package:bibliolife/features/reader/domain/models/reader_launch_request.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class BookDetailsScreen extends ConsumerStatefulWidget {
  const BookDetailsScreen({required this.bookId, super.key});

  final String bookId;

  @override
  ConsumerState<BookDetailsScreen> createState() => _BookDetailsScreenState();
}

class _BookDetailsScreenState extends ConsumerState<BookDetailsScreen> {
  final _classificationCache = BookDetailsClassificationCache();
  var _fileAvailable = false;
  var _fileCheckGeneration = 0;
  LibraryBook? _fileCheckedBook;
  var _openingBookmark = false;
  String? _cachedTocJson;
  BookTocSnapshot? _cachedToc;

  BookTocSnapshot? _tocFor(String? tocJson) {
    if (_cachedTocJson != tocJson) {
      _cachedTocJson = tocJson;
      _cachedToc = BookTocSnapshot.decode(tocJson);
    }
    return _cachedToc;
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.libraryPath);
    }
  }

  Future<void> _continueReading(LibraryBook book) async {
    if (book.format == BookFormat.unknown) {
      _showMessage('This format is not supported by the reader yet.');
      return;
    }
    await context.pushNamed(
      AppRoutes.readerName,
      pathParameters: {'bookId': book.id},
      extra: ReaderLaunchRequest(
        bookId: book.id,
        formatHint: book.format,
        source: 'book_details',
      ),
    );
  }

  Future<void> _checkFile(LocalBookActions actions) async {
    final generation = ++_fileCheckGeneration;
    setState(() {
      _fileAvailable = false;
      _fileCheckedBook = actions.book;
    });
    final available = await actions.canSave();
    if (mounted &&
        generation == _fileCheckGeneration &&
        LocalBookActions.sameFileSource(
          actions.book,
          ref.read(bookByIdProvider(widget.bookId)).asData?.value,
        )) {
      setState(() => _fileAvailable = available);
    }
  }

  void _showBookmarksAndAnnotations(LibraryBook book) {
    showBookBookmarksAndAnnotationsSheet(
      context: context,
      bookId: book.id,
      onOpenBookmark: (bookmark) => _openBookmark(bookmark, book.format),
      onEditBookmark: _editBookmark,
      onDeleteBookmark: _deleteBookmark,
    );
  }

  void _showToc(LibraryBook book, BookTocSnapshot toc) {
    showBookTocSheet<void>(
      context: context,
      entries: toc.entries,
      onOpen: (entry) => _openTocEntry(book, entry),
    );
  }

  Future<void> _openTocEntry(LibraryBook book, BookTocEntry entry) async {
    Navigator.of(context).pop();
    await context.pushNamed(
      AppRoutes.readerName,
      pathParameters: {'bookId': book.id},
      extra: ReaderLaunchRequest(
        bookId: book.id,
        initialLocatorJson: entry.locatorJson,
        formatHint: book.format,
        source: 'book_details',
      ),
    );
  }

  Future<void> _openBookmark(
    LibraryBookmark bookmark,
    BookFormat format,
  ) async {
    if (_openingBookmark) return;
    setState(() => _openingBookmark = true);
    try {
      await context.pushNamed(
        AppRoutes.readerName,
        pathParameters: {'bookId': bookmark.bookId},
        extra: ReaderLaunchRequest(
          bookId: bookmark.bookId,
          initialLocatorJson: bookmark.locatorJson,
          formatHint: format,
          source: 'book_details',
        ),
      );
    } finally {
      if (mounted) setState(() => _openingBookmark = false);
    }
  }

  Future<void> _editBookmark(LibraryBookmark bookmark) => showDialog<void>(
    context: context,
    builder: (context) => BookmarkEditDialog(
      bookmark: bookmark,
      onSave: (update) => ref
          .read(bookmarkRepositoryProvider)
          .updateBookmarkMetadata(bookmarkId: bookmark.id, update: update),
    ),
  );

  Future<void> _deleteBookmark(LibraryBookmark bookmark) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete bookmark?'),
        content: Text(
          'Delete ${bookmark.title ?? bookmark.chapterTitle ?? 'this bookmark'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(bookmarkRepositoryProvider).deleteBookmark(bookmark.id);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(bookByIdProvider(widget.bookId));
    return Scaffold(
      body: SafeArea(
        top: false,
        left: false,
        right: false,
        child: book.when(
          loading: () => _BookDetailsState(
            onBack: _back,
            child: const CircularProgressIndicator(),
          ),
          error: (_, _) => _BookDetailsState(
            onBack: _back,
            child: const Text('Could not load this book.'),
          ),
          data: (book) {
            if (book == null) {
              return _BookDetailsState(
                onBack: _back,
                child: const Text('Book not found.'),
              );
            }
            final toc = _tocFor(book.tocJson);
            final actions = LocalBookActions(
              context,
              ref,
              book,
              onDeleted: _back,
            );
            final busy = ref.watch(
              localBookActionStateProvider.select((state) => state[book.id]),
            );
            return _BookDetailsContent(
              book: book,
              busy: busy,
              actions: actions,
              fileAvailable:
                  _fileAvailable &&
                  LocalBookActions.sameFileSource(book, _fileCheckedBook),
              onMenuOpen: () => _checkFile(actions),
              classificationCache: _classificationCache,
              bookmarkActive:
                  ref
                      .watch(bookmarksForBookProvider(book.id))
                      .asData
                      ?.value
                      .isNotEmpty ??
                  false,
              onBack: _back,
              onContinueReading: () => _continueReading(book),
              onBookmark: () => _showBookmarksAndAnnotations(book),
              toc: toc,
              onToc: toc == null ? () {} : () => _showToc(book, toc),
              onFavorite: () => actions.run(LocalBookAction.favorite),
            );
          },
        ),
      ),
    );
  }
}

class _BookDetailsContent extends ConsumerWidget {
  const _BookDetailsContent({
    required this.book,
    required this.busy,
    required this.actions,
    required this.fileAvailable,
    required this.onMenuOpen,
    required this.classificationCache,
    required this.bookmarkActive,
    required this.onBack,
    required this.onContinueReading,
    required this.onBookmark,
    required this.toc,
    required this.onToc,
    required this.onFavorite,
  });

  final LibraryBook book;
  final LocalBookAction? busy;
  final LocalBookActions actions;
  final bool fileAvailable;
  final VoidCallback onMenuOpen;
  final BookDetailsClassificationCache classificationCache;
  final bool bookmarkActive;
  final VoidCallback onBack;
  final VoidCallback onContinueReading;
  final VoidCallback onBookmark;
  final BookTocSnapshot? toc;
  final VoidCallback onToc;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(readingProgressForBookProvider(book.id));
    final layout = BookDetailsLayout(
      data: LocalBookDetailsViewDataMapper(
        classificationCache: classificationCache,
      ).map(book),
      onBack: onBack,
      cover: BookDetailsCover.hero(book: book),
      primaryAction: BookDetailsFloatMenu(
        key: ValueKey(book.id),
        onRead: onContinueReading,
        onMenuOpen: onMenuOpen,
        actions: [
          for (final item in actions.items(
            busy: busy,
            fileAvailable: fileAvailable,
          ))
            BookDetailsMenuAction(
              label: item.label,
              icon: item.icon,
              semanticLabel: item.semanticLabel,
              enabled: item.enabled,
              busy: item.busy,
              destructive: item.destructive,
              onSelected: () => actions.run(item.value),
            ),
        ],
      ),
      afterPrimaryAction: [
        BookDetailsProgress(progress: progress.asData?.value),
        BookDetailsActionRow(
          tocAvailable: toc?.isUsable ?? false,
          bookmarkActive: bookmarkActive,
          favoriteActive: book.isFavorite,
          favoritePending: busy != null,
          onBookmark: onBookmark,
          onToc: onToc,
          onFavorite: onFavorite,
        ),
      ],
      trailingContent: const [],
    );
    return BookDetailsStatusBar(child: layout);
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('book-details-back'),
      tooltip: AppStrings.back,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(48),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      icon: const Icon(Icons.arrow_back),
    );
  }
}

class _BookDetailsState extends StatelessWidget {
  const _BookDetailsState({required this.onBack, required this.child});

  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.all(context.appTokens.pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BackButton(onPressed: onBack),
            Expanded(child: Center(child: child)),
          ],
        ),
      ),
    );
  }
}

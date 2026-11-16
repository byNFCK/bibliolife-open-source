import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/features/book_details/application/providers/book_file_export_service_provider.dart';
import 'package:bibliolife/features/book_details/application/services/book_file_export_service.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_modal_sheet_scaffold.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_edit_sheet.dart';
import 'package:bibliolife/features/collections/presentation/widgets/collection_selector_sheet.dart';
import 'package:bibliolife/features/library/application/providers/library_providers.dart';
import 'package:bibliolife/features/library/application/providers/library_use_case_providers.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:bibliolife/shared/presentation/widgets/app_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LocalBookAction { favorite, collection, refresh, edit, save, delete }

final localBookActionStateProvider =
    NotifierProvider<LocalBookActionState, Map<String, LocalBookAction>>(
      LocalBookActionState.new,
    );

class LocalBookActionState extends Notifier<Map<String, LocalBookAction>> {
  @override
  Map<String, LocalBookAction> build() => {};
  bool start(String id, LocalBookAction action) {
    if (state.containsKey(id)) return false;
    state = {...state, id: action};
    return true;
  }

  void finish(String id) {
    if (ref.mounted) state = {...state}..remove(id);
  }
}

/// The same definitions and operations serve every local-book menu.
class LocalBookActions {
  LocalBookActions(this.context, this.ref, this.book, {this.onDeleted});
  final BuildContext context;
  final WidgetRef ref;
  final LibraryBook book;
  final VoidCallback? onDeleted;

  List<AppContextMenuAction<LocalBookAction>> items({
    required LocalBookAction? busy,
    required bool fileAvailable,
    bool allowDelete = true,
  }) {
    final favoriteLabel = book.isFavorite
        ? 'Remove from favorites'
        : 'Add to favorites';
    AppContextMenuAction<LocalBookAction> item(
      LocalBookAction action,
      String label,
      IconData icon, {
      bool enabled = true,
      bool destructive = false,
    }) => AppContextMenuAction(
      value: action,
      label: label,
      icon: icon,
      semanticLabel: '$label, ${book.title}',
      enabled: busy == null && enabled,
      busy: busy == action,
      destructive: destructive,
    );
    return [
      item(
        LocalBookAction.favorite,
        favoriteLabel,
        book.isFavorite ? Icons.favorite : Icons.favorite_border,
      ),
      item(
        LocalBookAction.collection,
        AppStrings.addToCollection,
        Icons.playlist_add,
      ),
      item(LocalBookAction.edit, AppStrings.editBook, Icons.edit_outlined),
      item(
        LocalBookAction.save,
        AppStrings.saveBookFile,
        Icons.save_alt,
        enabled: fileAvailable,
      ),
      if (allowDelete)
        item(
          LocalBookAction.delete,
          AppStrings.delete,
          Icons.delete_outline,
          destructive: true,
        ),
    ];
  }

  static bool sameFileSource(LibraryBook a, LibraryBook? b) =>
      b != null &&
      a.id == b.id &&
      a.filePath == b.filePath &&
      a.originalFilePath == b.originalFilePath &&
      a.fileSizeBytes == b.fileSizeBytes &&
      a.format == b.format;

  Future<bool> canSave() async {
    try {
      return await ref
              .read(bookFileExportServiceProvider)
              .resolveSource(book) !=
          null;
    } catch (_) {
      return false;
    }
  }

  Future<void> run(LocalBookAction action) async {
    final state = ref.read(localBookActionStateProvider.notifier);
    if (!state.start(book.id, action)) return;
    void message(String text) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(text)));
      }
    }

    try {
      switch (action) {
        case LocalBookAction.favorite:
          await ref.read(setBookFavoriteProvider)(book.id, !book.isFavorite);
        case LocalBookAction.collection:
          await showBookDetailsModalSheet<void>(
            context: context,
            title: 'Add to collection',
            footerLabel: 'Apply',
            useRootNavigator: true,
            content: CollectionSelectorSheet(bookId: book.id),
          );
        case LocalBookAction.refresh:
          ref.invalidate(bookByIdProvider(book.id));
          await WidgetsBinding.instance.endOfFrame;
        case LocalBookAction.edit:
          await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            isDismissible: false,
            enableDrag: false,
            builder: (_) => BookEditSheet(book: book),
          );
        case LocalBookAction.save:
          final outcome = await ref
              .read(bookFileExportServiceProvider)
              .export(book);
          switch (outcome) {
            case BookFileSaveOutcome.saved:
              message(AppStrings.bookFileSaved);
            case BookFileSaveOutcome.cancelled:
              break;
            case BookFileSaveOutcome.unavailable:
              message(AppStrings.bookFileUnavailable);
            case BookFileSaveOutcome.failed:
            case BookFileSaveOutcome.busy:
              message(AppStrings.bookFileSaveError);
          }
        case LocalBookAction.delete:
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete book?'),
              content: Text(
                'Remove "${book.title}" and its saved reading progress from BiblioLife?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          if (confirmed == true && context.mounted) {
            await ref.read(deleteBookProvider)(book.id);
            if (context.mounted) {
              if (onDeleted != null) {
                onDeleted!();
              } else {
                message('Book deleted.');
              }
            }
          }
      }
    } catch (_) {
      message(switch (action) {
        LocalBookAction.favorite => 'Could not update favorite status.',
        LocalBookAction.delete => 'Could not delete book.',
        LocalBookAction.save => AppStrings.bookFileSaveError,
        _ => 'Could not complete this action.',
      });
    } finally {
      state.finish(book.id);
    }
  }
}

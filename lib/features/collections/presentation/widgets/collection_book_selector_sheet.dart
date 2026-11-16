import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/features/library/application/providers/library_providers.dart';
import 'package:bibliolife/features/collections/presentation/widgets/collection_draft_books_sliver.dart';
import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CollectionBookSelectorSheet extends ConsumerStatefulWidget {
  const CollectionBookSelectorSheet({
    required this.initialSelectedBookIds,
    this.accentScheme,
    super.key,
  });

  final Set<String> initialSelectedBookIds;
  final ColorScheme? accentScheme;

  @override
  ConsumerState<CollectionBookSelectorSheet> createState() =>
      _CollectionBookSelectorSheetState();
}

class _CollectionBookSelectorSheetState
    extends ConsumerState<CollectionBookSelectorSheet> {
  late Set<String> _selectedBookIds;

  @override
  void initState() {
    super.initState();
    _selectedBookIds = Set.of(widget.initialSelectedBookIds);
  }

  void _toggle(String id) {
    setState(() {
      if (!_selectedBookIds.remove(id)) _selectedBookIds.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final books = ref.watch(allBooksProvider);
    final mode = ref.watch(libraryViewModeProvider);
    return Material(
      key: const Key('collection-book-selector'),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          children: [
            AppBar(
              automaticallyImplyLeading: false,
              title: const Text('Add books'),
              actions: [
                TextButton(
                  key: const Key('collection-book-selector-done'),
                  style: widget.accentScheme == null
                      ? null
                      : TextButton.styleFrom(
                          foregroundColor: widget.accentScheme!.primary,
                        ),
                  onPressed: () => Navigator.of(context).pop(_selectedBookIds),
                  child: const Text(AppStrings.done),
                ),
              ],
            ),
            Expanded(
              child: books.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) =>
                    const Center(child: Text('Could not load books.')),
                data: (items) => items.isEmpty
                    ? const Center(child: Text('No books in your library.'))
                    : CustomScrollView(
                        key: PageStorageKey(('collection-selector', mode)),
                        slivers: [
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              mode == LibraryViewMode.grid ? 16 : 0,
                              0,
                              mode == LibraryViewMode.grid ? 16 : 0,
                              24,
                            ),
                            sliver: CollectionDraftBooksSliver(
                              books: items,
                              mode: mode,
                              itemPrefix: 'collection-book-selector',
                              onSelect: (book) => _toggle(book.id),
                              actionBuilder: (book) => Checkbox(
                                key: ValueKey(
                                  'collection-book-option-${book.id}',
                                ),
                                semanticLabel: 'Select ${book.title}',
                                value: _selectedBookIds.contains(book.id),
                                activeColor: widget.accentScheme?.primary,
                                checkColor: widget.accentScheme?.onPrimary,
                                onChanged: (_) => _toggle(book.id),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

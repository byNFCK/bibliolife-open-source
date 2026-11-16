import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/app/theme/app_spacing.dart';
import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:bibliolife/features/library/application/providers/library_providers.dart';
import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_grid.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  var _query = '';
  var _queryRevision = 0;

  void _setQuery(String value) {
    final query = value.trim().toLowerCase();
    if (query == _query) return;
    setState(() {
      _query = query;
      // A new query starts a fresh pair of mode-specific scroll positions,
      // including when the user later repeats an earlier query.
      _queryRevision++;
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.search)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(context.appTokens.pagePadding),
              child: SearchBar(
                controller: _textController,
                focusNode: _focusNode,
                autoFocus: true,
                hintText: 'Search your library',
                leading: const Icon(Icons.search),
                trailing: [
                  if (_query.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _textController.clear();
                        _setQuery('');
                      },
                      icon: const Icon(Icons.clear),
                    ),
                ],
                onChanged: _setQuery,
              ),
            ),
            Expanded(
              child: _SearchResults(
                query: _query,
                queryRevision: _queryRevision,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Observe data/layout only inside results so mode and book updates do not
// rebuild the SearchBar or replace its text controller and focus node.
class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query, required this.queryRevision});

  final String query;
  final int queryRevision;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(allBooksProvider);
    final mode = ref.watch(libraryViewModeProvider);
    return books.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(child: Text('Search is unavailable.')),
      data: (items) {
        final matches = query.isEmpty
            ? items
            : items.where((book) {
                return book.title.toLowerCase().contains(query) ||
                    (book.author?.toLowerCase().contains(query) ?? false);
              }).toList();
        if (matches.isEmpty) {
          return const Center(child: Text('No matching books'));
        }
        return LayoutBuilder(
          builder: (context, constraints) => CustomScrollView(
            key: PageStorageKey('local-search-$queryRevision-${mode.name}'),
            semanticChildCount: matches.length,
            slivers: [
              if (mode == LibraryViewMode.grid)
                LibraryGrid(
                  books: matches,
                  width: constraints.maxWidth,
                  itemKeyPrefix: 'search',
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    MediaQuery.viewPaddingOf(context).bottom + AppSpacing.md,
                  ),
                )
              else
                LibraryList(
                  books: matches,
                  itemKeyPrefix: 'search',
                  padding: EdgeInsets.only(
                    bottom:
                        MediaQuery.viewPaddingOf(context).bottom +
                        AppSpacing.md,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

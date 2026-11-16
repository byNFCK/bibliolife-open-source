import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/features/library/application/providers/library_section_provider.dart';
import 'package:bibliolife/shared/presentation/widgets/biblio_tabs.dart';
import 'package:flutter/material.dart';

class LibrarySectionTabs extends StatelessWidget {
  const LibrarySectionTabs({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final LibrarySection selected;
  final ValueChanged<LibrarySection> onSelected;

  static const _items = [
    BiblioTabItem(
      id: LibrarySection.collection,
      label: AppStrings.collection,
      key: Key('library-tab-collection'),
    ),
    BiblioTabItem(
      id: LibrarySection.follow,
      label: AppStrings.follow,
      key: Key('library-tab-follow'),
    ),
    BiblioTabItem(
      id: LibrarySection.allBooks,
      label: AppStrings.allBooks,
      key: Key('library-tab-all-books'),
    ),
  ];

  @override
  Widget build(BuildContext context) => BiblioTabs<LibrarySection>(
    key: const Key('library-section-tab-bar'),
    items: _items,
    selectedId: selected,
    onSelected: onSelected,
  );
}

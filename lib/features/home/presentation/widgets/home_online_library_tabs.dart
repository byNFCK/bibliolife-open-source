import 'package:bibliolife/app/theme/app_spacing.dart';
import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/shared/presentation/widgets/biblio_tabs.dart';
import 'package:flutter/material.dart';

/// Maps the configured catalog sources to the shared tab strip.
class HomeOnlineLibraryTabs extends StatelessWidget {
  const HomeOnlineLibraryTabs({
    required this.libraries,
    required this.selectedLibraryId,
    required this.onSelected,
    super.key,
  });

  final List<CatalogSource> libraries;
  final String selectedLibraryId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      context.appTokens.pagePadding,
      0,
      context.appTokens.pagePadding,
      AppSpacing.md,
    ),
    child: BiblioTabs<String>(
      key: const Key('home-online-library-tabs'),
      scrollStorageKey: const PageStorageKey('home-online-library-tabs-scroll'),
      items: [
        for (final library in libraries)
          BiblioTabItem(
            id: library.id,
            label: library.name,
            key: ValueKey('home-online-library-${library.id}'),
          ),
      ],
      selectedId: selectedLibraryId,
      onSelected: onSelected,
    ),
  );
}

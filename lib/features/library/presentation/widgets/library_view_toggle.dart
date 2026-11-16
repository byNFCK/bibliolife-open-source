import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:bibliolife/app/localization/app_strings.dart';

class LibraryViewToggle extends StatelessWidget {
  const LibraryViewToggle({
    required this.viewMode,
    required this.onPressed,
    super.key,
  });

  final LibraryViewMode viewMode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isGrid = viewMode == LibraryViewMode.grid;
    final tooltip = isGrid ? AppStrings.showListView : AppStrings.showGridView;

    return Semantics(
      label: tooltip,
      button: true,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(
          isGrid ? Icons.view_list_outlined : Icons.grid_view_outlined,
        ),
      ),
    );
  }
}

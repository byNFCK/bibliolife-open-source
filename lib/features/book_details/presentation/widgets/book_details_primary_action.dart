import 'package:flutter/material.dart';

/// The approved Read/Download action appearance, using the active palette.
ButtonStyle bookDetailsPrimaryActionStyle(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(56),
    backgroundColor: colors.primaryContainer,
    foregroundColor: colors.onPrimaryContainer,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
  );
}

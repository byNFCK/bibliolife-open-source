import 'package:flutter/material.dart';

/// Shared outline and shape for the app and Readium floating navigation shells.
abstract final class FloatingNavigationShellStyle {
  static const radius = 28.0;
  static const outlineWidth = 1.0;
  static const clipBehavior = Clip.antiAlias;

  static RoundedRectangleBorder shapeFor(BuildContext context) =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: outlineWidth,
        ),
      );
}

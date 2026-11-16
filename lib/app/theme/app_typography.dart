import 'package:flutter/material.dart';

abstract final class AppTypography {
  static TextTheme build({
    required Color primaryColor,
    required Color secondaryColor,
  }) {
    return TextTheme(
      headlineSmall: TextStyle(
        color: primaryColor,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(color: primaryColor, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: primaryColor),
      bodyMedium: TextStyle(color: secondaryColor),
      labelLarge: TextStyle(color: primaryColor, fontWeight: FontWeight.w600),
    );
  }
}

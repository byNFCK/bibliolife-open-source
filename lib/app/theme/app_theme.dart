import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const bibliolifeSeedColor = Color(0xFF435F91);

final fallbackLightColorScheme = ColorScheme.fromSeed(
  seedColor: bibliolifeSeedColor,
  brightness: Brightness.light,
);
final fallbackDarkColorScheme = ColorScheme.fromSeed(
  seedColor: bibliolifeSeedColor,
  brightness: Brightness.dark,
);

ThemeData buildAppTheme(ColorScheme colorScheme) {
  final tokens = AppThemeTokens.standard();
  final isDark = colorScheme.brightness == Brightness.dark;
  final overlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: isDark
        ? Brightness.light
        : Brightness.dark,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.surface,
    extensions: [tokens],
    textTheme: Typography.material2021().black.apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    ),
    dividerTheme: DividerThemeData(color: colorScheme.outlineVariant),
    cardTheme: CardThemeData(
      color: colorScheme.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.cardRadius),
      ),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      systemOverlayStyle: overlayStyle,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: tokens.navigationHeight,
      elevation: 0,
      backgroundColor: colorScheme.surfaceContainerHigh,
      indicatorColor: colorScheme.secondaryContainer,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return IconThemeData(
          color: states.contains(WidgetState.selected)
              ? colorScheme.onSecondaryContainer
              : colorScheme.onSurfaceVariant,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return ThemeData(
          colorScheme: colorScheme,
        ).textTheme.labelMedium?.copyWith(
          color: states.contains(WidgetState.selected)
              ? colorScheme.onSecondaryContainer
              : colorScheme.onSurfaceVariant,
        );
      }),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
  );
}

final lightTheme = buildAppTheme(fallbackLightColorScheme);
final darkTheme = buildAppTheme(fallbackDarkColorScheme);

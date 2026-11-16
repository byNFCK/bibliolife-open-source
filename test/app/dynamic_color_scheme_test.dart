// The plugin API and its sampled fixture still use MCU's deprecated CorePalette.
// ignore_for_file: deprecated_member_use

import 'package:bibliolife/app/theme/app_theme.dart';
import 'package:bibliolife/app/theme/dynamic_color_scheme.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:material_color_utilities/material_color_utilities.dart';

void main() {
  // Recreate the plugin's sampled-palette boundary, for two different hues.
  final palettes = [
    CorePalette.fromList(CorePalette.of(0xff428a47).asList()),
    CorePalette.fromList(CorePalette.of(0xff9650aa).asList()),
  ];
  for (var i = 0; i < palettes.length; i++) {
    for (final brightness in Brightness.values) {
      test(
        'palette $i $brightness matches Material roles and preserves other fields',
        () {
          final palette = palettes[i];
          final reference = DynamicScheme(
            sourceColorHct: Hct.fromInt(palette.primary.get(40)),
            variant: Variant.tonalSpot,
            isDark: brightness == Brightness.dark,
            primaryPalette: palette.primary,
            secondaryPalette: palette.secondary,
            tertiaryPalette: palette.tertiary,
            neutralPalette: palette.neutral,
            neutralVariantPalette: palette.neutralVariant,
          );
          final expected = palette
              .toColorScheme(brightness: brightness)
              .copyWith(
                surfaceDim: Color(reference.surfaceDim),
                surfaceBright: Color(reference.surfaceBright),
                surfaceContainerLowest: Color(reference.surfaceContainerLowest),
                surfaceContainerLow: Color(reference.surfaceContainerLow),
                surfaceContainer: Color(reference.surfaceContainer),
                surfaceContainerHigh: Color(reference.surfaceContainerHigh),
                surfaceContainerHighest: Color(
                  reference.surfaceContainerHighest,
                ),
              );
          final actual = dynamicSchemeFromCorePalette(palette, brightness);
          expect(actual, expected);
          final levels = [
            actual.surfaceContainerLowest,
            actual.surfaceContainerLow,
            actual.surfaceContainer,
            actual.surfaceContainerHigh,
            actual.surfaceContainerHighest,
          ];
          for (var j = 1; j < levels.length; j++) {
            final previous = levels[j - 1].computeLuminance();
            final next = levels[j].computeLuminance();
            expect(
              brightness == Brightness.dark
                  ? next >= previous
                  : next <= previous,
              isTrue,
            );
          }
        },
      );
    }
  }
  test('different sampled palettes retain different neutral colors', () {
    for (final brightness in Brightness.values) {
      expect(
        dynamicSchemeFromCorePalette(palettes[0], brightness).surfaceContainer,
        isNot(
          dynamicSchemeFromCorePalette(
            palettes[1],
            brightness,
          ).surfaceContainer,
        ),
      );
    }
  });
  test('fallback themes retain original seed schemes', () {
    for (final brightness in Brightness.values) {
      final expected = ColorScheme.fromSeed(
        seedColor: bibliolifeSeedColor,
        brightness: brightness,
      );
      final fallback = brightness == Brightness.light
          ? fallbackLightColorScheme
          : fallbackDarkColorScheme;
      expect(fallback, expected);
      expect(buildAppTheme(fallback).colorScheme, expected);
    }
  });
}

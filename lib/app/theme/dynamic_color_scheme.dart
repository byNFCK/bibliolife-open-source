import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
// CorePalette is supplied by dynamic_color, which already depends on MCU.
// ignore: depend_on_referenced_packages
import 'package:material_color_utilities/material_color_utilities.dart';

/// Completes only the Material 3 normal-contrast surface roles. Android's
/// sampled neutral tones are retained; MCU derives missing tones in HCT from
/// the hue and chroma estimated by TonalPalette.fromList.
ColorScheme dynamicSchemeFromCorePalette(
  // dynamic_color exposes CorePalette despite its MCU deprecation.
  // ignore: deprecated_member_use
  CorePalette palette,
  Brightness brightness,
) {
  final scheme = palette.toColorScheme(brightness: brightness);
  final neutral = palette.neutral;
  final dark = brightness == Brightness.dark;
  Color tone(int light, int darkTone) =>
      Color(neutral.get(dark ? darkTone : light));
  // MaterialDynamicColors, normal contrast (0), MCU 0.13.
  return scheme.copyWith(
    surfaceDim: tone(87, 6),
    surfaceBright: tone(98, 24),
    surfaceContainerLowest: tone(100, 4),
    surfaceContainerLow: tone(96, 10),
    surfaceContainer: tone(94, 12),
    surfaceContainerHigh: tone(92, 17),
    surfaceContainerHighest: tone(90, 22),
  );
}

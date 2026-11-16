# Implemented design system

Source review: 2026-11-10. Values below are Flutter logical pixels unless stated otherwise. This describes the working implementation, not a proposed redesign or device-accessibility certification.

## Theme and color

`lib/app/theme/app_theme.dart` builds Material 3 (`useMaterial3: true`) from a `ColorScheme`. `lib/app/app.dart` requests a platform CorePalette, then a platform accent-derived scheme if no palette is available; the fallback seed is `#435F91` for both brightness modes. Theme injection is also supported. `theme_mode_provider.dart` defaults to `ThemeMode.system`; its notifier holds state in memory and does not itself persist the selection.

`dynamic_color_scheme.dart` completes neutral surface roles at normal contrast. Light/dark tone pairs are: surfaceDim 87/6, surfaceBright 98/24, surfaceContainerLowest 100/4, Low 96/10, Container 94/12, High 92/17, Highest 90/22. These are palette tones, not fixed hex colors.

| Role | Confirmed usage |
| --- | --- |
| `surface`, `onSurface` | Scaffold/app bar and primary text; floating navigation background |
| `surfaceContainerLow` | Cards |
| `surfaceContainerHigh` | Tab tracks and book-card bottom panels |
| `surfaceContainerHighest` | Filled inputs |
| `secondaryContainer`, `onSecondaryContainer` | Selected tab and navigation treatment |
| `onSurfaceVariant` | Unselected navigation/tab foreground |
| `outlineVariant` | Dividers, input borders and floating-shell outline |
| `primary` | Focused input border, width 2 |

Floating navigation falls back to primaryContainer/onPrimaryContainer when secondaryContainer equals surface. BiblioTabs blends onSurface at 10% over the page if its track color equals the page color. Actual colors depend on the platform palette and brightness.

## Typography

The active theme uses `Typography.material2021().black.apply(...)`, recoloring body/display text with onSurface. It does not install `AppTypography.build`. No active custom font is declared in `pubspec.yaml`; reader publication typography is a separate concern. Filled buttons and tabs use weight w600; tabs honor platform bold text. `AppBookListTile` locally overrides titleMedium to size 18, weight w600 and height 1.2.

## Tokens

Sources: `lib/app/theme/app_spacing.dart`, `app_radius.dart`, `app_theme_tokens.dart`.

| Token family | Values |
| --- | --- |
| AppSpacing | xs 4, sm 8, md 16, lg 24, xl 32, xxl 48 |
| AppRadius | sm 8, md 12, lg 16, xl 24 |
| AppThemeTokens layout | pagePadding 20, sectionSpacing 32, carouselGap 12 |
| Book card | width 164, aspect ratio 0.65, cover aspect ratio 2/3, radius 24, outline width 1 |
| Book card bottom bar | height 40, horizontal padding 12, favorite icon 20, grid gap 16 |
| Navigation/button tokens | navigationRadius 24, navigationHeight 64, buttonRadius 999 |

`AppThemeTokens` is a ThemeExtension with interpolation and a standard fallback. A declared token is not proof every component consumes it.

## Components

`app_theme.dart` sets zero-elevation cards with radius 24; app bars have no elevation or scrolled-under elevation and use leading-aligned titles. Inputs are filled with radius 24 and outline borders; filled buttons have minimum size 48×48 and w600 text. The themed Material NavigationBar has height 64, no elevation and secondary-container selection, but the main shell uses a custom island instead.

Shared widget sources under `lib/shared/presentation/widgets/`:

- `app_book_card.dart`: card/cover layout with progress and optional favorite action; bottom panel uses surfaceContainerHigh at alpha 0.8 and blur sigma 8.
- `app_book_list_tile.dart`: cover 92×138, radius 12, cover gap 16, progress height 28 and action extent 48; measures text with current scaling and locale.
- `app_modal_sheet_scaffold.dart`: shared sheet presentation; horizontal padding 20, header top padding 12, drag handle 36×4 and button height 48.

## Navigation

`lib/app/router/app_router.dart` uses an indexed-stack stateful shell for Home, Library and Profile. `app_shell.dart` places a floating island above the bottom view inset plus 18, with surface color, elevation 6, horizontal/vertical internal padding 10/8, action spacing 8, touch extent 48, icons 24 and selected circle 40. Its intrinsic width is 244 and height 64. The declared outerHorizontalMargin is 20, but the shell centers a fixed-width island rather than applying that margin as a responsive constraint.

`floating_navigation_shell_style.dart` supplies radius 28, outline width 1 and anti-aliased clipping, shared by Flutter app/reader shells. This differs from the generic navigationRadius token of 24.

## BiblioTabs

`biblio_tabs.dart` is a controlled tab strip: callers own selection and fallback after item removal. Content-sized horizontal tabs can scroll; optional expandToFill distributes equal widths, and stackWhenNarrow enables vertical stacking when measured labels do not fit. Labels use current locale, direction and text scaling, with ellipsis for overflow. Item width is capped at 320; default horizontal label padding is 14, track padding is at most 4, and the default horizontal minimum height is 42. Stacked item height is at least 48 or measured label height + 12. Do not infer a universal 48-pixel tab height from the stacked mode.

Track/indicator shapes are stadiums; stacked track radius is 24. Selected foreground is onSecondaryContainer; other tabs use onSurfaceVariant; disabled foreground alpha is 0.38. Semantics expose tabBar/tab roles, selection, enabled state and mutually exclusive grouping. See [motion](motion.md) for selection and visibility animations.

## Accessibility, adaptation and gaps

Confirmed measures include navigation semantics, book/progress labels, BiblioTabs semantics and text measurement, SafeArea/view-inset handling, and local constraint-based layouts. They do not establish complete screen-reader, contrast, keyboard, large-text or tablet acceptance. The fixed-width navigation island and horizontal tabs with default height 42 warrant narrow-screen/touch-target review.

`AppLightColors`, `AppDarkColors`, `AppTypography` and `AppRadius` have no consumers found in the inspected Dart source; they must not be presented as the active palette/type/radius contract. Styling is split between ThemeData, AppThemeTokens and component-local constants, including differing navigation radii and local type sizes. There is no single comprehensive breakpoint or high-contrast policy established by these sources. Reduced Motion support is partial; see the motion reference.

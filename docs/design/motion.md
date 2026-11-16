# Implemented motion

Source review: 2026-11-10, including current uncommitted Reader/router work. This is a source-level record. No animations were changed, and no device run, build or physical acceptance was performed for this documentation. Durations below are milliseconds; framework defaults are identified rather than guessed.

## Navigation and floating navigation

Source: `lib/app/router/app_router.dart`, `app_shell.dart`.

- Home/Library/Profile use `StatefulShellRoute.indexedStack`. No custom animated branch-container transition is specified. Reselecting the active destination requests its initial location.
- Local Book Details and remote Publication Details use `NoTransitionPage`: there is no route-level transition. The `_BookDetailsCoverHero` name in `book_details_cover.dart` does not itself establish a Flutter Hero flight; the inspected cover implementation builds image/layout widgets.
- Reader entry is a fade plus vertical slide from Offset(0, 0.025) to zero: forward 260 with easeOutCubic; reverse 220 with easeInCubic. No explicit disableAnimations check appears in this route builder.
- Other builder-based routes use framework/router transitions; their duration and curves are not set here.
- The app floating island is positioned above bottom view padding + 18. Selection directly changes icons and a 40-pixel circle; no explicit selection/movement animation is specified. InkResponse splash and highlight are transparent.

## BiblioTabs

Source: `lib/shared/presentation/widgets/biblio_tabs.dart`.

The selected capsule uses AnimatedPositionedDirectional for position and width, or vertical placement in stacked mode: 200, easeInOut. After layout, selection/viewport/content-size changes reveal an offscreen selected tab with ScrollController.animateTo using the same 200/easeInOut. Already visible selection does not force centering. Initial offset is clamped to keep the selected tab visible; a supplied PageStorage key restores/saves scroll position.

Both animations use Duration.zero under MediaQuery.disableAnimations; reveal then uses jumpTo. This setting does not independently suppress every Material ink effect or caller-owned page animation.

## Library header and scrolling

Sources: `lib/features/library/presentation/screens/library_screen.dart` and `widgets/library_header.dart`.

The Library uses NestedScrollView with floatHeaderSlivers enabled. The search/actions row is a scrolling SliverToBoxAdapter; the tabs row is a PinnedHeaderSliver inside SliverOverlapAbsorber. Reverse scroll prioritizes revealing the outer row even when the active inner page is away from the top. This collapse/reveal is driven by scroll geometry, not a named timed header animation; no fixed duration or curve is declared for it.

Sections use PageView and PageController. Programmatic selection calls animateToPage: 260, easeOutCubic. The code retains the requested selection while passing intermediate pages and supports user drag takeover. No explicit Reduced Motion branch appears in this call. Page storage and per-page scroll-controller coordination retain positions while coordinating the visible inner page; this is not evidence of universally smooth device performance. Scroll physics without explicit overrides remain framework behavior.

## Book Details and sheets

Sources: `lib/features/book_details/presentation/widgets/expandable_book_details_section.dart`, `book_details_cover.dart`, and `lib/shared/presentation/widgets/app_modal_sheet_scaffold.dart`.

Expandable detail sections use AnimatedSize aligned top-center: 200, easeInOutCubic, or zero under disableAnimations. Cover layout adapts to constraints and image availability; no cover-flight duration is established by the inspected implementation.

The shared app modal-sheet AnimationStyle declares forward 200 and reverse 160. Its curve is not overridden by that style; framework sheet behavior applies. The shared helper enables dragging and scroll-controlled presentation. The helper does not explicitly substitute a zero-duration style for Reduced Motion. Background/foreground opacity properties default to kThemeChangeDuration; AnimatedOpacity instances without a curve override use their default linear curve.

## Reader UI

Sources: `lib/features/reader/presentation/widgets/unified_reader_screen.dart` and `reader_stable_components.dart`.

- Top and bottom chrome slide between zero and offsets (0, -1)/(0, 1): 180, easeOutCubic. Concurrent opacity changes use 180 with the default linear curve. Hidden controls ignore pointer input. Chrome is shown when controls are visible or an error exists; native selection suppression removes the chrome immediately. These chrome animations have no explicit disableAnimations branch.
- Slider interaction fades surrounding sheet/chrome content and the modal barrier toward opacity 0.15: 150, default linear for AnimatedOpacity. These paths explicitly reduce duration to zero under disableAnimations.
- Reader menus use the shared appModalSheetAnimation (200/160); the style does not itself specify a custom curve or Reduced Motion override.

This record covers Flutter UI motion. Native EPUB scrolling, pagination, reflow and progress-command completion have separate renderer/lifecycle behavior; their exact physical timing and acceptance are not established here. Operational timeouts and scrub cadence are not animation durations. No claim of completed Reader stabilization follows from these UI constants.

## Reduced Motion and acceptance gaps

Implemented explicit handling exists for BiblioTabs, expandable Book Details sections and Reader slider-focus fades. Explicit handling is absent from the inspected Reader route, chrome animations, Library page animation and shared sheet style. Framework/platform behavior may still influence runtime output; a global application-wide Reduced Motion guarantee is not established.

There is no unified motion token set in the inspected implementation. Smoothness, gesture interruption, nested scroll restoration, native reader transitions and large-text/Reduced Motion behavior require separate device verification. Historical validation reports are linked from the [documentation index](../index.md); their conclusions apply to the versions and scenarios they actually tested, not automatically to this working tree. No intended future behavior is treated as implemented in this reference.

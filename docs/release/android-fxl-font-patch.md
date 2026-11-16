# Android Fixed-Layout system-font patch

## Decision

BiblioLife's public-source candidate excludes Readium's legacy Android system-font patch and its eight Nimbus Sans/Roman WOFF files. The exact license grant and conversion provenance for those WOFF files were not established, so this repository does not redistribute them.

## What the patch was for

The vendored Readium patch documentation describes it as an optional Android-only workaround for Fixed-Layout EPUBs that contain positioned text but do not embed fonts. It maps Nimbus Roman to Times/Times New Roman and Nimbus Sans to Helvetica/Arial because their metrics are intended to be compatible with those common fonts. Readium's documentation says implementers decide when to load it; it is not a default mandatory stylesheet.

## Current BiblioLife behavior

A source inspection of this candidate found:
- `FixedWebRenditionState` loads the generated fixed-layout scripts, not the generated `readium-css/android-fonts-patch` stylesheet.
- `FixedSingleAreaApi` and `FixedDoubleAreaApi` load the fixed-layout HTML entrypoints and do not inject the Android font patch.
- The reflowable `ReadiumCss.kt` loader points to the separate `readium/readium-css/` asset tree; it does not reference `android-fonts-patch`.
- No application/native runtime source references the `android-fonts-patch` path.
- The web-internals webpack copy configuration now explicitly ignores `**/android-fonts-patch/**`, preventing a regeneration from copying the optional patch from the pinned `@readium/css` package.

The app therefore continues using its existing platform font fallback for these Fixed-Layout publications. This remediation removes dormant optional assets and prevents their regeneration; it does not change the active reader rendering algorithm.

## Known limitation

A Fixed-Layout EPUB that uses Times, Times New Roman, Arial or Helvetica in positioned text but does not embed the relevant fonts may render with Android's system fallback. Line wrapping, text-block geometry, overflow or overlap can differ from a system that injects metric-compatible Nimbus fonts. Prior isolated WebView A/B evidence in the audit showed that injecting the patch changes text geometry. This candidate does not claim pixel-identical FXL rendering for those publications.

Reintroducing a font patch requires:
1. a traceable font source and exact license/exception that permits the intended redistribution;
2. an explicit design decision to support this optional behavior;
3. regression testing on physical Android devices with FXL books that have unembedded positioned text, embedded fonts, images, TOC/link navigation, zoom and orientation changes.

Do not copy the removed WOFF files back into the repository or APK without completing those steps.

## References

- [Readium Android system generic families patch documentation](https://readium.org/css/docs/CSS09-default_fonts.html)
- [Readium CSS 2.0 migration guide](https://readium.org/css/docs/CSS28-migration_guide.html) — states that stable Readium CSS 2 no longer distributes fonts or the Android FXL patch.
- [Readium CSS package and release history](https://www.npmjs.com/package/@readium/css)
- [CopyWebpackPlugin `globOptions.ignore` documentation](https://www.npmjs.com/package/copy-webpack-plugin)

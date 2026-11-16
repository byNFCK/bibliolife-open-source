# BiblioLife asset provenance — release candidate

**Review date:** 2026-11-15  
**Result:** All 147 historical resource entries in the prior asset audit are resolved, attributed, replaced or excluded for this candidate. No owner-input rows remain in that historical inventory.

## Resolution summary

| Resolution | Count | Evidence / action |
|---|---:|---|
| Pinned Readium upstream resources | 79 | Exact Git blob matches against Readium Kotlin Toolkit commit `fe4c32b97f4745971facfbdfbde31520553c770`; toolkit BSD-3-Clause retained |
| Nimbus WOFF files | 8 | Removed from source candidate; build copy excludes the optional patch |
| Synthetic local test fixtures | 2 | 1×1 PNG and text fixture `text1`; BiblioLife test data under GPL-3.0-or-later |
| Owner-input rows | 50 | Replaced/attributed/project-owned; details in resolution CSV |
| Previously disputed icons | 2 | Annotation icon replaced with Material Icons 4.0.0; unused add-highlight drawable removed |
| Previously resolved items | 6 | Flutter template assets attributed, OpenDyslexic terms retained, owner icon refreshed |
| **Total** | **147** | **0 unresolved owner-input rows; 0 unresolved entries in this historical inventory** |

## 50 owner-input entries

All 50 rows from `BiblioLife-owner-input-required-2026-11-15.csv` were closed:

- 33 asset replacements: nine Reader vector icons replaced with Material Icons 4.0.0 equivalents and 24 iOS/macOS/web/Windows icon exports regenerated from the owner-confirmed BiblioLife master artwork.
- Four exact Flutter 3.44.7 template metadata files were attributed under Flutter BSD-3-Clause.
- Six Android theme/launch resources were identified as Flutter scaffold-derived or BiblioLife-specific Android configuration; applicable Flutter template attribution is retained.
- Seven project-owned strings and synthetic test geometry fixtures are covered by the root GPL-3.0-or-later grant.

The 24 platform icon exports use the owner-confirmed `assets/icons/app_icon.png` master. The original Flutter placeholder logo was replaced in the iOS, macOS, web/PWA and Windows app-icon slots. `ASSETS.md` records this provenance.

## Readium source verification

The 79 retained Readium resources were compared to the exact pinned upstream commit. Binary files were compared as raw Git blobs; text files were compared after CRLF-to-LF normalization. The set includes the vendored PhotoView 2.3.0 and AndroidPdfViewer 2.8.2 JARs, Readium demo/test-app artwork, OPDS examples, format sniffing fixtures, `settings-flow.svg`, and the LCP `prod-license.lcpl` probe. The upstream Readium Kotlin Toolkit BSD-3-Clause license and copyright notice remain in `third_party/readium-kotlin-toolkit/LICENSE`.

The `prod-license.lcpl` file is an exact upstream fixture for the public-domain `Moby-Dick` publication; its user fields are encrypted. It is not a BiblioLife-issued license or a production signing credential.

Two local Readium test fixtures differ from upstream and are synthetic:
- `png.unknown`: a 1×1 RGB pixel.
- `text1.txt`: the literal text `text1`.

They contain no third-party publication content and are covered as BiblioLife test data by GPL-3.0-or-later.

## Nimbus exclusion

Eight Nimbus Sans/Roman WOFF files and the associated optional Android FXL patch were removed. The web-internals CopyWebpackPlugin configuration excludes `**/android-fonts-patch/**`, preventing the pinned `@readium/css` beta package from copying them back during regeneration. The exact WOFF redistribution grant was not established; this candidate does not redistribute those fonts. The reader continues using Android system fallback for FXL books that depend on unembedded Times/Arial/Helvetica metrics. This is a documented limitation, not a claim of identical FXL layout. See [Android FXL font patch](android-fxl-font-patch.md).

## Files

- `asset-provenance-resolution.csv`: 147 path-by-path decisions, prior/current SHA-256, evidence and upstream blob IDs.
- `asset-inventory-release-resolution.json`: machine-readable resolution summary and entries.
- `THIRD_PARTY_NOTICES.md`: applicable Readium, Flutter, Material and font notices.

## Scope limitation

This audit closes the historical 147-item resource inventory only. It does not complete the separate dependency-level SBOM or prove every Maven/Flutter/native/engine binary notice in a future APK. Those remain independent release gates, as do production signing, clean build/test validation and physical-device acceptance.

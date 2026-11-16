# BiblioLife Readium source pin

This is the official Readium Kotlin Toolkit source used by BiblioLife through the
Android composite Gradle build. It is pinned to upstream tag `3.2.0`, whose
annotated tag object is `f54560fc87aa84223514b55f16ea886a90aa5b3e` and commit is
`fe4c32b97f4745971facfbdfbde31520553c770e`.

The local patch in `readium/navigator/.../R2BasicWebView.kt` locks the paginated
WebView viewport during native text-handle selection. Upstream license and notice
files are retained unchanged.

The composite build uses AGP 9.0.1 to match BiblioLife's host build; this is an
integration-only version alignment required by Gradle and does not change Readium
runtime source behavior.


## Asset provenance and redistribution

The vendored tree is pinned to upstream commit `fe4c32b97f4745971facfbdfbde31520553c770`. The BiblioLife release audit compared the D3 resource inventory against this exact upstream tree. 79 retained resources match upstream Git blob IDs; text files were compared after normalizing CRLF to LF. These resources remain covered by the toolkit's BSD 3-Clause license in `LICENSE`. Two tiny local synthetic fixtures (`png.unknown`, a 1×1 pixel, and `text1.txt`, containing `text1`) are BiblioLife test data and are covered by the root GPL-3.0-or-later license. The optional Nimbus Android FXL patch is not included in the BiblioLife release candidate; its CSS asset-copy path is excluded in `readium/navigators/web/internals/scripts/webpack.config.js`. See the root `docs/release/asset-provenance.md` and `docs/release/android-fxl-font-patch.md`.

# Dependency SBOM and release-artifact status


> This record describes an earlier candidate. v1.0.0 excludes Junrar and CBR extraction. Current [Android licenses](android-runtime-licenses.csv) and [Dart licenses](dart-runtime-licenses.csv) are available separately.

**Status: PARTIAL — not release clearance.**

## Source-declared inventory

`audit/source-sbom.cdx.json` and `audit/source-dependency-inventory.csv` were generated from:
- `pubspec.lock`;
- the direct Android app/plugin Gradle declarations and selected Readium project modules;
- both Readium `pnpm-lock.yaml` files and their `package.json` manifests;
- the Readium Gradle version catalog and Gradle build declarations;
- verified vendored components and observed toolchain versions.

The inventory currently contains 1,144 declaration rows and 754 unique CycloneDX component PURLs after deduplication. Many entries are optional, dev/test, catalog-only or transitive. 49 declaration rows now have a known license expression, one component has a separate UnRAR license, and 1,094 declaration rows do not have a license resolved from the lockfile or source declaration. This is expected for a source-declared inventory and is not proof that all 754 components are shipped in the application.

## Historical APK evidence

A prior release-candidate build audit (2026-11-14) recorded:
- 133 nodes in the release runtime dependency graph;
- 110 resolved Maven artifacts with SHA-256;
- 10 local variant-resolution errors described in the prior audit log;
- 718 APK entries, including DEX, native libraries and resources;
- Flutter 3.44.7 / Dart 3.12.2, framework commit `84fc5cbb223bc12f83d65b647ff8a56caf779ffd`, engine commit `69c8c61792f04cc809dfef0c910414fb9afc06cd`;
- a complete `NOTICES.Z` extraction and name/SHA index, but not a completed exact license-to-every-shipped-component reconciliation.

This is historical evidence from a previous candidate, not a fresh build of the current source. The current candidate also upgrades Junrar to 8.1.2, switches to NIO desugaring and adds a CBR destination boundary check. A fresh build, resolved dependency graph and artifact inspection are still required.

## Findings that narrow scope

- The previous BiblioLife release runtime graph did not contain `com.github.marain87:AndroidPdfViewer:3.2.8` or `com.github.marain87:PdfiumAndroid:1.9.8`; the app used `pdfx`. These remain optional source-module declarations, not evidence of APK contents.
- PhotoView 2.3.0 and AndroidPdfViewer 2.8.2 are retained in the vendored Readium source with their upstream license texts and provenance evidence.
- The LCP module does not appear as a separate node in the previous BiblioLife release graph, and the prior APK inventory had no `.lcpl` entry. The retained `prod-license.lcpl` is an exact Readium upstream source fixture and remains under the Readium toolkit BSD-3-Clause license.
- The prior APK included Flutter engine/native artifacts for three ABIs. The Flutter `NOTICES.Z` was extracted and indexed, but exact reconciliation of all notice sections to engine, embedding, Dart, SQLite and transitive binaries remains incomplete.
- DEX class attribution to Maven artifacts was not completed.

## Required before publication

1. Build the exact current source candidate with a clean, pinned toolchain and lockfile-enforced dependency resolution.
2. Recreate the release runtime graph and resolve all variant-resolution errors or prove they are optional/unreachable.
3. Inspect the resulting APK/AAB and produce a fresh artifact-level CycloneDX SBOM with DEX/native/resource hashes.
4. Reconcile every shipped component against its exact upstream LICENSE/NOTICE and the APK's `NOTICES.Z`; include license texts and attributions for all shipped binaries.
5. Repeat this audit whenever dependency versions, build plugins, Flutter engine, Readium modules or platform targets change.

The source-declared SBOM is included for transparency and future maintenance. It must not be described as a complete APK SBOM. Junrar 8.1.2 and file_picker 11.0.3 are security updates in this candidate; both require the pinned Pub/Gradle dependency checks and device tests.

## Static Android dependency trace

`docs/release/android-dependency-scope.md` and `audit/android-release-static-dependency-scope.csv` distinguish the selected app/Readium runtime source path from unused optional Readium modules, npm build tooling and test-only declarations. This is a source trace, not a resolved Gradle graph. Junrar 8.1.2, its SLF4J 2.0.17 runtime dependency, and file_picker 11.0.3 are now recorded; the UnRAR license is a separate compatibility review item.

The `sqlite3_flutter_libs` 0.6.0+eol and `sqlcipher_flutter_libs` 0.7.0+eol entries are no-op compatibility packages after sqlite3 3.x; they do not contribute native SQLite/SQLCipher libraries or old build scripts. The `pdfx` Android backend uses the platform PdfRenderer, so the optional Readium PDFium modules are not evidence of PDFium binaries in this Android APK. These static findings must still be checked against the resolved graph and artifact.

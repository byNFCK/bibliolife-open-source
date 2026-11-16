# Android release dependency scope — static source trace


> This record describes an earlier candidate. v1.0.0 excludes Junrar and CBR extraction. Current [Android licenses](android-runtime-licenses.csv) and [Dart licenses](dart-runtime-licenses.csv) are available separately.

**Review date:** 2026-11-16  
**Status:** STATIC SOURCE TRACE ONLY — not a Gradle-resolved dependency graph.

## Reachable project modules

The BiblioLife Android plugin declares Readium shared, streamer and navigator. The host `settings.gradle.kts` substitutes those three Maven coordinates with local projects from the pinned Readium 3.2.0 composite build. Source tracing shows the runtime path reaches the `:readium:shared`, `:readium:streamer` and `:readium:navigator` modules. Their direct and transitive source declarations are listed in `audit/android-release-static-dependency-scope.csv`.

## Modules not referenced by the app's selected project dependency path

The following vendored modules are included/configured in the Readium composite build but are not declared as dependencies of the three selected Readium modules or the BiblioLife plugin in the inspected source:

- Readium LCP (`:readium:lcp`)
- Readium OPDS (`:readium:opds`)
- Readium PDFium adapters (`:readium:adapters:pdfium:*`)
- Readium PSPDFKit adapters (`:readium:adapters:pspdfkit:*`)
- Readium ExoPlayer adapter (`:readium:adapters:exoplayer:*`)
- Readium Compose web navigators and media navigator modules
- Readium demo and test-app modules

This is a static source-reference conclusion only. Gradle configuration may still evaluate build plugins and build logic for included projects; a resolved graph is required to prove the exact artifact set.

## JavaScript packages

The two `pnpm-lock.yaml` files describe build/test tooling for Readium JavaScript assets. The app consumes committed generated navigator assets; npm lockfile packages are not automatically Android runtime Maven artifacts. The `readium/navigator` script package has production dependencies used to generate its bundled JavaScript. The web-internals package is associated with the separate Compose web-navigator module, which is not referenced by the selected BiblioLife Readium project dependency path. Exact copied asset/license mapping still requires review of the generated asset inputs and release APK.

## Flutter/Pub packages

`pubspec.lock` contains 138 package entries, including direct app dependencies, transitive dependencies, SDK packages and development/test tooling. The candidate upgrades `file_picker` to 11.0.3 (MIT) to address CVE-2026-38093; the v11 API migration has been applied to all three call sites. Because this frozen 11.x Android module has a known AGP 9 / `android.builtInKotlin=false` issue, `android/build.gradle.kts` applies the upstream-documented Kotlin plugin workaround and the validation script compiles `:file_picker:compileReleaseKotlin` explicitly. Version 11.0.3 also removes the Android Apache Tika dependency, so the previous 10.3.10 Tika 3.2.3 branch is not expected in the new graph. The lockfile pins versions but does not record license expressions. It also does not establish which native AAR/JAR/`.so`/`.bc` files are included in the Android APK. Notable platform-bearing packages include `file_picker` 11.0.3, `path_provider_android`, `pdfx`, `jni` and `jni_flutter`. `sqlite3_flutter_libs` 0.6.0+eol and `sqlcipher_flutter_libs` 0.7.0+eol are intentional no-op compatibility packages after the `sqlite3` 3.x migration; their current versions add no native SQLite/SQLCipher binaries or old build scripts. The `pdfx` Android backend uses the platform `PdfRenderer`; PDFium is used on Windows, not expected in the Android APK. These findings still need confirmation against the resolved graph and final APK.

## Known direct/runtime coordinates

The static scope CSV lists the app's explicit Gradle dependency, the plugin's direct dependencies, the three substituted Readium modules and the external dependencies directly declared by those modules. It also records test-only JUnit/Robolectric entries. Version conflict resolution is not inferred where two modules declare different versions; for example, BiblioLife declares `androidx.core:core-ktx:1.15.0` while Readium's catalog declares `1.18.0`. The selected version must be read from Gradle's resolved `releaseRuntimeClasspath`.

## New Junrar security remediation

The app calls `Junrar.extract(File, File)` when extracting CBR archives. Junrar 7.5.3 was affected by multiple 2026 path-traversal and denial-of-service advisories. The Pub lock also originally pinned file_picker 10.3.10, affected by CVE-2026-38093; it is now 11.0.3. The candidate now pins Junrar 8.1.2 and uses `desugar_jdk_libs_nio:2.1.5` in the app, plugin and Readium Android library build scopes. The host validates the canonical extraction destination beneath `cacheDir/bibliolife-comics/` before calling Junrar. See `android-dependency-security.md`.

## Required Gradle evidence

On a machine with the pinned Flutter SDK and Android SDK configured, run:

```powershell
Push-Location android
try {
    .\gradlew.bat :app:dependencies --configuration releaseRuntimeClasspath
    .\gradlew.bat :app:dependencyInsight --dependency junrar --configuration releaseRuntimeClasspath
    .\gradlew.bat :app:dependencyInsight --dependency slf4j-api --configuration releaseRuntimeClasspath
    .\gradlew.bat :app:dependencyInsight --dependency desugar_jdk_libs_nio --configuration releaseRuntimeClasspath
} finally {
    Pop-Location
}
```

Save the output to the audit folder and use the resolved artifacts, variants and POM metadata to generate the release SBOM. Do not treat the source inventory or this static trace as proof of APK contents.

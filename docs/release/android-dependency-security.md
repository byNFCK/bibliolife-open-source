# Android dependency security review — 2026-11-16


> This record describes an earlier candidate. v1.0.0 excludes Junrar and CBR extraction. Current [Android licenses](android-runtime-licenses.csv) and [Dart licenses](dart-runtime-licenses.csv) are available separately.

## Finding: Junrar 7.5.3 was unsafe for release

The candidate originally declared `com.github.junrar:junrar:7.5.3` in `android/app/build.gradle.kts`. The Android host calls `Junrar.extract(File(sourcePath), File(destinationPath))` when opening CBR comic archives, so this is a reachable extraction path, not an unused declaration.

The pinned version predates several published fixes:

| Advisory | Issue | Affected range | Fixed version |
|---|---|---|---|
| CVE-2026-28208 / GHSA-j273-m5qq-6825 | Backslash path traversal on Linux/Unix | before 7.5.8 | 7.5.8 |
| CVE-2026-41245 / GHSA-hf5p-q87m-crj7 | Sibling-directory path traversal | before 7.5.10 | 7.5.10 |
| CVE-2026-86071 / GHSA-89m4-43j5-vhhx | Directory creation outside extraction root | through 7.6.0 | 7.6.1 |
| CVE-2026-97370 / GHSA-h9h9-2rmf-rvhp | RAR4 extraction infinite CPU loop | through 7.6.0 | 7.6.1 |
| GHSA-h76x-7cgm-p442 | Residual out-of-bounds read in extended-time parsing | affected 7.5.1+ | 8.1.1 |
| GHSA-frq4-6xmx-hm4g | `Archive.getInputStream` could suppress extraction-integrity failures | before 8.1.2 | 8.1.2 |
| GHSA-ccq9-hw6f-p9cm | RAR5 link extraction could create directories outside root on Java 8 | 8.0.0–8.1.1 | 8.1.2 |

Sources: NVD and GitHub/GitLab advisory records linked in the references section below. The Junrar project release notes for 8.1.2 include path/link handling and integrity-reporting fixes.


## Finding: file_picker 10.3.10 had Android path traversal

The pinned Pub package `file_picker:10.3.10` was affected by CVE-2026-38093 / GHSA-r2rg-pm28-j8gw. The Android `openFileStream()` path used a provider-supplied `DISPLAY_NAME` without sufficient path sanitization, allowing a malicious local ContentProvider to create files/directories outside the intended picker cache area. BiblioLife uses file_picker for book imports and cover selection, so this is reachable.

Candidate remediation applied:

1. Upgraded `file_picker` from 10.3.10 to **11.0.3**. The upstream changelog states that 11.0.2 fixes the path traversal; 11.0.3 includes that fix and removes the Apache Tika dependency used for `saveFile()` MIME detection.
2. Migrated all three BiblioLife call sites from `FilePicker.platform.pickFiles()` to the v11 static `FilePicker.pickFiles()` API. No v12 API changes were adopted.
3. Updated `pubspec.lock` to 11.0.3 using the archive SHA-256 also present in an independently resolved pubspec.lock. The exact hash must still be verified by `flutter pub get --enforce-lockfile` in the pinned Flutter environment.
4. Added the documented upstream workaround for file_picker 11.0.3 on AGP 9 with `android.builtInKotlin=false`: apply the Kotlin Gradle Plugin to the `:file_picker` Android library after `com.android.library` and set JVM target 17. The release validation script explicitly compiles `:file_picker:compileReleaseKotlin` to catch the known missing-Kotlin-task failure.
5. Recorded the package's MIT license and the CVE remediation in the source SBOM.

The upstream 11.x AGP9 issue is documented at [file_picker issue #2200](https://github.com/vicajilau/flutter_file_picker/issues/2200); upstream states that the fix is in the 12.x federated line. The candidate keeps 11.0.3 to minimize API/dependency churn and applies the maintainer-confirmed Gradle workaround. A later upgrade to 12.x/13.x should remove this workaround and be tested separately.

Sources: [CVE-2026-38093 advisory](https://github.com/advisories/GHSA-r2rg-pm28-j8gw), [upstream issue #1967](https://github.com/miguelpruivo/flutter_file_picker/issues/1967), [11.0.3 changelog](https://pub.dev/packages/file_picker/versions/11.0.3/changelog).

## Candidate remediation applied

1. Changed the direct dependency to `com.github.junrar:junrar:8.1.2`.
2. Replaced the default `desugar_jdk_libs` dependency with `desugar_jdk_libs_nio:2.1.5` in all three relevant Android Gradle scopes: app, Flutter plugin and Readium library conventions. Junrar 8.x uses `java.nio.file`; the NIO flavor is required to desugar those APIs below Android API 26.
3. Added a host-side boundary check before calling Junrar: source must be a file, destination must already be a directory, and its canonical path must remain below `cacheDir/bibliolife-comics/`.
4. Added the Junrar UnRAR License and SLF4J 2.0.17 MIT notice; added the NIO desugaring GPL-2.0-with-Classpath-Exception notice.
5. Updated the source-declared CycloneDX inventory and dependency CSV to Junrar 8.1.2, SLF4J 2.0.17 and the NIO desugaring artifact.

## Important license qualification

Junrar's POM identifies the **UnRAR License**. The upstream terms permit use in software that handles RAR archives and distribution inside other software packages, while prohibiting use of the code to recreate the proprietary RAR compression algorithm. BiblioLife uses extraction only. This is not an SPDX standard license and should not be represented as an OSI-approved license. Its compatibility with distribution of the complete app under the root GPL-3.0-or-later grant needs explicit legal review. If that is unacceptable, replace Junrar with a library whose license is compatible with the intended project-wide licensing model.

## Validation status

The source changes are applied but **not compiled or tested** in this environment. Flutter, Dart, Android SDK/ADB and Gradle are not installed; the candidate's Gradle settings also require a real Flutter SDK path in `android/local.properties`. Required follow-up tests:

- Gradle resolution: `:app:dependencies --configuration releaseRuntimeClasspath`.
- Verify `com.github.junrar:junrar:8.1.2`, `org.slf4j:slf4j-api:2.0.17` and `com.android.tools:desugar_jdk_libs_nio:2.1.5` are the resolved artifacts.
- Build and test on minSdk 24/25 if those API levels remain in the supported matrix; specifically exercise Junrar `java.nio.file` calls.
- Run CBR extraction tests for RAR4, RAR5, multi-volume archives, encrypted archives, corrupt archives and traversal payloads.
- Verify file_picker 11.0.3 lockfile archive hash with `flutter pub get --enforce-lockfile`; test file picking from normal providers and a malicious ContentProvider with traversal-style `DISPLAY_NAME` values.
- Run the app on Nothing A065 (Android 16) and verify normal CBR open/reopen, page ordering, cache hits and cleanup.

## References

- [CVE-2026-28208](https://nvd.nist.gov/vuln/detail/CVE-2026-28208) · [GitHub advisory](https://github.com/junrar/junrar/security/advisories/GHSA-j273-m5qq-6825)
- [CVE-2026-41245](https://nvd.nist.gov/vuln/detail/CVE-2026-41245) · [GitHub advisory](https://github.com/junrar/junrar/security/advisories/GHSA-hf5p-q87m-crj7)
- [CVE-2026-86071 / GHSA-89m4-43j5-vhhx](https://github.com/junrar/junrar/security/advisories/GHSA-89m4-43j5-vhhx)
- [CVE-2026-97370 / GHSA-h9h9-2rmf-rvhp](https://github.com/junrar/junrar/security/advisories/GHSA-h9h9-2rmf-rvhp)
- [GHSA-h76x-7cgm-p442](https://github.com/junrar/junrar/security/advisories/GHSA-h76x-7cgm-p442)
- [GHSA-frq4-6xmx-hm4g](https://github.com/junrar/junrar/security/advisories/GHSA-frq4-6xmx-hm4g)
- [GHSA-ccq9-hw6f-p9cm](https://github.com/junrar/junrar/security/advisories/GHSA-ccq9-hw6f-p9cm)
- [Junrar 8.1.2 changelog](https://github.com/junrar/junrar/blob/v8.1.2/CHANGELOG.md)
- [Android NIO desugaring guide](https://developer.android.com/studio/write/java11-nio-support-table)

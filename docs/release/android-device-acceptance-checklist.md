# Android release acceptance — Nothing A065

Use `scripts/release/verify_android_release.ps1` from the candidate root after configuring Flutter 3.44.7, Dart 3.12.2, JDK 17+ and Android SDK. Run a profile APK first for physical acceptance; a profile APK uses the local debug signing key and is not the production release artifact.

## Before installation

- [ ] Back up any existing BiblioLife app data before uninstalling an older development package.
- [ ] Confirm the new application ID `app.bibliolife.reader` is intentional. It will not update an installation using the old package ID.
- [ ] Confirm the ADB device is the intended Nothing A065: record `ro.product.model`, `ro.product.device`, Android version and API level.
- [ ] Confirm `flutter pub get --enforce-lockfile` succeeds, including verification of the `file_picker 11.0.3` archive hash.
- [ ] Confirm the resolved release runtime graph contains Junrar 8.1.2, SLF4J 2.0.17 and `desugar_jdk_libs_nio` 2.1.5; confirm `tika-core` is absent.
- [ ] Confirm `:file_picker:compileReleaseKotlin` exists and compiles with the AGP 9 Kotlin plugin workaround; verify `file_picker` is resolved to 11.0.3.
- [ ] Save the complete `:app:dependencies --configuration releaseRuntimeClasspath` output and dependencyInsight reports into `audit/device-build/`.

## Import and file-picker tests

- [ ] Import EPUB, FB2, TXT, PDF, CBZ and CBR through Android's system file picker.
- [ ] Pick a file from internal storage, Downloads, a document provider/cloud provider and an SD/USB source if available.
- [ ] Cancel the picker and confirm no partial import or stuck loading state.
- [ ] Import files with spaces, Unicode names, long names and duplicate names.
- [ ] Pick book-cover and collection-cover images (JPG, JPEG, PNG and WebP); verify invalid formats fail gracefully.
- [ ] Verify the file_picker 11.0.3 API works in release/profile mode, not only debug.
- [ ] If a dedicated malicious ContentProvider test harness is available, return `DISPLAY_NAME` values containing `../`, backslashes and absolute-path forms. Verify no file/directory is created outside the plugin's intended cache area.

## CBR / Junrar security and compatibility

- [ ] Open a known-good RAR4 CBR and navigate forward/backward through pages.
- [ ] Open a known-good RAR5 CBR and verify page order and rendering.
- [ ] Reopen the same CBR; verify cache hit and no duplicate extraction.
- [ ] Open a multi-volume archive and confirm supported behavior or a clear graceful error.
- [ ] Open a password-protected archive and confirm a clear graceful error; no crash or indefinite spinner.
- [ ] Open a truncated/corrupt archive and confirm a clear graceful error.
- [ ] Use a test archive containing `../`, `..\\`, absolute paths, drive prefixes and symlink/hardlink entries. Confirm extraction remains inside `cacheDir/bibliolife-comics/` and no outside file is created.
- [ ] Confirm cache cleanup removes only BiblioLife's dedicated comic cache and does not touch unrelated app files.

## Reader acceptance

- [ ] EPUB open, close, reopen and saved-position restoration.
- [ ] EPUB continuous scrolling, chapter/TOC navigation, internal links and external links.
- [ ] EPUB bookmarks, highlights, annotations, selection and note persistence.
- [ ] TXT open, close, reopen and saved progress.
- [ ] FB2 open and text rendering.
- [ ] PDF open, zoom, page navigation, rotation and reopen.
- [ ] CBZ/CBR page order, zoom, navigation and reopen.
- [ ] Test a large EPUB, large PDF and large comic archive for memory pressure and UI responsiveness.
- [ ] Verify font settings, theme settings, orientation changes and Android predictive back.
- [ ] Verify app data migration and database schema 21 behavior on both fresh install and upgrade path.

## NIO desugaring compatibility

- [ ] Verify `Junrar 8.1.2` calls using `java.nio.file` work on Nothing A065 (Android 16).
- [ ] If API 24/25 remain in the supported range, run the CBR extraction smoke test on an API 24/25 emulator/device. The NIO desugaring flavor must resolve and run there.

## Release artifact and signing

- [ ] Inspect APK package ID, versionName/versionCode, minSdk/targetSdk, ABI splits, 16 KB page-size compatibility and native library contents.
- [ ] Verify the final APK's DEX/native/resource entries against the resolved Gradle graph and source SBOM.
- [ ] Extract `NOTICES.Z` from the APK and reconcile every shipped component with its license text and copyright notice.
- [ ] Verify the APK signature certificate fingerprint against the privately stored production certificate.
- [ ] Verify the APK can be installed and upgraded using the intended production signing key.
- [ ] Keep `android/key.properties`, keystore and passwords outside Git and outside the release ZIP. Never send them in chat.

## Sign-off record

Record date, tester, device model/device code, Android/API version, APK SHA-256, signing certificate SHA-256, test result, failed cases and log paths. Do not mark physical acceptance complete based only on a successful APK build.

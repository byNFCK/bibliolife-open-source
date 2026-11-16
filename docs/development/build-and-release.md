# Android build and release

Source review: 2026-11-15. The public candidate uses a neutral Android namespace and refuses to use the debug key for release. Without a private `android/key.properties`, the release variant is unsigned. Production signing and certificate continuity must be completed before distribution.

## Identity, versions and variants

| Item | Current configuration |
| --- | --- |
| Namespace / applicationId | app.bibliolife.reader |
| Declared Flutter version | 1.0.0+1 in pubspec.yaml |
| Android versionName / versionCode | flutter.versionName / flutter.versionCode; build name/number can override them |
| SDK / NDK | Delegated to selected Flutter SDK; observed defaults and required environment are in [setup](setup.md) |
| Native modules | Readium shared/streamer/navigator 3.2.0 substituted from the local customized checkout |
| App native dependencies | androidx.core:core-ktx 1.15.0, desugar_jdk_libs_nio 2.1.5 |

No product flavors or applicationIdSuffix are declared in the inspected app Gradle file. Debug/profile/release therefore target the same configured package identity; they are not isolated installations with separate user data.

| Mode | Intended use | Verified signing/native configuration |
| --- | --- | --- |
| Debug | Development and Flutter debugging | Standard debug build; no custom debug signing override declared |
| Profile | Flutter performance investigation | Explicit debug signing; debug fallback for the included Readium build |
| Release | Flutter release-mode packaging | Separate release key from `android/key.properties`, or unsigned when not configured |

The plugin also creates a profile type initialized from debug with a debug fallback. A profile build is not proof of release native behavior. Assertions, kDebugMode output and compile-time diagnostic flags affect observability differently; see [logging](../architecture/logging.md).

## Build commands and artifact locations

Use the environment and safe dependency-resolution steps in [setup](setup.md). Explicitly select lib/main.dart and do not use benchmark/test entrypoints.

~~~powershell
# Run from the project root
$flutterExe = 'flutter'

& $flutterExe build apk --debug --no-pub -t lib/main.dart
& $flutterExe build apk --profile -t lib/main.dart

# Release packaging examples only; production signing remains blocked.
& $flutterExe build apk --release -t lib/main.dart
& $flutterExe build appbundle --release -t lib/main.dart
~~~

These are alternatives for the intended validation task, not a requirement to build every variant. --no-pub requires resolved dependencies. Add the required Google Books compile-time definition as described in [setup](setup.md) and the [Google Books guide](google_books_configuration.md); do not embed a literal key in shared instructions.

For the normal commands without flavors, split-per-ABI options or custom output overrides, expected Flutter output locations are:

| Artifact | Expected path from project root |
| --- | --- |
| Debug APK | build/app/outputs/flutter-apk/app-debug.apk |
| Profile APK | build/app/outputs/flutter-apk/app-profile.apk |
| Release APK | build/app/outputs/flutter-apk/app-release.apk |
| Release AAB | build/app/outputs/bundle/release/app-release.aab |

These are expected tool output paths, not newly verified artifacts. Confirm build output, variant, timestamp, hash, package/version and signing certificate before using any file. An old APK at the expected path is not evidence that the last build succeeded. An AAB is a distribution bundle, not a file to pass directly to adb install.

The host [build configuration](../../android/build.gradle.kts) redirects native subproject outputs under the project build directory. Gradle may also update local SDK properties in the included checkout. Do not clean caches or regenerate Readium JavaScript bundles as a routine packaging step.

## Signing and versioning

The release build reads a private `android/key.properties` file. Start from [`android/key.properties.example`](../../android/key.properties.example), copy it to `android/key.properties`, and replace all placeholders. The actual key file is excluded by `.gitignore`. Store the keystore outside the repository and back it up securely. Do not put passwords in shell history, CI logs or source control.

If `key.properties` is absent, the release variant is intentionally unsigned. If it exists but is incomplete, Gradle fails configuration. The release variant never falls back to the debug key. A production release still requires the owner to create/choose a key, verify its certificate fingerprint, define backup/recovery and CI secret handling, and approve the distribution strategy. No key was created or certificate verified in this preparation.

The public candidate changes the Android package identity from the previous development identifier to `app.bibliolife.reader` to remove the owner-specific handle. This is a new application identity: Android will not treat it as an in-place update of an installation using the old package ID, and app data will not transfer automatically. Plan any migration separately before asking existing users to install it.

Changing the key can prevent an in-place update of an existing installation; do not uninstall the existing app to bypass a signature error. Flutter release mode and production signing are independent requirements.

For a future version, choose a deliberate user-facing build name and monotonically increasing Android build number. For example, replace both placeholders with approved values:

~~~powershell
& $flutterExe build appbundle --release -t lib/main.dart --build-name '<approved-version>' --build-number '<approved-integer>'
~~~

Do not run this placeholder command unchanged. Build overrides do not update pubspec.yaml automatically. Android versionCode, Flutter package version, Drift schema **23**, bridge protocol and upstream Readium version are different version contracts. Increasing an app build number does not authorize a database migration or a Readium upgrade.

## Data-preserving APK update procedure

For an authorized development-device update:

1. Record the installed package/version/signing identity and identify the exact device. Confirm a tested recovery plan and back up accessible app data, including database and book/cover files. run-as access depends on the installed build; do not assume it works for release.
2. Verify the intended APK's package, version and signing certificate are compatible with the existing installation. Confirm it is the normal application entrypoint/build.
3. Install the APK in place using replacement installation:

~~~powershell
$deviceId = '<device-id>'
$androidSdk = Join-Path $env:LOCALAPPDATA 'Android\sdk' # Adapt to configured sdk.dir.
$adbExe = Join-Path $androidSdk 'platform-tools\adb.exe'
$apkPath = 'build\app\outputs\flutter-apk\app-profile.apk'
& $adbExe -s $deviceId install -r $apkPath
~~~

4. Check installation success and then validate library records, local files, saved reading position, bookmarks/annotations and settings.

-r requests replacement while retaining application data; it is not a backup or guarantee that application startup/migrations cannot change data. If installation rejects the signature/version, stop and resolve compatibility. Do not use uninstall, pm clear, downgrade flags or automatic integration-test teardown as a shortcut. Read [Library benchmark safety](../testing/library_transition_benchmark_safety.md) before benchmark/device workflows.

## Release validation checklist

This is required future work, not a completed acceptance record:

- Establish production signing and certificate continuity; inspect the exact final artifact and approve the store/distribution configuration.
- Freeze an identifiable main-repository state and nested Readium state, including all required modified/untracked source. Current worktrees contain unrelated unfinished work; a HEAD identifier alone is not reproducible release evidence.
- Resolve recorded dependencies and document SDK/JDK/native toolchain versions and compile-time definitions; keep diagnostic/benchmark flags at intended production values.
- Run relevant static checks, focused Flutter/native tests and release-variant verification in a separately authorized task. Unit tests do not replace physical acceptance.
- Verify schema-23 migration/recovery scenarios and saved locator/annotation compatibility. The package-ID change means this candidate cannot in-place upgrade the prior development app.
- Physically validate Reader opening/restoration/reopen, Continuous and Paginated navigation, selection/highlights, settings/reflow, progress Cancel/timeouts, PDF/comics and applicable converted TXT/FB2 paths.
- Check Online/Offline behavior, key restrictions/quota and failure/retry handling; successful key creation does not prove requests work.
- Review privacy, diagnostics, Android permissions, supported device/OS behavior and store requirements at release time.

Known blockers/uncertainties remain: production key/certificate setup; unfinished Reader/device acceptance; no newly verified release artifact, certificate, clean reproducible source state, complete migration matrix or store readiness. See [architecture](../architecture/overview.md), [Readium customizations](../architecture/readium-customizations.md) and [active acceptance records](../index.md#active-reader-investigations-and-acceptance). Nothing here claims production readiness.

Run the standard release command with Pub enabled. Flutter 3.44.7 skips mode-specific Android registrant regeneration with --no-pub. In particular, a standalone flutter pub get can leave dev-only plugins in the registrant. The release command regenerates it in release mode; integration_test remains a dev dependency.

## Candidate release validation

Use `scripts/release/verify_android_release.ps1` to run the pinned dependency checks, Flutter analyze/tests, Gradle dependency reports, profile APK and release APK builds. The physical-device acceptance steps are documented in `../release/android-device-acceptance-checklist.md`. The script does not create or expose a production signing key.

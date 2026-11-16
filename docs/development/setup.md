# Development setup

Source review: 2026-11-10. All commands below are **instructions for a future development session**; none were executed while preparing these documents. Preserve the main and nested Readium worktrees before changing environment or resolving dependencies.

## Toolchain requirements and observed versions

| Component | Repository configuration / observed value |
| --- | --- |
| Dart | pubspec.yaml requires ^3.12.2; lockfile records >=3.12.2 <4.0.0 |
| Flutter | Local Readium package and lockfile require >=3.44.0; no exact application SDK pin was found in the inspected version files |
| Observed local SDK | The previous validation environment used Flutter 3.44.7 stable and Dart 3.12.2; this is an observed version, not a portable repository pin |
| Gradle wrapper | 9.1.0: host wrapper uses all distribution, nested Readium wrapper uses bin |
| Android Gradle Plugin / Kotlin plugin | 9.0.1 / 2.3.20, aligned with the nested Readium version catalog |
| Java | App/plugin Java compatibility and Kotlin JVM target are 17. The actual Gradle Java runtime is not pinned by these target settings and was not executed/verified here; select a JDK compatible with Gradle 9.1.0 / AGP 9.0.1 |
| Android SDK | Plugin and Readium compile SDK 36; app compile/min/target and NDK delegate to the selected Flutter SDK |
| Observed Flutter SDK defaults | compile 36, target 36, min 24, NDK 28.2.13676358, read from that local SDK's FlutterExtension.kt; recheck if the SDK changes |
| Readium library minimum | Plugin and nested toolkit min SDK 23; this does not override the app's observed min SDK 24 |

Sources: [pubspec.yaml](../../pubspec.yaml), [pubspec.lock](../../pubspec.lock), [local package manifest](../../packages/bibliolife_readium/pubspec.yaml), [Android settings](../../android/settings.gradle.kts), [host wrapper](../../android/gradle/wrapper/gradle-wrapper.properties), [app Gradle](../../android/app/build.gradle.kts), [plugin Gradle](../../packages/bibliolife_readium/android/build.gradle.kts), [Readium properties](../../third_party/readium-kotlin-toolkit/gradle.properties) and [version catalog](../../third_party/readium-kotlin-toolkit/gradle/libs.versions.toml).

Install Android platform 36, platform tools and the NDK selected by Flutter, plus a compatible JDK. Exact SDK/build-tools availability, licenses, JAVA_HOME/Android Studio JDK selection and host readiness were not validated by running tools. App/plugin target 17 does not mean every upstream module uses that bytecode target: the toolkit library convention retains Java compatibility 11. Use checked-in wrappers rather than an arbitrary system Gradle installation. android/gradle.properties currently enables AndroidX and disables the new DSL/built-in Kotlin switches; do not “modernize” these settings as setup cleanup.

## Layout and customized Readium

lib/app composes the application; lib/features contains feature modules; lib/core and lib/shared hold infrastructure/models/widgets. The local bibliolife_readium dependency resolves from packages/bibliolife_readium. Android substitutes the shared, streamer and navigator 3.2.0 modules with the customized checkout under third_party/readium-kotlin-toolkit.

Keep both repositories, modified files and untracked custom sources/tests intact. A plain upstream 3.2.0 checkout or published dependency is not an equivalent replacement. Read the [architecture](../architecture/overview.md) and [Readium customization reference](../architecture/readium-customizations.md) before native work. Do not regenerate JavaScript bundles or run code generation as a routine setup step.

## Local SDK paths

android/settings.gradle.kts requires flutter.sdk in android/local.properties. Android SDK resolution is sdk.dir, then ANDROID_SDK_ROOT, then ANDROID_HOME. For a new environment, local properties can use forward slashes:

~~~properties
flutter.sdk=C:/path/to/flutter
sdk.dir=C:/path/to/Android/sdk
~~~

Preserve existing unrelated properties; do not overwrite this file wholesale. Gradle settings propagate sdk.dir into the nested toolkit's ignored local.properties; configuring Gradle can therefore write that local file even without an APK build. Do not commit machine-specific paths.

Example PowerShell shell setup:

~~~powershell
# Run from the project root
$flutterExe = 'flutter'
$deviceId = '<device-id>'
# Set JAVA_HOME to an installed compatible JDK only if your environment needs it.
# The configured sdk.dir can be used instead of an SDK environment variable.
~~~

Android Studio's chosen Gradle JDK and the shell's JAVA_HOME can differ. Confirm the selected runtime separately before diagnosing native compilation problems.

## Dependencies and normal application entrypoint

The repository includes pubspec.lock. Key declarations include Riverpod 3.3.2, GoRouter 17.3.0, file_picker 11.0.3, archive 4.0.9, xml 7.0.1, Drift ^2.34.2 and drift_flutter ^0.3.1. Caret constraints are not exact resolved versions; use the lockfile for those.

For an existing checkout, resolve the recorded dependencies without upgrading:

~~~powershell
& $flutterExe pub get --enforce-lockfile
& $flutterExe run --debug --no-pub -t lib/main.dart -d $deviceId
~~~

Dependency resolution can create generated/local tool state. Review both Git statuses afterwards; do not accept an unexpected lockfile/dependency change merely to make setup succeed. Do not use pub upgrade, dependency replacement or cache cleaning as a default remedy. --no-pub assumes successful prior dependency resolution.

For a separately authorized profile run:

~~~powershell
& $flutterExe run --profile --no-pub -t lib/main.dart -d $deviceId
~~~

Debug is for development/debugging; profile is for representative Flutter performance work. The app profile variant is debug-signed and uses a debug fallback for the included toolkit; profile does not imply release-equivalent native optimization. See [build and release](build-and-release.md).

## Compile-time configuration

Google Books uses the compile-time GOOGLE_BOOKS_API_KEY definition, not automatic process-environment discovery. An example using a key already supplied securely to the current shell:

~~~powershell
& $flutterExe run --debug --no-pub -t lib/main.dart -d $deviceId "--dart-define=GOOGLE_BOOKS_API_KEY=$env:GOOGLE_BOOKS_API_KEY"
~~~

Do not run this with an empty variable. Compile-time definitions are embedded in the application and are not a secure server-side secret store; restrict the key appropriately and avoid exposing it in shell history or shared command output.

The [Google Books guide](google_books_configuration.md) documents the required key, supported request paths, missing-key failure and quota/restriction considerations. The current [adapter](../../lib/features/catalog_sources/data/google_books_remote_catalog_adapter.dart) throws an apiKeyMissing configuration failure before HTTP work when the key is blank; keyless operation is not supported by this application path.

Optional diagnostic flags and their distinct defaults are documented in [logging](../architecture/logging.md). Normal development/release examples do not enable them. The native bibliolifeContinuousScrollCutover Gradle property defaults true and is a rendition rollback control, not a Dart environment definition; do not change it unintentionally.

## Focused checks for future code work

After dependency resolution, examples of bounded host-side checks are:

~~~powershell
& $flutterExe test --no-pub test/shared/presentation/widgets/biblio_tabs_test.dart
Push-Location android
try {
    .\gradlew.bat :bibliolife_readium:testDebugUnitTest --tests 'app.bibliolife.reader.readium.ReadiumEpubBackendResolverTest'
    .\gradlew.bat :bibliolife_readium:testDebugUnitTest --tests 'app.bibliolife.reader.readium.ProgressNavigationLeaseTest'
} finally {
    Pop-Location
}
~~~

The [named native tests](../../packages/bibliolife_readium/android/src/test/kotlin/app/bibliolife/reader/readium/) exist. Gradle unit-test tasks can compile dependencies and create outputs; these examples are not read-only commands and were not executed here. Choose tests that cover the actual change; passing JVM/helper tests is separate from device acceptance. Never substitute the Library integration benchmark for a normal entrypoint; follow [benchmark safety](../testing/library_transition_benchmark_safety.md) before a separately authorized physical run.

## Common pitfalls and open requirements

- Do not infer feature parity from non-Android scaffold directories; the local Readium plugin registers Android only.
- Do not mix up Flutter build mode, native rendition selection and PlatformView composition backend; they are separate decisions.
- Do not reset, stash, clean or replace the customized checkout to resolve an SDK mismatch.
- Do not treat build success as acceptance of Reader restore, selection, reflow or progress navigation.
- Do not alter the unrelated trailing-whitespace issue in pubspec.yaml as part of setup.
- No environment readiness, fresh test result or physical acceptance is claimed by these instructions.

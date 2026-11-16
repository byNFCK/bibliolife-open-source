# Logging and diagnostics

Source review: 2026-11-10. This describes existing code, not a new logging implementation or a fresh runtime validation. No application logs, Logcat captures, tests or builds were generated for this documentation.

See [application architecture](overview.md) and [Readium customizations](readium-customizations.md) for component ownership and renderer behavior.

## Architecture and ownership

| Channel | Owner and destination | Important boundary |
| --- | --- | --- |
| Flutter application history | Riverpod AppLogService; in-memory AppLogEntry list consumed by the LOG screen | Only explicit service writes enter this history |
| Reader opening | ReaderOpenAttempt plus native opening facts | Native stages are correlated with a Flutter-owned opening attempt |
| Reader progress/reflow | Application Reader controller consumes typed native diagnostics and records local UI/command observations | These events are selectively forwarded; not every native line becomes an app entry |
| Flutter developer/performance output | debugPrint, print, dart:developer logging and selected Timeline markers | Console/tooling output is distinct from AppLogService |
| Kotlin/Readium output | Android Log calls and typed diagnostic events | Logcat output and bridge events are separate paths |
| Local session files | Manually organized development evidence | Directory conventions do not create a runtime sink |

[AppLogService](../../lib/shared/application/logging/app_log_provider.dart) is a NotifierProvider owned by the application ProviderScope. App initializes it; features opt in by calling its notifier. There is no global interception of debugPrint, Android Logcat or arbitrary exceptions into the LOG screen. No FlutterError.onError, PlatformDispatcher error handler or runZonedGuarded app-log hook was found in the inspected application entry/composition code.

### Native-to-Flutter diagnostics

ReadiumReaderSession emits State.Diagnostic maps. [ReadiumPlatformViewBridge](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ReadiumPlatformViewBridge.kt) serializes session observations through the per-view EventChannel; its transport posts EventSink callbacks to Flutter's main thread. This is not an Android Logcat subscription.

The local package's [ReadiumEpubController](../../packages/bibliolife_readium/lib/src/bridge/readium_epub_controller.dart) routes category Reader.Open to onOpenDiagnostic; other diagnostic events enter a broadcast diagnostics stream. The application [ReadiumEpubReaderController](../../lib/features/reader/presentation/models/readium_epub_reader_controller.dart) correlates progress context and appends selected diagnostics when an AppLogService is supplied. It writes category Reader.Progress for that explicit category and otherwise labels forwarded diagnostics Reader.Reflow. That fallback is a formatting convention, not proof that every forwarded event originated in a reflow operation.

Opening diagnostics use a different path: [ReaderOpenAttempt](../../lib/features/reader/application/services/reader_open_attempt.dart) validates attempt correlation, accumulates stages/facts and records a terminal outcome. Late or mismatched events may be ignored; neither the app buffer nor a broadcast stream should be assumed to contain an exhaustive replay of native history.

## Entry lifecycle, storage and LOG screen

[AppLogEntry](../../lib/shared/application/logging/app_log_entry.dart) stores timestamp, level, category and message. AppLogService supplies UTC timestamps and debug/info/warning/error methods. Formatting is an ISO-8601 UTC timestamp followed by uppercase level, category and message.

- Provider initialization creates one App/info entry: “Application log service initialized”.
- Each append creates an immutable replacement list. The limit is **1,000 entries**; excess oldest entries are removed. There is no byte-size/message-length budget in this service.
- Storage is memory-only: no database, file writer or restart recovery is implemented here. Recreating the provider/process starts a new history.
- appendDeferred schedules a microtask and checks that the provider Ref remains mounted before writing. A deferred entry may therefore be dropped during teardown.
- clear() replaces the list with an empty list. It does not clear native Logcat, historical session files or other console sinks, and does not prevent later producers from appending again.

[AppLogScreen](../../lib/features/app_logs/presentation/screens/app_log_screen.dart) watches the list and displays selectable monospaced lines in insertion order, or an empty-state message. After the first frame it records App/“LOG page opened”.

COPY first appends App/“COPY invoked”, then takes formattedText and writes that snapshot to the system clipboard. The copied snapshot consequently includes the COPY entry. Success/failure is displayed by a snackbar when the screen is still mounted. Clipboard errors are caught, but this handler does not add a separate failure entry to the log. The inspected screen has no Clear action, level/category filtering, file export, share action or native-log export. Clipboard copying is the implemented export mechanism; a service-level clear method is not a user-visible Clear button.

### Logging failures and actual guarantees

Reader controller diagnostic writes catch failures so observers do not affect reading behavior. Several native session diagnostic callbacks use runCatching; diagnostic watchdog reporting also isolates observer failures. ReadiumOpenDiagnostics filters exception text before emitting opening facts. These protections are local, not a universal logging-failure policy.

AppLogService itself has no general append/serialization failure recovery or durable fallback. ReaderOpenAttempt JSON encoding and arbitrary console producers do not all share the Reader controller's guarded writer. A dropped/swallowed diagnostic has no guaranteed visible loss counter. An error result in a domain model or persisted download task is not automatically an error-level AppLogEntry.

## Actual categories and markers

Categories in the app history, Android tags, field values and console marker prefixes are different namespaces. The following are representative source-confirmed names, not a promise of complete emission in every build.

| Area | Existing names | Source / destination |
| --- | --- | --- |
| App / LOG UI | App; initialization, LOG page opened, COPY invoked | AppLogService and AppLogScreen → app history |
| EPUB opening and initialization | Reader.Open; book_open_start, book_open_stage, book_open_terminal; file_access, asset_retrieval, publication_open, readium_initialization, reader_ready | ReaderOpenAttempt, [PublicationLoader](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/PublicationLoader.kt), [ReadiumOpenDiagnostics](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ReadiumOpenDiagnostics.kt) → typed opening path / app history |
| Initial locator / restoration | initial_locator_restoration, locator_canonicalization, restoration_terminal; restoration failure/skip reasons | ReadiumInitialLocatorDiagnostics in ReadiumOpenDiagnostics.kt → opening attempt; not a new app category |
| Progress ownership / persistence | Reader.Progress; progress_navigation_start, progress_navigation_terminal, progress_navigation_verified, progress_navigation_watchdog, progress_persistence | [Reader controller](../../lib/features/reader/presentation/models/readium_epub_reader_controller.dart), [scrub coordinator](../../lib/features/reader/presentation/models/reader_progress_scrub_coordinator.dart), [native session](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ReadiumReaderSession.kt), [lease](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ProgressNavigationLease.kt) |
| Settings / reflow | Reader.Reflow; slider_start, slider_end, adapter_apply_start/done/fail, preference_terminal, reflow_terminal | Application controller and native preference/session diagnostics |
| Text-render investigation | webview_text_render_snapshot, webview_text_render_compare | [ContinuousTextRenderDiagnostics](../../third_party/readium-kotlin-toolkit/readium/navigator/src/main/java/org/readium/r2/navigator/epub/continuous/ContinuousTextRenderDiagnostics.kt) and the toolkit JavaScript diagnostic path |
| Native timing / failures | Android tag BiblioLifeReadium; CONTINUOUS_INITIAL_VIEWPORT_FAILURE, PUBLICATION_CLOSE_FAILED; tag BIBLIOLIFE_OPEN_TIMING | Native session and [BiblioLifeOpenTimingDiagnostics](../../third_party/readium-kotlin-toolkit/readium/navigator/src/main/java/org/readium/r2/navigator/epub/continuous/BiblioLifeOpenTimingDiagnostics.kt) → Logcat; typed failures may also travel through the bridge |
| Flutter Reader performance | READER_PERF_* markers | [reader_performance.dart](../../lib/features/reader/performance/reader_performance.dart) → console |
| Network authorization | NETWORK_ACCESS_BLOCKED, APP_CONNECTIVITY_MODE_CHANGED, ONLINE_ACCESS_REVOKED | [NetworkAccessPolicy](../../lib/features/connectivity/application/network_access_policy.dart) and connectivity notifier → assert-gated developer output |
| Online request / failure diagnostics | SEARCH_PERF_HEALTH, SEARCH_PERF_MARKER, REQUEST_TRANSPORT_ABORTED, GOOGLE_BOOKS_REQUEST_BUILD_FAILED, GOOGLE_BOOKS_REQUEST_FAILED | [Online performance](../../lib/core/performance/online_pipeline_performance.dart), HTTP transport and Google Books adapter → developer/console output |
| Acquisition / import | ACQUISITION_DOWNLOAD_STARTED, ACQUISITION_HEADERS_RECEIVED, ACQUISITION_DOWNLOAD_VALIDATED, ACQUISITION_IMPORT_COMPLETED | [Foreground downloader](../../lib/features/catalog_sources/data/foreground_remote_book_downloader.dart), queue facade → debug output; failure state is also represented separately by download results/tasks |
| Metadata import | EPUB_METADATA_* stage names, EPUB_TITLE_ASSESSED, EPUB_TITLE_SELECTED, EPUB_IMPORT_STAGE, EPUB_IMPORT_FAILED, EPUB_FILENAME_SOURCE | [EpubMetadataDiagnostics](../../lib/features/metadata/data/services/epub_metadata_diagnostics.dart) → assert-gated developer output |

Publication-loading and native failure facts carry stage/component/result/error information; they are not all independent log categories. Terminal ready, failed, cancelled, superseded, timeout and persisted outcomes must be interpreted according to their producing code. A diagnostic named “verified” or a historical PASS does not establish the stability of the current working tree.

## Enablement and correlation limits

There is no universal logging switch:

- BIBLIOLIFE_READER_PERF_LOGS defaults false and gates Flutter Reader performance instrumentation.
- BIBLIOLIFE_READIUM_PROGRESS_LOGS defaults false and gates certain additional Dart seek-console lines. It does **not** disable all Reader.Progress app-history/bridge diagnostics.
- BIBLIOLIFE_NET_PERF_LOGS defaults false. BIBLIOLIFE_NET_PERF_VERBOSE_LOGS and BIBLIOLIFE_SEARCH_FRAME_METRICS require that primary flag as well as their own flags. The source describes frame timing as intended for opt-in profile runs.
- Several network/metadata diagnostics are assert-gated or use kDebugMode. These differ from compile-time performance flags and from ungated Android Log calls.
- A native progress debug-output path checks Android Log.isLoggable with BiblioLifeProgress and writes under BiblioLifeReadium. Not every native line shares that check.

App entries have wall-clock UTC timestamps. Opening attempts and native diagnostics also use elapsed times, local IDs, generations and resource indexes. These aid correlation but are not a globally unique, persistent cross-restart tracing system. Concurrent sources and deferred writes can affect observation order.

## Local diagnostic sessions and historical evidence

The [logs README](../../logs/README.md) defines a future local convention under logs/sessions/YYYY-MM-DD_session-name/, with optional manifest, application log, Android Logcat, summary and evidence files. Those files are conventions, not automatically generated artifacts.

Creating logs/sessions/ does not redirect AppLogService, debugPrint, Android Logcat or bridge diagnostics. Clipboard output does not save itself there. The 1,000-entry in-app limit does not govern separately captured files.

Existing build/physical_tests/, build/task-reflow-diagnostics/ and artifacts/ locations remain historical development evidence with their original collection workflows. No migration, collection, retention cleanup or automatic expiry is implemented by this documentation. See [benchmark safety](../testing/library_transition_benchmark_safety.md) before any separately authorized capture. No critical factual contradiction was found in logs/README.md; it remains unchanged.

## Privacy and security boundaries

Logs are development data, not guaranteed anonymous telemetry. Review every exported/captured artifact before sharing.

- Publication text and selected text can appear in raw renderer/channel payloads or diagnostic captures. EPUB metadata diagnostics encode a short content/filename prefix as Unicode code points; that representation is reversible and must not be treated as anonymization.
- Reader.Open starts include a book identifier; Reader.Progress observations include resource href/progression and command/session context. Locators, resource names, titles and identifiers may reveal reading history even without full book text.
- Reader opening filters recognized Dart/native exception phrases and records file-reference type/storage facts instead of automatically logging the full path. This protection does not establish that every raw exception, native stack trace or console producer redacts paths/content.
- Continuous text-render diagnostics allowlist metrics/strings, reject malformed or oversized input and exclude arbitrary JavaScript keys/DOM text. The source caps the incoming payload at 12,000 characters and restricts accepted string fields; it is a local boundary, not a blanket guarantee for other diagnostics.
- Online sanitizedUri removes user information/query/fragment by reconstructing scheme, host and path. Request fingerprints omit selected sensitive query names, including key/token/signature-related fields, but retain other values such as possible search terms. This is not a complete credential or personal-data classifier.
- Google Books debug configuration records key presence and length; failure diagnostics record failure categories and whether a key was attached. Never include actual API keys, authentication headers, cookies or signed URLs in shared artifacts. See [Google Books configuration](../development/google_books_configuration.md).
- Raw Logcat and capture manifests may include device identifiers, absolute filesystem paths and publication content. Clipboard copying exposes the full selected app-history snapshot to the system clipboard; there is no per-entry export-redaction UI.

No real secret, user publication excerpt, device identifier or sensitive log payload is reproduced in this document.

## Known limitations and future implementation opportunities

These are gaps/opportunities, not changes delivered here:

1. No durable in-app history, restart restoration, byte-budgeted buffer or disk rotation. Add these only with an explicit retention/privacy contract.
2. LOG has clipboard export only; filtering/search, file/share export and a Clear control would require implementation.
3. App history, console, Logcat, bridge events and session folders are not one collected stream. A unified collector or session exporter does not exist in the inspected paths.
4. Event formats mix JSON messages, key=value strings and free text; category fallback to Reader.Reflow and different clocks/gating complicate automated correlation.
5. Missing/deferred/ignored diagnostics and swallowed observer failures have no consistent loss accounting. Global uncaught-error capture is not wired to AppLogService in the inspected startup.
6. Redaction is producer-specific. Encoded metadata prefixes, query values, hrefs, book IDs and raw exception paths remain privacy risks; comprehensive structured export redaction would require separate work.
7. Download failure state and Reader error state are not guaranteed to appear in the LOG screen. Debug-only output can leave profile/release blind spots.
8. No automatic logs/sessions writer, historical-log migration, retention policy enforcement or backup/restore guarantee is provided by the directory convention.
9. Source-confirmed markers do not prove physical acceptance, complete failure-path coverage, full source/bundle equivalence or reliable log delivery under process death.

This reference makes no current-device delivery/completeness claim. It does not certify every third-party/native log producer or historical capture.

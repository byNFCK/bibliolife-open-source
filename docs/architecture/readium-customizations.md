# Readium customizations

Source review: 2026-11-10. This document describes the current working tree, including extensive modified and untracked native/JavaScript files. It is an ownership and invariant map, not a declaration that the current Reader is stable. No tests, builds, bundle generation or device checks were performed for this review.

See the [application architecture](overview.md) for routing, persistence and Online ingestion. The application’s Drift schema remains **21**; the native renderer does not own or migrate that schema.

## Upstream baseline and integration strategy

The [source pin](../../third_party/readium-kotlin-toolkit/BIBLIOLIFE_PIN.md) was checked against local Git metadata:

| Item | Verified value |
| --- | --- |
| Nested HEAD | fe4c32b97f4745971facfbdfbde31520553c770e |
| Upstream tag | 3.2.0; local git describe resolves to this tag |
| Peeled tag commit | fe4c32b97f4745971facfbdfbde31520553c770e |
| Annotated tag object | f54560fc87aa84223514b55f16ea886a90aa5b3e |
| Configured origin | https://github.com/readium/kotlin-toolkit.git |

This verifies the checked-out baseline from local objects, not a fresh remote comparison. Local worktree changes sit on top of that commit; HEAD alone does not describe the running integration.

The local Flutter plugin declares Readium shared/streamer/navigator 3.2.0 dependencies in its [Gradle configuration](../../packages/bibliolife_readium/android/build.gradle.kts). The Android composite-build substitution strategy is described in the application architecture. The pin also records AGP alignment, but its description of a WebView selection patch is incomplete relative to today’s much broader local fork. Do not treat it as a complete patch inventory.

## Ownership boundaries

| Owner | Purpose and invariant | Principal sources |
| --- | --- | --- |
| Application Reader | Flutter controls, settings/progress persistence and repository-backed annotations; transient native UI does not own durable annotation records | [readium_epub_reader_controller.dart](../../lib/features/reader/presentation/models/readium_epub_reader_controller.dart), [readium_epub_annotation_coordinator.dart](../../lib/features/reader/application/services/readium_epub_annotation_coordinator.dart) |
| Local Dart package | Typed controller API, per-view commands/events, PlatformView composition and disposal; instance/session identity must accompany asynchronous work | [bridge sources](../../packages/bibliolife_readium/lib/src/bridge/) |
| Native plugin / PlatformView | Engine/activity dependencies, host attachment, codec validation, transport and native-session creation; transport does not become the Activity/session owner | [BiblioLifeReadiumPlugin.kt](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/BiblioLifeReadiumPlugin.kt), [ReadiumPlatformViewSession.kt](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ReadiumPlatformViewSession.kt), [ReadiumPlatformViewBridge.kt](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ReadiumPlatformViewBridge.kt) |
| Native Reader session | Publication opening, selected rendition, positions, navigation, preferences and native interaction; terminal/cancelled work must not publish as current | [ReadiumReaderSession.kt](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ReadiumReaderSession.kt), [ReadiumReaderSessionState.kt](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ReadiumReaderSessionState.kt) |
| Customized toolkit | Resource WebViews, publication URL/server environment, layout/geometry, selection and renderer callbacks; resource identity and generations fence late work | [navigator sources](../../third_party/readium-kotlin-toolkit/readium/navigator/src/main/java/org/readium/r2/navigator/) |

Protocol version 1 and channel names are defined by [ReadiumBridgeConstants](../../packages/bibliolife_readium/lib/src/bridge/readium_bridge_constants.dart). Per-view MethodChannel commands and EventChannel events carry navigation, preferences, search, decorations, selection and diagnostics. They are not a direct SQLite interface. The plugin-level channel also serves operations such as TOC extraction; it is distinct from a view’s command/event pair.

## Rendering: Continuous and Paginated

[ReadiumEpubBackendResolver.kt](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ReadiumEpubBackendResolver.kt) is the native rendition decision point before session construction. Paginated requests use LEGACY. Eligible scroll requests can use CONTINUOUS_EXPERIMENTAL; eligible types are EPUB and converted TXT/FB2 EPUB. PDF/comics are ineligible and use other application viewports. The package Gradle property bibliolifeContinuousScrollCutover defaults to true; resolver false/missing/malformed controls select legacy. This is a build/session decision, not a new persisted user setting or proof of acceptance.

The legacy path retains EpubNavigatorFragment and paginated WebViews/pager. Local modifications expose manual page activity, discrete page/geometry samples, navigation ownership and selection policy. [PaginatedManualPagePublicationGate.kt](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/PaginatedManualPagePublicationGate.kt) fences manual samples by epoch/navigation generation and refuses publication during programmatic navigation. The fork’s [R2EpubPageFragment.kt](../../third_party/readium-kotlin-toolkit/readium/navigator/src/main/java/org/readium/r2/navigator/pager/R2EpubPageFragment.kt), [R2PagerAdapter.kt](../../third_party/readium-kotlin-toolkit/readium/navigator/src/main/java/org/readium/r2/navigator/pager/R2PagerAdapter.kt) and [R2ViewPager.kt](../../third_party/readium-kotlin-toolkit/readium/navigator/src/main/java/org/readium/r2/navigator/pager/R2ViewPager.kt) integrate these behaviors.

Continuous is a separate multi-resource rendition, not just a renamed paginated scroll option:

- [ContinuousEpubRendition.kt](../../third_party/readium-kotlin-toolkit/readium/navigator/src/main/java/org/readium/r2/navigator/epub/continuous/ContinuousEpubRendition.kt) owns one publication environment and concurrent resource renderers.
- [ContinuousReflowableHostView.kt](../../third_party/readium-kotlin-toolkit/readium/navigator/src/main/java/org/readium/r2/navigator/epub/continuous/ContinuousReflowableHostView.kt) coordinates the parent viewport, materialization, initial reveal, navigation and geometry.
- [ContinuousEpubResourceWindow.kt](../../third_party/readium-kotlin-toolkit/readium/navigator/src/main/java/org/readium/r2/navigator/epub/continuous/ContinuousEpubResourceWindow.kt) bounds live resources and tracks pin reasons; resource reuse must respect identity/generation and pins.
- [EpubWebPublicationEnvironment.kt](../../third_party/readium-kotlin-toolkit/readium/navigator/src/main/java/org/readium/r2/navigator/epub/EpubWebPublicationEnvironment.kt) owns the publication-scoped server and URL space. Resource WebViews use this environment rather than owning independent publication servers.

Initial-restore authority holds the viewport until the actual target reaches a terminal outcome. The cover/reveal and preload gates depend on readiness/visual boundaries, not an elapsed-time assumption. Callback ownership must still match layout, resource and materialization identity.

## Opening, publication loading and lifecycle

[local_reader_body.dart](../../lib/features/reader/presentation/screens/local_reader_body.dart) owns adapters and annotation coordination, including explicit session replacement on committed reading-mode changes. [reflowable_readium_publication_service.dart](../../lib/features/reader/application/services/reflowable_readium_publication_service.dart) supplies generated EPUB files for TXT/FB2 before entering the native EPUB route.

[ReadiumPlatformViewSession.kt](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ReadiumPlatformViewSession.kt) validates opening identity, book/path fields and protocol compatibility. [PublicationLoader.kt](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/PublicationLoader.kt) checks local file access and EPUB format, retrieves an asset, opens the publication with allowUserInteraction=false, and returns structured failures. It closes an asset when publication opening fails and rethrows coroutine cancellation. The session parses/canonicalizes the initial locator, loads publication/positions and coordinates navigator readiness; a malformed locator or failed restore is distinct from successful opening.

[ReadiumHostBindingCoordinator.kt](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ReadiumHostBindingCoordinator.kt) separates bind/attach/layout/detach/dispose with generation tokens. Native host/session disposal, bridge disposal and publication-environment disposal are different responsibilities. A callback from an old host/resource must not act on a replacement. Engine detach clears plugin handlers/dependencies and cancels plugin work; Activity configuration changes have their own attachment handling.

The Dart viewport resolves HCPP support and falls back to legacy hybrid composition. View composition choice is separate from legacy-versus-Continuous rendition choice. See [ReadiumEpubViewport](../../packages/bibliolife_readium/lib/src/bridge/readium_epub_viewport.dart).

## Locator, restoration and persistence

[ReadiumPositionsCache.kt](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ReadiumPositionsCache.kt) computes publication positions at most once per session. [ContinuousPublicationPositionMap.kt](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ContinuousPublicationPositionMap.kt) maps resource-local locators into publication position/progression rather than using transient parent-scroll pixels as durable reading state.

The modified [R2BasicWebView.kt](../../third_party/readium-kotlin-toolkit/readium/navigator/src/main/java/org/readium/r2/navigator/R2BasicWebView.kt) provides resource-local selection/locator and JavaScript execution boundaries. Continuous geometry and resource-locator normalization reconcile visible resource coordinates with canonical publication identity; stale resource results are not interchangeable with current viewport evidence.

Application persistence belongs to ReadiumEpubReaderController and its repository dependencies. It keeps a persistable position separate from transient UI state, schedules ordinary saves at 350 ms, defers during manual movement/scrub ownership where required and serializes writes. A scrub final without a nonblank locator and valid progression cannot be persisted as verified success.

Temporary same-document anchors in [continuous-dom-anchor.js](../../third_party/readium-kotlin-toolkit/readium/navigator/src/main/assets/_scripts/src/continuous-dom-anchor.js) retain text-node/offset identity for preference reflow. Their explicit invariant is **not for persisted position, selection or general navigation**. They supplement canonical locators rather than replace the persistence contract.

## Progress navigation and command ownership

| Customization | Purpose and important invariant | Sources |
| --- | --- | --- |
| Modal / gesture / command split | The modal captures its origin; a finger gesture does not itself own a native lease. Commands retain independent identity/authority and drain asynchronously. Default preview cadence is 100 ms | [reader_progress_scrub_coordinator.dart](../../lib/features/reader/presentation/models/reader_progress_scrub_coordinator.dart) |
| Native scrub authority | Reserve ownership before waiting for navigation; newer preview/final authority invalidates old suspended work and later publications | [ProgressScrubOwnership.kt](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ProgressScrubOwnership.kt), [ProgressNavigationModel.kt](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ProgressNavigationModel.kt) |
| Verified completion | Success requires target-viewport evidence with current authority; callback receipt alone is insufficient | [ProgressNavigationCompletion.kt](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ProgressNavigationCompletion.kt) |
| Watchdog / recovery | An 8,000 ms lease bounds a dispatched seek; timeout is not verified success. Finish/release is idempotent; recovered automatic publication is fenced | [ProgressNavigationLease.kt](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ProgressNavigationLease.kt) |
| Bounded locator lookup | At most one active request and one newest pending follow-up; a final owned publication must not be coalesced away | [ContinuousLocatorDispatchGate.kt](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ContinuousLocatorDispatchGate.kt) |
| Manual-final fencing | Match rendition, scroll epoch, navigation and preference generations. After accepted canonical manual final, automatic callbacks cannot overwrite it in that context; a final lacking canonical progression does not close the fence | [ContinuousPositionPublicationGate.kt](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ContinuousPositionPublicationGate.kt) |

Current Flutter code also contains Cancel/origin rollback and command/write-generation guards. These are source-confirmed mechanisms under ongoing development, not a guarantee that all cancel/timeout/reopen races have passed device acceptance. Manual sampling, UI preview cadence, navigation watchdogs and persistence delays serve different purposes and must not be conflated.

## Selection, bookmarks, highlights and annotations

The fork adds configurable AndroidSelectionHandleMode, WebView selection-session callbacks, resource-local selection access and custom-handle JavaScript. The selection policy includes native, custom-for-unsafe-ranges and custom-for-all-paginated modes. Key sources are [AndroidSelectionHandleMode.kt](../../third_party/readium-kotlin-toolkit/readium/navigator/src/main/java/org/readium/r2/navigator/epub/AndroidSelectionHandleMode.kt), [R2BasicWebView.kt](../../third_party/readium-kotlin-toolkit/readium/navigator/src/main/java/org/readium/r2/navigator/R2BasicWebView.kt) and [selection.js](../../third_party/readium-kotlin-toolkit/readium/navigator/src/main/assets/_scripts/src/selection.js); this is substantially more than the original pin’s viewport-lock description.

Selection/session identity and resource ownership protect interaction during recycling or asynchronous replies. Native [ReadiumSelectionSession.kt](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ReadiumSelectionSession.kt) and [ReadiumSelectionInteraction.kt](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ReadiumSelectionInteraction.kt) coordinate selection; ReaderHighlightToolbarPresenter and related placement/window-guard classes own native toolbar presentation. Flutter chrome suppression during native selection is implemented by [unified_reader_screen.dart](../../lib/features/reader/presentation/widgets/unified_reader_screen.dart).

[readium_epub_annotation_coordinator.dart](../../lib/features/reader/application/services/readium_epub_annotation_coordinator.dart) validates view/session requests, writes through the annotation repository, restores the authoritative decoration snapshot and then acknowledges native actions. Native [ReadiumDecorationSession.kt](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ReadiumDecorationSession.kt) and [ReaderAnnotationDecorationMapper.kt](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ReaderAnnotationDecorationMapper.kt) present highlights; they do not replace the database as the annotation source of truth. Bookmarks are application-owned saved locations used for navigation; locator publication and bookmark UI are distinct from native selection ownership.

Changes in decorator.js, rect.js, dom.js, utils.js and HtmlDecorationTemplate.kt support local selection/geometry/decoration behavior. Exact overlap/union merging remains limited; see [annotation limitations](reader_annotation_limitations.md). Do not silently merge/delete records based on visual overlap.

## Preferences and reflow

[ReadiumPreferencesMapper.kt](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ReadiumPreferencesMapper.kt) maps application payloads to Readium preferences; the application adapter owns persisted settings and preview/commit decisions. A committed reading-mode change can replace the Reader session instead of treating every preference as an in-place update.

Continuous reflow has explicit capture/materialize/restore/converge/complete/cancel state, semantic anchoring and generation ownership. Invariants include:

- [ContinuousCssMutationGate.kt](../../third_party/readium-kotlin-toolkit/readium/navigator/src/main/java/org/readium/r2/navigator/epub/continuous/ContinuousCssMutationGate.kt): revocation stops queued CSS mutation from starting; an already-started synchronous setter must drain before terminal publication.
- [ContinuousAppliedLayoutState.kt](../../third_party/readium-kotlin-toolkit/readium/navigator/src/main/java/org/readium/r2/navigator/epub/continuous/ContinuousAppliedLayoutState.kt): physical applied WebView state survives logical cancellation. Measurement/commit must match layout/resource/epoch and, when present, the applied CSS token.
- [ContinuousMeasurementDispatcher.kt](../../third_party/readium-kotlin-toolkit/readium/navigator/src/main/java/org/readium/r2/navigator/epub/continuous/ContinuousMeasurementDispatcher.kt): measurements are dispatched independently of resource-view attachment.
- ContinuousReflowableHostView and ContinuousEpubRendition commit geometry under the current transaction rather than treating a stale preference callback as a current measurement.

Local [HtmlInjector.kt](../../third_party/readium-kotlin-toolkit/readium/navigator/src/main/java/org/readium/r2/navigator/epub/HtmlInjector.kt), [ReadiumCss.kt](../../third_party/readium-kotlin-toolkit/readium/navigator/src/main/java/org/readium/r2/navigator/epub/css/ReadiumCss.kt) and [WebViewServer.kt](../../third_party/readium-kotlin-toolkit/readium/navigator/src/main/java/org/readium/r2/navigator/epub/WebViewServer.kt) are also changed relative to upstream. Treat HTML/bootstrap/CSS delivery and the shared resource URL environment as coupled integration surfaces during upgrades.

The [motion reference](../design/motion.md) covers Flutter animation/Reduced Motion behavior. Reflow correctness and visible text jitter are not established by animation constants or source-level atomicity guards.

## Diagnostics, failure handling and test evidence

[ReadiumOpenDiagnostics.kt](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ReadiumOpenDiagnostics.kt) produces Reader.Open stages and bounded/sanitized failure facts; PublicationLoader and Reader session distinguish access, asset, publication, locator, readiness and navigation failures. [reader_open_attempt.dart](../../lib/features/reader/application/services/reader_open_attempt.dart) correlates Flutter opening stages. ProgressScrubDiagnostics and controller diagnostics trace authority, terminal outcomes and persistence separately. Logging may use bridge events, in-app logging or native Logcat; there is no assumption that all diagnostics are always enabled or centrally persisted.

[continuous-text-render.js](../../third_party/readium-kotlin-toolkit/readium/navigator/src/main/assets/_scripts/src/continuous-text-render.js) and ContinuousTextRenderDiagnostics inspect font/text/Range geometry around reflow. They are diagnostic evidence, not a demonstrated repair for intermittent visible jitter. Timeout/cancellation/failure must not be reported as a persisted navigation success.

Existing test sources provide focused coverage for:

- [Native plugin tests](../../packages/bibliolife_readium/android/src/test/kotlin/app/bibliolife/reader/readium/): backend selection, opening, host/session/bridge lifecycle, positions, selection/decorations, progress ownership/completion/watchdog and publication gates.
- [Toolkit navigator tests](../../third_party/readium-kotlin-toolkit/readium/navigator/src/test/java/org/readium/r2/navigator/): resource windows, restore boundaries, callback generations, geometry/CSS ownership, reflow and JavaScript-result handling.
- [JavaScript contract tests](../../third_party/readium-kotlin-toolkit/readium/navigator/src/main/assets/_scripts/test/) and [text-render tests](../../third_party/readium-kotlin-toolkit/readium/navigator/src/main/assets/_scripts/tests/).

This documents test presence and intended contracts, not fresh passing results. Historical reports in the [documentation index](../index.md) apply only to the versions/scenarios they tested; unresolved physical acceptance remains unresolved.

## Upgrade risks and review gaps

1. Preserve both modified tracked files and untracked custom renderer/helpers/tests. Updating only the nested HEAD or saving only git diff would omit essential untracked source.
2. Reconcile upstream changes to internal/experimental navigator APIs, pager/WebView callbacks, publication ownership, URL interception and disposal against each local boundary above.
3. Keep Dart/Kotlin protocol payloads, identity tokens, result semantics and progress/annotation ownership aligned. An upgrade must not bypass authority fences or change persistence ownership.
4. Review JavaScript source and shipped readium-fixed/readium-reflowable bundles together. Both bundles are locally modified; this documentation did not regenerate them or prove source/bundle equivalence.
5. Keep schema 23 and stored locator/annotation compatibility intact. New upstream selectors do not automatically establish a safe legacy-data merge policy.
6. Revalidate device behavior separately: restoration/reopen, Continuous resource transitions, Paginated gestures, selection handles, settings/reflow, Cancel/timeout races and composition fallback. Existing phase completion titles are not acceptance evidence for the current worktree.

Targeted inspection cannot confidently certify every legacy fixed-layout/RTL/vertical-writing combination, DRM/authentication path, Android WebView version, fallback composition branch or transient font-rendering race. The pin is not a comprehensive change ledger, full generated-bundle parity was not checked, and no fresh physical stability claim is made. These are review gaps, not assertions that each capability is broken.

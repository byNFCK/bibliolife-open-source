# Current product roadmap

Reviewed: 2026-11-11. This is the current source-informed product roadmap, not a release promise or an acceptance certificate. There are no release dates or deadlines. “Implemented” means a concrete product path is present in source; it does not mean every edge case or device scenario has passed validation.

## Basis and status rules

Sources include the [README](../../README.md), [application architecture](../architecture/overview.md), [Readium customizations](../architecture/readium-customizations.md), feature references below, and historical plans kept outside this preparation copy.

Historical suggestions are inputs, not current implementation contracts. In particular, PDF now uses pdfx rather than the old proposed Readium PDF adapter; canonical merging/acquisition already have implementations; and an opds2 enum value is not evidence of an OPDS 2 parser.

Status categories:

1. **Implemented:** a bounded user-facing path is present; scope and remaining checks are stated.
2. **Implemented but requiring validation or stabilization:** functionality exists, but acceptance, reliability or coverage is incomplete.
3. **In active development:** current Reader work and unresolved records provide evidence of ongoing implementation; this does not assign a deadline.
4. **Planned:** retained historical scope or a proposed next product increment. Sequencing below is a recommendation, not a newly approved implementation commitment.
5. **Long-term ideas:** optional vision requiring product/architecture decisions before implementation.

An area can have an implemented core and unfinished increments in later sections. No feature is marked wholly complete solely because code exists.

## 1. Implemented

| Area | Current scope and source evidence | Known limits | Next logical milestone |
| --- | --- | --- | --- |
| Local Library | Managed local import, library grid/list views, favorites/recent-book observations and local search: [BookImporter](../../lib/features/import/data/services/book_importer.dart), [Library providers](../../lib/features/library/application/providers/library_providers.dart), [SearchScreen](../../lib/features/search/presentation/screens/search_screen.dart) | Local search is not remote catalog search; original-path duplicate checks do not establish universal content deduplication. Device/data-integrity coverage is not certified here | Validate import → browse/search → open → reopen with representative existing data and failure cases |
| Collections | Creation, rename/delete, membership, editor description/custom-cover fields: [repository contract](../../lib/features/collections/domain/repositories/collection_repository.dart), [Drift implementation](../../lib/features/collections/data/repositories/drift_collection_repository.dart), [editor](../../lib/features/collections/presentation/screens/collection_editor_screen.dart) | Local persistence; no cross-device collection contract established. Presence of editor operations is not acceptance of every save/cancel case | Validate membership persistence, editor cancellation and collection/book deletion boundaries |
| Book Details | Local metadata/cover editing, reading action, progress, contents and saved-item panels: [screen](../../lib/features/book_details/presentation/screens/book_details_screen.dart), [edit service](../../lib/features/book_details/application/services/book_details_edit_service.dart) | Local imported books and remote publication details have separate paths. Historical plans for statistics, discussions and general book notes must not be inferred from this screen | Validate metadata/cover edits and navigation to the correct saved reading location without data loss |
| Settings and personalization | Material 3 light/dark/dynamic themes; Library/Home choices, connectivity/cache controls and Reader appearance settings: [SettingsBody](../../lib/features/settings/presentation/widgets/settings_body.dart), [design reference](../design/design-system.md) | Settings use different persistence owners; theme-mode notifier itself is in memory. Profile currently hosts settings rather than demonstrating an account/login system | Establish a settings persistence/restore matrix and validate Preview/Apply/Cancel separately |

These are implemented foundations for the local-first product. Reader, Online and acceptance-sensitive extensions below remain explicitly qualified.

## 2. Implemented but requiring validation or stabilization

| Area | Current status and source evidence | Known limits | Next logical milestone |
| --- | --- | --- | --- |
| Reader formats | EPUB via customized Readium; TXT/FB2 via generated EPUB; PDF via pdfx; CBZ/CBR via comic viewports: [format routing](../../lib/features/reader/domain/models/reader_kind.dart), [LocalReaderBody](../../lib/features/reader/presentation/screens/local_reader_body.dart) | Feature parity differs by format: [capabilities](../../lib/features/reader/domain/models/reader_capabilities.dart) disables PDF/comic bookmarks/highlights/TOC while exposing page seek/zoom. Advertised reflowable capabilities still require real samples/device checks | Validate opening, navigation and restoration per format; keep unsupported actions unavailable |
| EPUB / Readium | Continuous/Paginated renditions, TOC, search, selection, settings and saved-position machinery exist: [customization map](../architecture/readium-customizations.md) | Physical acceptance is incomplete; startup/resource/reflow races, composition fallback and typography edge cases are not generally certified | Complete a bounded current-build acceptance matrix for open/restore/reopen, both modes and resource boundaries |
| Bookmarks, highlights and annotations | EPUB/reflowable saved locations, native selection/decorations and repository-backed annotation notes: [annotation coordinator](../../lib/features/reader/application/services/readium_epub_annotation_coordinator.dart), [UnifiedReaderScreen](../../lib/features/reader/presentation/widgets/unified_reader_screen.dart) | Ordered selection boundaries are insufficient for reliable overlap/union merging; visually overlapping annotations may coexist. This is not a standalone knowledge-management/quote-export module | Validate create/edit/delete/reopen and exact saved-location navigation; retain [annotation limitations](../architecture/reader_annotation_limitations.md) until supported range semantics exist |
| Online catalogs and acquisition | Source-aware OPDS 1, Open Library, Google Books, Internet Archive and Gutenberg-related discovery; remote details and access-aware acquisition resolver: [transport](../../lib/features/catalog_sources/data/source_aware_remote_catalog_transport.dart), [resolver](../../lib/features/catalog_sources/application/canonical_acquisition_resolver.dart), [availability model](../../lib/features/catalog_sources/domain/canonical_acquisition_resolution.dart) | Discovery metadata is not proof of a downloadable full EPUB. Borrow/preview/purchase/metadata-only paths differ; source policies and service availability vary. Google Books currently requires an API key | Validate a source/action matrix, ensuring download availability is honest and each supported direct acquisition reaches local import |
| Downloads | Persisted sequential foreground queue, cancellation/retry/reconciliation and reuse of local BookImporter: [queue providers](../../lib/features/catalog_sources/application/remote_download_queue_provider.dart), [facade](../../lib/features/catalog_sources/application/remote_download_queue_facade.dart) | No background-worker/notification/range-resume promise. Temporary files and durable task state have different lifetimes; queue identity is not universal duplicate detection | Validate restart, cancellation, retry, missing-file recovery and repeated import without duplicate local books |
| Metadata and search | Local metadata parsing/normalization; multi-catalog search, canonical merging and acquisition classification already exist: [search controller](../../lib/features/catalog_sources/application/multi_catalog_search_controller.dart), [merger](../../lib/features/catalog_sources/application/canonical_book_merger.dart), [metadata merge](../../lib/features/metadata/data/services/book_metadata_merger.dart) | ISBN/title-author-language rules can still misidentify editions/translations. Existing code does not prove all historical field-priority, cover-quality, enrichment or latency goals are met | Validate identity/edition/language cases, source failure isolation and provenance; measure current search behavior before changing ranking |
| Accessibility | Tab/navigation semantics, text-scaling-aware measurements and partial Reduced Motion handling exist: [BiblioTabs](../../lib/shared/presentation/widgets/biblio_tabs.dart), [design](../design/design-system.md), [motion](../design/motion.md) | No complete TalkBack, keyboard, large-text, narrow-screen or contrast acceptance matrix. Reduced Motion is not applied uniformly | Agree acceptance scenarios, test actual screens and close confirmed gaps before claiming accessibility completion |
| Release readiness | Android build variants and package identity exist: [release guide](../development/build-and-release.md) | **Release is unsigned unless a private production key is configured.** Reader physical acceptance, reproducible source state, certificate continuity and final artifact/store validation remain unverified | Establish approved production signing and a data-preserving update strategy, then satisfy release acceptance gates |

The [Online baseline](../architecture/online_technical_baseline.md) explains queue contracts and distinguishes current source-aware/Home discovery from its original OPDS 1 scope. [Google Books configuration](../development/google_books_configuration.md) documents the adapter's required compile-time key; this requirement does not apply to every catalog source.

## 3. In active development

These entries reflect current Reader implementation work and unresolved acceptance records, not newly scheduled projects.

| Workstream | Evidence and current status | Remaining uncertainty | Next logical milestone |
| --- | --- | --- | --- |
| Progress navigation | [Scrub coordinator](../../lib/features/reader/presentation/models/reader_progress_scrub_coordinator.dart), [Reader adapter](../../lib/features/reader/presentation/models/readium_epub_reader_controller.dart), [native lease](../../packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ProgressNavigationLease.kt): command authority, modal origin/Cancel rollback, latest-target handling and watchdog recovery are present in uncommitted work | Final verified position, persistence, cancellation and late callbacks need current-build physical acceptance. A timeout is not successful navigation | Validate drag/preview/final, Cancel rollback, supersession, timeout recovery and close/reopen without persisting an unverified target |
| Settings and Continuous reflow | Current CSS/measurement ownership, semantic anchoring, preview coordination and diagnostic paths are described in [Readium customizations](../architecture/readium-customizations.md) | Source guards and diagnostics do not prove visible jitter is resolved; Preview/Apply/Cancel and font/resource timing remain acceptance-sensitive | Capture only the evidence needed to distinguish remaining failure boundaries in a separately authorized validation task, then accept or repair a bounded candidate |
| Opening/restoration diagnostics | [ReaderOpenAttempt](../../lib/features/reader/application/services/reader_open_attempt.dart) and structured native opening stages are present; [logging reference](../architecture/logging.md) explains ownership | Diagnostic instrumentation is not a stable-open guarantee; failure paths and current session/resource lifetimes still need correlation | Validate one complete success/failure/restore lifecycle on the current candidate and preserve actionable evidence |

[Active UX-PROGRESS records](../index.md#active-reader-investigations-and-acceptance) remain evidence of incomplete acceptance. Older completed phases apply to their tested versions only; none automatically closes the current work.

## 4. Planned

These retained/proposed increments are not represented as implemented or actively staffed.

| Area | Historical basis / current boundary | Limitation or prerequisite | Next logical milestone |
| --- | --- | --- | --- |
| Reading history and statistics | RoadMap.txt proposes reading sessions, time totals and statistics; current Library providers already expose recent/last-opened state and progress | Recent books and a saved percentage are not session-duration accounting or a statistics product | Define session/timing semantics and acceptance criteria before proposing data changes |
| Dictionary and vocabulary | RoadMap.txt proposes lookup from selected text and saved words | No implemented dictionary/vocabulary flow was established by this targeted review; provider/offline/privacy choices remain open | Specify one lookup flow and its storage/network contract |
| General book notes and quote workflows | Historical roadmap proposes general notes, quote lists and broader work with citations; selection-linked annotation notes already exist | Do not duplicate the existing annotation model or claim general notes/export from selection-note support | Define which missing user workflow extends existing notes and how it preserves locator/provenance |
| OPDS 2 and broader catalog capability | RoadMap_2.txt proposes OPDS 2; current CatalogSourceType has an opds2 value, while inspected production parser/transport uses Atom/OPDS 1 | An enum/capability label is not end-to-end JSON OPDS 2 support; authentication/DRM and general borrowing remain unestablished | Specify supported discovery/search/acquisition contracts and implement only after explicit scope approval |
| Metadata/acquisition refinements | new_parcing noadmap.txt proposes canonical results, provider priorities, cover choice and access-aware actions; substantial foundations already exist | Remaining product policy and validation must be identified against current merger/resolver rather than restarting the old design | Produce a small gap/acceptance set for edition matching, missing fields and truthful access badges |
| Synchronization and accounts | RoadMap.txt retains offline-first progress/bookmark/note sync and conflict resolution. [ProfileScreen](../../lib/features/profile/presentation/screens/profile_screen.dart) currently presents SettingsBody | No working account service, backend or cross-device sync was established in inspected application paths. Local schema **23** is not a sync contract | Decide identity/privacy, conflict semantics and a minimal progress-sync scope; design before implementing backend/schema changes |

Background downloads, additional persistent personalization and cross-platform parity require separate scope decisions. They are not implied by current interfaces or by this roadmap.

## 5. Long-term ideas

| Idea | Historical basis and current status | Prerequisites / next decision |
| --- | --- | --- |
| Audiobooks / Listen | RoadMap.txt proposes local audio, playback progress/speed, sleep timer, background media controls and audio bookmarks. No application audiobook module was established by this review | First validate stable reading; then define a dedicated audio vertical slice, media lifecycle and persistence contract. Transitive Readium/media dependencies are not an implemented player |
| AI-assisted reading / Learn | Historical ideas include explaining a selection, chapter summaries, book Q&A, flashcards, translation and note/quote analysis; none is claimed implemented | Select one user problem, consent/data boundary, provider/cost policy and evaluation criteria before integration |
| Broader knowledge/social ecosystem | Historical vision includes discussions, recommendations, manga/ranobe discovery and expanded study workflows | Separate existing CBZ/CBR image reading from a new manga catalog/social product; validate demand and scope before architecture commitments |

These are optional product directions, not a mandate to implement every historical idea.

## Recommended milestone order and exit evidence

1. **Accept the current local reading foundation:** close bounded Reader opening/restoration, progress and reflow acceptance gaps; verify existing library/collections/details/annotations survive reopen and updates.
2. **Validate the implemented Online vertical slice:** correct canonical identity and access classification → direct supported acquisition → recoverable download → one local import → correct Reader launch.
3. **Close release gates:** production signing, compatible data-preserving upgrades, current schema-23 migration/recovery evidence, accessibility scenarios and final artifact/device validation.
4. **Choose the next product increment:** prioritize a demonstrated gap from the planned section; accounts/sync, audio and AI need explicit product decisions rather than inherited “MVP” labels.

This is dependency-based sequencing without deadlines. Release acceptance requires current evidence and an identifiable source/configuration state; code existence, a historical PASS, an APK at an expected path or a successful build alone is insufficient.

## Remaining uncertainty and debt

This targeted review did not run tests/builds or certify live provider behavior. Important debt is the incomplete Reader physical matrix, annotation-range limitations, partial accessibility/Reduced Motion coverage, debug release signing, heterogeneous persistence/backup recovery and unverified edge cases in canonical identity/acquisition. Absence of an implementation claim for future features is scoped to the inspected modules, not an exhaustive proof that no prototype exists anywhere.

Archived plans remain unchanged. Future updates to this roadmap should change status only when both implementation scope and the relevant validation evidence are stated.

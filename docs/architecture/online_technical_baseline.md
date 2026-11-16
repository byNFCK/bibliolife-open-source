# Online technical baseline

This reference documents the persisted EPUB acquisition/download/import ownership
contract, originally established for OPDS 1. Current source-aware discovery also
includes Open Library, Google Books, Internet Archive and Home feeds; see the
[application architecture](overview.md#online-discovery-acquisition-and-downloads)
and [source-aware transport](../../lib/features/catalog_sources/data/source_aware_remote_catalog_transport.dart).
It is not an OPDS-only specification of the whole current application.

## Authoritative flow

`CatalogSource` → `PolicyAwareRemoteCatalogGateway` → source-aware browse/search →
`RemoteCatalogPublicationSummary` → Publication Details →
`RemoteDownloadQueueFacade.enqueueOrReuse` →
`RemoteDownloadQueueCoordinator` → persisted `RemoteDownloadTask` →
`RemoteBookDownloader` → controlled temporary EPUB →
`RemoteDownloadQueueFacade.importCompleted` →
`ProductionRemoteTemporaryEpubImporter` → `BookImporter` →
`BookMetadataMerger` → Drift `Book` → Library/Book Details → Reader.

No production screen owns a downloader, cancellation token, temporary import,
or retry lifecycle. `RemoteBookDownloadController` is legacy lower-level code
used only by isolated tests; no production code references it.

## Ownership boundaries

- Catalog gateway: resolves opaque OPDS locations and maps transport failures.
- Network policy: is the only Online/Offline authorization boundary before
  catalog or EPUB transport.
- Downloader: owns one explicit HTTP attempt, validation, controlled `.part`
  cleanup, checksum, and atomic completion rename.
- Task repository: owns durable task state, attempt counters, progress,
  immutable metadata snapshots, and filtered history observation.
- Queue coordinator: is the sole production download lifecycle owner and runs
  one FIFO task at a time.
- Queue facade: is the sole screen-facing enqueue/cancel/retry/import/history
  API and serializes imports per task.
- Importer: validates task-owned temporary input and delegates local persistence
  to the existing `BookImporter`.
- Metadata merger: applies field-specific provenance rules. Parsed title/authors
  have priority when present; trusted remote description has priority, subjects
  are combined, and ISBN/date use their dedicated selectors. See
  [BookMetadataMerger](../../lib/features/metadata/data/services/book_metadata_merger.dart).
- Reader: opens only an already persisted local book and owns no Online work.

## Stable identity and retry

Task reuse uses the exact tuple `(sourceId, remotePublicationId,
acquisitionUri)`. The planner resolves relative OPDS links to absolute HTTPS
URIs; query parameters remain significant because they may identify distinct
files. Duplicate links resolving to the same tuple reuse one task. Imported and
duplicate history is reused until explicitly hidden; retry retains the task and
immutable metadata while incrementing `attemptId` and clearing attempt-local
download state.

## Recovery and Offline behavior

Startup reconciliation performs no network calls and never redownloads.
Interrupted downloads become `pausedByAppRestart`; controlled `.part` files are
removed. A persisted `importing` task becomes retryable `failed/importFailure`.
Valid completed files remain available; missing completed files become
`failed/storage`. Terminal history is unchanged.

Offline browse/search/download attempts stop at `NetworkAccessPolicy`. Explicit
retry performs one new policy check; changing connectivity mode does not
automatically retry history. Local Library, Downloads history, and import of an
already completed task remain local operations.

## Metadata snapshot

The nullable `remote_metadata_json` field was introduced in schema 13; the current
[application schema is 21](../../lib/core/database/app_database.dart). The current
[codec](../../lib/features/catalog_sources/data/trusted_remote_metadata_snapshot.dart)
writes deterministic JSON payload version 2 and reads versions 1 and 2, with a
maximum accepted size of 64 KiB. Unknown keys and missing optional keys are
tolerated. Malformed, oversized or unsupported-version payloads restore as absent
metadata without breaking queue observation. Schema 12 rows remain importable
with a null snapshot and trigger no metadata fetch.

## Current scope

The queue has one application-scoped Riverpod coordinator and sequential
foreground EPUB downloads, without a background worker, notifications or range
resume. It does not implement authentication/DRM or general borrowing flows.
The inspected OPDS transport parses Atom/OPDS 1; an OPDS 2 source-type value is
not evidence of an implemented OPDS 2 parser.

Home catalog discovery is implemented separately from this queue contract.
Discovery metadata is not proof of a downloadable full EPUB. The current
[Google Books adapter requires a configured API key](../development/google_books_configuration.md);
other sources have their own capabilities and restrictions.

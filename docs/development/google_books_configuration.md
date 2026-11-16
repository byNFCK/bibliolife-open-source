# Google Books configuration

Source review: 2026-11-11. The current BiblioLife Google Books adapter **requires a nonblank API key**. This is an application requirement, regardless of whether an external API endpoint might otherwise permit a keyless request.

## Supported configuration

[GoogleBooksRemoteCatalogAdapter](../../lib/features/catalog_sources/data/google_books_remote_catalog_adapter.dart) defaults its apiKey constructor argument to String.fromEnvironment('GOOGLE_BOOKS_API_KEY'). The [production transport wiring](../../lib/features/catalog_sources/data/source_aware_remote_catalog_transport.dart) uses that default. Supply the key through Flutter's compile-time --dart-define mechanism; the application does not automatically read a process environment variable or provide a runtime key-entry screen.

A constructor override exists for injected clients/tests; it is not a separate user configuration flow. Compile-time configuration cannot be added to an already installed APK without rebuilding.

## Missing-key behavior

Search, Home/root discovery, pagination and volume-detail request paths converge on the adapter's _load method. Before making an HTTP request it checks apiKey.trim().isNotEmpty. A missing/whitespace-only key throws GoogleBooksRequestException with category apiKeyMissing and statusCode 0, a local configuration failure rather than an HTTP response. The diagnostic path records GOOGLE_BOOKS_REQUEST_BUILD_FAILED and a missing-configuration early exit. Invalid page/cursor arguments can fail validation earlier.

A missing key does not silently enable keyless Google Books search. Other catalog adapters have their own requirements; this requirement must not be applied to all Online sources.

## Windows examples

These are future development instructions, not commands executed for documentation. Resolve dependencies first using [development setup](setup.md). Supply the key securely to the current shell before using these examples; no real key belongs in this file:

~~~powershell
# Run from the project root
$flutterExe = 'flutter'
$deviceId = '<device-id>'

if ([string]::IsNullOrWhiteSpace($env:GOOGLE_BOOKS_API_KEY)) {
    throw 'Supply GOOGLE_BOOKS_API_KEY securely in this shell first.'
}
& $flutterExe run --debug --no-pub -t lib/main.dart -d $deviceId "--dart-define=GOOGLE_BOOKS_API_KEY=$env:GOOGLE_BOOKS_API_KEY"
~~~

For a development APK:

~~~powershell
& $flutterExe build apk --debug --no-pub -t lib/main.dart "--dart-define=GOOGLE_BOOKS_API_KEY=$env:GOOGLE_BOOKS_API_KEY"
~~~

The shell variable is expanded into a compile-time definition by these commands; it is not runtime environment-variable support. --no-pub assumes prior successful dependency resolution. Use the intended device ID, not a device identifier copied from an old report.

## Restrictions, diagnostics and verification limits

Before a separately authorized provider test, enable the Books API in the intended Google Cloud project, create an appropriately restricted key and check quota. Verify restrictions against this application's REST request and the intended signing/package configuration; possession of a key does not prove that requests will succeed. See [build and release](build-and-release.md) for the current signing blocker.

The adapter's debug configuration line reports key presence, trimmed length and build mode; failure lines report category/status and whether a key was attached. This is more than a presence-only log. URI/fingerprint sanitization exists in shared transport/performance paths, but it is not a universal guarantee that every console or captured payload is redacted. See [logging privacy boundaries](../architecture/logging.md#privacy-and-security-boundaries).

Do not commit keys or expose them in shared logs, shell history or screenshots. A --dart-define value is embedded in the client application, not a server-side secret store. Live key validity, quota, restrictions and provider availability were not tested for this documentation.

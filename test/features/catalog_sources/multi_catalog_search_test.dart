import 'dart:async';

import 'package:bibliolife/core/network/request_cancellation.dart';
import 'package:bibliolife/features/catalog_sources/application/multi_catalog_search_controller.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/canonical_book_merger.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway_provider.dart';
import 'package:bibliolife/features/catalog_sources/data/built_in_catalog_sources.dart';
import 'package:bibliolife/features/catalog_sources/data/opds1_atom_parser.dart';
import 'package:bibliolife/features/catalog_sources/domain/book_source_record.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_search_filters.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/google_books_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/internet_archive_acquisition.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_access_hint.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/multi_catalog_search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('multi-catalog online search', () {
    test('an empty query never calls the online repository', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      await harness.controller.submit('   ');

      expect(harness.gateway.rootCalls, isEmpty);
      expect(harness.gateway.queries, isEmpty);
    });

    test('a title query is trimmed, normalized, and forwarded', () async {
      final harness = _Harness(initial: _page('Frankenstein'));
      addTearDown(harness.dispose);

      await harness.controller.submit('  Frankenstein  ');
      await harness.controller.submit('frankenstein');

      expect(harness.gateway.queries, ['Frankenstein']);
      expect(harness.state.results.single.publication.title, 'Frankenstein');
    });

    test('an author query is forwarded to the online search', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      await harness.controller.submit(' Mary   Shelley ');

      expect(harness.gateway.queries, ['Mary Shelley']);
    });

    test('a stale response cannot replace a newer query', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final old = Completer<RemoteCatalogPage>();
      final fresh = Completer<RemoteCatalogPage>();
      harness.gateway.pending['Old'] = old;
      harness.gateway.pending['New'] = fresh;

      final oldSearch = harness.controller.submit('Old');
      await Future<void>.delayed(Duration.zero);
      harness.controller.setQuery('New');
      final freshSearch = harness.controller.submit('New');
      await Future<void>.delayed(Duration.zero);
      fresh.complete(_page('New'));
      await freshSearch;
      old.complete(_page('Old'));
      await oldSearch;

      expect(harness.state.query, 'New');
      expect(harness.state.results.single.publication.title, 'New');
      expect(harness.gateway.tokens['Old']!.isCancelled, isTrue);
    });

    test(
      'IA enrichment completes a verified free Open Library edition',
      () async {
        final harness = _Harness(
          initial: _page(
            'IA linked',
            publications: [_openLibraryIaPublication('IA linked')],
          ),
          sources: [_openLibrarySource, _internetArchiveSource],
          archiveResolver: _ArchiveResolver.publicEpub(),
        );
        addTearDown(harness.dispose);
        await harness.controller.applyFilters(
          CatalogSearchFilters(selectedSourceIds: [_internetArchiveSource.id]),
        );

        await harness.controller.submit('IA linked');
        await _settle();

        expect(harness.state.isLoading, isFalse);
        expect(harness.state.results, hasLength(1));
        expect(
          harness
              .state
              .results
              .single
              .routePublication
              .accessHints
              .single
              .providerId,
          internetArchiveCatalogSourceId,
        );
      },
    );

    test(
      'Open Library selection still enriches a verified IA EPUB for free search',
      () async {
        final harness = _Harness(
          initial: _page(
            'carrier',
            publications: [_openLibraryIaPublication('carrier')],
          ),
          sources: [_openLibrarySource, _internetArchiveSource],
          archiveResolver: _ArchiveResolver.publicEpub(),
        );
        addTearDown(harness.dispose);
        await harness.controller.applyFilters(
          CatalogSearchFilters(selectedSourceIds: [_openLibrarySource.id]),
        );

        await harness.controller.submit('carrier');
        await _settle();

        expect(harness.gateway.rootCalls, [_openLibrarySource]);
        expect(harness.state.results, hasLength(1));
        final result = harness.state.results.single;
        expect(result.source.id, _openLibrarySource.id);
        expect(
          result.routePublication.accessHints.single.providerId,
          internetArchiveCatalogSourceId,
        );
      },
    );

    test(
      'a free-search carrier stays hidden until IA verifies its public file',
      () async {
        final resolution = Completer<InternetArchiveAcquisitionResult>();
        final harness = _Harness(
          initial: _page(
            'deferred-carrier',
            publications: [_openLibraryIaPublication('deferred-carrier')],
          ),
          sources: [_openLibrarySource, _internetArchiveSource],
          archiveResolver: _ArchiveResolver((_) => resolution.future),
        );
        addTearDown(harness.dispose);
        await harness.controller.applyFilters(
          CatalogSearchFilters(selectedSourceIds: [_openLibrarySource.id]),
        );

        await harness.controller.submit('deferred-carrier');
        await _settle();

        expect(harness.state.isEnriching, isTrue);
        expect(harness.state.results, isEmpty);

        resolution.complete(_publicArchiveResult);
        await _settle();

        expect(harness.state.isEnriching, isFalse);
        expect(harness.state.results, hasLength(1));
      },
    );

    test('a verified IA PDF passes the free filter after enrichment', () async {
      final harness = _Harness(
        initial: _page('pdf', publications: [_openLibraryIaPublication('pdf')]),
        sources: [_openLibrarySource, _internetArchiveSource],
        archiveResolver: _ArchiveResolver(
          (_) => Future.value(
            InternetArchiveAcquisitionResult.directPdf(
              identifier: 'public-pdf',
              uri: Uri.parse('https://archive.example/public.pdf'),
            ),
          ),
        ),
      );
      addTearDown(harness.dispose);
      await harness.controller.applyFilters(
        CatalogSearchFilters(selectedSourceIds: [_openLibrarySource.id]),
      );

      await harness.controller.submit('pdf');
      await _settle();

      expect(harness.state.results, hasLength(1));
      expect(
        harness
            .state
            .results
            .single
            .routePublication
            .accessHints
            .single
            .mediaType,
        'application/pdf',
      );
    });

    test(
      'IA-only selection uses Open Library as its metadata carrier',
      () async {
        final harness = _Harness(
          initial: _page(
            'provider',
            publications: [_openLibraryIaPublication('provider')],
          ),
          sources: [_source, _openLibrarySource, _internetArchiveSource],
          archiveResolver: _ArchiveResolver.publicEpub(),
        );
        addTearDown(harness.dispose);
        await harness.controller.applyFilters(
          CatalogSearchFilters(selectedSourceIds: [_internetArchiveSource.id]),
        );

        await harness.controller.submit('provider');
        await _settle();

        expect(harness.gateway.rootCalls, [_openLibrarySource]);
        expect(harness.state.results, hasLength(1));
        expect(
          harness
              .state
              .results
              .single
              .routePublication
              .accessHints
              .single
              .providerId,
          internetArchiveCatalogSourceId,
        );
      },
    );

    test(
      'Open Library and IA selection keep one canonical result with both provenances',
      () async {
        final harness = _Harness(
          initial: _page(
            'combined-providers',
            publications: [_openLibraryIaPublication('combined-providers')],
          ),
          sources: [_openLibrarySource, _internetArchiveSource],
          archiveResolver: _ArchiveResolver.publicEpub(),
        );
        addTearDown(harness.dispose);
        await harness.controller.applyFilters(
          CatalogSearchFilters(
            selectedSourceIds: [
              _openLibrarySource.id,
              _internetArchiveSource.id,
            ],
          ),
        );

        await harness.controller.submit('combined-providers');
        await _settle();

        expect(harness.gateway.rootCalls, [_openLibrarySource]);
        expect(harness.state.results, hasLength(1));
        expect(harness.state.results.single.source.id, _openLibrarySource.id);
        expect(
          harness
              .state
              .results
              .single
              .routePublication
              .accessHints
              .single
              .providerId,
          internetArchiveCatalogSourceId,
        );
      },
    );

    test(
      'failed IA enrichment releases loading and does not block another item',
      () async {
        final resolver = _ArchiveResolver(
          (ids) => ids.single == 'bad'
              ? Future.error(StateError('network failure'))
              : Future.value(_publicArchiveResult),
        );
        final harness = _Harness(
          initial: _page(
            'mixed',
            publications: [
              _openLibraryIaPublication('bad', identifier: 'bad'),
              _openLibraryIaPublication('good', identifier: 'good'),
            ],
          ),
          sources: [_openLibrarySource, _internetArchiveSource],
          archiveResolver: resolver,
        );
        addTearDown(harness.dispose);
        await harness.controller.applyFilters(
          CatalogSearchFilters(selectedSourceIds: [_internetArchiveSource.id]),
        );

        await harness.controller.submit('mixed');
        await _settle();

        expect(harness.state.isLoading, isFalse);
        expect(harness.state.results.map((item) => item.publication.title), [
          'good',
        ]);
      },
    );

    test(
      'IA enrichment is bounded and leaves fetched results usable',
      () async {
        final resolver = _BlockingArchiveResolver();
        final harness = _Harness(
          initial: _page(
            'batch',
            publications: [
              for (var index = 0; index < 6; index += 1)
                _openLibraryIaPublication(
                  'book-$index',
                  identifier: 'ia-$index',
                ),
            ],
          ),
          sources: [_openLibrarySource, _internetArchiveSource],
          archiveResolver: resolver,
        );
        addTearDown(harness.dispose);
        await harness.controller.applyFilters(
          CatalogSearchFilters(
            onlyFreelyDownloadable: false,
            selectedSourceIds: [
              _openLibrarySource.id,
              _internetArchiveSource.id,
            ],
          ),
        );

        await harness.controller.submit('batch');
        await _settle();

        expect(harness.state.isLoading, isFalse);
        expect(harness.state.isEnriching, isTrue);
        expect(harness.state.results, hasLength(6));
        expect(resolver.maximumConcurrent, 3);

        resolver.release();
        await _settle();

        expect(harness.state.isEnriching, isFalse);
        expect(resolver.maximumConcurrent, 3);
      },
    );

    test(
      'changing the query clears old pagination before the debounce fires',
      () async {
        final harness = _Harness(
          initial: _page('First', next: _location('/2')),
        );
        addTearDown(harness.dispose);
        await harness.controller.submit('First');

        harness.controller.setQuery('Second');

        expect(harness.state.results, isEmpty);
        expect(harness.state.hasMore, isFalse);
        expect(harness.state.awaitingDebounce, isTrue);
      },
    );

    test('exact title matches rank before partial title matches', () {
      final state = _stateFor('Frankenstein', [
        _publication('Frankenstein and Friends'),
        _publication('Frankenstein'),
      ]);

      expect(state.results.map((item) => item.publication.title), [
        'Frankenstein',
        'Frankenstein and Friends',
      ]);
    });

    test('exact author matches rank before partial author matches', () {
      final state = _stateFor('Mary Shelley', [
        _publication('Another novel', authors: ['Mary Shelley Smith']),
        _publication('Frankenstein', authors: ['Mary Shelley']),
      ]);

      expect(state.results.map((item) => item.publication.title), [
        'Frankenstein',
        'Another novel',
      ]);
    });

    test('downloadable sources win an otherwise equal search rank', () {
      final openLibrary = _source.copyWith(name: 'Open Library');
      final state = MultiCatalogSearchState(
        query: 'Frankenstein',
        sources: {
          openLibrary.id: MultiCatalogSourceSearchState(
            source: CatalogSource(
              id: 'builtin-open-library',
              name: openLibrary.name,
              baseUri: openLibrary.baseUri,
              type: CatalogSourceType.openLibrary,
              isBuiltIn: true,
              isEnabled: true,
              supportsSearch: true,
              supportsNavigation: false,
              supportsAcquisition: false,
              createdAt: openLibrary.createdAt,
              updatedAt: openLibrary.updatedAt,
            ),
            page: _page(
              'Frankenstein',
              publications: [_publication('Frankenstein')],
            ),
          ),
          _source.id: MultiCatalogSourceSearchState(
            source: _source,
            page: _page(
              'Frankenstein',
              publications: [_publication('Frankenstein')],
            ),
          ),
        },
      );

      expect(state.results.first.source.id, _source.id);
    });

    test(
      'default filter materializes a parsed Gutenberg EPUB search result',
      () {
        final publication = _parsedGutenbergPublication();
        final canonical = const CanonicalBookMerger().merge([
          BookSourceRecord.fromPublication(
            sourceId: _source.id,
            sourcePriority: 1,
            publication: publication,
          ),
        ]);
        final sources = {
          _source.id: MultiCatalogSourceSearchState(
            source: _source,
            page: _page('Pride and Prejudice', publications: [publication]),
          ),
        };

        final results = materializeCanonicalSearchResults(
          books: canonical,
          sources: sources,
          presentationIds: const {},
          query: 'Pride and Prejudice',
          filters: CatalogSearchFilters.defaults(),
        );

        expect(results, hasLength(1));
        expect(results.single.routePublication.acquisitions, hasLength(1));
      },
    );

    test('Google-only failure retains its classified user message', () {
      final google = CatalogSource(
        id: 'builtin-google-books',
        name: 'Google Books',
        baseUri: Uri.parse('https://www.googleapis.com/books/v1/volumes'),
        type: CatalogSourceType.googleBooks,
        isBuiltIn: true,
        isEnabled: true,
        supportsSearch: true,
        supportsNavigation: false,
        supportsAcquisition: false,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      const message =
          'The Google Books request limit has been reached. Try again later.';
      final state = MultiCatalogSearchState(
        query: 'war',
        sources: {
          google.id: MultiCatalogSourceSearchState(
            source: google,
            failure: RemoteCatalogFailure.httpStatus,
            failureMessage: message,
          ),
        },
      );

      expect(state.allFailed, isTrue);
      expect(state.isolatedFailureMessage, message);
    });

    test('missing Google build configuration is not retryable', () {
      final entry = MultiCatalogSourceSearchState(
        source: _source,
        failure: RemoteCatalogFailure.googleBooksApiKeyMissing,
      );

      expect(entry.isRetryable, isFalse);
    });

    test(
      'missing Google configuration preserves Open Library and Gutenberg results',
      () async {
        final google = _catalogSource(
          id: 'builtin-google-books',
          name: 'Google Books',
          baseUri: 'https://www.googleapis.com/books/v1/volumes',
          type: CatalogSourceType.googleBooks,
        );
        final openLibrary = _catalogSource(
          id: 'builtin-open-library',
          name: 'Open Library',
          baseUri: 'https://openlibrary.org/search.json',
          type: CatalogSourceType.openLibrary,
        );
        final harness = _Harness(sources: [google, _source, openLibrary]);
        addTearDown(harness.dispose);
        harness.gateway.searchErrors[google.id] = GoogleBooksRequestException(
          category: GoogleBooksFailureCategory.apiKeyMissing,
          statusCode: 0,
        );
        harness.gateway.pages[_source.id] = _page(
          'Gutenberg result',
          publications: [_publication('Gutenberg result')],
        );
        harness.gateway.pages[openLibrary.id] = _pageFor(
          openLibrary,
          'Open Library result',
        );

        await harness.controller.submit('Pride');

        expect(
          harness.state.results.map((item) => item.publication.title),
          containsAll(['Gutenberg result', 'Open Library result']),
        );
        expect(
          harness.state.sources[google.id]!.failure,
          RemoteCatalogFailure.googleBooksApiKeyMissing,
        );
      },
    );

    test('merged Google and Gutenberg result preserves Gutenberg route', () {
      final google = CatalogSource(
        id: 'builtin-google-books',
        name: 'Google Books',
        baseUri: Uri.parse('https://www.googleapis.com/books/v1/volumes'),
        type: CatalogSourceType.googleBooks,
        isBuiltIn: true,
        isEnabled: true,
        supportsSearch: true,
        supportsNavigation: false,
        supportsAcquisition: false,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final googleBook = RemoteCatalogPublicationSummary(
        remoteId: 'google-id',
        title: 'Frankenstein',
        authors: const ['Mary Shelley'],
        identifiers: const ['ISBN_13:9780141439518'],
      );
      final gutenbergBook = RemoteCatalogPublicationSummary(
        remoteId: 'gutenberg-id',
        title: 'Frankenstein',
        authors: const ['Mary Shelley'],
        identifiers: const ['ISBN_13:9780141439518'],
      );
      final state = MultiCatalogSearchState(
        query: 'Frankenstein',
        sources: {
          google.id: MultiCatalogSourceSearchState(
            source: google,
            page: _page('Google', publications: [googleBook]),
          ),
          _source.id: MultiCatalogSourceSearchState(
            source: _source,
            page: _page('Gutenberg', publications: [gutenbergBook]),
          ),
        },
      );

      expect(state.results, hasLength(1));
      expect(state.results.single.publication.remoteId, 'google-id');
      expect(state.results.single.source.id, _source.id);
      expect(state.results.single.routePublication.remoteId, 'gutenberg-id');
    });

    test('later ISBN enrichment retains the first visible source key', () {
      final google = CatalogSource(
        id: 'builtin-google-books',
        name: 'Google Books',
        baseUri: Uri.parse('https://www.googleapis.com/books/v1/volumes'),
        type: CatalogSourceType.googleBooks,
        isBuiltIn: true,
        isEnabled: true,
        supportsSearch: true,
        supportsNavigation: false,
        supportsAcquisition: false,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final openLibrary = CatalogSource(
        id: 'builtin-open-library',
        name: 'Open Library',
        baseUri: Uri.parse('https://openlibrary.org/'),
        type: CatalogSourceType.openLibrary,
        isBuiltIn: true,
        isEnabled: true,
        supportsSearch: true,
        supportsNavigation: false,
        supportsAcquisition: false,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      final googleBook = _publication(
        'Pride and Prejudice',
        id: 'google',
        authors: const ['Jane Austen'],
        identifiers: const ['ISBN_13:9780141439518'],
      );
      final openBook = _publication(
        'Pride and Prejudice',
        id: 'open',
        authors: const ['Jane Austen'],
        identifiers: const ['ISBN_10:0141439513'],
      );
      final sourceKey = '${google.id}\u0000${googleBook.remoteId}';
      final state = MultiCatalogSearchState(
        query: 'Pride and Prejudice',
        presentationIds: {sourceKey: sourceKey},
        sources: {
          google.id: MultiCatalogSourceSearchState(
            source: google,
            page: _page('Google', publications: [googleBook]),
          ),
          openLibrary.id: MultiCatalogSourceSearchState(
            source: openLibrary,
            page: _page('Open Library', publications: [openBook]),
          ),
        },
      );

      expect(state.results, hasLength(1));
      expect(state.results.single.identity, sourceKey);
    });

    test('network errors remain recoverable search state', () async {
      final harness = _Harness()
        ..gateway.searchError = const RemoteCatalogException.transport();
      addTearDown(harness.dispose);

      await harness.controller.submit('Frankenstein');
      await harness.controller.submit('frankenstein');
      await harness.controller.retryFailed();

      expect(harness.state.allFailed, isTrue);
      expect(harness.state.hasRecoverableFailure, isTrue);
      expect(harness.gateway.queries, ['Frankenstein', 'Frankenstein']);
    });

    test(
      'pagination keeps the active query and deduplicates result identities',
      () async {
        final harness =
            _Harness(
                initial: _page(
                  'Sherlock',
                  publications: [_publication('Sherlock Holmes', id: '1')],
                  next: _location('/next'),
                ),
              )
              ..gateway.nextPage = _page(
                'Sherlock',
                publications: [
                  _publication('Sherlock Holmes', id: '1'),
                  _publication('The Adventures of Sherlock Holmes', id: '2'),
                ],
              );
        addTearDown(harness.dispose);

        await harness.controller.submit('Sherlock');
        await harness.controller.loadMore();

        expect(harness.state.query, 'Sherlock');
        expect(harness.gateway.queries, ['Sherlock']);
        expect(harness.gateway.pageLocations, [_location('/next')]);
        expect(harness.state.results.map((item) => item.publication.remoteId), [
          '1',
          '2',
        ]);
      },
    );
  });

  testWidgets('typing invokes online search after the 400 ms debounce', (
    tester,
  ) async {
    final gateway = _Gateway(_page('Frankenstein'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogSourceRepositoryProvider.overrideWithValue(_Repository()),
          remoteCatalogGatewayProvider.overrideWithValue(gateway),
        ],
        child: const MaterialApp(home: MultiCatalogSearchScreen()),
      ),
    );

    await tester.enterText(find.byType(SearchBar), 'Frankenstein');
    await tester.pump(const Duration(milliseconds: 399));
    expect(gateway.queries, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    await tester.pump();

    expect(gateway.queries, ['Frankenstein']);
    expect(
      find.byKey(
        const ValueKey(
          'catalog-search-publication-builtin-project-gutenberg\u0000Frankenstein',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('search field remains focused while loading changes to results', (
    tester,
  ) async {
    final gateway = _Gateway(_page('Frankenstein'));
    final response = Completer<RemoteCatalogPage>();
    gateway.pending['Frankenstein'] = response;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogSourceRepositoryProvider.overrideWithValue(_Repository()),
          remoteCatalogGatewayProvider.overrideWithValue(gateway),
        ],
        child: const MaterialApp(home: MultiCatalogSearchScreen()),
      ),
    );

    final searchField = find.byType(SearchBar);
    await tester.tap(searchField);
    await tester.enterText(searchField, 'Frankenstein');
    expect(tester.widget<SearchBar>(searchField).focusNode!.hasFocus, isTrue);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<SearchBar>(searchField).focusNode!.hasFocus, isTrue);

    response.complete(_page('Frankenstein'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey(
          'catalog-search-publication-builtin-project-gutenberg\u0000Frankenstein',
        ),
      ),
      findsOneWidget,
    );
    expect(tester.widget<SearchBar>(searchField).focusNode!.hasFocus, isTrue);
  });

  testWidgets('keyboard Search cancels a pending debounce request', (
    tester,
  ) async {
    final gateway = _Gateway(_page('Frankenstein'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogSourceRepositoryProvider.overrideWithValue(_Repository()),
          remoteCatalogGatewayProvider.overrideWithValue(gateway),
        ],
        child: const MaterialApp(home: MultiCatalogSearchScreen()),
      ),
    );

    await tester.enterText(find.byType(SearchBar), 'Frankenstein');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(gateway.queries, ['Frankenstein']);
  });

  testWidgets('search cards fit narrow rows at supported text scales', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final configuration in [
      (const Size(360, 800), 1.0),
      (const Size(320, 800), 1.3),
    ]) {
      await tester.binding.setSurfaceSize(configuration.$1);
      final gateway = _Gateway(
        _page(
          'A deliberately long result title that needs two lines',
          publications: [
            _publication(
              'A deliberately long result title that needs two lines',
              authors: const ['A deliberately long author name'],
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: configuration.$1,
            textScaler: TextScaler.linear(configuration.$2),
          ),
          child: ProviderScope(
            overrides: [
              catalogSourceRepositoryProvider.overrideWithValue(_Repository()),
              remoteCatalogGatewayProvider.overrideWithValue(gateway),
            ],
            child: const MaterialApp(home: MultiCatalogSearchScreen()),
          ),
        ),
      );
      await tester.enterText(find.byType(SearchBar), 'result');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final tile = find.byKey(
        const ValueKey(
          'catalog-search-publication-builtin-project-gutenberg\u0000A deliberately long result title that needs two lines',
        ),
      );
      final title = find.text(
        'A deliberately long result title that needs two lines',
      );
      final author = find.text('A deliberately long author name');
      expect(tester.takeException(), isNull);
      expect(
        tester.getBottomRight(title).dy,
        lessThanOrEqualTo(tester.getBottomRight(tile).dy),
      );
      expect(
        tester.getBottomRight(author).dy,
        lessThanOrEqualTo(tester.getBottomRight(tile).dy),
      );
      final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .mainAxisExtent,
        isNotNull,
      );
    }
  });
}

final _source = CatalogSource(
  id: 'builtin-project-gutenberg',
  name: 'Project Gutenberg',
  baseUri: Uri.parse('https://www.gutenberg.org/ebooks/search.opds/'),
  type: CatalogSourceType.opds1,
  isBuiltIn: true,
  isEnabled: true,
  supportsSearch: true,
  supportsNavigation: true,
  supportsAcquisition: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

final _openLibrarySource = CatalogSource(
  id: 'builtin-open-library',
  name: 'Open Library',
  baseUri: _source.baseUri,
  type: CatalogSourceType.openLibrary,
  isBuiltIn: true,
  isEnabled: true,
  supportsSearch: true,
  supportsNavigation: false,
  supportsAcquisition: false,
  createdAt: _source.createdAt,
  updatedAt: _source.updatedAt,
);

final _internetArchiveSource = CatalogSource(
  id: internetArchiveCatalogSourceId,
  name: 'Internet Archive',
  baseUri: _source.baseUri,
  type: CatalogSourceType.internetArchive,
  isBuiltIn: true,
  isEnabled: true,
  supportsSearch: false,
  supportsNavigation: false,
  supportsAcquisition: true,
  createdAt: _source.createdAt,
  updatedAt: _source.updatedAt,
);

final _publicArchiveResult = InternetArchiveAcquisitionResult.directEpub(
  identifier: 'public',
  uri: Uri.parse('https://archive.example/public.epub'),
);

final _capability = RemoteCatalogSearchCapability.directTemplate(
  _location('/search?q=%7BsearchTerms%7D'),
);

RemoteCatalogLocation _location(String path) =>
    RemoteCatalogLocation.parse('https://catalog.example$path');

RemoteCatalogPublicationSummary _publication(
  String title, {
  String? id,
  List<String> authors = const ['Author'],
  List<String> identifiers = const [],
}) => RemoteCatalogPublicationSummary(
  remoteId: id ?? title,
  title: title,
  authors: authors,
  identifiers: identifiers,
  accessHints: [
    RemoteCatalogAccessHint(
      type: RemoteCatalogAccessType.directDownload,
      uri: Uri.parse('https://catalog.example/$title.epub'),
      mediaType: 'application/epub+zip',
      isFullBook: true,
      isDrmFree: true,
    ),
  ],
);

RemoteCatalogPublicationSummary _openLibraryIaPublication(
  String title, {
  String? identifier,
}) => RemoteCatalogPublicationSummary(
  remoteId: title,
  title: title,
  authors: const ['Author'],
  sourceLists: {
    'openLibrary.internetArchiveIds': [identifier ?? title],
  },
);

Future<void> _settle() async {
  for (var index = 0; index < 8; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

RemoteCatalogPublicationSummary _parsedGutenbergPublication() =>
    const Opds1AtomParser()
        .parse(
          sourceId: _source.id,
          location: RemoteCatalogLocation.parse(
            'https://www.gutenberg.org/ebooks/search.opds/?query=Pride',
          ),
          isSearchResult: true,
          body:
              '<feed xmlns="http://www.w3.org/2005/Atom"><title>Books</title>'
              '<entry><id>https://www.gutenberg.org/ebooks/1342.opds</id>'
              '<title>Pride and Prejudice</title><content>Jane Austen</content>'
              '<link rel="subsection" href="/ebooks/1342.opds"/>'
              '</entry></feed>',
        )
        .publications
        .single;

RemoteCatalogPage _page(
  String title, {
  List<RemoteCatalogPublicationSummary>? publications,
  RemoteCatalogLocation? next,
}) => RemoteCatalogPage(
  sourceId: _source.id,
  location: _location('/search'),
  title: title,
  publications: publications ?? [_publication(title)],
  nextPageLocation: next,
  searchCapability: _capability,
);

RemoteCatalogPage _pageFor(CatalogSource source, String title) =>
    RemoteCatalogPage(
      sourceId: source.id,
      location: _location('/search'),
      title: title,
      publications: [_publication(title)],
      searchCapability: _capability,
    );

CatalogSource _catalogSource({
  required String id,
  required String name,
  required String baseUri,
  required CatalogSourceType type,
}) => CatalogSource(
  id: id,
  name: name,
  baseUri: Uri.parse(baseUri),
  type: type,
  isBuiltIn: true,
  isEnabled: true,
  supportsSearch: true,
  supportsNavigation: false,
  supportsAcquisition: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

MultiCatalogSearchState _stateFor(
  String query,
  List<RemoteCatalogPublicationSummary> publications,
) => MultiCatalogSearchState(
  query: query,
  sources: {
    _source.id: MultiCatalogSourceSearchState(
      source: _source,
      page: _page(query, publications: publications),
    ),
  },
);

class _Harness {
  _Harness({
    RemoteCatalogPage? initial,
    List<CatalogSource>? sources,
    InternetArchiveAcquisitionResolver? archiveResolver,
  }) : gateway = _Gateway(initial ?? _page('default')) {
    _sources = sources ?? [_source];
    container = ProviderContainer(
      overrides: [
        catalogSourceRepositoryProvider.overrideWithValue(
          _Repository(_sources),
        ),
        remoteCatalogGatewayProvider.overrideWithValue(gateway),
        if (archiveResolver != null)
          internetArchiveAcquisitionResolverProvider.overrideWithValue(
            archiveResolver,
          ),
      ],
    );
    subscription = container.listen(
      multiCatalogSearchControllerProvider,
      (_, _) {},
    );
  }

  final _Gateway gateway;
  late final List<CatalogSource> _sources;
  late final ProviderContainer container;
  late final ProviderSubscription<MultiCatalogSearchState> subscription;

  MultiCatalogSearchController get controller =>
      container.read(multiCatalogSearchControllerProvider.notifier);
  MultiCatalogSearchState get state =>
      container.read(multiCatalogSearchControllerProvider);

  void dispose() {
    subscription.close();
    container.dispose();
  }
}

class _ArchiveResolver implements InternetArchiveAcquisitionResolver {
  _ArchiveResolver(this._resolve);

  factory _ArchiveResolver.publicEpub() =>
      _ArchiveResolver((_) => Future.value(_publicArchiveResult));

  final Future<InternetArchiveAcquisitionResult> Function(Iterable<String>)
  _resolve;

  @override
  Future<InternetArchiveAcquisitionResult> resolve(
    Iterable<String> identifiers,
  ) => _resolve(identifiers);
}

class _BlockingArchiveResolver implements InternetArchiveAcquisitionResolver {
  final _release = Completer<void>();
  var active = 0;
  var maximumConcurrent = 0;

  @override
  Future<InternetArchiveAcquisitionResult> resolve(
    Iterable<String> identifiers,
  ) async {
    active++;
    if (active > maximumConcurrent) maximumConcurrent = active;
    await _release.future;
    active--;
    return _publicArchiveResult;
  }

  void release() => _release.complete();
}

class _Gateway implements RemoteCatalogGateway {
  _Gateway(this.initial);

  final RemoteCatalogPage initial;
  final List<CatalogSource> rootCalls = [];
  final List<String> queries = [];
  final List<RemoteCatalogLocation> pageLocations = [];
  final Map<String, Completer<RemoteCatalogPage>> pending = {};
  final Map<String, CancellationToken> tokens = {};
  final Map<String, RemoteCatalogPage> pages = {};
  final Map<String, RemoteCatalogException> searchErrors = {};
  RemoteCatalogPage? nextPage;
  RemoteCatalogException? searchError;

  @override
  Future<RemoteCatalogPage> loadRoot(CatalogSource source) async {
    rootCalls.add(source);
    return RemoteCatalogPage(
      sourceId: source.id,
      location: _location('/root'),
      title: source.name,
      searchCapability: _capability,
    );
  }

  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) async {
    queries.add(query);
    final token = MetadataRequestScope.current?.token;
    if (token != null) tokens[query] = token;
    if (searchErrors[source.id] case final error?) throw error;
    if (searchError case final error?) throw error;
    if (pending[query] case final completer?) return completer.future;
    return pages[source.id] ?? initial;
  }

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) async {
    pageLocations.add(location);
    return nextPage!;
  }
}

class _Repository implements CatalogSourceRepository {
  _Repository([List<CatalogSource>? sources]) : sources = sources ?? [_source];

  final List<CatalogSource> sources;

  @override
  Future<CatalogSource?> getById(String id) async =>
      sources.where((source) => source.id == id).firstOrNull;

  @override
  Future<List<CatalogSource>> getAll() async => sources;

  @override
  Stream<List<CatalogSource>> watchAll() => Stream.value(sources);

  @override
  Future<void> ensureBuiltInSources() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

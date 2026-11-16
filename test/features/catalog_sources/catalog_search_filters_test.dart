import 'package:bibliolife/features/catalog_sources/application/canonical_book_merger.dart';
import 'package:bibliolife/features/catalog_sources/data/opds1_atom_parser.dart';
import 'package:bibliolife/features/catalog_sources/domain/book_source_record.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_search_filters.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_access_hint.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_acquisition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CatalogSearchFilters', () {
    test('default is stable and free download alone is not custom', () {
      final filters = CatalogSearchFilters.defaults();
      expect(filters.isDefault, isTrue);
      expect(filters.hasCustomFilters, isFalse);
    });

    test('normalizes identity and detects custom filter', () {
      final a = CatalogSearchFilters(
        author: ' Mary   Shelley ',
        languages: const ['EN'],
      );
      final b = CatalogSearchFilters(
        author: 'mary shelley',
        languages: const ['en'],
      );
      expect(a, b);
      expect(a.hasCustomFilters, isTrue);
    });

    test('parsed Gutenberg EPUB survives the default free filter', () {
      final book = const CanonicalBookMerger().merge([
        _gutenbergRecord(),
      ]).single;
      expect(
        const CatalogSearchPostFilter().apply(
          book,
          CatalogSearchFilters.defaults(),
        ),
        isNotNull,
      );
    });

    test(
      'Gutenberg acquisition remains eligible after metadata merge and edition pruning',
      () {
        final gutenberg = _gutenbergRecord(publishedDate: '1813');
        final metadataOnly = BookSourceRecord.fromPublication(
          sourceId: 'metadata-only',
          sourcePriority: 0,
          publication: RemoteCatalogPublicationSummary(
            remoteId: 'metadata-pride',
            title: 'Pride and Prejudice',
            authors: ['Jane Austen'],
            publishedDate: '2020',
          ),
        );
        final canonical = const CanonicalBookMerger().merge([
          metadataOnly,
          gutenberg,
        ]).single;

        expect(canonical.primary.publication.acquisitions, isEmpty);
        final result = const CatalogSearchPostFilter().apply(
          canonical,
          CatalogSearchFilters(editionYearTo: 1900),
        );

        expect(result, isNotNull);
        expect(result!.sources, hasLength(1));
        expect(result.sources.single.sourceId, 'builtin-project-gutenberg');
        expect(result.sources.single.publication.acquisitions, hasLength(1));
      },
    );

    test('verified direct Internet Archive PDF survives the free filter', () {
      final record = BookSourceRecord.fromPublication(
        sourceId: 'builtin-open-library',
        sourcePriority: 1,
        publication: RemoteCatalogPublicationSummary(
          remoteId: 'public-pdf',
          title: 'Public PDF',
          acquisitions: [
            RemoteAcquisition(
              relation: 'http://opds-spec.org/acquisition/open-access',
              href: 'https://archive.org/download/public-pdf/public.pdf',
              mediaType: 'application/pdf',
            ),
          ],
        ),
      );

      expect(
        const CatalogSearchPostFilter().apply(
          const CanonicalBookMerger().merge([record]).single,
          CatalogSearchFilters.defaults(),
        ),
        isNotNull,
      );
    });

    test(
      'Internet Archive source filter matches an eligible provider hint',
      () {
        final record = BookSourceRecord.fromPublication(
          sourceId: 'builtin-open-library',
          sourcePriority: 1,
          publication: RemoteCatalogPublicationSummary(
            remoteId: 'open-library-work',
            title: 'Public archive work',
            accessHints: [
              RemoteCatalogAccessHint(
                type: RemoteCatalogAccessType.directDownload,
                uri: Uri.parse('https://archive.org/download/public/work.epub'),
                mediaType: 'application/epub+zip',
                isFullBook: true,
                isDrmFree: true,
                providerId: 'builtin-internet-archive',
              ),
            ],
          ),
        );
        final book = const CanonicalBookMerger().merge([record]).single;

        final filtered = const CatalogSearchPostFilter().apply(
          book,
          CatalogSearchFilters(
            selectedSourceIds: const ['builtin-internet-archive'],
          ),
        );

        expect(filtered, isNotNull);
        expect(filtered!.sources, hasLength(1));
        expect(
          filtered.acquisitionCandidates.single.sourceId,
          'builtin-internet-archive',
        );
      },
    );

    test('metadata-only, LCP, and unknown records remain rejected', () {
      final metadataOnly = BookSourceRecord.fromPublication(
        sourceId: 'metadata-only',
        sourcePriority: 1,
        publication: RemoteCatalogPublicationSummary(
          remoteId: 'metadata',
          title: 'Metadata only',
        ),
      );
      final lcp = BookSourceRecord.fromPublication(
        sourceId: 'lcp',
        sourcePriority: 1,
        publication: RemoteCatalogPublicationSummary(
          remoteId: 'lcp',
          title: 'Protected',
          acquisitions: [
            RemoteAcquisition(
              relation: 'http://opds-spec.org/acquisition/open-access',
              href: 'https://catalog.example/protected.lcpl',
              mediaType: 'application/vnd.readium.lcp.license.v1.0+json',
            ),
          ],
        ),
      );
      final unknown = BookSourceRecord.fromPublication(
        sourceId: 'unknown',
        sourcePriority: 1,
        publication: RemoteCatalogPublicationSummary(
          remoteId: 'unknown',
          title: 'Unknown availability',
          acquisitions: [
            RemoteAcquisition(
              relation: 'https://example.com/acquisition/unknown',
              href: 'https://catalog.example/unknown.epub',
              mediaType: 'application/epub+zip',
            ),
          ],
        ),
      );
      final filter = const CatalogSearchPostFilter();

      expect(
        filter.apply(
          const CanonicalBookMerger().merge([metadataOnly]).single,
          CatalogSearchFilters.defaults(),
        ),
        isNull,
      );
      expect(
        filter.apply(
          const CanonicalBookMerger().merge([lcp]).single,
          CatalogSearchFilters.defaults(),
        ),
        isNull,
      );
      expect(
        filter.apply(
          const CanonicalBookMerger().merge([unknown]).single,
          CatalogSearchFilters.defaults(),
        ),
        isNull,
      );
    });

    test(
      'include OR, exclude veto, author, year, language and free provenance',
      () {
        final book = const CanonicalBookMerger().merge([
          _record(
            'old',
            subjects: const ['Fantasy'],
            author: 'Mary Shelley',
            year: '1818',
            language: 'en',
            free: true,
          ),
          _record(
            'new',
            subjects: const ['Horror'],
            author: 'Mary Shelley',
            year: '2020',
            language: 'en',
            free: false,
          ),
        ]).single;
        final filter = const CatalogSearchPostFilter();
        expect(
          filter.apply(
            book,
            CatalogSearchFilters(
              includedGenres: const ['Horror', 'Fantasy'],
              author: 'shelley mary',
              languages: const ['en'],
              editionYearTo: 1900,
            ),
          ),
          isNotNull,
        );
        expect(
          filter.apply(
            book,
            CatalogSearchFilters(excludedGenres: const ['Fantasy']),
          ),
          isNull,
        );
        final edition = filter.apply(
          book,
          CatalogSearchFilters(
            editionYearFrom: 2000,
            onlyFreelyDownloadable: false,
          ),
        );
        expect(edition?.sources.single.remoteId, 'new');
        expect(
          filter.apply(book, CatalogSearchFilters(editionYearFrom: 2000)),
          isNull,
        );
      },
    );
  });
}

BookSourceRecord _gutenbergRecord({String? publishedDate}) {
  final parsed = const Opds1AtomParser().parse(
    sourceId: 'builtin-project-gutenberg',
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
  );
  final publication = parsed.publications.single;
  return BookSourceRecord.fromPublication(
    sourceId: 'builtin-project-gutenberg',
    sourcePriority: 1,
    publication: RemoteCatalogPublicationSummary(
      remoteId: publication.remoteId,
      title: publication.title,
      authors: publication.authors,
      acquisitions: publication.acquisitions,
      detailsLocation: publication.detailsLocation,
      publishedDate: publishedDate ?? publication.publishedDate,
    ),
  );
}

BookSourceRecord _record(
  String id, {
  required List<String> subjects,
  required String author,
  required String year,
  required String language,
  required bool free,
}) => BookSourceRecord.fromPublication(
  sourceId: 'source-$id',
  sourcePriority: 1,
  publication: RemoteCatalogPublicationSummary(
    remoteId: id,
    title: 'Frankenstein',
    authors: [author],
    subjects: subjects,
    publishedDate: year,
    language: language,
    accessHints: free
        ? [
            RemoteCatalogAccessHint(
              type: RemoteCatalogAccessType.directDownload,
              uri: Uri.parse('https://catalog.example/$id.epub'),
              mediaType: 'application/epub+zip',
              isFullBook: true,
              isDrmFree: true,
            ),
          ]
        : const [],
  ),
);

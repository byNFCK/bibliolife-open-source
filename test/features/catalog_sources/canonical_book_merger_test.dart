import 'package:bibliolife/features/catalog_sources/application/canonical_book_merger.dart';
import 'package:bibliolife/features/catalog_sources/domain/book_source_record.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_acquisition.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_access_hint.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const merger = CanonicalBookMerger();

  test('same valid ISBN-13 merges and keeps source references', () {
    final books = merger.merge([
      _record(
        'builtin-google-books',
        1,
        identifiers: ['ISBN_13:9780141439518'],
      ),
      _record(
        'builtin-project-gutenberg',
        3,
        identifiers: ['isbn:9780141439518'],
      ),
    ]);

    expect(books, hasLength(1));
    expect(books.single.canonicalId, 'isbn13:9780141439518');
    expect(
      books.single.sourceReferences.map((item) => item.sourceId),
      containsAll(['builtin-google-books', 'builtin-project-gutenberg']),
    );
  });

  test('same valid ISBN-10 merges and keeps canonical ID stable', () {
    final first = merger.merge([
      _record('open', 2, identifiers: ['ISBN_10:0141439513']),
    ]);
    final enriched = merger.merge([
      _record('open', 2, identifiers: ['ISBN_10:0141439513']),
      _record('google', 1, identifiers: ['ISBN_10:0141439513']),
    ]);

    expect(enriched.single.canonicalId, first.single.canonicalId);
  });

  test('equivalent ISBN-10 and ISBN-13 merge as one edition', () {
    final books = merger.merge([
      _record('google', 1, identifiers: ['ISBN_13:9780141439518']),
      _record('open', 2, identifiers: ['ISBN_10:0141439513']),
    ]);

    expect(books, hasLength(1));
    expect(books.single.identifiers.isbn13, contains('9780141439518'));
  });

  test('same title and author merges only with compatible language', () {
    final books = merger.merge([
      _record('google', 1),
      _record('gutenberg', 3),
      _record('other-language', 2, language: 'fr'),
    ]);

    expect(books, hasLength(2));
  });

  test('same title with a conflicting author does not merge', () {
    final books = merger.merge([
      _record('google', 1),
      _record('commentary', 2, author: 'Someone Else'),
    ]);

    expect(books, hasLength(2));
  });

  test('conflicting valid ISBNs never merge, even with matching metadata', () {
    final books = merger.merge([
      _record('google', 1, identifiers: ['ISBN_13:9780141439518']),
      _record('open', 2, identifiers: ['ISBN_13:9780199535569']),
    ]);

    expect(books, hasLength(2));
  });

  test('Google metadata wins, empty values do not erase populated values', () {
    final books = merger.merge([
      _record('gutenberg', 3, description: 'Complete description'),
      _record('google', 1, description: 'Google description'),
      _record('open', 2, description: ''),
    ]);

    expect(books.single.description, 'Google description');
    expect(books.single.fieldProvenance['description'], 'google');
  });

  test('Open Library contributes subjects and first publication year', () {
    final books = merger.merge([
      _record(
        'google',
        1,
        description:
            'A sufficiently detailed Google description for the selected field.',
      ),
      _record(
        'open',
        2,
        subjects: ['Romance', 'Classic fiction'],
        firstPublicationYear: '1813',
      ),
    ]);

    expect(
      books.single.categories,
      containsAll(['Romance', 'Classic fiction']),
    );
    expect(books.single.firstPublicationYear, '1813');
    expect(books.single.fieldProvenance['firstPublicationYear'], 'open');
  });

  test(
    'retains a verified Gutenberg EPUB as a direct acquisition candidate',
    () {
      final books = merger.merge([_record('gutenberg', 3)]);

      expect(
        books.single.acquisitionCandidates.single.type,
        RemoteCatalogAccessType.directDownload,
      );
      expect(books.single.acquisitionCandidates.single.fullBook, isTrue);
    },
  );

  test(
    'canonical enrichment keeps its ID while upgrading to the best cover',
    () {
      final initial = merger.merge([_record('gutenberg', 3)]).single;
      final enriched = merger.merge([
        _record('gutenberg', 3, cover: 'https://gutenberg.example/small.jpg'),
        _record('google', 1, cover: 'https://books.google.com/large.jpg'),
      ]).single;

      expect(enriched.canonicalId, initial.canonicalId);
      expect(
        enriched.selectedCover.toString(),
        'https://books.google.com/large.jpg',
      );
      expect(enriched.displayPublication.coverLocation, enriched.selectedCover);
    },
  );

  test(
    'incremental pages use indexes and preserve the first presentation ID',
    () {
      final accumulator = CanonicalSearchAccumulator();
      final first = _record(
        'google',
        1,
        identifiers: ['ISBN_13:9780141439518'],
      );
      final later = _record(
        'gutenberg',
        3,
        identifiers: ['ISBN_10:0141439513'],
      );

      accumulator.addPage([first]);
      final change = accumulator.addPage([later]);

      expect(accumulator.books, hasLength(1));
      expect(change.enrichedCanonicalRecords, 1);
      expect(accumulator.fullScans, 0);
      expect(accumulator.indexHits, greaterThan(0));
      expect(
        accumulator.presentationIds['gutenberg\u0000gutenberg-id'],
        'google\u0000google-id',
      );
    },
  );

  test(
    'replaying an already applied page does not change canonical records',
    () {
      final accumulator = CanonicalSearchAccumulator();
      final page = [_record('google', 1)];

      accumulator.addPage(page);
      final replay = accumulator.addPage(page);

      expect(replay.didChange, isFalse);
      expect(accumulator.books, hasLength(1));
    },
  );
}

BookSourceRecord _record(
  String source,
  int priority, {
  String author = 'Jane Austen',
  String language = 'en',
  String? description,
  List<String> identifiers = const [],
  List<String> subjects = const [],
  String? firstPublicationYear,
  String? cover,
}) => BookSourceRecord.fromPublication(
  sourceId: source,
  sourcePriority: priority,
  publication: RemoteCatalogPublicationSummary(
    remoteId: '$source-id',
    title: 'Pride and Prejudice',
    authors: [author],
    language: language,
    summary: description,
    identifiers: identifiers,
    subjects: subjects,
    coverLocation: cover == null ? null : RemoteCatalogLocation.parse(cover),
    sourceMetadata: firstPublicationYear == null
        ? const {}
        : {'openLibrary.firstPublishYear': firstPublicationYear},
    acquisitions: source == 'gutenberg'
        ? [
            RemoteAcquisition(
              relation: 'http://opds-spec.org/acquisition/open-access',
              href: 'https://example.test/book.epub',
              mediaType: 'application/epub+zip',
            ),
          ]
        : const [],
  ),
);

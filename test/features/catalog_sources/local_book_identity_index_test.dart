import 'package:bibliolife/features/catalog_sources/application/local_search_result_assembler.dart';
import 'package:bibliolife/features/catalog_sources/application/multi_catalog_search_controller.dart';
import 'package:bibliolife/features/catalog_sources/domain/book_source_record.dart';
import 'package:bibliolife/features/catalog_sources/domain/canonical_book.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalBookIdentityIndex', () {
    test('prefers exact catalog source and remote publication ID', () {
      final match = _index(
        _book(catalogSourceId: 'source', remoteId: 'remote-id'),
      ).match(_target());

      expect(match?.book.id, 'local');
      expect(match?.method, LocalSearchMatchMethod.remoteIdentity);
    });

    test('matches persisted import provenance before ISBN', () {
      final match = _index(
        _book(
          catalogSourceId: 'source',
          publicationLocation: 'https://catalog.example/details/book',
        ),
      ).match(_target());

      expect(match?.method, LocalSearchMatchMethod.provenanceOrCanonicalAlias);
    });

    test('matches a canonical source alias', () {
      final match =
          _index(
            _book(
              catalogSourceId: 'archive',
              remoteId: 'ia-7',
              publicationLocation: 'https://archive.example/edition/ia-7',
            ),
          ).match(
            _target(
              aliases: const [
                LocalBookIdentityAlias(
                  sourceId: 'archive',
                  remotePublicationId: 'ia-7',
                  publicationLocation: 'https://archive.example/edition/ia-7',
                ),
              ],
            ),
          );

      expect(match?.method, LocalSearchMatchMethod.provenanceOrCanonicalAlias);
    });

    test('matches normalized ISBN from any persisted identifier', () {
      final match = _index(
        _book(identifiers: const ['ISBN 978-0-306-40615-7']),
      ).match(_target(identifiers: const ['urn:isbn:9780306406157']));

      expect(match?.method, LocalSearchMatchMethod.isbn);
    });

    test('matches conservative normalized title, author, and language', () {
      final match = _index(
        _book(title: 'A  Book!', authors: const ['One Author'], language: 'EN'),
      ).match(_target(title: 'a book', authors: const ['One Author']));

      expect(match?.method, LocalSearchMatchMethod.titleAuthorLanguage);
    });

    test('never matches a title-only collision', () {
      final match = _index(
        _book(authors: const ['Someone Else']),
      ).match(_target(authors: const []));

      expect(match, isNull);
    });

    test('keeps different-language editions separate', () {
      final match = _index(_book(language: 'de')).match(_target());

      expect(match, isNull);
    });

    test('does not treat an empty source or remote ID as an exact match', () {
      final match = _index(
        _book(
          title: 'Different edition',
          authors: const ['Different author'],
          catalogSourceId: '',
          remoteId: 'remote-id',
        ),
      ).match(_target());

      expect(match, isNull);
    });

    test('does not use an empty or invalid ISBN as identity evidence', () {
      final match = _index(
        _book(
          title: 'Different edition',
          authors: const ['Different author'],
          identifiers: const ['not-an-isbn'],
        ),
      ).match(_target(identifiers: const ['not-an-isbn']));

      expect(match, isNull);
    });

    test('does not accept an uncorroborated work-level alias', () {
      final match =
          _index(
            _book(
              title: 'Different edition',
              authors: const ['Different author'],
              catalogSourceId: 'archive',
              remoteId: 'work-identifier',
            ),
          ).match(
            _target(
              aliases: const [
                LocalBookIdentityAlias(
                  sourceId: 'archive',
                  remotePublicationId: 'work-identifier',
                ),
              ],
            ),
          );

      expect(match, isNull);
    });

    test('keeps materially different ISBN editions separate', () {
      final match = _index(
        _book(identifiers: const ['9780306406157']),
      ).match(_target(identifiers: const ['9780131103627']));

      expect(match, isNull);
    });

    test(
      'leaves ambiguous title, author, and language candidates separate',
      () {
        final match = LocalBookIdentityIndex([
          _book(id: 'first'),
          _book(id: 'second'),
        ]).match(_target());

        expect(match, isNull);
      },
    );

    test('requires both author and language for title fallback', () {
      expect(
        _index(_book(authors: const [], language: 'en')).match(_target()),
        isNull,
      );
      expect(
        _index(
          _book(authors: const ['One Author'], language: null),
        ).match(_target()),
        isNull,
      );
    });

    test('Search assembly uses the same shared identity matcher', () {
      final local = _book(identifiers: const ['9780306406157']);
      final assembled = assembleLocalSearchResults(
        remote: [_result()],
        local: [local],
        query: 'book',
      );

      expect(assembled, hasLength(1));
      expect(assembled.single.localBook?.id, local.id);
      expect(assembled.single.matchMethod, LocalSearchMatchMethod.isbn);
    });
  });
}

LocalBookIdentityIndex _index(LibraryBook book) =>
    LocalBookIdentityIndex([book]);

LocalBookIdentityTarget _target({
  String title = 'A book',
  Iterable<String> authors = const ['One Author'],
  String? language = 'en',
  Iterable<String> identifiers = const [],
  Iterable<LocalBookIdentityAlias> aliases = const [],
}) => LocalBookIdentityTarget(
  sourceId: 'source',
  remotePublicationId: 'remote-id',
  title: title,
  authors: authors,
  language: language,
  identifiers: identifiers,
  publicationLocation: 'https://catalog.example/details/book',
  acquisitionLocation: 'https://catalog.example/download/book.epub',
  aliases: aliases,
);

LibraryBook _book({
  String id = 'local',
  String title = 'A book',
  Iterable<String> authors = const ['One Author'],
  String? language = 'en',
  Iterable<String> identifiers = const [],
  String? catalogSourceId,
  String? remoteId,
  String? publicationLocation,
}) => LibraryBook(
  id: id,
  title: title,
  sortTitle: title,
  author: authors.join('; '),
  description: null,
  filePath: 'C:/library/$id.epub',
  fileName: '$id.epub',
  fileExtension: 'epub',
  format: BookFormat.epub,
  mediaType: 'application/epub+zip',
  coverPath: null,
  language: language,
  publisher: null,
  publishedDate: null,
  isbn: null,
  pageCount: null,
  fileSizeBytes: 1,
  dateAdded: DateTime.utc(2026),
  lastOpenedAt: null,
  isFavorite: false,
  authors: authors.toList(),
  identifiers: identifiers.toList(),
  catalogSourceId: catalogSourceId,
  remotePublicationId: remoteId,
  remotePublicationLocation: publicationLocation,
);

MultiCatalogSearchResult _result() {
  final publication = RemoteCatalogPublicationSummary(
    remoteId: 'remote-id',
    title: 'A book',
    authors: const ['One Author'],
    language: 'en',
    identifiers: const ['urn:isbn:9780306406157'],
  );
  final record = BookSourceRecord.fromPublication(
    sourceId: 'source',
    sourcePriority: 0,
    publication: publication,
  );
  return MultiCatalogSearchResult(
    source: CatalogSource(
      id: 'source',
      name: 'Source',
      baseUri: Uri.parse('https://catalog.example'),
      type: CatalogSourceType.opds1,
      isBuiltIn: false,
      isEnabled: true,
      supportsSearch: true,
      supportsNavigation: true,
      supportsAcquisition: true,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
    publication: publication,
    routePublication: publication,
    canonicalBook: CanonicalBook(
      canonicalId: 'book',
      primary: record,
      sources: [record],
      identifiers: const BookIdentifiers(),
    ),
    presentationIdentity: 'source\u0000remote-id',
  );
}

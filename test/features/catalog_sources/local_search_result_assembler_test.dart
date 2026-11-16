import 'package:bibliolife/features/catalog_sources/application/local_search_result_assembler.dart';
import 'package:bibliolife/features/catalog_sources/application/multi_catalog_search_controller.dart';
import 'package:bibliolife/features/catalog_sources/domain/book_source_record.dart';
import 'package:bibliolife/features/catalog_sources/domain/canonical_book.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_search_filters.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final matching = _book(
    id: 'matching',
    title: 'Лісова пісня',
    author: 'Леся Українка',
    isbn: 'ISBN 978-0-306-40615-7',
    language: 'uk',
    publishedDate: '1911',
    subjects: const ['Fantasy'],
  );
  final unrelated = _book(
    id: 'unrelated',
    title: 'Orbital mechanics',
    author: 'Ada Lovelace',
    isbn: '9780131103627',
    language: 'en',
    publishedDate: '2020',
    subjects: const ['Science fiction'],
    fileName: 'лисова-пісня.epub',
  );

  test(
    'title, author, ISBN, and Unicode whitespace match only local fields',
    () {
      expect(
        _localIds(
          query: '  ЛІСОВА\u00a0\u00a0ПІСНЯ  ',
          books: [matching, unrelated],
        ),
        ['matching'],
      );
      expect(_localIds(query: 'українка', books: [matching, unrelated]), [
        'matching',
      ]);
      expect(
        _localIds(query: '978 0306 40615 7', books: [matching, unrelated]),
        ['matching'],
      );
    },
  );

  test('unrelated and filename-only queries never materialize local books', () {
    expect(
      _localIds(query: 'unrelated query', books: [matching, unrelated]),
      isEmpty,
    );
    expect(
      _localIds(query: 'лисова-пісня', books: [matching, unrelated]),
      isEmpty,
    );
  });

  test('empty queries do not dump the library without local narrowing', () {
    for (final filters in [
      CatalogSearchFilters.defaults(),
      CatalogSearchFilters(onlyFreelyDownloadable: true),
      CatalogSearchFilters(selectedSourceIds: const ['builtin-google-books']),
    ]) {
      expect(
        _localIds(query: '', filters: filters, books: [matching, unrelated]),
        isEmpty,
      );
    }
  });

  test('local-compatible filters narrow empty-query local results', () {
    expect(
      _localIds(
        query: '',
        filters: CatalogSearchFilters(author: 'українка'),
        books: [matching, unrelated],
      ),
      ['matching'],
    );
    expect(
      _localIds(
        query: '',
        filters: CatalogSearchFilters(
          includedGenres: const ['Fantasy'],
          languages: const ['uk'],
          editionYearTo: 1911,
        ),
        books: [matching, unrelated],
      ),
      ['matching'],
    );
    expect(
      _localIds(
        query: '',
        filters: CatalogSearchFilters(excludedGenres: const ['Fantasy']),
        books: [matching, unrelated],
      ),
      ['unrelated'],
    );
  });

  test('source filters never assign provenance to local-only books', () {
    expect(
      _localIds(
        query: 'лісова',
        filters: CatalogSearchFilters(
          selectedSourceIds: const ['builtin-open-library'],
        ),
        books: [matching],
      ),
      isEmpty,
    );
  });

  test(
    'a matching local edition merges once and never adds remote records',
    () {
      final remote = _remote(title: matching.title, id: 'remote-matching');
      final merged = _book(
        id: 'merged',
        title: matching.title,
        author: matching.author!,
        isbn: matching.isbn,
        language: matching.language,
        catalogSourceId: 'source',
        remotePublicationId: 'remote-matching',
      );
      final assembled = assembleLocalSearchResults(
        remote: [remote],
        local: [merged, unrelated],
        query: 'лісова',
      );

      expect(assembled, hasLength(1));
      expect(assembled.single.isMerged, isTrue);
      expect(assembled.single.localBook?.id, 'merged');
      expect(assembled.single.remote, same(remote));
    },
  );

  test('one local edition cannot merge into multiple remote cards', () {
    final local = _book(
      id: 'single-local',
      title: matching.title,
      author: matching.author!,
      language: matching.language,
      catalogSourceId: 'source',
      remotePublicationId: 'same-remote',
    );
    final assembled = assembleLocalSearchResults(
      remote: [
        _remote(title: matching.title, id: 'same-remote'),
        _remote(title: matching.title, id: 'same-remote'),
      ],
      local: [local],
      query: 'лісова',
    );

    expect(assembled.where((result) => result.isMerged), hasLength(1));
  });
}

List<String> _localIds({
  required String query,
  required List<LibraryBook> books,
  CatalogSearchFilters? filters,
}) => assembleLocalSearchResults(
  remote: const [],
  local: books,
  query: query,
  filters: filters,
).map((result) => result.localBook!.id).toList();

LibraryBook _book({
  required String id,
  required String title,
  required String author,
  String? isbn,
  String? language,
  String? publishedDate,
  List<String> subjects = const [],
  String? fileName,
  String? catalogSourceId,
  String? remotePublicationId,
}) => LibraryBook(
  id: id,
  title: title,
  sortTitle: title,
  author: author,
  description: null,
  filePath: 'C:/private/$id.epub',
  fileName: fileName ?? '$id.epub',
  fileExtension: 'epub',
  format: BookFormat.epub,
  mediaType: 'application/epub+zip',
  coverPath: null,
  language: language,
  publisher: null,
  publishedDate: publishedDate,
  isbn: isbn,
  pageCount: null,
  fileSizeBytes: 1,
  dateAdded: DateTime.utc(2026),
  lastOpenedAt: null,
  isFavorite: false,
  authors: [author],
  identifiers: [isbn].whereType<String>().toList(),
  subjects: subjects,
  catalogSourceId: catalogSourceId,
  remotePublicationId: remotePublicationId,
);

MultiCatalogSearchResult _remote({required String title, required String id}) {
  final publication = RemoteCatalogPublicationSummary(
    remoteId: id,
    title: title,
    authors: const ['Леся Українка'],
    language: 'uk',
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
      canonicalId: id,
      primary: record,
      sources: [record],
      identifiers: const BookIdentifiers(),
    ),
    presentationIdentity: 'source\u0000$id',
  );
}

import 'package:bibliolife/features/catalog_sources/application/canonical_acquisition_resolver.dart';
import 'package:bibliolife/features/catalog_sources/domain/book_source_record.dart';
import 'package:bibliolife/features/catalog_sources/domain/canonical_acquisition_resolution.dart';
import 'package:bibliolife/features/catalog_sources/domain/canonical_book.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/internet_archive_acquisition.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_acquisition.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_access_hint.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('verified Google direct EPUB beats Gutenberg', () async {
    final book = _book([
      _record(_google, hints: [_googleDirect()]),
      _record(
        _gutenberg,
        acquisitions: [_epub('https://gutenberg.test/images.epub')],
      ),
    ]);

    final result = await _resolver().resolve(book);

    expect(
      result.availability,
      AcquisitionAvailability.multipleDirectEpubCandidates,
    );
    expect(result.selected?.sourceId, _google.id);
    expect(result.downloadPlan?.sourceId, _google.id);
  });

  test('unverified Google and ACS candidates lose to Gutenberg', () async {
    final book = _book([
      _record(
        _google,
        hints: [
          RemoteCatalogAccessHint(
            type: RemoteCatalogAccessType.authenticatedDownload,
            uri: Uri.parse('https://books.test/acs'),
            mediaType: 'application/epub+zip',
            requiresAuthentication: true,
          ),
        ],
      ),
      _record(
        _gutenberg,
        acquisitions: [_epub('https://gutenberg.test/book.epub')],
      ),
    ]);

    final result = await _resolver().resolve(book);

    expect(result.availability, AcquisitionAvailability.directEpubAvailable);
    expect(result.selected?.sourceId, _gutenberg.id);
    expect(
      result.downloadPlan?.remoteMetadata?.description,
      'Canonical summary',
    );
    expect(result.downloadPlan?.remoteMetadata?.sourceId, _gutenberg.id);
  });

  test('Gutenberg beats a public Internet Archive EPUB', () async {
    final book = _book([
      _record(
        _gutenberg,
        acquisitions: [_epub('https://gutenberg.test/book.epub')],
      ),
      _record(_openLibrary, archiveIds: const ['public-book']),
    ]);

    final result = await _resolver(archive: _Archive.direct()).resolve(book);

    expect(result.selected?.sourceId, _gutenberg.id);
  });

  test(
    'public Internet Archive EPUB is selected after unavailable sources',
    () async {
      final book = _book([
        _record(_openLibrary, archiveIds: const ['public-book']),
      ]);

      final result = await _resolver(archive: _Archive.direct()).resolve(book);

      expect(result.availability, AcquisitionAvailability.directEpubAvailable);
      expect(result.selected?.sourceId, _internetArchive.id);
      expect(result.selected?.sourceRemoteId, 'public-book');
      expect(result.downloadPlan?.sourceId, _internetArchive.id);
    },
  );

  test('disabling Internet Archive prevents its acquisition request', () async {
    final archive = _Archive.direct();
    final book = _book([
      _record(_openLibrary, archiveIds: const ['public-book']),
    ]);

    final result = await _resolver(
      archive: archive,
      internetArchiveEnabled: false,
    ).resolve(book);

    expect(result.availability, AcquisitionAvailability.metadataOnly);
    expect(archive.calls, 0);
  });

  test(
    'borrow-only Internet Archive result remains an action, not Download',
    () async {
      final book = _book([
        _record(_openLibrary, archiveIds: const ['borrow-book']),
      ]);

      final result = await _resolver(archive: _Archive.borrow()).resolve(book);

      expect(result.availability, AcquisitionAvailability.borrowingRequired);
      expect(result.downloadPlan, isNull);
    },
  );

  test('a Google details failure continues to Gutenberg', () async {
    final google = _record(_google, details: true, hints: [_googleDirect()]);
    final book = _book([
      google,
      _record(
        _gutenberg,
        acquisitions: [_epub('https://gutenberg.test/book.epub')],
      ),
    ]);

    final result = await _resolver(
      gateway: _Gateway(failGoogle: true),
    ).resolve(book);

    expect(result.selected?.sourceId, _gutenberg.id);
    expect(result.failures.single.sourceId, _google.id);
  });
}

final _google = _source('builtin-google-books', CatalogSourceType.googleBooks);
final _gutenberg = _source(
  'builtin-project-gutenberg',
  CatalogSourceType.opds1,
);
final _openLibrary = _source(
  'builtin-open-library',
  CatalogSourceType.openLibrary,
);
final _internetArchive = _source(
  'builtin-internet-archive',
  CatalogSourceType.internetArchive,
);

CanonicalAcquisitionResolver _resolver({
  _Archive? archive,
  _Gateway? gateway,
  bool internetArchiveEnabled = true,
}) => CanonicalAcquisitionResolver(
  _Repository([
    _google,
    _gutenberg,
    _openLibrary,
    _internetArchive.copyWith(isEnabled: internetArchiveEnabled),
  ]),
  gateway ?? _Gateway(),
  archive ?? _Archive.none(),
);

CanonicalBook _book(List<BookSourceRecord> records) => CanonicalBook(
  canonicalId: 'work:book|author|en',
  primary: records.first,
  sources: records,
  identifiers: const BookIdentifiers(),
  title: 'Book',
  authors: const ['Author'],
  description: 'Canonical summary',
);

BookSourceRecord _record(
  CatalogSource source, {
  List<RemoteCatalogAccessHint> hints = const [],
  List<RemoteAcquisition> acquisitions = const [],
  List<String> archiveIds = const [],
  bool details = false,
}) => BookSourceRecord.fromPublication(
  sourceId: source.id,
  sourcePriority: source.type == CatalogSourceType.googleBooks ? 0 : 10,
  publication: RemoteCatalogPublicationSummary(
    remoteId: '${source.id}-remote',
    title: 'Book',
    authors: const ['Author'],
    accessHints: hints,
    acquisitions: acquisitions,
    detailsLocation: details
        ? RemoteCatalogLocation.parse('https://catalog.test/details')
        : null,
    sourceLists: {'openLibrary.internetArchiveIds': archiveIds},
  ),
);

RemoteCatalogAccessHint _googleDirect() => RemoteCatalogAccessHint(
  type: RemoteCatalogAccessType.directDownload,
  uri: Uri.parse('https://books.test/full.epub'),
  mediaType: 'application/epub+zip',
  isFullBook: true,
  isDrmFree: true,
);

RemoteAcquisition _epub(String url) => RemoteAcquisition(
  relation: 'http://opds-spec.org/acquisition/open-access',
  href: url,
  mediaType: 'application/epub+zip',
);

CatalogSource _source(String id, CatalogSourceType type) => CatalogSource(
  id: id,
  name: id,
  baseUri: Uri.parse('https://catalog.test/'),
  type: type,
  isBuiltIn: true,
  isEnabled: true,
  supportsSearch: true,
  supportsNavigation: true,
  supportsAcquisition: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _Repository implements CatalogSourceRepository {
  _Repository(this.sources);
  final List<CatalogSource> sources;
  @override
  Future<CatalogSource?> getById(String id) async =>
      sources.where((s) => s.id == id).firstOrNull;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Gateway implements RemoteCatalogGateway {
  _Gateway({this.failGoogle = false});
  final bool failGoogle;
  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required location,
  }) async {
    if (failGoogle && source.type == CatalogSourceType.googleBooks) {
      throw StateError('Google unavailable');
    }
    return RemoteCatalogPage(
      sourceId: source.id,
      location: location,
      title: 'details',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Archive implements InternetArchiveAcquisitionResolver {
  _Archive._(this.result);
  final InternetArchiveAcquisitionResult result;
  var calls = 0;
  factory _Archive.none() =>
      _Archive._(const InternetArchiveAcquisitionResult.metadataOnly());
  factory _Archive.direct() => _Archive._(
    InternetArchiveAcquisitionResult.directEpub(
      identifier: 'public-book',
      uri: Uri.parse('https://archive.org/download/public-book/book.epub'),
    ),
  );
  factory _Archive.borrow() => _Archive._(
    const InternetArchiveAcquisitionResult.borrowingRequired(
      identifier: 'borrow-book',
    ),
  );
  @override
  Future<InternetArchiveAcquisitionResult> resolve(
    Iterable<String> identifiers,
  ) async {
    calls++;
    return result;
  }
}

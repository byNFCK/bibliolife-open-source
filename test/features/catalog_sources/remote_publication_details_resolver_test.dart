import 'package:bibliolife/features/catalog_sources/application/remote_publication_details_resolver.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_acquisition.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_access_hint.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'hydrates a lightweight Gutenberg result and keeps search identity',
    () async {
      final gateway = _Gateway(
        RemoteCatalogPage(
          sourceId: 'gutenberg',
          location: _location('/ebooks/1342.opds'),
          title: 'Pride and Prejudice',
          publications: [
            RemoteCatalogPublicationSummary(
              remoteId: 'https://www.gutenberg.org/ebooks/1342',
              title: 'Pride and Prejudice',
              authors: const ['Jane Austen'],
              acquisitions: [_epub()],
            ),
            RemoteCatalogPublicationSummary(
              remoteId: 'urn:gutenberg:1342:images',
              title: 'Pride and Prejudice',
              authors: const ['Jane Austen'],
              acquisitions: [
                RemoteAcquisition(
                  relation: 'http://opds-spec.org/acquisition/open-access',
                  href:
                      'https://www.gutenberg.org/cache/epub/1342/pg1342-images.epub',
                  mediaType: 'application/epub+zip',
                  isSecure: true,
                ),
              ],
            ),
          ],
        ),
      );
      final resolver = RemotePublicationDetailsResolver(
        _Repository(_source(CatalogSourceType.opds1)),
        gateway,
      );
      final searchResult = RemoteCatalogPublicationSummary(
        remoteId: 'search-result-id',
        title: 'Pride and Prejudice',
        authors: const ['Austen, Jane'],
        detailsLocation: _location('/ebooks/1342.opds'),
      );

      final result = await resolver.resolve(
        sourceId: 'gutenberg',
        publication: searchResult,
      );

      expect(result.availability, RemotePublicationAvailability.downloadable);
      expect(result.publication.remoteId, 'search-result-id');
      expect(result.publication.acquisitions, hasLength(2));
      expect(gateway.pageCalls, 1);
    },
  );

  test(
    'Open Library gives a source-specific no-download result without fetch',
    () async {
      final gateway = _Gateway(_page());
      final resolver = RemotePublicationDetailsResolver(
        _Repository(_source(CatalogSourceType.openLibrary)),
        gateway,
      );

      final result = await resolver.resolve(
        sourceId: 'gutenberg',
        publication: RemoteCatalogPublicationSummary(
          remoteId: '/works/OL123W',
          title: 'A work',
          detailsLocation: _location('/works/OL123W'),
        ),
      );

      expect(result.availability, RemotePublicationAvailability.metadataOnly);
      expect(result.unavailableMessage, contains('Open Library'));
      expect(gateway.pageCalls, 0);
    },
  );

  test(
    'Google details hydrate metadata without claiming a direct EPUB',
    () async {
      final gateway = _Gateway(
        RemoteCatalogPage(
          sourceId: 'gutenberg',
          location: _location('/books/v1/volumes/google'),
          title: 'Google details',
          publications: [
            RemoteCatalogPublicationSummary(
              remoteId: 'google',
              title: 'A work',
              accessHints: [
                RemoteCatalogAccessHint(
                  type: RemoteCatalogAccessType.preview,
                  uri: Uri.parse('https://books.example/preview'),
                ),
              ],
            ),
          ],
        ),
      );
      final resolver = RemotePublicationDetailsResolver(
        _Repository(_source(CatalogSourceType.googleBooks)),
        gateway,
      );

      final result = await resolver.resolve(
        sourceId: 'gutenberg',
        publication: RemoteCatalogPublicationSummary(
          remoteId: 'google',
          title: 'A work',
          detailsLocation: _location('/books/v1/volumes/google'),
        ),
      );

      expect(result.availability, RemotePublicationAvailability.metadataOnly);
      expect(result.unavailableMessage, contains('Preview information'));
      expect(gateway.pageCalls, 1);
    },
  );
}

RemoteAcquisition _epub() => RemoteAcquisition(
  relation: 'http://opds-spec.org/acquisition/open-access',
  href: 'https://www.gutenberg.org/cache/epub/1342/pg1342-images.epub',
  mediaType: 'application/epub+zip',
  isSecure: true,
);

RemoteCatalogLocation _location(String path) =>
    RemoteCatalogLocation.parse('https://www.gutenberg.org$path');

RemoteCatalogPage _page() => RemoteCatalogPage(
  sourceId: 'gutenberg',
  location: _location('/root'),
  title: 'Root',
);

CatalogSource _source(CatalogSourceType type) => CatalogSource(
  id: 'gutenberg',
  name: type == CatalogSourceType.openLibrary
      ? 'Open Library'
      : 'Project Gutenberg',
  baseUri: Uri.parse('https://www.gutenberg.org/'),
  type: type,
  isBuiltIn: true,
  isEnabled: true,
  supportsSearch: true,
  supportsNavigation: true,
  supportsAcquisition: type != CatalogSourceType.openLibrary,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _Repository implements CatalogSourceRepository {
  _Repository(this.source);
  final CatalogSource source;

  @override
  Future<CatalogSource?> getById(String id) async => source;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Gateway implements RemoteCatalogGateway {
  _Gateway(this.page);
  final RemoteCatalogPage page;
  var pageCalls = 0;

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) async {
    pageCalls++;
    return page;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

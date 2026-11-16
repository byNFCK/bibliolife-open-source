import 'package:bibliolife/features/catalog_sources/data/source_aware_remote_catalog_transport.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Gutenberg uses weekly ranking only for Home and retains OPDS Search',
    () async {
      final opds = _Transport('opds');
      final weekly = _Transport('weekly');
      final transport = SourceAwareRemoteCatalogTransport(
        opds: opds,
        gutenbergWeekly: weekly,
      );
      final source = _source();

      expect((await transport.loadRoot(source)).title, 'weekly');
      expect(
        (await transport.search(
          source: source,
          capability: const RemoteCatalogSearchCapability.unsupported(),
          query: 'query',
        )).title,
        'opds',
      );
      expect(
        (await transport.loadPage(
          source: source,
          location: RemoteCatalogLocation.parse(
            'https://www.gutenberg.org/ebooks/1.opds',
          ),
        )).title,
        'opds',
      );
    },
  );

  test(
    'Standard Ebooks Home uses its public recent-release Atom feed',
    () async {
      final opds = _Transport('opds');
      final transport = SourceAwareRemoteCatalogTransport(opds: opds);
      final standard = _standardSource();
      final page = await transport.loadRoot(standard);

      expect(
        opds.lastRootSource!.baseUri.toString(),
        'https://standardebooks.org/feeds/atom/new-releases',
      );
      expect(page.homeRanking!.label, 'Recently added');
    },
  );
}

CatalogSource _source() => CatalogSource(
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

CatalogSource _standardSource() => CatalogSource(
  id: 'builtin-standard-ebooks',
  name: 'Standard Ebooks',
  baseUri: Uri.parse('https://standardebooks.org/feeds/opds'),
  type: CatalogSourceType.standardEbooks,
  isBuiltIn: true,
  isEnabled: true,
  supportsSearch: false,
  supportsNavigation: false,
  supportsAcquisition: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _Transport implements RemoteCatalogTransport {
  _Transport(this.name);
  final String name;
  CatalogSource? lastRootSource;

  RemoteCatalogPage _page(CatalogSource source) => RemoteCatalogPage(
    sourceId: source.id,
    location: RemoteCatalogLocation.parse('https://example.test/$name'),
    title: name,
  );

  @override
  Future<RemoteCatalogPage> loadRoot(CatalogSource source) async {
    lastRootSource = source;
    return _page(source);
  }

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) async => _page(source);

  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) async => _page(source);
}

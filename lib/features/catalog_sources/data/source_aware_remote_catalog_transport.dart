import 'package:bibliolife/features/catalog_sources/data/http_opds_remote_catalog_transport.dart';
import 'package:bibliolife/features/catalog_sources/data/open_library_remote_catalog_adapter.dart';
import 'package:bibliolife/features/catalog_sources/data/google_books_remote_catalog_adapter.dart';
import 'package:bibliolife/features/catalog_sources/data/internet_archive_home_discovery_adapter.dart';
import 'package:bibliolife/features/catalog_sources/data/project_gutenberg_weekly_adapter.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_payload_parser_dispatcher.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:bibliolife/features/home/domain/models/home_feed_ranking.dart';

class SourceAwareRemoteCatalogTransport implements RemoteCatalogTransport {
  static final _standardEbooksRecentAtomFeed = Uri.parse(
    'https://standardebooks.org/feeds/atom/new-releases',
  );
  SourceAwareRemoteCatalogTransport({
    HttpCatalogClient? client,
    RemoteCatalogTransport? opds,
    RemoteCatalogTransport? openLibrary,
    RemoteCatalogTransport? googleBooks,
    RemoteCatalogTransport? internetArchive,
    RemoteCatalogTransport? gutenbergWeekly,
    MetadataPayloadParserDispatcher? parserDispatcher,
  }) : _opds =
           opds ??
           HttpOpdsRemoteCatalogTransport(
             client: client,
             parserDispatcher: parserDispatcher,
           ),
       _openLibrary =
           openLibrary ??
           OpenLibraryRemoteCatalogAdapter(
             client: client,
             parserDispatcher: parserDispatcher,
           ),
       _googleBooks =
           googleBooks ??
           GoogleBooksRemoteCatalogAdapter(
             client: client,
             parserDispatcher: parserDispatcher,
           ),
       _internetArchive =
           internetArchive ??
           InternetArchiveHomeDiscoveryAdapter(client: client),
       _gutenbergWeekly =
           gutenbergWeekly ?? ProjectGutenbergWeeklyAdapter(client: client);

  final RemoteCatalogTransport _opds;
  final RemoteCatalogTransport _openLibrary;
  final RemoteCatalogTransport _googleBooks;
  final RemoteCatalogTransport _internetArchive;
  final RemoteCatalogTransport _gutenbergWeekly;

  RemoteCatalogTransport _for(CatalogSource source) => switch (source.type) {
    CatalogSourceType.openLibrary => _openLibrary,
    CatalogSourceType.googleBooks => _googleBooks,
    CatalogSourceType.internetArchive => _internetArchive,
    _ when source.id == 'builtin-project-gutenberg' => _gutenbergWeekly,
    _ => _opds,
  };

  @override
  Future<RemoteCatalogPage> loadRoot(CatalogSource source) async {
    // Standard Ebooks' OPDS catalogue is authenticated. Its public Atom
    // release feed is explicitly available to everyone and is ordered by first
    // release, so it is the honest unauthenticated Home fallback.
    final discoverySource = source.type == CatalogSourceType.standardEbooks
        ? source.copyWith(baseUri: _standardEbooksRecentAtomFeed)
        : source;
    return _withHomeFallback(
      source,
      await _for(discoverySource).loadRoot(discoverySource),
    );
  }

  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) async => _withHomeFallback(
    source,
    await _pageTransport(
      source,
      location,
    ).loadPage(source: source, location: location),
  );

  @override
  Future<RemoteCatalogPage> search({
    required CatalogSource source,
    required RemoteCatalogSearchCapability capability,
    required String query,
  }) => _searchTransport(
    source,
  ).search(source: source, capability: capability, query: query);

  RemoteCatalogTransport _pageTransport(
    CatalogSource source,
    RemoteCatalogLocation location,
  ) =>
      source.id == 'builtin-project-gutenberg' &&
          location.uri.path != '/browse/scores/top-en.html'
      ? _opds
      : _for(source);

  RemoteCatalogTransport _searchTransport(CatalogSource source) =>
      source.id == 'builtin-project-gutenberg' ? _opds : _for(source);

  RemoteCatalogPage _withHomeFallback(
    CatalogSource source,
    RemoteCatalogPage page,
  ) {
    if (source.type != CatalogSourceType.standardEbooks ||
        page.homeRanking != null) {
      return page;
    }
    return RemoteCatalogPage(
      sourceId: page.sourceId,
      location: page.location,
      title: page.title,
      navigation: page.navigation,
      publications: page.publications,
      nextPageLocation: page.nextPageLocation,
      searchCapability: page.searchCapability,
      homeRanking: const HomeFeedRanking.recentlyAdded(),
    );
  }
}

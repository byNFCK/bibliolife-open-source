import 'dart:convert';

import 'package:bibliolife/features/catalog_sources/data/http_opds_remote_catalog_transport.dart';
import 'package:bibliolife/features/catalog_sources/data/project_gutenberg_weekly_adapter.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/home/domain/models/home_feed_ranking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parser accepts only the seven-day ebook section', () {
    final entries = parseGutenbergWeeklyRanking(_fixture);

    expect(entries.map((entry) => entry.ebookId), ['10', '20']);
    expect(entries.map((entry) => entry.rank), [1, 2]);
    expect(entries.map((entry) => entry.downloadCount), [1234, 99]);
  });

  test('parser rejects a malformed weekly section safely', () {
    expect(
      () => parseGutenbergWeeklyRanking('<h2>Top 100 EBooks last 7 days</h2>'),
      throwsFormatException,
    );
  });

  test(
    'weekly page preserves official order and strict public EPUB mapping',
    () async {
      final page = await ProjectGutenbergWeeklyAdapter(
        client: _Client(_fixture),
      ).loadRoot(_source());

      expect(page.homeRanking!.method, HomeFeedRankingMethod.weeklyPopularity);
      expect(page.homeRanking!.isExactWeeklyPopularity, isTrue);
      expect(page.publications.map((book) => book.remoteId), ['10', '20']);
      expect(page.publications.first.homeRanking!.rank, 1);
      expect(page.publications.first.homeRanking!.providerScore, 1234);
      expect(
        page.publications.first.acquisitions.single.href,
        'https://www.gutenberg.org/ebooks/10.epub.images',
      );
    },
  );
}

const _fixture = '''
<h2>Top 100 EBooks yesterday</h2><ol><li><a href="/ebooks/1">Yesterday</a> (9999)</li></ol>
<h2>Top 100 EBooks last 7 days</h2><ol>
  <li><a href="/ebooks/10">Weekly first (1,234)</a></li>
  <li><a href="https://www.gutenberg.org/ebooks/20">Weekly second (99)</a></li>
</ol>
<h2>Top 100 EBooks last 30 days</h2><ol><li><a href="/ebooks/30">Month</a> (888)</li></ol>
<h2>Top 100 Authors last 7 days</h2><ol><li><a href="/browse/authors/1">Author</a> (777)</li></ol>
''';

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

class _Client implements HttpCatalogClient {
  _Client(this.body);
  final String body;

  @override
  Future<HttpCatalogResponse> get({
    required RemoteCatalogLocation location,
    required Map<String, String> headers,
    required Duration timeout,
    required int maximumResponseBytes,
    required int maximumRedirects,
  }) async => HttpCatalogResponse(
    statusCode: 200,
    bodyBytes: utf8.encode(body),
    effectiveLocation: location,
  );
}

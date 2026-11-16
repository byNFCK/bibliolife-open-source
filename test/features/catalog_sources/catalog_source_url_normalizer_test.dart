import 'package:bibliolife/features/catalog_sources/data/catalog_source_url_normalizer.dart';
import 'package:bibliolife/features/catalog_sources/data/drift_catalog_source_repository.dart';
import 'package:bibliolife/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes canonical HTTPS URLs without fragment', () {
    final result = CatalogSourceUrlNormalizer.normalize(
      ' HTTPS://Example.ORG:443/catalog?lang=uk#ignored ',
    );

    expect(result.isValid, isTrue);
    expect(result.uri.toString(), 'https://example.org/catalog?lang=uk');
  });

  test('normalizes an empty path and preserves a meaningful path', () {
    expect(
      CatalogSourceUrlNormalizer.normalize('https://EXAMPLE.org').uri.toString(),
      'https://example.org/',
    );
    expect(
      CatalogSourceUrlNormalizer.normalize('https://example.org/opds/v2').uri.toString(),
      'https://example.org/opds/v2',
    );
  });

  test('rejects unsafe, incomplete and malformed URLs without throwing', () {
    final cases = <String, CatalogSourceUrlFailure>{
      '': CatalogSourceUrlFailure.emptyUrl,
      'https:///catalog': CatalogSourceUrlFailure.missingHost,
      'http://example.org': CatalogSourceUrlFailure.insecureHttp,
      'file:///book.epub': CatalogSourceUrlFailure.unsupportedScheme,
      'content://provider/item': CatalogSourceUrlFailure.unsupportedScheme,
      'javascript:alert(1)': CatalogSourceUrlFailure.unsupportedScheme,
      'data:text/plain,test': CatalogSourceUrlFailure.unsupportedScheme,
      'ftp://example.org': CatalogSourceUrlFailure.unsupportedScheme,
      'https://[bad': CatalogSourceUrlFailure.malformedUrl,
    };
    for (final entry in cases.entries) {
      expect(CatalogSourceUrlNormalizer.normalize(entry.key).failure, entry.value);
    }
    expect(() => CatalogSourceUrlNormalizer.normalize('https://книги.example/каталог'),
        returnsNormally);
  });

  test('canonically equivalent URLs are duplicate repository keys', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final repository = DriftCatalogSourceRepository(database, idGenerator: () => 'id-1');
    addTearDown(database.close);
    final first = CatalogSourceUrlNormalizer.normalize('https://EXAMPLE.org:443#one').uri!;
    final second = CatalogSourceUrlNormalizer.normalize('https://example.org/').uri!;
    await repository.addCustomSource(name: 'One', baseUri: first);
    expect(await repository.normalizedUrlExists(second), isTrue);
  });
}

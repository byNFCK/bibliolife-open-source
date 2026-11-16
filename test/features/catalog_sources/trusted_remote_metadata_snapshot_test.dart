import 'dart:convert';

import 'package:bibliolife/features/catalog_sources/data/trusted_remote_metadata_snapshot.dart';
import 'package:bibliolife/features/metadata/domain/entities/trusted_remote_book_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'trusted remote metadata snapshot round trips every supported field',
    () {
      final metadata = TrustedRemoteBookMetadata(
        sourceId: 'gutenberg',
        publicationId: 'pg-42',
        title: 'Remote title',
        authors: const ['Author', 'Second Author'],
        description: 'Sanitized prose\nbyte-for-byte.',
        publisher: 'Publisher',
        language: 'en',
        publishedDate: '1901-02-03',
        identifiers: const ['urn:isbn:9781234567890', 'pg:42'],
        subjects: const ['Fiction', 'Adventure'],
        rights: 'Public domain',
        publicationLocation: Uri.parse('https://example.test/books/42'),
        coverLocation: Uri.parse('https://example.test/covers/42.jpg'),
        acquisitionLocation: Uri.parse('https://example.test/books/42.epub'),
      );

      final encoded = encodeTrustedRemoteMetadataSnapshot(metadata);
      final restored = decodeTrustedRemoteMetadataSnapshot(encoded)!;

      expect(
        jsonDecode(encoded)['version'],
        trustedRemoteMetadataSnapshotVersion,
      );
      expect(restored.sourceId, metadata.sourceId);
      expect(restored.publicationId, metadata.publicationId);
      expect(restored.title, metadata.title);
      expect(restored.authors, metadata.authors);
      expect(restored.description, metadata.description);
      expect(restored.publisher, metadata.publisher);
      expect(restored.language, metadata.language);
      expect(restored.publishedDate, metadata.publishedDate);
      expect(restored.identifiers, metadata.identifiers);
      expect(restored.subjects, metadata.subjects);
      expect(restored.rights, metadata.rights);
      expect(restored.publicationLocation, metadata.publicationLocation);
      expect(restored.coverLocation, metadata.coverLocation);
      expect(restored.acquisitionLocation, metadata.acquisitionLocation);
    },
  );

  test('decoder tolerates unknown keys and missing optional fields', () {
    final restored = decodeTrustedRemoteMetadataSnapshot(
      jsonEncode({
        'version': 1,
        'sourceId': 'source',
        'publicationId': 'publication',
        'title': 'Title',
        'acquisitionLocation': 'https://example.test/book.epub',
        'futureKey': {'ignored': true},
      }),
    )!;

    expect(restored.description, isNull);
    expect(restored.authors, isEmpty);
    expect(restored.subjects, isEmpty);
  });

  test('invalid and absent legacy snapshots safely restore as absent', () {
    expect(decodeTrustedRemoteMetadataSnapshot(null), isNull);
    expect(decodeTrustedRemoteMetadataSnapshot('{broken'), isNull);
    expect(decodeTrustedRemoteMetadataSnapshot('{"version":1}'), isNull);
    expect(
      decodeTrustedRemoteMetadataSnapshot(
        '{"version":3,"sourceId":"source","publicationId":"publication",'
        '"title":"Title","acquisitionLocation":"https://example.test/a.epub"}',
      ),
      isNull,
    );
    expect(
      decodeTrustedRemoteMetadataSnapshot(
        'x' * (maximumTrustedRemoteMetadataSnapshotBytes + 1),
      ),
      isNull,
    );
  });
}

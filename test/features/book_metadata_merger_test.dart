import 'package:bibliolife/features/metadata/data/services/book_metadata_merger.dart';
import 'package:bibliolife/features/metadata/domain/entities/extracted_book_metadata.dart';
import 'package:bibliolife/features/metadata/domain/entities/trusted_remote_book_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const merger = BookMetadataMerger();

  test(
    'EPUB wins strong fields while remote fills gaps and merges subjects',
    () {
      final result = merger.merge(
        _epub(
          title: 'EPUB title',
          authors: const ['EPUB Author'],
          publisher: 'EPUB Press',
          publishedDate: '2024',
          isbn: '0306406152',
          subjects: const ['Shared', 'EPUB subject'],
        ),
        _remote(
          title: 'Remote title',
          authors: const ['Remote Author'],
          description: 'Remote description',
          publisher: 'Remote Press',
          publishedDate: '2024-03-05',
          identifiers: const ['urn:isbn:978-0-306-40615-7'],
          subjects: const ['Shared', 'Remote subject'],
        ),
      );

      expect(result.metadata.title, 'EPUB title');
      expect(result.metadata.authors, ['EPUB Author']);
      expect(result.metadata.description, 'Remote description');
      expect(result.metadata.publisher, 'EPUB Press');
      expect(result.metadata.isbn, '9780306406157');
      expect(result.metadata.publishedDate, '2024-03-05');
      expect(result.metadata.subjects, [
        'Shared',
        'EPUB subject',
        'Remote subject',
      ]);
      expect(result.origins['description'], 'remote');
      expect(result.origins['subjects'], 'epub+remote');
    },
  );

  test(
    'invalid remote values fabricate nothing and output is deterministic',
    () {
      final remote = _remote(
        title: '',
        language: 'not a language',
        publishedDate: 'yesterday',
        identifiers: const ['gutenberg:2701', 'not-isbn'],
        subjects: const ['One', 'One'],
      );
      final first = merger.merge(_epub(), remote);
      final second = merger.merge(_epub(), remote);

      expect(first.metadata.title, isNull);
      expect(first.metadata.language, isNull);
      expect(first.metadata.publishedDate, isNull);
      expect(first.metadata.isbn, isNull);
      expect(first.metadata.subjects, ['One']);
      expect(second.metadata.subjects, first.metadata.subjects);
      expect(second.origins, first.origins);
    },
  );

  test('cleaned-empty remote description behaves as absent', () {
    final result = merger.merge(
      _epub(),
      _remote(
        title: 'Remote title',
        description:
            '(This is an automatically generated summary.)\nLanguage: English\nRights: Public domain',
      ),
    );

    expect(result.metadata.description, isNull);
    expect(result.origins.containsKey('description'), isFalse);
  });

  test('trusted remote description wins while EPUB fills an absent one', () {
    final trusted = merger.merge(
      _epub(description: 'EPUB description'),
      _remote(title: 'Remote title', description: 'Trusted remote summary'),
    );
    final enriched = merger.merge(
      _epub(description: 'EPUB description'),
      _remote(title: 'Remote title'),
    );

    expect(trusted.metadata.description, 'Trusted remote summary');
    expect(trusted.origins['description'], 'remote');
    expect(enriched.metadata.description, 'EPUB description');
    expect(enriched.origins['description'], 'epub');
  });
}

ExtractedBookMetadata _epub({
  String? title,
  List<String> authors = const [],
  String? publisher,
  String? publishedDate,
  String? isbn,
  List<String> subjects = const [],
  String? description,
}) => ExtractedBookMetadata(
  title: title,
  sortTitle: null,
  authors: authors,
  description: description,
  language: null,
  publisher: publisher,
  publishedDate: publishedDate,
  isbn: isbn,
  coverBytes: null,
  coverExtension: null,
  mediaType: null,
  subjects: subjects,
);

TrustedRemoteBookMetadata _remote({
  required String title,
  List<String> authors = const [],
  String? description,
  String? publisher,
  String? language,
  String? publishedDate,
  List<String> identifiers = const [],
  List<String> subjects = const [],
}) => TrustedRemoteBookMetadata(
  sourceId: 'builtin-project-gutenberg',
  publicationId: 'gutenberg:2701',
  title: title,
  authors: authors,
  description: description,
  publisher: publisher,
  language: language,
  publishedDate: publishedDate,
  identifiers: identifiers,
  subjects: subjects,
  publicationLocation: Uri.parse('https://www.gutenberg.org/ebooks/2701'),
  acquisitionLocation: Uri.parse(
    'https://www.gutenberg.org/ebooks/2701.epub3.images',
  ),
);

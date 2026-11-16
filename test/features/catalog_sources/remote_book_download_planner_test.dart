import 'package:bibliolife/features/catalog_sources/domain/remote_acquisition.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download_plan.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const planner = RemoteBookDownloadPlanner();
  const selector = PreferredEpubAcquisitionSelector();

  group('PreferredEpubAcquisitionSelector', () {
    RemoteAcquisition acquisition(
      String href,
      String mediaType, {
      String? title,
    }) => RemoteAcquisition(
      relation: 'http://opds-spec.org/acquisition/open-access',
      href: href,
      mediaType: mediaType,
      title: title,
    );

    test('prefers illustrated EPUB independently of feed order', () {
      final plain = acquisition(
        'https://www.gutenberg.org/ebooks/1.epub.noimages',
        'application/epub+zip',
        title: 'EPUB no images',
      );
      final illustrated = acquisition(
        'https://www.gutenberg.org/ebooks/1.epub.images',
        'application/epub+zip',
        title: 'EPUB with images',
      );
      final other = [
        acquisition(
          'https://example.test/book.mobi',
          'application/x-mobipocket-ebook',
        ),
        acquisition('https://example.test/book.html', 'text/html'),
        acquisition('https://example.test/book.txt', 'text/plain'),
      ];
      expect(
        selector.select([plain, ...other, illustrated]),
        same(illustrated),
      );
      expect(
        selector.select([illustrated, ...other, plain]),
        same(illustrated),
      );
    });

    test('uses standard EPUB fallback and rejects non EPUB', () {
      final standard = acquisition(
        'https://example.test/book.epub',
        'application/epub+zip',
      );
      expect(
        selector.select([
          acquisition('https://example.test/book.pdf', 'application/pdf'),
          standard,
        ]),
        same(standard),
      );
      expect(
        selector.select([
          acquisition('https://example.test/book.zip', 'application/zip'),
          acquisition('https://example.test/book.txt', 'text/plain'),
        ]),
        isNull,
      );
    });
  });

  test('open-access direct EPUB wins independent of link order', () {
    final generic = _acquisition();
    final open = _acquisition(
      relation: 'http://opds-spec.org/acquisition/open-access',
      href: 'https://catalog.example/open.epub',
    );
    for (final values in [
      [generic, open],
      [open, generic],
    ]) {
      final result = planner.create(
        sourceId: 'source',
        publication: _publication(values),
      );
      expect(result.plan?.acquisitionUri.toString(), endsWith('/open.epub'));
      expect(result.plan?.supported, isTrue);
    }
  });

  test('direct generic EPUB beats indirect EPUB', () {
    final result = planner.create(
      sourceId: 'source',
      publication: _publication([
        _acquisition(
          mediaType: 'application/atom+xml',
          indirect: ['application/epub+zip'],
        ),
        _acquisition(),
      ]),
    );
    expect(result.plan?.isIndirect, isFalse);
  });

  test('indirect EPUB creates local plan recording required resolution', () {
    final result = planner.create(
      sourceId: 'source',
      publication: _publication([
        _acquisition(
          mediaType: 'application/atom+xml',
          indirect: ['application/epub+zip'],
        ),
      ]),
    );
    expect(result.plan?.isIndirect, isTrue);
    expect(
      result.plan?.unsupportedReason,
      RemoteDownloadUnsupportedReason.indirectResolutionRequired,
    );
  });

  test('authentication-required EPUB is excluded', () {
    final result = planner.create(
      sourceId: 'source',
      publication: _publication([_acquisition(requiresAuthentication: true)]),
    );
    expect(
      result.reason,
      RemoteDownloadUnsupportedReason.authenticationRequired,
    );
    expect(result.plan, isNull);
  });

  test('unsupported-only and no-acquisition results are typed', () {
    final unsupported = planner.create(
      sourceId: 'source',
      publication: _publication([_acquisition(mediaType: 'application/pdf')]),
    );
    expect(
      unsupported.reason,
      RemoteDownloadUnsupportedReason.unsupportedMediaType,
    );
    final empty = planner.create(
      sourceId: 'source',
      publication: _publication([]),
    );
    expect(empty.reason, RemoteDownloadUnsupportedReason.noAcquisitions);
  });

  test('plan is immutable metadata and preserves source ID', () {
    final result = planner.create(
      sourceId: 'removed-source',
      publication: _publication([_acquisition()]),
    );
    expect(result.plan?.sourceId, 'removed-source');
    expect(result.plan?.authors, ['Author']);
    expect(result.plan?.suggestedFilename, 'Book.epub');
  });

  test('plan carries the same details cover identity into remote import', () {
    final publication = RemoteCatalogPublicationSummary(
      remoteId: 'book',
      title: 'Book',
      acquisitions: [_acquisition()],
      coverLocation: RemoteCatalogLocation.parse(
        'https://books.google.com/thumbnail',
      ),
      imageCandidates: [
        RemoteCatalogLocation.parse('https://books.google.com/smallThumbnail'),
        RemoteCatalogLocation.parse('https://books.google.com/medium'),
      ],
    );

    final plan = planner
        .create(sourceId: 'builtin-google-books', publication: publication)
        .plan;

    expect(plan?.remoteMetadata?.coverLocation?.path, '/medium');
  });

  test('filename removes traversal separators and invalid characters', () {
    final value = suggestEpubFilename(r' ..\folder/Bad:<Book>?*.. ');
    expect(value, isNot(contains('/')));
    expect(value, isNot(contains(r'\')));
    expect(value, isNot(contains('..')));
    expect(value, endsWith('.epub'));
  });

  test('filename keeps Unicode and handles reserved and empty names', () {
    expect(suggestEpubFilename('Кобзар 日本語'), 'Кобзар 日本語.epub');
    expect(suggestEpubFilename('CON'), '_CON.epub');
    expect(suggestEpubFilename(' ... '), 'remote-book.epub');
  });

  test('filename length is bounded deterministically', () {
    final title = List.filled(200, 'a').join();
    expect(suggestEpubFilename(title).length, 125);
    expect(suggestEpubFilename(title), suggestEpubFilename(title));
  });
}

RemoteCatalogPublicationSummary _publication(
  List<RemoteAcquisition> acquisitions,
) => RemoteCatalogPublicationSummary(
  remoteId: 'book',
  title: 'Book',
  authors: const ['Author'],
  acquisitions: acquisitions,
);

RemoteAcquisition _acquisition({
  String relation = 'http://opds-spec.org/acquisition',
  String href = 'https://catalog.example/book.epub',
  String mediaType = 'application/epub+zip',
  List<String> indirect = const [],
  bool requiresAuthentication = false,
}) => RemoteAcquisition(
  relation: relation,
  href: href,
  mediaType: mediaType,
  indirectMediaTypes: indirect,
  requiresAuthentication: requiresAuthentication,
);

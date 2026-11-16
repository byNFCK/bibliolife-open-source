import 'package:bibliolife/shared/presentation/presenters/book_reading_progress_availability.dart';
import 'package:bibliolife/shared/presentation/widgets/app_context_menu.dart';
import 'package:bibliolife/shared/presentation/presenters/book_list_status_presenter.dart';
import 'package:bibliolife/shared/presentation/widgets/app_book_list_tile.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_access_hint.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_acquisition.dart';
import 'package:bibliolife/features/catalog_sources/presentation/widgets/remote_catalog_book_tile.dart';
import 'package:bibliolife/features/library/application/providers/library_providers.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_book_tile.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_providers.dart';
import 'package:bibliolife/features/reader/domain/models/reading_progress.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 11, 9, 14, 30);
void main() {
  for (final entry in <(String, DateTime?, String)>[
    ('never opened', null, 'Ready to read'),
    ('yesterday', DateTime(2026, 11, 8, 22), 'Opened yesterday'),
    ('two hours', DateTime(2026, 11, 9, 12, 30), 'Opened 2 hours ago'),
    ('three days', DateTime(2026, 11, 6), 'Opened 3 days ago'),
    ('minutes', DateTime(2026, 11, 9, 14, 25), 'Opened 5 minutes ago'),
    ('old date', DateTime(2026, 1, 2), 'Opened 02.01.2026'),
    ('future clock', DateTime(2027), 'Ready to read'),
  ]) {
    test('local ${entry.$1} uses timestamp and shared strings', () {
      expect(
        BookListStatusPresenter.local(_book(opened: entry.$2), now: _now),
        entry.$3,
      );
    });
  }
  final remoteCases = <(String, RemoteCatalogPublicationSummary, String?)>[
    (
      'full direct free',
      _publication(
        hints: [_hint(RemoteCatalogAccessType.directDownload, full: true)],
      ),
      'Read for free',
    ),
    (
      'full external free',
      _publication(
        hints: [_hint(RemoteCatalogAccessType.externalRead, full: true)],
      ),
      'Read for free',
    ),
    (
      'explicit open access',
      _publication(
        acquisitions: [
          RemoteAcquisition(
            relation: 'http://opds-spec.org/acquisition/open-access',
            href: 'https://example.test/book.epub',
            mediaType: 'application/epub+zip',
          ),
        ],
      ),
      'Read for free',
    ),
    (
      'Google free',
      _publication(metadata: {'sale.saleability': 'FREE'}),
      'Read for free',
    ),
    (
      'real retail price',
      _publication(
        metadata: {
          'sale.retailPrice.amount': '12.99',
          'sale.retailPrice.currencyCode': 'USD',
        },
      ),
      'Price: 12.99 USD',
    ),
    (
      'real list price',
      _publication(
        metadata: {
          'sale.listPrice.amount': '250',
          'sale.listPrice.currencyCode': 'UAH',
        },
      ),
      'Price: 250 UAH',
    ),
    (
      'unavailable',
      _publication(
        hints: [
          const RemoteCatalogAccessHint(
            type: RemoteCatalogAccessType.unavailable,
          ),
        ],
      ),
      'Unavailable',
    ),
    (
      'unavailable keeps priority over a historical price',
      _publication(
        metadata: {
          'sale.retailPrice.amount': '12.99',
          'sale.retailPrice.currencyCode': 'USD',
        },
        hints: [
          const RemoteCatalogAccessHint(
            type: RemoteCatalogAccessType.unavailable,
          ),
        ],
      ),
      'Unavailable',
    ),
    ('unknown', _publication(), null),
    (
      'preview',
      _publication(hints: [_hint(RemoteCatalogAccessType.preview)]),
      null,
    ),
    (
      'purchase without price',
      _publication(hints: [_hint(RemoteCatalogAccessType.purchase)]),
      null,
    ),
    (
      'partial external reader',
      _publication(hints: [_hint(RemoteCatalogAccessType.externalRead)]),
      null,
    ),
    (
      'auth needed',
      _publication(
        hints: [
          _hint(RemoteCatalogAccessType.directDownload, full: true, auth: true),
        ],
      ),
      null,
    ),
    (
      'price without currency',
      _publication(metadata: {'sale.retailPrice.amount': '12.99'}),
      null,
    ),
    (
      'invalid price',
      _publication(
        metadata: {
          'sale.retailPrice.amount': 'NaN',
          'sale.retailPrice.currencyCode': 'USD',
        },
      ),
      null,
    ),
    (
      'generic acquisition is not confirmed free',
      _publication(
        acquisitions: [
          RemoteAcquisition(
            relation: 'http://opds-spec.org/acquisition',
            href: 'https://example.test/book.epub',
            mediaType: 'application/epub+zip',
          ),
        ],
      ),
      null,
    ),
    (
      'not-for-sale is not unavailable',
      _publication(
        metadata: {
          'sale.saleability': 'NOT_FOR_SALE',
          'access.viewability': 'NO_PAGES',
        },
      ),
      null,
    ),
  ];
  for (final entry in remoteCases) {
    testWidgets('remote ${entry.$1} renders only authoritative status', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          RemoteCatalogBookTile(
            publication: entry.$2,
            sourceId: 'source',
            onOpen: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final tile = tester.widget<AppBookListTile>(find.byType(AppBookListTile));
      expect(tile.bookStatus, entry.$3);
      if (entry.$3 != null) expect(find.text(entry.$3!), findsOneWidget);
      expect(find.byKey(const Key('book-list-progress')), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });
  }

  testWidgets(
    'real local identity beats price and progress never invents history',
    (tester) async {
      final local = _book();
      await tester.pumpWidget(
        _app(
          RemoteCatalogBookTile(
            sourceId: 'source',
            publication: _publication(
              metadata: {
                'sale.retailPrice.amount': '12.99',
                'sale.retailPrice.currencyCode': 'USD',
              },
            ),
            onOpen: () {},
          ),
          books: [local],
          progress: .53,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ready to read'), findsOneWidget);
      expect(find.text('53%'), findsOneWidget);
      expect(find.textContaining('Price:'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _app(
          RemoteCatalogBookTile(
            sourceId: 'source',
            publication: _publication(
              hints: [
                const RemoteCatalogAccessHint(
                  type: RemoteCatalogAccessType.unavailable,
                ),
              ],
            ),
            onOpen: () {},
          ),
          books: [
            _book(opened: DateTime.now().subtract(const Duration(days: 3))),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Opened 3 days ago'), findsOneWidget);
      expect(find.text('Unavailable'), findsNothing);
    },
  );

  testWidgets(
    'unknown local state and active operations do not fabricate availability',
    (tester) async {
      await tester.pumpWidget(
        _app(
          RemoteCatalogBookTile(
            sourceId: 'source',
            publication: _publication(
              hints: [
                _hint(RemoteCatalogAccessType.directDownload, full: true),
              ],
            ),
            status: const Text('Downloading'),
            onOpen: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Downloading'), findsOneWidget);
      expect(find.text('Read for free'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [allBooksProvider.overrideWithValue(const AsyncLoading())],
          child: MaterialApp(
            home: Scaffold(
              body: RemoteCatalogBookTile(
                sourceId: 'source',
                publication: _publication(
                  hints: [
                    const RemoteCatalogAccessHint(
                      type: RemoteCatalogAccessType.unavailable,
                    ),
                  ],
                ),
                onOpen: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Unavailable'), findsNothing);
    },
  );

  testWidgets(
    'disabled future three-dot action absorbs tap without row navigation',
    (tester) async {
      var opens = 0;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          RemoteCatalogBookTile(
            sourceId: 'source',
            publication: _publication(),
            onOpen: () => opens++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final action = find.byKey(const Key('book-list-actions'));
      expect(tester.getSize(action), const Size(48, 48));
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNull,
      );
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(opens, 0);
      expect(find.byType(PopupMenuItem<String>), findsNothing);
      await tester.tap(find.byKey(const Key('book-list-title')));
      expect(opens, 1);
      semantics.dispose();
    },
  );

  testWidgets(
    'ordinary local row keeps legal Favorite in three-dot menu without Delete',
    (tester) async {
      await tester.pumpWidget(
        _app(
          LibraryBookTile(book: _book(), allowDeleteBook: false, onOpen: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(find.text('Ready to read'), findsOneWidget);
      await tester.tap(find.byType(AppContextMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Add to favorites'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
    },
  );
}

Widget _app(
  Widget child, {
  List<LibraryBook> books = const [],
  double? progress,
}) => ProviderScope(
  overrides: [
    localBookFileAvailableProvider.overrideWith(
      (ref, source) => progress != null,
    ),
    allBooksProvider.overrideWithValue(AsyncData(books)),
    readingProgressProvider.overrideWith(
      (ref, id) => Stream.value(
        progress == null
            ? null
            : ReadingProgress(
                bookId: id,
                locatorJson: null,
                progression: progress,
                currentChapterTitle: null,
                currentPage: null,
                totalPages: null,
                updatedAt: _now,
              ),
      ),
    ),
  ],
  child: MaterialApp(home: Scaffold(body: child)),
);
RemoteCatalogAccessHint _hint(
  RemoteCatalogAccessType type, {
  bool full = false,
  bool auth = false,
}) => RemoteCatalogAccessHint(
  type: type,
  uri: Uri.parse('https://example.test/book'),
  isFullBook: full,
  requiresAuthentication: auth,
);
RemoteCatalogPublicationSummary _publication({
  List<RemoteCatalogAccessHint> hints = const [],
  Map<String, String> metadata = const {},
  List<RemoteAcquisition> acquisitions = const [],
}) => RemoteCatalogPublicationSummary(
  remoteId: 'remote',
  title: 'Book',
  accessHints: hints,
  accessMetadata: metadata,
  acquisitions: acquisitions,
);
LibraryBook _book({DateTime? opened}) => LibraryBook(
  id: 'local',
  title: 'Book',
  sortTitle: null,
  author: 'Author',
  description: null,
  filePath: '/unused.epub',
  fileName: 'unused.epub',
  fileExtension: 'epub',
  format: BookFormat.epub,
  mediaType: null,
  coverPath: null,
  language: null,
  publisher: null,
  publishedDate: null,
  isbn: null,
  pageCount: null,
  fileSizeBytes: 1,
  dateAdded: _now,
  lastOpenedAt: opened,
  isFavorite: false,
  catalogSourceId: 'source',
  remotePublicationId: 'remote',
);

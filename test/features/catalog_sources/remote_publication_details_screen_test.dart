import 'package:archive/archive.dart';
import 'package:bibliolife/core/database/app_database.dart' show AppDatabase;
import 'package:bibliolife/features/catalog_sources/data/drift_remote_download_task_repository.dart';
import 'package:bibliolife/features/catalog_sources/data/foreground_remote_book_downloader.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_temporary_epub_importer.dart';
import 'package:bibliolife/features/import/data/services/book_importer.dart';
import 'package:bibliolife/features/import/data/services/import_file_picker.dart';
import 'package:bibliolife/features/library/data/repositories/drift_library_repository.dart';
import 'package:bibliolife/features/metadata/data/repositories/local_book_metadata_repository.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:bibliolife/core/performance/online_pipeline_performance.dart';
import 'dart:io';
import 'package:bibliolife/features/catalog_sources/data/remote_cache_service.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_image.dart';
import 'package:bibliolife/shared/models/book_cover_reference.dart';
import 'dart:async';

import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_book_download_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_download_queue_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_temporary_epub_import_provider.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_acquisition.dart';
import 'package:bibliolife/features/catalog_sources/domain/book_source_record.dart';
import 'package:bibliolife/features/catalog_sources/domain/canonical_book.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download_plan.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_access_hint.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_download_task.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_download_task_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_temporary_epub_import.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/remote_publication_details_screen.dart';
import 'package:bibliolife/features/library/application/providers/library_repository_provider.dart';
import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';

void main() {
  testWidgets(
    'uses production details layout and trusted metadata immediately',
    (tester) async {
      final downloader = _Downloader();
      await tester.pumpWidget(_app(_metadataRequest(), downloader));
      expect(find.byType(Image), findsNothing);
      expect(find.byKey(const Key('book-details-title')), findsOneWidget);
      expect(find.text('Description'), findsOneWidget);
      expect(find.text('More information'), findsOneWidget);
      expect(find.textContaining('Project Gutenberg'), findsWidgets);
      expect(find.textContaining('<p>'), findsNothing);
      expect(find.text('Download'), findsOneWidget);
      expect(
        find.bySemanticsLabel('No cover available for Book title'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('book-details-cover-placeholder')),
        findsOneWidget,
      );
    },
  );

  testWidgets('availability states fit 320 dp at text scale 2', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(_app(_canonicalPreviewRequest(), _Downloader()));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote details renders the selected remote cover', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _metadataRequest(
          cover: RemoteCatalogLocation.parse(
            'https://covers.example/selected.jpg?size=large',
          ),
        ),
        _Downloader(),
      ),
    );

    final image = tester.widget<BookCoverImage>(find.byType(BookCoverImage));
    expect(
      (image.cover as RemoteBookCover).uri.toString(),
      'https://covers.example/selected.jpg?size=large',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('book-details-cover-placeholder')),
      findsOneWidget,
    );
  });

  testWidgets('Download has no dialog, enqueues once and exposes progress', (
    tester,
  ) async {
    final downloader = _Downloader();
    await tester.pumpWidget(_app(_request(), downloader));
    await tester.ensureVisible(find.text('Download'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('remote-primary-action')));
    await tester.tap(find.byKey(const Key('remote-primary-action')));
    await _pumpQueue(tester);
    expect(find.byType(Dialog), findsNothing);
    expect(downloader.calls, 1);
    expect(find.text('Downloading 10%'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.byKey(const Key('remote-primary-action')));
    await tester.pump();
    expect(downloader.calls, 1);
    // End the controlled download before the fake clock is torn down.
    downloader.fail(RemoteBookDownloadFailure.cancelled);
    await _pumpQueue(tester);
  });

  testWidgets('Download redirects to an already-local exact remote edition', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final downloader = _Downloader();
    await tester.pumpWidget(
      _routedApp(
        downloader,
        _Importer(),
        library: _ExistingLibraryRepository(
          _book(catalogSourceId: 'source', remotePublicationId: 'book'),
        ),
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('remote-primary-action')));
    await tester.tap(find.byKey(const Key('remote-primary-action')));
    await tester.pumpAndSettle();

    expect(find.text('Local details local-book'), findsOneWidget);
    expect(downloader.calls, 0);
  });

  testWidgets('real EPUB becomes readable after details is disposed', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp(
        'details-acquisition-',
      );
      final docs = await Directory.systemTemp.createTemp('details-library-');
      final db = AppDatabase(NativeDatabase.memory());
      final library = DriftLibraryRepository(db.booksDao);
      final tasks = DriftRemoteDownloadTaskRepository(db);
      expect(await tasks.getAll(), isEmpty);
      final bookImporter = BookImporter(
        filePicker: _NoPicker(),
        libraryRepository: library,
        metadataRepository: LocalBookMetadataRepository(),
        documentsDirectory: () async => docs,
        idGenerator: () => 'real-book',
      );
      final importer = ProductionRemoteTemporaryEpubImporter(
        bookImporter,
        library,
        () async => root,
      );
      final downloader = _Downloader();
      final directory = Directory(
        path.join(root.path, 'remote-downloads', 'one'),
      );
      await directory.create(recursive: true);
      final bytes = ZipEncoder().encode(
        Archive()
          ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
          ..addFile(
            ArchiveFile.string(
              'META-INF/container.xml',
              '<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
            ),
          )
          ..addFile(
            ArchiveFile.string(
              'book.opf',
              '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">book-id</dc:identifier><dc:title>Book title</dc:title><dc:creator>Author One</dc:creator><dc:language>en</dc:language></metadata><manifest><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="chapter"/></spine></package>',
            ),
          )
          ..addFile(
            ArchiveFile.string(
              'chapter.xhtml',
              '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Chapter</title></head><body><p>Readable text.</p></body></html>',
            ),
          ),
      );
      final file = File(path.join(directory.path, 'book.epub'));
      await file.writeAsBytes(bytes);
      await tester.pumpWidget(
        _routedApp(
          downloader,
          importer,
          library: library,
          tasks: tasks,
          temporaryDirectory: () async => root,
        ),
      );
      await _start(tester);
      await downloader.started.future.timeout(const Duration(seconds: 5));
      GoRouter.of(
        tester.element(find.byType(RemotePublicationDetailsScreen)),
      ).go(AppRoutes.homePath);
      await tester.pumpAndSettle();
      expect(find.byType(RemotePublicationDetailsScreen), findsNothing);
      final imported = tasks.watchAll().firstWhere(
        (items) =>
            items.any((item) => item.state == RemoteDownloadTaskState.imported),
      );
      downloader.success(
        RemoteBookDownloadResult(
          temporaryFilePath: file.path,
          byteCount: bytes.length,
          declaredMediaType: 'application/epub+zip',
          effectiveUri: Uri.parse('https://catalog.example/book.epub'),
          suggestedFilename: 'book.epub',
          sourceId: 'source',
          publicationRemoteId: 'book',
          checksum: sha256.convert(bytes).toString(),
        ),
      );
      await imported;
      final books = await library.getAllBooks();
      expect(books, hasLength(1));
      expect(await File(books.single.filePath).exists(), isTrue);
      expect(await File(books.single.filePath).length(), greaterThan(0));
      const EpubPackageValidator().validate(File(books.single.filePath));
      expect(books.single.catalogSourceId, 'source');
      expect(books.single.remotePublicationId, 'book');
      expect(downloader.calls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await db.close();
      await root.delete(recursive: true);
      await docs.delete(recursive: true);
    });
  });
  for (final leaveImmediately in [true, false]) {
    testWidgets(
      leaveImmediately
          ? 'leave immediately, then reopen during import'
          : 'leave during transfer, then reopen during import',
      (tester) async {
        final downloader = _Downloader();
        final importer = _Importer();
        await tester.pumpWidget(_routedApp(downloader, importer));
        await tester.ensureVisible(find.text('Download'));
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(RemotePublicationDetailsScreen)),
        );
        final facade = container.read(remoteDownloadQueueFacadeProvider);
        final repository = container.read(remoteDownloadTaskRepositoryProvider);
        final router = GoRouter.of(
          tester.element(find.byType(RemotePublicationDetailsScreen)),
        );
        await tester.tap(find.text('Download'));
        if (!leaveImmediately) await _pumpQueue(tester);
        router.go(AppRoutes.homePath);
        await tester.pumpAndSettle();
        expect(find.byType(RemotePublicationDetailsScreen), findsNothing);
        await _pumpQueue(tester);
        downloader.success();
        await _pumpQueue(tester);
        expect(importer.calls, 1);
        final id = (await repository.getAll()).single.id;
        final first = facade.importCompleted(id);
        final second = facade.importCompleted(id);
        expect(identical(first, second), isTrue);
        router.go('/details');
        await tester.pumpAndSettle();
        expect(importer.calls, 1);
        expect(downloader.calls, 1);
        importer.complete(RemoteTemporaryEpubImported(_book()));
        await tester.pumpAndSettle();
        await Future.wait([first, second]);
        expect(downloader.calls, 1);
      },
    );
  }
  testWidgets('completed download replaces remote details with local details', (
    tester,
  ) async {
    final downloader = _Downloader();
    final importer = _Importer();
    await tester.pumpWidget(_routedApp(downloader, importer));
    await _start(tester);
    downloader.success();
    await _pumpQueue(tester);
    expect(importer.calls, 1);
    expect(find.text('Adding to library'), findsOneWidget);
    importer.complete(RemoteTemporaryEpubImported(_book()));
    await tester.pumpAndSettle();
    expect(find.text('Local details local-book'), findsOneWidget);
    expect(find.byKey(const Key('remote-primary-action')), findsNothing);
    expect(downloader.calls, 1);
  });

  testWidgets(
    'duplicate import replaces remote details and does not redownload',
    (tester) async {
      final downloader = _Downloader();
      final importer = _Importer();
      await tester.pumpWidget(_routedApp(downloader, importer));
      await _start(tester);
      downloader.success();
      await _pumpQueue(tester);
      importer.complete(RemoteTemporaryEpubAlreadyInLibrary(_book()));
      await tester.pumpAndSettle();
      expect(find.text('Local details local-book'), findsOneWidget);
      expect(find.byKey(const Key('remote-primary-action')), findsNothing);
      expect(downloader.calls, 1);
    },
  );

  testWidgets('failed import renders Retry and retries import only', (
    tester,
  ) async {
    final downloader = _Downloader();
    final importer = _Importer();
    await tester.pumpWidget(_app(_request(), downloader, importer));
    await _start(tester);
    downloader.success();
    await _pumpQueue(tester);
    importer.complete(
      const RemoteTemporaryEpubImportFailed(
        RemoteTemporaryEpubImportFailure.persistenceFailure,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('The book could not be saved to the library.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(importer.calls, 2);
    expect(downloader.calls, 1);
  });

  testWidgets('import leaves no remote details action in the route', (
    tester,
  ) async {
    final downloader = _Downloader();
    final importer = _Importer();
    await tester.pumpWidget(_routedApp(downloader, importer));
    await _start(tester);
    downloader.success();
    await _pumpQueue(tester);
    importer.complete(RemoteTemporaryEpubImported(_book()));
    await tester.pumpAndSettle();
    expect(find.text('Local details local-book'), findsOneWidget);
    expect(find.byKey(const Key('remote-primary-action')), findsNothing);
  });

  testWidgets('unsupported and missing request are typed and safe', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _request(
          acquisition: _acquisition(
            mediaType: 'application/atom+xml',
            indirect: const ['application/epub+zip'],
          ),
        ),
        _Downloader(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Download unavailable'), findsOneWidget);
    await tester.pumpWidget(_app(null, _Downloader()));
    expect(
      find.text('Publication metadata is no longer available.'),
      findsOneWidget,
    );
  });

  testWidgets('canonical preview is never presented as Download', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_canonicalPreviewRequest(), _Downloader()));
    await tester.pumpAndSettle();

    expect(find.text('Preview available'), findsOneWidget);
    expect(
      find.textContaining('no verified downloadable EPUB'),
      findsOneWidget,
    );
    expect(find.text('Download'), findsNothing);
  });
}

Future<void> _start(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Download'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Download'));
  await _pumpQueue(tester);
}

Future<void> _pumpQueue(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Widget _app(
  RemotePublicationDetailsRequest? request,
  RemoteBookDownloader downloader, [
  RemoteTemporaryEpubImporter? importer,
  RemoteDownloadTaskRepository? repository,
]) => ProviderScope(
  overrides: [
    remoteCacheServiceProvider.overrideWithValue(_NoCoverCache()),
    remoteDownloadTaskRepositoryProvider.overrideWithValue(
      repository ?? _Repository(),
    ),
    remoteBookDownloaderProvider.overrideWithValue(downloader),
    remoteTemporaryEpubImporterProvider.overrideWithValue(
      importer ?? _Importer(),
    ),
    catalogSourceRepositoryProvider.overrideWithValue(_CatalogSources()),
    remoteCatalogGatewayProvider.overrideWithValue(_CatalogGateway()),
    libraryRepositoryProvider.overrideWithValue(_ExistingLibraryRepository()),
  ],
  child: MaterialApp(home: RemotePublicationDetailsScreen(request: request)),
);

Widget _routedApp(
  RemoteBookDownloader downloader,
  RemoteTemporaryEpubImporter importer, {
  LibraryRepository? library,
  RemoteDownloadTaskRepository? tasks,
  Future<Directory> Function()? temporaryDirectory,
}) {
  final router = GoRouter(
    initialLocation: '/details',
    routes: [
      GoRoute(
        path: '/details',
        builder: (_, _) => RemotePublicationDetailsScreen(request: _request()),
      ),
      GoRoute(
        path: AppRoutes.readerPath,
        name: AppRoutes.readerName,
        builder: (_, state) => Text('Reader ${state.pathParameters['bookId']}'),
      ),
      GoRoute(
        path: AppRoutes.bookDetailsPath,
        name: AppRoutes.bookDetailsName,
        builder: (_, state) =>
            Text('Local details ${state.pathParameters['bookId']}'),
      ),
      GoRoute(
        path: AppRoutes.libraryPath,
        name: AppRoutes.libraryName,
        builder: (_, _) => const Text('Library destination'),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      remoteCacheServiceProvider.overrideWithValue(_NoCoverCache()),
      remoteDownloadTaskRepositoryProvider.overrideWithValue(
        tasks ?? _Repository(),
      ),
      if (temporaryDirectory != null)
        remoteDownloadTemporaryDirectoryProvider.overrideWithValue(
          temporaryDirectory,
        ),
      remoteBookDownloaderProvider.overrideWithValue(downloader),
      remoteTemporaryEpubImporterProvider.overrideWithValue(importer),
      catalogSourceRepositoryProvider.overrideWithValue(_CatalogSources()),
      remoteCatalogGatewayProvider.overrideWithValue(_CatalogGateway()),
      libraryRepositoryProvider.overrideWithValue(
        library ?? _ExistingLibraryRepository(),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

RemotePublicationDetailsRequest _request({RemoteAcquisition? acquisition}) =>
    RemotePublicationDetailsRequest(
      sourceId: 'source',
      sourceName: 'Library',
      publication: RemoteCatalogPublicationSummary(
        remoteId: 'book',
        title: 'Book title',
        authors: const ['Author One', 'Author Two'],
        summary: 'Summary',
        acquisitions: [acquisition ?? _acquisition()],
      ),
    );

RemotePublicationDetailsRequest _metadataRequest({
  RemoteCatalogLocation? cover,
}) => RemotePublicationDetailsRequest(
  sourceId: 'builtin-project-gutenberg',
  sourceName: 'Project Gutenberg',
  publication: RemoteCatalogPublicationSummary(
    remoteId: 'book',
    title: 'Book title',
    authors: const ['Author One'],
    summary: '<p>A trusted <b>description</b>.</p>',
    publisher: 'Project Gutenberg',
    language: 'en',
    publishedDate: '2026-07-25',
    identifiers: const ['urn:isbn:9781234567897'],
    subjects: const ['Fiction'],
    rights: 'Public domain',
    coverLocation: cover,
    acquisitions: [_acquisition()],
  ),
);

RemotePublicationDetailsRequest _canonicalPreviewRequest() {
  final publication = RemoteCatalogPublicationSummary(
    remoteId: 'canonical-preview',
    title: 'Preview title',
    authors: const ['Author'],
    accessHints: [
      RemoteCatalogAccessHint(
        type: RemoteCatalogAccessType.preview,
        uri: Uri.parse('https://catalog.example/preview'),
      ),
    ],
  );
  final record = BookSourceRecord.fromPublication(
    sourceId: 'source',
    sourcePriority: 1,
    publication: publication,
  );
  return RemotePublicationDetailsRequest(
    sourceId: 'source',
    sourceName: 'Library',
    publication: publication,
    canonicalBook: CanonicalBook(
      canonicalId: 'work:preview|author|en',
      primary: record,
      sources: [record],
      identifiers: const BookIdentifiers(),
      title: publication.title,
      authors: publication.authors,
    ),
  );
}

RemoteAcquisition _acquisition({
  String mediaType = 'application/epub+zip',
  List<String> indirect = const [],
}) => RemoteAcquisition(
  relation: 'http://opds-spec.org/acquisition/open-access',
  href: 'https://catalog.example/book.epub',
  mediaType: mediaType,
  indirectMediaTypes: indirect,
);

class _ExistingLibraryRepository implements LibraryRepository {
  _ExistingLibraryRepository([this.book]);

  final LibraryBook? book;

  @override
  Future<LibraryBook?> getBookById(String id) async => book ?? _book();

  @override
  Stream<List<LibraryBook>> watchAllBooks() => Stream.value([book ?? _book()]);

  @override
  Stream<List<LibraryBook>> watchFavoriteBooks() => Stream.value(
    [book ?? _book()].where((item) => item.isFavorite).toList(growable: false),
  );

  @override
  Stream<List<LibraryBook>> watchUnsortedBooks() => watchAllBooks();

  @override
  Future<List<LibraryBook>> getAllBooks() async => [book ?? _book()];

  @override
  Future<LibraryBook?> findBookByFilePath(String filePath) async => null;

  @override
  Future<LibraryBook?> findBookByOriginalFilePath(
    String originalFilePath,
  ) async => null;

  @override
  Future<void> addBook(LibraryBook book) async {}

  @override
  Future<void> updateBook(LibraryBook book) async {}

  @override
  Future<void> deleteBook(String id) async {}

  @override
  Future<void> setFavorite(String id, bool isFavorite) async {}

  @override
  Future<void> markBookOpened(String id, DateTime openedAt) async {}
}

class _Downloader implements RemoteBookDownloader {
  final started = Completer<void>();
  Completer<RemoteBookDownloadResult>? pending;
  int calls = 0;

  @override
  Future<RemoteBookDownloadResult> download({
    required RemoteBookDownloadPlan plan,
    required RemoteBookDownloadCancellation cancellation,
    required void Function(RemoteBookDownloadProgress progress) onProgress,
  }) {
    calls++;
    pending = Completer<RemoteBookDownloadResult>();
    if (!started.isCompleted) started.complete();
    onProgress(
      const RemoteBookDownloadProgress(
        phase: RemoteBookDownloadPhase.downloading,
        bytesReceived: 10,
        totalBytes: 100,
      ),
    );
    cancellation.onCancel(() {
      if (!pending!.isCompleted) {
        pending!.completeError(
          const RemoteBookDownloadException(
            RemoteBookDownloadFailure.cancelled,
          ),
        );
      }
    });
    return pending!.future;
  }

  void success([RemoteBookDownloadResult? result]) {
    pending!.complete(
      result ??
          RemoteBookDownloadResult(
            temporaryFilePath: 'Book title.epub',
            byteCount: 42,
            declaredMediaType: 'application/epub+zip',
            effectiveUri: Uri.parse('https://catalog.example/book.epub'),
            suggestedFilename: 'Book title.epub',
            sourceId: 'source',
            publicationRemoteId: 'book',
            checksum: List.filled(64, 'a').join(),
          ),
    );
  }

  void fail(RemoteBookDownloadFailure failure) {
    pending!.completeError(RemoteBookDownloadException(failure));
  }
}

class _Importer implements RemoteTemporaryEpubImporter {
  Completer<RemoteTemporaryEpubImportResult>? pending;
  int calls = 0;

  @override
  Future<RemoteTemporaryEpubImportResult> import(
    RemoteTemporaryEpubImportInput input,
  ) {
    calls++;
    pending = Completer<RemoteTemporaryEpubImportResult>();
    return pending!.future;
  }

  void complete(RemoteTemporaryEpubImportResult result) {
    pending!.complete(result);
  }
}

LibraryBook _book({String? catalogSourceId, String? remotePublicationId}) =>
    LibraryBook(
      id: 'local-book',
      title: 'Book title',
      sortTitle: null,
      author: 'Author One; Author Two',
      description: null,
      filePath: r'C:\library\local-book.epub',
      originalFilePath: r'C:\temp\Book title.epub',
      fileName: 'local-book.epub',
      fileExtension: 'epub',
      format: BookFormat.epub,
      mediaType: 'application/epub+zip',
      coverPath: null,
      language: null,
      publisher: null,
      publishedDate: null,
      isbn: null,
      pageCount: null,
      fileSizeBytes: 42,
      dateAdded: DateTime(2026, 7, 25),
      lastOpenedAt: null,
      isFavorite: false,
      catalogSourceId: catalogSourceId,
      remotePublicationId: remotePublicationId,
    );

class _Repository implements RemoteDownloadTaskRepository {
  final _items = <String, RemoteDownloadTask>{};
  final _changes = StreamController<List<RemoteDownloadTask>>.broadcast(
    sync: true,
  );

  void _emit() => _changes.add(_items.values.toList());

  @override
  Stream<List<RemoteDownloadTask>> watchAll() async* {
    yield _items.values.toList();
    yield* _changes.stream;
  }

  @override
  Stream<RemoteDownloadTask?> watchById(String id) =>
      watchAll().map((items) => _items[id]);

  @override
  Stream<RemoteDownloadTask?> watchByIdentity(
    String sourceId,
    String publicationId,
    String acquisitionUri,
  ) => watchAll().map(
    (items) => items
        .where(
          (task) =>
              task.sourceId == sourceId &&
              task.publicationRemoteId == publicationId &&
              task.acquisitionUri == acquisitionUri &&
              task.state != RemoteDownloadTaskState.deleted,
        )
        .firstOrNull,
  );

  @override
  Future<List<RemoteDownloadTask>> getAll() async => _items.values.toList();

  @override
  Future<RemoteDownloadTask?> getById(String id) async => _items[id];

  @override
  Future<RemoteDownloadTask?> findActiveByIdentity(
    String sourceId,
    String publicationId,
    String acquisitionUri,
  ) async => _items.values
      .where(
        (task) =>
            task.sourceId == sourceId &&
            task.publicationRemoteId == publicationId &&
            task.acquisitionUri == acquisitionUri &&
            task.state != RemoteDownloadTaskState.deleted,
      )
      .firstOrNull;

  @override
  Future<void> create(RemoteDownloadTask task) async {
    _items[task.id] = task;
    _emit();
  }

  @override
  Future<void> updateProgress(
    String id,
    int attemptId,
    int downloadedBytes,
    int? totalBytes,
  ) async {
    final old = _items[id];
    if (old == null ||
        old.attemptId != attemptId ||
        old.state != RemoteDownloadTaskState.downloading) {
      return;
    }
    _items[id] = _copy(
      old,
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
    );
    _emit();
  }

  @override
  Future<void> transition(
    String id,
    RemoteDownloadTaskState to, {
    int? attemptId,
    String? temporaryFilePath,
    String? sha256,
    String? importedBookId,
    RemoteDownloadFailureCategory? failure,
    int? downloadedBytes,
    int? totalBytes,
  }) async {
    final old = _items[id]!;
    if (attemptId != null && attemptId != old.attemptId) {
      throw StateError('stale');
    }
    _items[id] = _copy(
      old,
      state: to,
      attemptId: to == RemoteDownloadTaskState.queued && old.canRetry
          ? old.attemptId + 1
          : old.attemptId,
      temporaryFilePath: temporaryFilePath,
      sha256: sha256,
      importedBookId: importedBookId,
      failure: failure,
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
    );
    _emit();
  }

  @override
  Future<void> recoverInterrupted() async {}

  RemoteDownloadTask _copy(
    RemoteDownloadTask old, {
    RemoteDownloadTaskState? state,
    int? attemptId,
    String? temporaryFilePath,
    String? sha256,
    String? importedBookId,
    RemoteDownloadFailureCategory? failure,
    int? downloadedBytes,
    int? totalBytes,
  }) => RemoteDownloadTask(
    id: old.id,
    sourceId: old.sourceId,
    publicationRemoteId: old.publicationRemoteId,
    title: old.title,
    authors: old.authors,
    acquisitionUri: old.acquisitionUri,
    suggestedFilename: old.suggestedFilename,
    state: state ?? old.state,
    downloadedBytes: downloadedBytes ?? old.downloadedBytes,
    retryCount: old.retryCount,
    createdAt: old.createdAt,
    updatedAt: DateTime.now(),
    declaredMediaType: old.declaredMediaType,
    expectedFinalMediaType: old.expectedFinalMediaType,
    expectedSizeBytes: old.expectedSizeBytes,
    totalBytes: totalBytes ?? old.totalBytes,
    temporaryFilePath: temporaryFilePath ?? old.temporaryFilePath,
    sha256: sha256 ?? old.sha256,
    failure: failure,
    startedAt: old.startedAt,
    completedAt: old.completedAt,
    importedBookId: importedBookId ?? old.importedBookId,
    attemptId: attemptId ?? old.attemptId,
  );
}

class _CatalogSources implements CatalogSourceRepository {
  @override
  Future<CatalogSource?> getById(String id) async => CatalogSource(
    id: id,
    name: 'Library',
    baseUri: Uri.parse('https://catalog.example/root'),
    type: CatalogSourceType.opds1,
    isBuiltIn: true,
    isEnabled: true,
    supportsSearch: true,
    supportsNavigation: true,
    supportsAcquisition: true,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CatalogGateway implements RemoteCatalogGateway {
  @override
  Future<RemoteCatalogPage> loadPage({
    required CatalogSource source,
    required RemoteCatalogLocation location,
  }) async => RemoteCatalogPage(
    sourceId: source.id,
    location: location,
    title: 'Details',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoCoverCache extends RemoteCacheService {
  @override
  Future<File?> cover(
    Uri uri, {
    OnlineSearchPerformanceSession? performanceSession,
  }) async => null;
}

class _NoPicker implements ImportFilePicker {
  @override
  Future<PickedImportFile?> pickBookFile() async => null;
}

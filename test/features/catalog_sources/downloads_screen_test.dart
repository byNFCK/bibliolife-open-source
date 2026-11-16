import 'dart:async';
import 'dart:io';

import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/core/database/app_database.dart' as db;
import 'package:bibliolife/features/catalog_sources/application/remote_book_download_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_download_queue_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_temporary_epub_import_provider.dart';
import 'package:bibliolife/features/catalog_sources/data/drift_remote_download_task_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download_plan.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_download_task.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_temporary_epub_import.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/downloads_screen.dart';
import 'package:bibliolife/features/library/application/providers/library_repository_provider.dart';
import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';
import 'package:bibliolife/features/metadata/domain/entities/trusted_remote_book_metadata.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  final stateActions = <RemoteDownloadTaskState, List<String>>{
    RemoteDownloadTaskState.queued: [],
    RemoteDownloadTaskState.downloading: ['Cancel download'],
    RemoteDownloadTaskState.pausedByAppRestart: [
      'Retry download',
      'Remove history',
    ],
    RemoteDownloadTaskState.completedTemporary: [
      'Add to library',
      'Delete temporary file',
    ],
    RemoteDownloadTaskState.importing: [],
    RemoteDownloadTaskState.imported: [
      'Open book',
      'Go to Library',
      'Remove history',
    ],
    RemoteDownloadTaskState.duplicate: [
      'Open book',
      'Go to Library',
      'Remove history',
    ],
    RemoteDownloadTaskState.failed: ['Retry download', 'Remove history'],
    RemoteDownloadTaskState.cancelled: ['Retry download', 'Remove history'],
  };

  for (final entry in stateActions.entries) {
    testWidgets('${entry.key.name} renders only its legal actions', (
      tester,
    ) async {
      final harness = (await tester.runAsync(_Harness.create))!;
      addTearDown(harness.dispose);
      await harness.repository.create(
        harness.task(
          entry.key,
          importedBookId:
              entry.key == RemoteDownloadTaskState.imported ||
                  entry.key == RemoteDownloadTaskState.duplicate
              ? 'local-book'
              : null,
        ),
      );
      await tester.pumpWidget(harness.app());
      await _pump(tester);

      expect(find.text('Queue Book'), findsOneWidget);
      for (final action in entry.value) {
        expect(find.byTooltip('$action: Queue Book'), findsOneWidget);
      }
      if (entry.key == RemoteDownloadTaskState.downloading) {
        expect(find.textContaining('25 bytes'), findsOneWidget);
      }
      if (entry.key == RemoteDownloadTaskState.importing) {
        expect(find.byType(IconButton), findsNothing);
      }
      expect(find.textContaining(harness.root.path), findsNothing);
      expect(find.textContaining('StateError'), findsNothing);
    });
  }

  testWidgets('cancel and retry each create one legal transition', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_Harness.create))!;
    addTearDown(harness.dispose);
    await harness.repository.create(
      harness.task(RemoteDownloadTaskState.downloading),
    );
    await tester.pumpWidget(harness.app());
    await _pump(tester);
    await tester.tap(find.byTooltip('Cancel download: Queue Book'));
    await _pump(tester);
    expect(
      (await harness.repository.getById('task'))?.state,
      RemoteDownloadTaskState.cancelled,
    );
    harness.currentTask = await harness.repository.getById('task');
    await tester.pumpWidget(harness.app());
    await _pump(tester);
    await tester.tap(find.byTooltip('Retry download: Queue Book'));
    await _pump(tester);
    expect((await harness.repository.getById('task'))?.attemptId, 1);
    // Complete the controlled operation so Future.timeout releases its timer.
    await tester.runAsync(() async {
      harness.downloader.cancel();
    });
    await _pump(tester);
    expect(
      (await harness.repository.getById('task'))?.state,
      RemoteDownloadTaskState.cancelled,
    );
  });

  testWidgets('controlled temporary EPUB can be deleted', (tester) async {
    final harness = (await tester.runAsync(_Harness.create))!;
    addTearDown(harness.dispose);
    final file = File('${harness.controlled.path}/book.epub')
      ..writeAsBytesSync([1, 2, 3]);
    await harness.repository.create(
      harness.task(
        RemoteDownloadTaskState.completedTemporary,
        temporaryFilePath: file.path,
      ),
    );
    await tester.pumpWidget(harness.app());
    await _pump(tester);
    expect(find.byTooltip('Delete temporary file: Queue Book'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DownloadsScreen)),
    );
    await tester.runAsync(
      () => container
          .read(remoteDownloadQueueFacadeProvider)
          .deleteTemporaryEpub('task'),
    );
    await _pump(tester);
    expect(await tester.runAsync(file.exists), isFalse);
    expect(
      (await harness.repository.getById('task'))?.state,
      RemoteDownloadTaskState.deleted,
    );
  });

  testWidgets('outside temporary EPUB is never deleted', (tester) async {
    final harness = (await tester.runAsync(_Harness.create))!;
    addTearDown(harness.dispose);
    final outside = File('${harness.root.path}/outside.epub')
      ..writeAsBytesSync([1]);
    await harness.repository.create(
      harness.task(
        RemoteDownloadTaskState.completedTemporary,
        temporaryFilePath: outside.path,
      ),
    );
    await tester.pumpWidget(harness.app());
    await _pump(tester);
    expect(find.byTooltip('Delete temporary file: Queue Book'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DownloadsScreen)),
    );
    await tester.runAsync(
      () => container
          .read(remoteDownloadQueueFacadeProvider)
          .deleteTemporaryEpub('task'),
    );
    await _pump(tester);
    expect(await tester.runAsync(outside.exists), isTrue);
    expect(
      (await harness.repository.getById('task'))?.state,
      RemoteDownloadTaskState.completedTemporary,
    );
  });

  testWidgets('import activation is single and persists local book ID', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_Harness.create))!;
    addTearDown(harness.dispose);
    final file = File('${harness.controlled.path}/book.epub')
      ..writeAsBytesSync([1]);
    await harness.repository.create(
      harness.task(
        RemoteDownloadTaskState.completedTemporary,
        temporaryFilePath: file.path,
      ),
    );
    await tester.pumpWidget(harness.app());
    await _pump(tester);
    expect(find.byTooltip('Add to library: Queue Book'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DownloadsScreen)),
    );
    await tester.runAsync(() async {
      final facade = container.read(remoteDownloadQueueFacadeProvider);
      await Future.wait([
        facade.importCompleted('task'),
        facade.importCompleted('task'),
      ]);
    });
    expect(harness.importer.calls, 1);
    expect(
      harness.importer.lastInput?.remoteMetadata?.description,
      'Queue description',
    );
    expect(
      (await harness.repository.getById('task'))?.importedBookId,
      'local-book',
    );
  });

  testWidgets('open, library, and history removal preserve local book', (
    tester,
  ) async {
    final harness = (await tester.runAsync(_Harness.create))!;
    addTearDown(harness.dispose);
    await harness.database.booksDao.insertBook(
      db.BooksCompanion.insert(
        id: 'local-book',
        title: 'Local',
        filePath: r'C:\library\local.epub',
        fileName: 'local.epub',
        fileExtension: 'epub',
        fileSizeBytes: 1,
        dateAdded: DateTime(2026, 7, 25),
      ),
    );
    await harness.repository.create(
      harness.task(
        RemoteDownloadTaskState.imported,
        importedBookId: 'local-book',
      ),
    );
    await tester.pumpWidget(harness.app(routed: true));
    await _pump(tester);
    await tester.tap(find.byTooltip('Open book: Queue Book'));
    await _pump(tester);
    expect(find.text('Reader local-book'), findsOneWidget);
    harness.router.pop();
    await _pump(tester);
    final libraryButton = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.tooltip == 'Go to Library: Queue Book',
      ),
    );
    libraryButton.onPressed!();
    await _pump(tester);
    expect(find.text('Library destination'), findsOneWidget);
    harness.router.go('${AppRoutes.downloadsPath}?history=1');
    await _pump(tester);
    await tester.runAsync(
      () => ProviderScope.containerOf(
        tester.element(find.byType(DownloadsScreen)),
      ).read(remoteDownloadQueueFacadeProvider).removeHistory('task'),
    );
    expect(
      (await harness.database.booksDao.getBookById('local-book')),
      isNotNull,
    );
  });
}

class _Harness {
  _Harness._(
    this.database,
    this.repository,
    this.root,
    this.controlled,
    this.importer,
    this.router,
  );

  final db.AppDatabase database;
  final DriftRemoteDownloadTaskRepository repository;
  final Directory root;
  final Directory controlled;
  final _Importer importer;
  final GoRouter router;
  final downloader = _NeverDownloader();
  RemoteDownloadTask? currentTask;

  static Future<_Harness> create() async {
    final database = db.AppDatabase(NativeDatabase.memory());
    final repository = DriftRemoteDownloadTaskRepository(database);
    final root = await Directory.systemTemp.createTemp('downloads_screen');
    final controlled = Directory('${root.path}/remote-downloads/task')
      ..createSync(recursive: true);
    final importer = _Importer();
    late GoRouter router;
    router = GoRouter(
      initialLocation: AppRoutes.downloadsPath,
      routes: [
        GoRoute(
          path: AppRoutes.downloadsPath,
          builder: (_, _) => const DownloadsScreen(),
        ),
        GoRoute(
          path: AppRoutes.readerPath,
          name: AppRoutes.readerName,
          builder: (_, state) =>
              Text('Reader ${state.pathParameters['bookId']}'),
        ),
        GoRoute(
          path: AppRoutes.libraryPath,
          name: AppRoutes.libraryName,
          builder: (_, _) => const Text('Library destination'),
        ),
      ],
    );
    return _Harness._(database, repository, root, controlled, importer, router);
  }

  Widget app({bool routed = false}) => ProviderScope(
    overrides: [
      remoteDownloadTaskRepositoryProvider.overrideWithValue(repository),
      remoteDownloadTasksProvider.overrideWithValue(AsyncData([currentTask!])),
      remoteBookDownloaderProvider.overrideWithValue(downloader),
      remoteTemporaryEpubImporterProvider.overrideWithValue(importer),
      remoteDownloadTemporaryDirectoryProvider.overrideWithValue(
        () async => root,
      ),
      libraryRepositoryProvider.overrideWithValue(_ExistingLibraryRepository()),
    ],
    child: routed
        ? MaterialApp.router(routerConfig: router)
        : const MaterialApp(home: DownloadsScreen()),
  );

  RemoteDownloadTask task(
    RemoteDownloadTaskState state, {
    String? temporaryFilePath,
    String? importedBookId,
  }) {
    final value = RemoteDownloadTask(
      id: 'task',
      sourceId: 'source',
      publicationRemoteId: 'publication',
      title: 'Queue Book',
      authors: const ['Author'],
      acquisitionUri: 'https://example.test/book.epub',
      suggestedFilename: 'book.epub',
      state: state,
      downloadedBytes: state == RemoteDownloadTaskState.downloading ? 25 : 1,
      totalBytes: state == RemoteDownloadTaskState.downloading ? 100 : 1,
      retryCount: 0,
      createdAt: DateTime(2026, 7, 25),
      updatedAt: DateTime(2026, 7, 25),
      temporaryFilePath: temporaryFilePath,
      sha256: temporaryFilePath == null ? null : 'hash',
      importedBookId: importedBookId,
      failure: state == RemoteDownloadTaskState.failed
          ? RemoteDownloadFailureCategory.transport
          : null,
      remoteMetadata: TrustedRemoteBookMetadata(
        sourceId: 'source',
        publicationId: 'publication',
        title: 'Queue Book',
        authors: const ['Author'],
        description: 'Queue description',
        publisher: 'Publisher',
        language: 'en',
        publishedDate: '1901',
        identifiers: const ['isbn:9781234567890'],
        subjects: const ['Fiction'],
        rights: 'Public domain',
        publicationLocation: Uri.parse('https://example.test/book'),
        acquisitionLocation: Uri.parse('https://example.test/book.epub'),
      ),
    );
    currentTask = value;
    return value;
  }

  Future<void> dispose() async {
    router.dispose();
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

class _ExistingLibraryRepository implements LibraryRepository {
  @override
  Future<LibraryBook?> getBookById(String id) async => _book();

  @override
  Stream<List<LibraryBook>> watchAllBooks() => Stream.value([_book()]);

  @override
  Stream<List<LibraryBook>> watchFavoriteBooks() => watchAllBooks();

  @override
  Stream<List<LibraryBook>> watchUnsortedBooks() => watchAllBooks();

  @override
  Future<List<LibraryBook>> getAllBooks() async => [_book()];

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

class _NeverDownloader implements RemoteBookDownloader {
  final _pending = Completer<RemoteBookDownloadResult>();
  void cancel() => _pending.completeError(
    const RemoteBookDownloadException(RemoteBookDownloadFailure.cancelled),
  );
  @override
  Future<RemoteBookDownloadResult> download({
    required RemoteBookDownloadPlan plan,
    required RemoteBookDownloadCancellation cancellation,
    required void Function(RemoteBookDownloadProgress progress) onProgress,
  }) => _pending.future;
}

class _Importer implements RemoteTemporaryEpubImporter {
  int calls = 0;
  RemoteTemporaryEpubImportInput? lastInput;

  @override
  Future<RemoteTemporaryEpubImportResult> import(
    RemoteTemporaryEpubImportInput input,
  ) async {
    calls++;
    lastInput = input;
    return RemoteTemporaryEpubImported(_book());
  }
}

LibraryBook _book() => LibraryBook(
  id: 'local-book',
  title: 'Queue Book',
  sortTitle: null,
  author: 'Author',
  description: null,
  filePath: r'C:\library\local.epub',
  originalFilePath: null,
  fileName: 'local.epub',
  fileExtension: 'epub',
  format: BookFormat.epub,
  mediaType: 'application/epub+zip',
  coverPath: null,
  language: null,
  publisher: null,
  publishedDate: null,
  isbn: null,
  pageCount: null,
  fileSizeBytes: 1,
  dateAdded: DateTime(2026, 7, 25),
  lastOpenedAt: null,
  isFavorite: false,
);

Future<void> _pump(WidgetTester tester) async {
  for (var frame = 0; frame < 20; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

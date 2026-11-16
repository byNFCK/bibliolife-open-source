import 'package:bibliolife/core/database/app_database.dart' as db;
import 'package:bibliolife/features/catalog_sources/data/drift_remote_download_task_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_download_task.dart';
import 'package:bibliolife/features/metadata/domain/entities/trusted_remote_book_metadata.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late db.AppDatabase database;
  late DriftRemoteDownloadTaskRepository repository;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    repository = DriftRemoteDownloadTaskRepository(database);
  });

  tearDown(() => database.close());

  test('fresh repository is empty and persists every task field', () async {
    expect(await repository.getAll(), isEmpty);
    final task = _task(
      state: RemoteDownloadTaskState.completedTemporary,
      downloadedBytes: 42,
      totalBytes: 42,
      temporaryFilePath: r'C:\temp\book.epub',
      sha256: 'abc',
      failure: RemoteDownloadFailureCategory.storage,
      importedBookId: 'local-book',
      attemptId: 3,
      retryCount: 2,
    );
    await repository.create(task);

    final reloaded = await repository.getById(task.id);
    expect(reloaded?.sourceId, task.sourceId);
    expect(reloaded?.publicationRemoteId, task.publicationRemoteId);
    expect(reloaded?.title, task.title);
    expect(reloaded?.authors, task.authors);
    expect(reloaded?.acquisitionUri, task.acquisitionUri);
    expect(reloaded?.declaredMediaType, task.declaredMediaType);
    expect(reloaded?.expectedFinalMediaType, task.expectedFinalMediaType);
    expect(reloaded?.suggestedFilename, task.suggestedFilename);
    expect(reloaded?.expectedSizeBytes, task.expectedSizeBytes);
    expect(reloaded?.downloadedBytes, 42);
    expect(reloaded?.totalBytes, 42);
    expect(reloaded?.temporaryFilePath, task.temporaryFilePath);
    expect(reloaded?.sha256, 'abc');
    expect(reloaded?.failure, RemoteDownloadFailureCategory.storage);
    expect(reloaded?.importedBookId, 'local-book');
    expect(reloaded?.attemptId, 3);
    expect(reloaded?.retryCount, 2);
    expect(reloaded?.remoteMetadata?.description, 'Exact remote description.');
    expect(reloaded?.remoteMetadata?.publisher, 'Remote Publisher');
    expect(reloaded?.remoteMetadata?.language, 'en');
    expect(reloaded?.remoteMetadata?.publishedDate, '2026-07-25');
    expect(reloaded?.remoteMetadata?.identifiers, const ['isbn:9781234567890']);
    expect(reloaded?.remoteMetadata?.subjects, const ['Fiction', 'Classic']);
    expect(reloaded?.remoteMetadata?.rights, 'Public domain');
    expect(
      reloaded?.remoteMetadata?.publicationLocation.toString(),
      'https://example.test/details',
    );
  });

  test('observes one, all, and stable acquisition identity', () async {
    final first = _task();
    final second = _task(
      id: 'second',
      publicationRemoteId: 'second',
      acquisitionUri: 'https://example.test/second.epub',
      createdAt: DateTime(2026, 7, 25, 12, 1),
    );
    await repository.create(first);
    await repository.create(second);

    expect(
      (await repository.watchAll().first).map((t) => t.id),
      containsAll([first.id, second.id]),
    );
    expect((await repository.watchById(first.id).first)?.title, first.title);
    expect(
      (await repository
              .watchByIdentity(
                first.sourceId,
                first.publicationRemoteId,
                first.acquisitionUri,
              )
              .first)
          ?.id,
      first.id,
    );
    expect(
      (await repository.findActiveByIdentity(
        first.sourceId,
        first.publicationRemoteId,
        first.acquisitionUri,
      ))?.id,
      first.id,
    );
  });

  test(
    'legal transitions persist terminal data and illegal ones fail',
    () async {
      await repository.create(_task());
      await repository.transition('task', RemoteDownloadTaskState.downloading);
      await repository.transition(
        'task',
        RemoteDownloadTaskState.completedTemporary,
        temporaryFilePath: r'C:\temp\book.epub',
        sha256: 'hash',
        downloadedBytes: 50,
        totalBytes: 50,
      );
      final terminal = await repository.getById('task');
      expect(terminal?.state, RemoteDownloadTaskState.completedTemporary);
      expect(terminal?.temporaryFilePath, r'C:\temp\book.epub');
      expect(terminal?.sha256, 'hash');
      expect(terminal?.completedAt, isNotNull);
      expect(
        () =>
            repository.transition('task', RemoteDownloadTaskState.downloading),
        throwsStateError,
      );
    },
  );

  test(
    'progress is monotonic, bounded, and stale attempts are ignored',
    () async {
      await repository.create(_task());
      await repository.transition('task', RemoteDownloadTaskState.downloading);
      await repository.updateProgress('task', 0, 40, 100);
      await repository.updateProgress('task', 0, 20, 100);
      expect((await repository.getById('task'))?.downloadedBytes, 40);
      await repository.updateProgress('task', 0, 140, 100);
      expect((await repository.getById('task'))?.downloadedBytes, 100);
      await repository.updateProgress('task', 99, 10, 100);
      expect((await repository.getById('task'))?.downloadedBytes, 100);
    },
  );

  test('retry creates a clean new attempt', () async {
    await repository.create(
      _task(
        state: RemoteDownloadTaskState.failed,
        downloadedBytes: 80,
        totalBytes: 100,
        temporaryFilePath: r'C:\temp\stale.part',
        sha256: 'stale',
        failure: RemoteDownloadFailureCategory.transport,
      ),
    );
    await repository.transition('task', RemoteDownloadTaskState.queued);
    final retried = await repository.getById('task');
    expect(retried?.attemptId, 1);
    expect(retried?.retryCount, 1);
    expect(retried?.downloadedBytes, 0);
    expect(retried?.totalBytes, isNull);
    expect(retried?.temporaryFilePath, isNull);
    expect(retried?.sha256, isNull);
    expect(retried?.failure, isNull);
    expect(retried?.remoteMetadata?.description, 'Exact remote description.');
  });

  test('deleted history is excluded and never deletes local book', () async {
    await database.booksDao.insertBook(
      db.BooksCompanion.insert(
        id: 'local-book',
        title: 'Local',
        filePath: r'C:\library\local.epub',
        fileName: 'local.epub',
        fileExtension: 'epub',
        fileSizeBytes: 42,
        dateAdded: DateTime(2026, 7, 25),
      ),
    );
    await repository.create(
      _task(
        state: RemoteDownloadTaskState.imported,
        importedBookId: 'local-book',
      ),
    );
    expect((await repository.getById('task'))?.importedBookId, 'local-book');
    await repository.transition('task', RemoteDownloadTaskState.deleted);

    expect(await repository.watchAll().first, isEmpty);
    expect(
      await repository.findActiveByIdentity(
        'source',
        'publication',
        'https://example.test/book.epub',
      ),
      isNull,
    );
    expect((await database.booksDao.getBookById('local-book'))?.title, 'Local');
  });

  test('repository reload preserves task state', () async {
    await repository.create(
      _task(state: RemoteDownloadTaskState.duplicate, importedBookId: 'book'),
    );
    expect(
      (await DriftRemoteDownloadTaskRepository(
        database,
      ).getById('task'))?.state,
      RemoteDownloadTaskState.duplicate,
    );
  });
}

RemoteDownloadTask _task({
  String id = 'task',
  String publicationRemoteId = 'publication',
  String acquisitionUri = 'https://example.test/book.epub',
  RemoteDownloadTaskState state = RemoteDownloadTaskState.queued,
  int downloadedBytes = 0,
  int? totalBytes,
  String? temporaryFilePath,
  String? sha256,
  RemoteDownloadFailureCategory? failure,
  String? importedBookId,
  int attemptId = 0,
  int retryCount = 0,
  DateTime? createdAt,
}) {
  final created = createdAt ?? DateTime(2026, 7, 25, 12);
  return RemoteDownloadTask(
    id: id,
    sourceId: 'source',
    publicationRemoteId: publicationRemoteId,
    title: 'Book',
    authors: const ['Author One', 'Author Two'],
    acquisitionUri: acquisitionUri,
    declaredMediaType: 'application/epub+zip',
    expectedFinalMediaType: 'application/epub+zip',
    suggestedFilename: 'Book.epub',
    expectedSizeBytes: 100,
    state: state,
    downloadedBytes: downloadedBytes,
    totalBytes: totalBytes,
    temporaryFilePath: temporaryFilePath,
    sha256: sha256,
    failure: failure,
    importedBookId: importedBookId,
    retryCount: retryCount,
    attemptId: attemptId,
    createdAt: created,
    updatedAt: created,
    remoteMetadata: TrustedRemoteBookMetadata(
      sourceId: 'source',
      publicationId: publicationRemoteId,
      title: 'Book',
      authors: const ['Author One', 'Author Two'],
      description: 'Exact remote description.',
      publisher: 'Remote Publisher',
      language: 'en',
      publishedDate: '2026-07-25',
      identifiers: const ['isbn:9781234567890'],
      subjects: const ['Fiction', 'Classic'],
      rights: 'Public domain',
      publicationLocation: Uri.parse('https://example.test/details'),
      acquisitionLocation: Uri.parse(acquisitionUri),
    ),
  );
}

import 'dart:async';
import 'dart:io';

import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/core/database/database_provider.dart';
import 'package:drift/native.dart';

import 'package:bibliolife/features/import/application/providers/book_import_provider.dart';
import 'package:bibliolife/features/import/application/providers/import_repository_provider.dart';
import 'package:bibliolife/features/import/data/repositories/local_import_repository.dart';
import 'package:bibliolife/features/import/data/services/book_importer.dart';
import 'package:bibliolife/features/import/data/services/import_file_picker.dart';
import 'package:bibliolife/features/import/domain/entities/import_result.dart';
import 'package:bibliolife/features/import/domain/repositories/import_repository.dart';
import 'package:bibliolife/features/library/application/providers/library_repository_provider.dart';
import 'package:bibliolife/features/library/application/providers/library_section_provider.dart';
import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';
import 'package:bibliolife/features/library/presentation/screens/library_screen.dart';
import 'package:bibliolife/features/metadata/domain/entities/extracted_book_metadata.dart';
import 'package:bibliolife/features/metadata/domain/entities/metadata_extraction_result.dart';
import 'package:bibliolife/features/metadata/domain/repositories/book_metadata_repository.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_providers.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;
  late Directory documentsDirectory;
  late File sourceFile;
  late _FakeLibraryRepository libraryRepository;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'bibliolife_import_test',
    );
    documentsDirectory = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}documents',
    );
    await documentsDirectory.create();
    sourceFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}book.epub',
    );
    await sourceFile.writeAsString('book contents');
    libraryRepository = _FakeLibraryRepository();
  });

  tearDown(() => temporaryDirectory.delete(recursive: true));

  LocalImportRepository repositoryFor(
    PickedImportFile? pickedFile, {
    String? fixedId,
    BookMetadataRepository? metadataRepository,
  }) {
    return LocalImportRepository(
      BookImporter(
        filePicker: _FakeFilePicker(pickedFile),
        libraryRepository: libraryRepository,
        metadataRepository: metadataRepository,
        documentsDirectory: () async => documentsDirectory,
        idGenerator: () => fixedId ?? 'generated-id',
      ),
    );
  }

  test('successfully copies a picked file into managed storage', () async {
    final result = await repositoryFor(
      PickedImportFile(path: sourceFile.path, name: 'My Book.epub'),
    ).importFile();

    expect(result, isA<ImportSuccess>());
    final book = (result as ImportSuccess).book;
    expect(book.fileName, 'My Book.epub');
    expect(book.originalFilePath, sourceFile.path);
    expect(await File(book.filePath).readAsString(), 'book contents');
    expect(
      File(book.filePath).parent.path,
      '${documentsDirectory.path}${Platform.pathSeparator}books',
    );
  });

  test(
    'imports readable EPUB when optional metadata is machine-generated',
    () async {
      const hexTitle = 'f4c3b00c2b9f43e1a129ada1e7a315aa';
      final result = await repositoryFor(
        PickedImportFile(
          path: sourceFile.path,
          name: 'Readable Ukrainian Book.epub',
        ),
        metadataRepository: _FakeMetadataRepository(
          const ExtractedBookMetadata(
            title: hexTitle,
            sortTitle: null,
            authors: ['Unknown'],
            description: null,
            language: null,
            publisher: null,
            publishedDate: null,
            isbn: null,
            coverBytes: null,
            coverExtension: null,
            mediaType: null,
          ),
        ),
      ).importFile();

      expect(result, isA<ImportSuccess>());
      final book = (result as ImportSuccess).book;
      expect(book.title, 'Readable Ukrainian Book');
      expect(book.author, 'Unknown');
      expect(book.description, isNull);
      expect(book.publisher, isNull);
      expect(libraryRepository._books, contains(book));
      expect(await File(book.filePath).exists(), isTrue);
    },
  );

  test(
    'uses the original Cyrillic filename instead of the stored UUID name',
    () async {
      const expectedTitle = '\u0413\u043b\u043e\u0440\u0456\u044f';
      const hexTitle = 'f4c3b00c2b9f43e1a129ada1e7a315aa';
      final result = await repositoryFor(
        PickedImportFile(path: sourceFile.path, name: '$expectedTitle.epub'),
        fixedId: '6d6ff818-6bff-4b33-942e-b86b3f5d1f70',
        metadataRepository: _FakeMetadataRepository(
          const ExtractedBookMetadata(
            title: hexTitle,
            sortTitle: null,
            authors: ['Unknown'],
            description: null,
            language: null,
            publisher: null,
            publishedDate: null,
            isbn: null,
            coverBytes: null,
            coverExtension: null,
            mediaType: null,
          ),
        ),
      ).importFile();

      final book = (result as ImportSuccess).book;
      expect(book.title, expectedTitle);
      expect(book.title, isNot('Unknown title'));
      expect(book.fileName, '$expectedTitle.epub');
      expect(
        book.filePath,
        contains('6d6ff818-6bff-4b33-942e-b86b3f5d1f70.epub'),
      );
    },
  );

  test(
    'reports a duplicate when the original file was already imported',
    () async {
      final repository = repositoryFor(
        PickedImportFile(path: sourceFile.path, name: 'book.epub'),
      );
      await repository.importFile();

      expect(await repository.importFile(), isA<ImportDuplicate>());
    },
  );

  test('reports unsupported extensions without copying a file', () async {
    final result = await repositoryFor(
      PickedImportFile(path: sourceFile.path, name: 'book.mobi'),
    ).importFile();

    expect(result, isA<ImportUnsupportedFormat>());
    expect(
      await Directory(
        '${documentsDirectory.path}${Platform.pathSeparator}books',
      ).exists(),
      isFalse,
    );
  });

  test('accepts supported extensions regardless of letter case', () async {
    for (final name in [
      'book.epub',
      'book.EPUB',
      'book.PdF',
      'book.FB2',
      'book.CBZ',
      'book.TXT',
    ]) {
      expect(BookFormat.fromFileName(name), isNot(BookFormat.unknown));
    }
  });

  test(
    'imports non-EPUB formats when metadata extraction cannot parse them',
    () async {
      for (final metadataResult in const [
        MetadataUnsupportedFormat(),
        MetadataParsingFailed(),
      ]) {
        for (final extension in ['pdf', 'fb2', 'txt', 'cbz']) {
          final suffix = '${metadataResult.runtimeType}-$extension';
          final formatSource = File(
            '${temporaryDirectory.path}${Platform.pathSeparator}book-$suffix',
          );
          await formatSource.writeAsString('book contents');
          final result = await repositoryFor(
            PickedImportFile(path: formatSource.path, name: 'book.$extension'),
            fixedId: 'generated-$suffix',
            metadataRepository: _FixedMetadataResultRepository(metadataResult),
          ).importFile();

          expect(result, isA<ImportSuccess>(), reason: suffix);
          expect(
            (result as ImportSuccess).book.format,
            BookFormat.fromExtension(extension),
          );
        }
      }
    },
  );

  test('rejects an EPUB when metadata extraction fails', () async {
    final result = await repositoryFor(
      PickedImportFile(path: sourceFile.path, name: 'unreadable.epub'),
      metadataRepository: const _FixedMetadataResultRepository(
        MetadataParsingFailed(),
      ),
    ).importFile();

    expect(result, isA<ImportUnreadableFile>());
    expect(libraryRepository._books, isEmpty);
  });

  test('rejects missing, deceptive and unsupported final extensions', () async {
    for (final name in ['book', 'book.', 'book.epub.exe', 'book.CBR']) {
      final result = await repositoryFor(
        PickedImportFile(path: sourceFile.path, name: name),
      ).importFile();
      expect(result, isA<ImportUnsupportedFormat>(), reason: name);
    }
  });

  test('central supported extensions include every import format', () {
    expect(
      BookFormat.supportedExtensions,
      containsAll(['epub', 'pdf', 'fb2', 'cbz', 'txt']),
    );
    expect(BookFormat.supportedExtensions, hasLength(5));
  });

  test('Android picker uses any type while desktop keeps custom filtering', () {
    expect(
      FilePickerImportFilePicker.fileTypeFor(isAndroid: true),
      FileType.any,
    );
    expect(
      FilePickerImportFilePicker.fileTypeFor(isAndroid: false),
      FileType.custom,
    );
    expect(
      FilePickerImportFilePicker.allowedExtensions,
      BookFormat.supportedExtensions,
    );
  });

  test('reports cancellation when the picker returns no file', () async {
    expect(await repositoryFor(null).importFile(), isA<ImportCancelled>());
  });

  test('reports a failed copy when the selected file cannot be read', () async {
    final missingPath =
        '${temporaryDirectory.path}${Platform.pathSeparator}missing.epub';

    expect(
      await repositoryFor(
        PickedImportFile(path: missingPath, name: 'missing.epub'),
      ).importFile(),
      isA<ImportCopyFailed>(),
    );
  });

  test('book import provider exposes loading and result states', () async {
    final completer = Completer<ImportResult>();
    final container = ProviderContainer(
      overrides: [
        importRepositoryProvider.overrideWithValue(
          _ControlledImportRepository(completer),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(bookImportProvider);

    final importing = container.read(bookImportProvider.notifier).importFile();
    expect(container.read(bookImportProvider).isLoading, isTrue);

    completer.complete(const ImportDuplicate());
    await importing;

    expect(container.read(bookImportProvider).value, isA<ImportDuplicate>());
  });

  test('book import provider exposes success and cancelled results', () async {
    final successContainer = ProviderContainer(
      overrides: [
        importRepositoryProvider.overrideWithValue(
          _ImmediateImportRepository(ImportSuccess(_book())),
        ),
      ],
    );
    addTearDown(successContainer.dispose);
    successContainer.read(bookImportProvider);

    await successContainer.read(bookImportProvider.notifier).importFile();
    expect(
      successContainer.read(bookImportProvider).value,
      isA<ImportSuccess>(),
    );

    final cancelledContainer = ProviderContainer(
      overrides: [
        importRepositoryProvider.overrideWithValue(
          _ImmediateImportRepository(const ImportCancelled()),
        ),
      ],
    );
    addTearDown(cancelledContainer.dispose);
    cancelledContainer.read(bookImportProvider);

    await cancelledContainer.read(bookImportProvider.notifier).importFile();
    expect(
      cancelledContainer.read(bookImportProvider).value,
      isA<ImportCancelled>(),
    );
  });

  testWidgets(
    'Library Add action disables while importing and renders the imported book',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final books = _ReactiveLibraryRepository();
      final completer = Completer<ImportResult>();
      final importedBook = _book();
      final importRepository = _ControlledImportRepository(
        completer,
        onSuccess: () => books.publish([importedBook]),
      );
      addTearDown(books.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            libraryRepositoryProvider.overrideWithValue(books),
            defaultLibrarySectionProvider.overrideWith(
              _FixedDefaultLibrarySectionNotifier.new,
            ),
            importRepositoryProvider.overrideWithValue(importRepository),
            readingProgressProvider.overrideWith(
              (ref, bookId) => Stream.value(null),
            ),
          ],
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      books.publish([]);
      await tester.pump();

      await tester.tap(find.byTooltip('Add'));
      await tester.pump();
      final addButton = find.widgetWithIcon(IconButton, Icons.add);
      expect(tester.widget<IconButton>(addButton).onPressed, isNull);

      completer.complete(ImportSuccess(importedBook));
      await tester.pump();
      await tester.pump();

      expect(find.text('No books in your library'), findsNothing);
      expect(find.text('Imported book'), findsOneWidget);
    },
  );
}

class _FixedDefaultLibrarySectionNotifier
    extends DefaultLibrarySectionNotifier {
  @override
  LibrarySection build() => LibrarySection.allBooks;
}

class _FakeFilePicker implements ImportFilePicker {
  const _FakeFilePicker(this.file);

  final PickedImportFile? file;

  @override
  Future<PickedImportFile?> pickBookFile() async => file;
}

class _FakeMetadataRepository implements BookMetadataRepository {
  const _FakeMetadataRepository(this.metadata);

  final ExtractedBookMetadata metadata;

  @override
  Future<MetadataExtractionResult> extractMetadata({
    required String filePath,
    required BookFormat format,
  }) async => MetadataExtractionSuccess(metadata);
}

class _FixedMetadataResultRepository implements BookMetadataRepository {
  const _FixedMetadataResultRepository(this.result);

  final MetadataExtractionResult result;

  @override
  Future<MetadataExtractionResult> extractMetadata({
    required String filePath,
    required BookFormat format,
  }) async => result;
}

class _FakeLibraryRepository implements LibraryRepository {
  final List<LibraryBook> _books = [];

  @override
  Stream<List<LibraryBook>> watchAllBooks() => Stream.value(_books);

  @override
  Stream<List<LibraryBook>> watchFavoriteBooks() => Stream.value(
    _books.where((book) => book.isFavorite).toList(growable: false),
  );

  @override
  Stream<List<LibraryBook>> watchUnsortedBooks() => watchAllBooks();

  @override
  Future<List<LibraryBook>> getAllBooks() async => _books;

  @override
  Future<LibraryBook?> getBookById(String id) async => null;

  @override
  Future<LibraryBook?> findBookByFilePath(String filePath) async => null;

  @override
  Future<LibraryBook?> findBookByOriginalFilePath(
    String originalFilePath,
  ) async {
    for (final book in _books) {
      if (book.originalFilePath == originalFilePath) return book;
    }
    return null;
  }

  @override
  Future<void> addBook(LibraryBook book) async => _books.add(book);

  @override
  Future<void> updateBook(LibraryBook book) async {}

  @override
  Future<void> deleteBook(String id) async {}

  @override
  Future<void> setFavorite(String id, bool isFavorite) async {}

  @override
  Future<void> markBookOpened(String id, DateTime openedAt) async {}
}

class _ReactiveLibraryRepository extends _FakeLibraryRepository {
  final _controller = StreamController<List<LibraryBook>>.broadcast();

  @override
  Stream<List<LibraryBook>> watchAllBooks() => _controller.stream;

  void publish(List<LibraryBook> books) => _controller.add(books);

  void dispose() => _controller.close();
}

class _ControlledImportRepository implements ImportRepository {
  _ControlledImportRepository(this._completer, {this.onSuccess});

  final Completer<ImportResult> _completer;
  final void Function()? onSuccess;

  @override
  Future<ImportResult> importFile() async {
    final result = await _completer.future;
    if (result is ImportSuccess) onSuccess?.call();
    return result;
  }

  @override
  Future<void> removeImportedFile(LibraryBook book) async {}
}

class _ImmediateImportRepository implements ImportRepository {
  const _ImmediateImportRepository(this._result);

  final ImportResult _result;

  @override
  Future<ImportResult> importFile() async => _result;

  @override
  Future<void> removeImportedFile(LibraryBook book) async {}
}

LibraryBook _book() {
  return LibraryBook(
    id: 'imported',
    title: 'Imported book',
    sortTitle: null,
    author: null,
    description: null,
    filePath: '/managed/imported.epub',
    fileName: 'imported.epub',
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
    dateAdded: DateTime(2026, 1, 1),
    lastOpenedAt: null,
    isFavorite: false,
  );
}

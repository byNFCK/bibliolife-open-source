import 'dart:io';
import 'dart:typed_data';

import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/book_details/application/services/book_details_edit_service.dart';
import 'package:bibliolife/features/metadata/data/services/cover_storage_service.dart';
import 'package:bibliolife/shared/models/book_cover_provenance.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:bibliolife/core/database/mappers/book_mapper.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late Directory root;
  late BookDetailsEditService service;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    root = await Directory.systemTemp.createTemp('book-edit-');
    service = BookDetailsEditService(
      booksDao: database.booksDao,
      coverStorage: CoverStorageService(
        documentsDirectory: () async => root,
        imageValidator: const _AcceptImageValidator(),
      ),
      idGenerator: () => 'unique-cover',
    );
  });

  tearDown(() async {
    await database.close();
    await root.delete(recursive: true);
  });

  test(
    'atomically saves requested fields and preserves the source book',
    () async {
      final oldCover = File('${root.path}/old-custom-cover.jpg');
      await oldCover.writeAsBytes([9, 9]);
      final original = _book(
        author: 'Old Author',
        authors: const ['One Author', 'Two Author'],
        coverPath: oldCover.path,
        coverProvenance: BookCoverProvenance.embedded,
      );
      await database.booksDao.insertBook(original.toBooksCompanion());
      final sourceDirectory = Directory('${root.path}/user-images')
        ..createSync();
      final sourceImage = File('${sourceDirectory.path}/original.png');
      await sourceImage.writeAsBytes([1, 2, 3]);

      await service.save(
        bookId: original.id,
        title: '  New title  ',
        author: '  New author  ',
        replacementCoverBytes: await sourceImage.readAsBytes(),
        replacementCoverExtension: 'png',
      );

      final saved = (await database.booksDao.getBookById(original.id))!;
      expect(saved.title, 'New title');
      expect(saved.sortTitle, 'New title');
      expect(saved.author, 'New author');
      expect(saved.authorsJson, '["New author"]');
      expect(saved.coverProvenance, BookCoverProvenance.manual.name);
      expect(saved.coverPath, isNot(original.coverPath));
      expect(await File(saved.coverPath!).readAsBytes(), [1, 2, 3]);
      expect(await sourceImage.exists(), isTrue);
      expect(await sourceImage.readAsBytes(), [1, 2, 3]);
      expect(saved.filePath, original.filePath);
      expect(saved.originalFilePath, original.originalFilePath);
      expect(saved.fileName, original.fileName);
      expect(saved.fileExtension, original.fileExtension);
      expect(saved.fileSizeBytes, original.fileSizeBytes);
      expect(saved.dateAdded, original.dateAdded);
      expect(saved.lastOpenedAt, original.lastOpenedAt);
      expect(saved.isFavorite, original.isFavorite);
      expect(saved.catalogSourceId, original.catalogSourceId);
      expect(saved.remotePublicationId, original.remotePublicationId);
      expect(saved.tocJson, original.tocJson);
      expect(await oldCover.exists(), isTrue);
    },
  );

  test('cover-only save preserves existing author representations', () async {
    final original = _book(
      authors: const ['First Author', 'Second Author'],
      coverPath: '/cache/embedded.jpg',
      coverProvenance: BookCoverProvenance.embedded,
    );
    await database.booksDao.insertBook(original.toBooksCompanion());

    await service.save(
      bookId: original.id,
      title: original.title,
      author: original.author,
      updateTitle: false,
      updateAuthor: false,
      replacementCoverBytes: Uint8List.fromList([7, 8]),
      replacementCoverExtension: 'jpg',
    );

    final saved = (await database.booksDao.getBookById(original.id))!;
    expect(saved.title, original.title);
    expect(saved.sortTitle, original.sortTitle);
    expect(saved.author, original.author);
    expect(saved.authorsJson, '["First Author","Second Author"]');
    expect(saved.coverProvenance, BookCoverProvenance.manual.name);
  });

  test('remove clears only a manual cover override', () async {
    final manual = _book(
      id: 'manual',
      coverPath: '/cache/custom.jpg',
      coverProvenance: BookCoverProvenance.manual,
    );
    final embedded = _book(
      id: 'embedded',
      coverPath: '/cache/embedded.jpg',
      coverProvenance: BookCoverProvenance.embedded,
    );
    await database.booksDao.insertBook(manual.toBooksCompanion());
    await database.booksDao.insertBook(embedded.toBooksCompanion());

    await service.save(
      bookId: manual.id,
      title: manual.title,
      author: manual.author,
      updateTitle: false,
      updateAuthor: false,
      removeManualCover: true,
    );
    await service.save(
      bookId: embedded.id,
      title: embedded.title,
      author: embedded.author,
      updateTitle: false,
      updateAuthor: false,
      removeManualCover: true,
    );

    final removed = (await database.booksDao.getBookById(manual.id))!;
    final retained = (await database.booksDao.getBookById(embedded.id))!;
    expect(removed.coverPath, isNull);
    expect(removed.coverProvenance, BookCoverProvenance.none.name);
    expect(retained.coverPath, embedded.coverPath);
    expect(retained.coverProvenance, BookCoverProvenance.embedded.name);
  });

  test(
    'restored cover cleanup retains a path still referenced by another book',
    () async {
      final directory = Directory('${root.path}/covers')..createSync();
      final oldCover = File('${directory.path}/book-edit-manual-shared.jpg')
        ..writeAsBytesSync([4, 5, 6]);
      final original = _book(
        coverPath: oldCover.path,
        coverProvenance: BookCoverProvenance.manual,
      );
      final otherBook = _book(
        id: 'other-book',
        coverPath: oldCover.path,
        coverProvenance: BookCoverProvenance.manual,
      );
      await database.booksDao.insertBook(original.toBooksCompanion());
      await database.booksDao.insertBook(otherBook.toBooksCompanion());

      await service.save(
        bookId: original.id,
        title: 'Restored title',
        author: original.author,
        updateTitle: true,
        updateAuthor: false,
        replacementCoverBytes: Uint8List.fromList([7, 8]),
        replacementCoverExtension: 'png',
        replacementCoverProvenance: BookCoverProvenance.embedded,
        cleanupReplacedManualCover: true,
      );

      final restored = (await database.booksDao.getBookById(original.id))!;
      final other = (await database.booksDao.getBookById(otherBook.id))!;
      expect(restored.coverPath, isNot(oldCover.path));
      expect(restored.coverProvenance, BookCoverProvenance.embedded.name);
      expect(other.coverPath, oldCover.path);
      expect(await oldCover.readAsBytes(), [4, 5, 6]);
    },
  );

  test(
    'restore without source cover clears and cleans an owned manual cover',
    () async {
      final directory = Directory('${root.path}/covers')..createSync();
      final oldCover = File('${directory.path}/book-edit-manual-old.jpg')
        ..writeAsBytesSync([4, 5, 6]);
      final original = _book(
        coverPath: oldCover.path,
        coverProvenance: BookCoverProvenance.manual,
      );
      await database.booksDao.insertBook(original.toBooksCompanion());

      await service.save(
        bookId: original.id,
        title: 'Restored title',
        author: null,
        updateTitle: true,
        updateAuthor: true,
        clearCover: true,
        cleanupReplacedManualCover: true,
      );

      final saved = (await database.booksDao.getBookById(original.id))!;
      expect(saved.title, 'Restored title');
      expect(saved.author, isNull);
      expect(saved.coverPath, isNull);
      expect(saved.coverProvenance, BookCoverProvenance.none.name);
      expect(await oldCover.exists(), isFalse);
    },
  );

  test('invalid cover does not modify the book or create files', () async {
    final original = _book();
    await database.booksDao.insertBook(original.toBooksCompanion());

    await expectLater(
      service.save(
        bookId: original.id,
        title: 'Changed title',
        author: original.author,
        replacementCoverBytes: Uint8List(0),
        replacementCoverExtension: 'png',
      ),
      throwsA(isA<InvalidBookCover>()),
    );

    final saved = (await database.booksDao.getBookById(original.id))!;
    expect(saved.title, original.title);
    expect(saved.coverPath, original.coverPath);
    expect(await Directory('${root.path}/covers').exists(), isFalse);
  });

  test('empty title is rejected and blank author becomes nullable', () async {
    final original = _book();
    await database.booksDao.insertBook(original.toBooksCompanion());

    await expectLater(
      service.save(
        bookId: original.id,
        title: '  \n ',
        author: original.author,
      ),
      throwsA(isA<InvalidBookTitle>()),
    );
    await service.save(
      bookId: original.id,
      title: original.title,
      author: '  ',
      updateTitle: false,
      updateAuthor: true,
    );

    final saved = (await database.booksDao.getBookById(original.id))!;
    expect(saved.title, original.title);
    expect(saved.author, isNull);
    expect(saved.authorsJson, isNull);
  });

  test(
    'database failure removes only the new copy and preserves old cover',
    () async {
      final oldCover = File('${root.path}/old-custom-cover.png');
      await oldCover.writeAsBytes([4, 5, 6]);
      final original = _book(
        coverPath: oldCover.path,
        coverProvenance: BookCoverProvenance.manual,
      );
      await database.booksDao.insertBook(original.toBooksCompanion());
      await database.customStatement(
        "CREATE TRIGGER reject_book_edit BEFORE UPDATE ON books "
        "BEGIN SELECT RAISE(ABORT, 'blocked edit'); END",
      );

      await expectLater(
        service.save(
          bookId: original.id,
          title: 'Should roll back',
          author: 'Should roll back',
          replacementCoverBytes: Uint8List.fromList([7, 8, 9]),
          replacementCoverExtension: 'jpg',
        ),
        throwsA(anything),
      );

      final saved = (await database.booksDao.getBookById(original.id))!;
      expect(saved.title, original.title);
      expect(saved.author, original.author);
      expect(saved.coverPath, oldCover.path);
      expect(saved.coverProvenance, BookCoverProvenance.manual.name);
      expect(await oldCover.readAsBytes(), [4, 5, 6]);
      final storedFiles = await Directory(
        '${root.path}/covers',
      ).list(recursive: true).where((entity) => entity is File).toList();
      expect(storedFiles, isEmpty);
    },
  );
}

LibraryBook _book({
  String id = 'book-edit',
  String title = 'Original title',
  String? author = 'Original author',
  List<String> authors = const [],
  String? coverPath,
  BookCoverProvenance coverProvenance = BookCoverProvenance.none,
}) => LibraryBook(
  id: id,
  title: title,
  sortTitle: null,
  author: author,
  description: 'Preserve this description',
  filePath: '/app/books/$id.epub',
  originalFilePath: '/user/books/$id.epub',
  fileName: '$id.epub',
  fileExtension: 'epub',
  format: BookFormat.epub,
  mediaType: 'application/epub+zip',
  coverPath: coverPath,
  coverProvenance: coverProvenance,
  language: 'en',
  publisher: 'Publisher',
  publishedDate: '2020',
  isbn: '9780000000000',
  pageCount: 5,
  fileSizeBytes: 1234,
  dateAdded: DateTime(2026, 1, 1),
  lastOpenedAt: DateTime(2026, 2, 1),
  isFavorite: true,
  authors: authors,
  catalogSourceId: 'source-id',
  remotePublicationId: 'publication-id',
  tocJson: '{"toc":true}',
);

class _AcceptImageValidator implements CoverImageValidator {
  const _AcceptImageValidator();

  @override
  Future<bool> isDecodable(Uint8List bytes) async => bytes.isNotEmpty;
}

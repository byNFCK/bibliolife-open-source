import 'package:bibliolife/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.customStatement('PRAGMA foreign_keys = ON');
    await database.booksDao.insertBook(BooksCompanion.insert(
      id: 'book-1', title: 'Book', filePath: '/books/book.epub',
      fileName: 'book.epub', fileExtension: 'epub', fileSizeBytes: 1,
      dateAdded: DateTime(2026),
    ));
  });
  tearDown(() => database.close());

  ReaderAnnotationsCompanion annotation({required String id, required String key}) =>
      ReaderAnnotationsCompanion.insert(
        id: id, bookId: 'book-1', locatorJson: '{"href":"chapter.xhtml"}',
        locationKey: key, selectedText: 'Selected text', href: 'chapter.xhtml',
        createdAt: DateTime(2026), updatedAt: DateTime(2026),
      );

  test('stores defaults, nullable fields, and exact locator data', () async {
    await database.into(database.readerAnnotations).insert(annotation(id: 'a1', key: 'key-1'));
    final row = await (database.select(database.readerAnnotations)..where((t) => t.id.equals('a1'))).getSingle();
    expect(row.locatorJson, '{"href":"chapter.xhtml"}');
    expect(row.style, 'highlight'); expect(row.color, 'yellow');
    expect(row.textBefore, isNull); expect(row.textAfter, isNull); expect(row.note, isNull);
    expect(row.progression, isNull); expect(row.totalProgression, isNull);
  });

  test('enforces logical uniqueness and cascades with book deletion', () async {
    await database.into(database.readerAnnotations).insert(annotation(id: 'a1', key: 'key-1'));
    await expectLater(database.into(database.readerAnnotations).insert(annotation(id: 'a2', key: 'key-1')), throwsA(isA<Exception>()));
    await database.booksDao.deleteBookById('book-1');
    expect(await database.select(database.readerAnnotations).get(), isEmpty);
  });
}

import 'package:bibliolife/core/database/app_database.dart' as db;
import 'package:bibliolife/features/reader/data/mappers/reader_annotation_mapper.dart';
import 'package:bibliolife/features/reader/domain/models/reader_annotation.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final annotation = ReaderAnnotation(id: 'a', bookId: 'b', locatorJson: '{"x":"!?"}', locationKey: 'key', selectedText: 'Привіт 😀', note: '', style: ReaderAnnotationStyle.underline, color: ReaderAnnotationColor.purple, href: 'c', progression: 0, totalProgression: .5, createdAt: DateTime(2026), updatedAt: DateTime(2026, 1, 2));
  test('companion preserves domain fields', () {
    final row = annotation.toReaderAnnotationsCompanion();
    expect(row.style.value, 'underline'); expect(row.color.value, 'purple');
    expect(row.note.value, ''); expect(row.locatorJson.value, annotation.locatorJson);
  });
  test('database round trip preserves annotation', () async {
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.booksDao.insertBook(db.BooksCompanion.insert(id: 'b', title: 'B', filePath: '/b', fileName: 'b', fileExtension: 'epub', fileSizeBytes: 1, dateAdded: DateTime(2026)));
    await database.into(database.readerAnnotations).insert(annotation.toReaderAnnotationsCompanion());
    final row = await database.select(database.readerAnnotations).getSingle();
    expect(row.toDomain(), annotation);
  });
}

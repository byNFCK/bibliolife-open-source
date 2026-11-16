import 'package:bibliolife/features/reader/domain/models/reader_annotation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final value = ReaderAnnotation(
    id: 'id', bookId: 'book', locatorJson: '{"href":"c"}', locationKey: 'key',
    selectedText: 'Selected', textBefore: 'Before', textAfter: 'After', note: 'Note',
    style: ReaderAnnotationStyle.underline, color: ReaderAnnotationColor.purple,
    href: 'c.xhtml', progression: .25, totalProgression: .5,
    createdAt: DateTime(2026), updatedAt: DateTime(2026, 1, 2),
  );

  test('style storage contract is exact and safe', () {
    expect(ReaderAnnotationStyle.highlight.storageValue, 'highlight');
    expect(ReaderAnnotationStyle.underline.storageValue, 'underline');
    expect(ReaderAnnotationStyle.tryParse('highlight'), ReaderAnnotationStyle.highlight);
    expect(ReaderAnnotationStyle.tryParse('Highlight'), isNull);
    expect(ReaderAnnotationStyle.tryParse('unknown'), isNull);
  });
  test('color storage contract is exact and safe', () {
    for (final color in ReaderAnnotationColor.values) {
      expect(ReaderAnnotationColor.tryParse(color.storageValue), color);
    }
    expect(ReaderAnnotationColor.tryParse('Yellow'), isNull);
    expect(ReaderAnnotationColor.tryParse('unknown'), isNull);
  });
  test('model preserves values and has value equality', () {
    final same = ReaderAnnotation(
      id: 'id', bookId: 'book', locatorJson: '{"href":"c"}', locationKey: 'key',
      selectedText: 'Selected', textBefore: 'Before', textAfter: 'After', note: 'Note',
      style: ReaderAnnotationStyle.underline, color: ReaderAnnotationColor.purple,
      href: 'c.xhtml', progression: .25, totalProgression: .5,
      createdAt: DateTime(2026), updatedAt: DateTime(2026, 1, 2),
    );
    expect(value.locatorJson, '{"href":"c"}'); expect(value.locationKey, 'key');
    expect(value.selectedText, 'Selected'); expect(value, same); expect(value.hashCode, same.hashCode);
    expect(value, isNot(ReaderAnnotation(id: 'other', bookId: 'book', locatorJson: value.locatorJson, locationKey: value.locationKey, selectedText: value.selectedText, href: value.href, createdAt: value.createdAt, updatedAt: value.updatedAt)));
  });
  test('null and empty note remain distinct', () {
    final nullNote = ReaderAnnotation(id: 'id', bookId: 'book', locatorJson: '{}', locationKey: 'key', selectedText: 'x', href: 'c', createdAt: DateTime(2026), updatedAt: DateTime(2026));
    final emptyNote = ReaderAnnotation(id: 'id', bookId: 'book', locatorJson: '{}', locationKey: 'key', selectedText: 'x', note: '', href: 'c', createdAt: DateTime(2026), updatedAt: DateTime(2026));
    expect(nullNote.note, isNull); expect(nullNote, isNot(emptyNote));
  });
}

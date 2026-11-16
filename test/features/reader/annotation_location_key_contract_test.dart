import 'package:bibliolife/features/reader/domain/value_objects/annotation_location_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v2 ignores progression when stable fragments identify a range', () {
    final first = AnnotationLocationKey.build(
      bookId: 'book', href: 'chapter.xhtml', fragments: ['#p4', ':~:text=a'],
      progression: .25, selectedText: 'Selected text',
    );
    final repeated = AnnotationLocationKey.build(
      bookId: 'book', href: 'chapter.xhtml', fragments: ['#p4', ':~:text=a'],
      progression: .250001, selectedText: 'Selected text',
    );
    expect(repeated, first);
    expect(first, matches(RegExp(r'^v2:[0-9a-f]{64}$')));
  });

  test('v2 distinguishes ranges and uses progression without fragments', () {
    final rangeA = AnnotationLocationKey.build(
      bookId: 'book', href: 'chapter.xhtml', fragments: ['#p4'],
      progression: .25, selectedText: 'Same text',
    );
    final rangeB = AnnotationLocationKey.build(
      bookId: 'book', href: 'chapter.xhtml', fragments: ['#p5'],
      progression: .25, selectedText: 'Same text',
    );
    final fallbackA = AnnotationLocationKey.build(
      bookId: 'book', href: 'chapter.xhtml', fragments: const [],
      progression: .25, selectedText: 'Same text',
    );
    final fallbackB = AnnotationLocationKey.build(
      bookId: 'book', href: 'chapter.xhtml', fragments: const [],
      progression: .5, selectedText: 'Same text',
    );
    expect(rangeB, isNot(rangeA));
    expect(fallbackB, isNot(fallbackA));
  });
}

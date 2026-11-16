import 'package:bibliolife/features/book_details/domain/models/book_toc_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TOC snapshot round-trips hierarchy and normalizes titles', () {
    const snapshot = BookTocSnapshot([
      BookTocEntry(
        title: 'Chapter',
        locatorJson: '{"href":"chapter.xhtml"}',
        children: [
          BookTocEntry(title: 'Section', locatorJson: '{"href":"section"}'),
        ],
      ),
    ]);
    final decoded = BookTocSnapshot.decode(snapshot.encode())!;
    expect(decoded.entries.single.title, 'Chapter');
    expect(decoded.entries.single.children.single.title, 'Section');
  });

  test('unusable parents are flattened while usable children survive', () {
    final decoded = BookTocSnapshot.decode(
      '{"version":1,"entries":[{"title":"  ","locatorJson":"",'
      '"children":[{"title":" A   title ","locatorJson":"{\\"href\\":\\"a\\"}"}]}]}',
    )!;
    expect(decoded.entries.single.title, 'A title');
  });
}

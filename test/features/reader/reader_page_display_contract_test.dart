import 'package:bibliolife/features/reader/domain/models/reader_kind.dart';
import 'package:bibliolife/features/reader/domain/models/reader_progress_state.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PDF CBZ and CBR expose exact one-based Page labels', () {
    for (final format in [BookFormat.pdf, BookFormat.cbz, BookFormat.cbr]) {
      final progress = ReaderProgressState.page(page: 7, total: 19);
      expect(progress.label, 'Page 7 of 19', reason: format.name);
      expect(progress.current, 6, reason: format.name);
      expect(progress.pageFor(progress.progression), 7, reason: format.name);
    }
  });

  test('all supported formats route to their intended page model', () {
    expect(readerKindFor(BookFormat.epub), ReaderKind.epub);
    expect(readerKindFor(BookFormat.fb2), ReaderKind.reflowable);
    expect(readerKindFor(BookFormat.txt), ReaderKind.reflowable);
    expect(readerKindFor(BookFormat.pdf), ReaderKind.pdf);
    expect(readerKindFor(BookFormat.cbz), ReaderKind.comic);
    expect(readerKindFor(BookFormat.cbr), ReaderKind.comic);
  });
}

import 'package:bibliolife/shared/models/book_format.dart';

enum ReaderKind { epub, pdf, reflowable, comic, unsupported }

enum ReaderPresentation {
  readiumFlutter,
  readiumReflowable,
  flutterPdf,
  flutterComic,
  unsupported,
}

ReaderKind readerKindFor(BookFormat format) => switch (format) {
  BookFormat.epub => ReaderKind.epub,
  BookFormat.pdf => ReaderKind.pdf,
  BookFormat.fb2 || BookFormat.txt => ReaderKind.reflowable,
  BookFormat.cbz || BookFormat.cbr => ReaderKind.comic,
  BookFormat.unknown => ReaderKind.unsupported,
};

ReaderPresentation readerPresentationFor(BookFormat format) =>
    switch (readerKindFor(format)) {
      ReaderKind.epub => ReaderPresentation.readiumFlutter,
      ReaderKind.pdf => ReaderPresentation.flutterPdf,
      ReaderKind.reflowable => ReaderPresentation.readiumReflowable,
      ReaderKind.comic => ReaderPresentation.flutterComic,
      ReaderKind.unsupported => ReaderPresentation.unsupported,
    };

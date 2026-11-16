import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';

sealed class ImportResult {
  const ImportResult();
}

class ImportSuccess extends ImportResult {
  const ImportSuccess(this.book);

  final LibraryBook book;
}

class ImportCancelled extends ImportResult {
  const ImportCancelled();
}

class ImportUnsupportedFormat extends ImportResult {
  const ImportUnsupportedFormat(this.format);

  final BookFormat format;
}

class ImportDuplicate extends ImportResult {
  const ImportDuplicate();
}

class ImportCopyFailed extends ImportResult {
  const ImportCopyFailed();
}

class ImportUnreadableFile extends ImportResult {
  const ImportUnreadableFile();
}

class ImportDatabaseFailed extends ImportResult {
  const ImportDatabaseFailed();
}

class ImportUnknownFailure extends ImportResult {
  const ImportUnknownFailure();
}

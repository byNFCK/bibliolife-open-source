import 'package:bibliolife/features/import/domain/entities/import_result.dart';
import 'package:bibliolife/shared/models/library_book.dart';

abstract interface class ImportRepository {
  Future<ImportResult> importFile();
  Future<void> removeImportedFile(LibraryBook book);
}

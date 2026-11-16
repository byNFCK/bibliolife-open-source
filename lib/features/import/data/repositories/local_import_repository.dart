import 'package:bibliolife/features/import/data/services/book_importer.dart';
import 'package:bibliolife/features/import/domain/entities/import_result.dart';
import 'package:bibliolife/features/import/domain/repositories/import_repository.dart';
import 'package:bibliolife/shared/models/library_book.dart';

class LocalImportRepository implements ImportRepository {
  const LocalImportRepository(this._bookImporter);

  final BookImporter _bookImporter;

  @override
  Future<ImportResult> importFile() => _bookImporter.importFile();

  @override
  Future<void> removeImportedFile(LibraryBook book) {
    return _bookImporter.removeImportedFile(book);
  }
}

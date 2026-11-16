import 'package:bibliolife/features/import/application/services/managed_book_deletion_service.dart';

class DeleteBook {
  const DeleteBook(this._deletionService);

  final ManagedBookDeletionService _deletionService;

  Future<void> call(String id) => _deletionService.delete(id);
}

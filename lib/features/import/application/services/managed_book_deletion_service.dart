import 'dart:io';

import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';
import 'package:bibliolife/features/metadata/data/services/cover_storage_service.dart';

/// Deletes the database record first, then removes only app-managed book assets.
/// Cleanup errors propagate so callers can report or retry orphan cleanup.
class ManagedBookDeletionService {
  const ManagedBookDeletionService(
    this._libraryRepository,
    this._coverStorageService,
  );

  final LibraryRepository _libraryRepository;
  final CoverStorageService _coverStorageService;

  Future<void> delete(String id) async {
    final book = await _libraryRepository.getBookById(id);
    if (book == null) return;
    await _libraryRepository.deleteBook(id);
    final managedBook = File(book.filePath);
    if (await managedBook.exists()) await managedBook.delete();
    await _coverStorageService.deleteStoredCover(book.coverPath);
  }
}

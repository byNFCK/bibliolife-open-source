import 'dart:convert';
import 'dart:typed_data';

import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/metadata/data/services/cover_storage_service.dart';
import 'package:bibliolife/shared/models/book_cover_provenance.dart';
import 'package:uuid/uuid.dart';

class BookDetailsEditService {
  BookDetailsEditService({
    required this._booksDao,
    required this._coverStorage,
    String Function()? idGenerator,
  }) : _idGenerator = idGenerator ?? const Uuid().v4;

  final BooksDao _booksDao;
  final CoverStorageService _coverStorage;
  final String Function() _idGenerator;

  Future<void> save({
    required String bookId,
    required String title,
    required String? author,
    bool updateTitle = true,
    bool updateAuthor = true,
    Uint8List? replacementCoverBytes,
    String? replacementCoverExtension,
    BookCoverProvenance? replacementCoverProvenance,
    List<String>? replacementAuthors,
    bool removeManualCover = false,
    bool clearCover = false,
    bool cleanupReplacedManualCover = false,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) throw const InvalidBookTitle();
    if (replacementCoverBytes != null && (removeManualCover || clearCover)) {
      throw ArgumentError('A cover cannot be replaced and removed together.');
    }

    final trimmedAuthor = author?.trim();
    final normalizedAuthor = trimmedAuthor == null || trimmedAuthor.isEmpty
        ? null
        : trimmedAuthor;
    String? newCoverPath;
    final coverProvenance =
        replacementCoverProvenance ?? BookCoverProvenance.manual;
    if (replacementCoverBytes != null) {
      final extension = replacementCoverExtension?.toLowerCase();
      final allowedExtensions = coverProvenance == BookCoverProvenance.embedded
          ? {...supportedCoverExtensions, 'gif'}
          : supportedCoverExtensions;
      if ((extension == null &&
              coverProvenance != BookCoverProvenance.embedded) ||
          (extension != null && !allowedExtensions.contains(extension))) {
        throw const InvalidBookCover();
      }
      newCoverPath = await _coverStorage.storeValidatedCover(
        bookId:
            '$bookId-${coverProvenance == BookCoverProvenance.manual ? 'manual' : 'restored'}-${_idGenerator()}',
        bytes: replacementCoverBytes,
        extension: extension,
      );
      if (newCoverPath == null) throw const InvalidBookCover();
    }

    final BookDetailsFieldsUpdateResult update;
    try {
      final saved = await _booksDao.updateBookDetailsFields(
        id: bookId,
        title: trimmedTitle,
        author: normalizedAuthor,
        authorsJson: replacementAuthors == null
            ? normalizedAuthor == null
                  ? null
                  : jsonEncode([normalizedAuthor])
            : jsonEncode(replacementAuthors),
        updateTitle: updateTitle,
        updateAuthor: updateAuthor,
        replacementCoverPath: newCoverPath,
        replacementCoverProvenance: replacementCoverProvenance,
        replaceCover: newCoverPath != null,
        removeManualCover: removeManualCover,
        clearCover: clearCover,
      );
      if (saved == null) throw const BookDetailsEditNotFound();
      update = saved;
    } catch (_) {
      if (newCoverPath != null) {
        try {
          await _coverStorage.deleteStoredCover(newCoverPath);
        } on Object {
          // This path belongs only to the failed edit attempt.
        }
      }
      rethrow;
    }

    final previousCover = update.previous;
    final currentCover = update.current;
    if (cleanupReplacedManualCover &&
        previousCover.coverProvenance == BookCoverProvenance.manual.name &&
        previousCover.coverPath != null &&
        previousCover.coverPath != currentCover.coverPath) {
      try {
        if (await _coverStorage.isManagedManualBookCoverPath(
              coverPath: previousCover.coverPath,
              bookId: bookId,
            ) &&
            !await _booksDao.isCoverPathReferenced(previousCover.coverPath!)) {
          await _coverStorage.deleteStoredCover(previousCover.coverPath);
        }
      } on Object {
        // Cleanup is best-effort after the metadata transaction commits.
      }
    }
  }
}

const supportedCoverExtensions = {'jpg', 'jpeg', 'png', 'webp'};

class InvalidBookTitle implements Exception {
  const InvalidBookTitle();
}

class InvalidBookCover implements Exception {
  const InvalidBookCover();
}

class BookDetailsEditNotFound implements Exception {
  const BookDetailsEditNotFound();
}

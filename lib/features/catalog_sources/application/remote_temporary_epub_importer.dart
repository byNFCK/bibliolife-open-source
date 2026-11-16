import 'dart:io';

import 'package:bibliolife/features/catalog_sources/data/foreground_remote_book_downloader.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_temporary_epub_import.dart';
import 'package:bibliolife/features/import/data/services/book_importer.dart';
import 'package:bibliolife/features/import/data/services/import_file_picker.dart';
import 'package:bibliolife/features/import/domain/entities/import_result.dart';
import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:bibliolife/shared/models/library_book.dart';

class ProductionRemoteTemporaryEpubImporter
    implements RemoteTemporaryEpubImporter {
  ProductionRemoteTemporaryEpubImporter(
    this._bookImporter,
    this._libraryRepository,
    this._temporaryDirectory,
  );

  final BookImporter _bookImporter;
  final LibraryRepository _libraryRepository;
  final Future<Directory> Function() _temporaryDirectory;
  final _remoteHashes = <String, String>{};
  final _hashBookIds = <String, String>{};

  @override
  Future<RemoteTemporaryEpubImportResult> import(
    RemoteTemporaryEpubImportInput input,
  ) async {
    final remoteKey = '${input.sourceId}\u0000${input.publicationRemoteId}';
    final rememberedHash = _remoteHashes[remoteKey];
    if (rememberedHash != null && rememberedHash != input.sha256) {
      return const RemoteTemporaryEpubImportFailed(
        RemoteTemporaryEpubImportFailure.conflictingRemoteIdentity,
      );
    }
    final rememberedBookId = _hashBookIds[input.sha256];
    if (rememberedBookId != null) {
      final existing = await _libraryRepository.getBookById(rememberedBookId);
      if (existing != null) {
        await _deleteControlledInput(input);
        return RemoteTemporaryEpubAlreadyInLibrary(existing);
      }
    }

    final validation = await _validate(input);
    if (validation != null) return RemoteTemporaryEpubImportFailed(validation);

    final duplicate = await _findHashDuplicate(input.sha256);
    if (duplicate != null) {
      _remoteHashes[remoteKey] = input.sha256;
      _hashBookIds[input.sha256] = duplicate.id;
      await _deleteControlledInput(input);
      return RemoteTemporaryEpubAlreadyInLibrary(duplicate);
    }

    final result = await _bookImporter.importLocalFile(
      PickedImportFile(
        path: input.temporaryFilePath,
        name: input.suggestedFilename,
      ),
      remoteMetadata: input.remoteMetadata,
    );
    if (result case ImportSuccess(:final book)) {
      _remoteHashes[remoteKey] = input.sha256;
      _hashBookIds[input.sha256] = book.id;
      await _deleteControlledInput(input);
      return RemoteTemporaryEpubImported(book);
    }
    return RemoteTemporaryEpubImportFailed(switch (result) {
      ImportCopyFailed() => RemoteTemporaryEpubImportFailure.storageFailure,
      ImportDatabaseFailed() =>
        RemoteTemporaryEpubImportFailure.persistenceFailure,
      _ => RemoteTemporaryEpubImportFailure.unknown,
    });
  }

  Future<RemoteTemporaryEpubImportFailure?> _validate(
    RemoteTemporaryEpubImportInput input,
  ) async {
    final file = File(input.temporaryFilePath);
    final root = Directory(
      path.join((await _temporaryDirectory()).path, 'remote-downloads'),
    );
    final rootPath = path.normalize(path.absolute(root.path));
    final filePath = path.normalize(path.absolute(file.path));
    if (!path.isWithin(rootPath, filePath)) {
      return RemoteTemporaryEpubImportFailure.uncontrolledPath;
    }
    if (!await file.exists()) {
      return RemoteTemporaryEpubImportFailure.missingTemporaryFile;
    }
    if (await file.length() != input.downloadedByteCount) {
      return RemoteTemporaryEpubImportFailure.changedSize;
    }
    final checksum = (await sha256.bind(file.openRead()).first).toString();
    if (checksum.toLowerCase() != input.sha256.toLowerCase()) {
      return RemoteTemporaryEpubImportFailure.checksumMismatch;
    }
    try {
      const EpubPackageValidator().validate(file);
    } catch (_) {
      return RemoteTemporaryEpubImportFailure.invalidEpub;
    }
    return null;
  }

  Future<LibraryBook?> _findHashDuplicate(String expectedHash) async {
    for (final book in await _libraryRepository.getAllBooks()) {
      final file = File(book.filePath);
      if (!await file.exists()) continue;
      final hash = (await sha256.bind(file.openRead()).first).toString();
      if (hash.toLowerCase() == expectedHash.toLowerCase()) return book;
    }
    return null;
  }

  Future<void> _deleteControlledInput(
    RemoteTemporaryEpubImportInput input,
  ) async {
    final failure = await _validatePathOnly(input.temporaryFilePath);
    if (failure != null) return;
    final file = File(input.temporaryFilePath);
    if (await file.exists()) await file.delete();
    final parent = file.parent;
    if (await parent.exists() && await parent.list().isEmpty) {
      await parent.delete();
    }
  }

  Future<RemoteTemporaryEpubImportFailure?> _validatePathOnly(
    String filePath,
  ) async {
    final root = Directory(
      path.join((await _temporaryDirectory()).path, 'remote-downloads'),
    );
    return path.isWithin(
          path.normalize(path.absolute(root.path)),
          path.normalize(path.absolute(filePath)),
        )
        ? null
        : RemoteTemporaryEpubImportFailure.uncontrolledPath;
  }
}

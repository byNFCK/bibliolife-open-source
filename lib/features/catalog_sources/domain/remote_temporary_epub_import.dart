import 'package:bibliolife/shared/models/library_book.dart';
import 'package:bibliolife/features/metadata/domain/entities/trusted_remote_book_metadata.dart';

class RemoteTemporaryEpubImportInput {
  RemoteTemporaryEpubImportInput({
    required this.temporaryFilePath,
    required this.sourceId,
    required this.publicationRemoteId,
    required this.remoteTitle,
    required Iterable<String> remoteAuthors,
    required this.acquisitionUri,
    required this.sha256,
    required this.downloadedByteCount,
    required this.suggestedFilename,
    this.remoteMetadata,
  }) : remoteAuthors = List.unmodifiable(remoteAuthors);

  final String temporaryFilePath;
  final String sourceId;
  final String publicationRemoteId;
  final String remoteTitle;
  final List<String> remoteAuthors;
  final Uri acquisitionUri;
  final String sha256;
  final int downloadedByteCount;
  final String suggestedFilename;
  final TrustedRemoteBookMetadata? remoteMetadata;
}

enum RemoteTemporaryEpubImportFailure {
  missingTemporaryFile,
  changedSize,
  checksumMismatch,
  invalidEpub,
  uncontrolledPath,
  conflictingRemoteIdentity,
  storageFailure,
  persistenceFailure,
  unknown,
}

sealed class RemoteTemporaryEpubImportResult {
  const RemoteTemporaryEpubImportResult();
}

class RemoteTemporaryEpubImported extends RemoteTemporaryEpubImportResult {
  const RemoteTemporaryEpubImported(this.book);
  final LibraryBook book;
}

class RemoteTemporaryEpubAlreadyInLibrary
    extends RemoteTemporaryEpubImportResult {
  const RemoteTemporaryEpubAlreadyInLibrary(this.book);
  final LibraryBook book;
}

class RemoteTemporaryEpubImportFailed extends RemoteTemporaryEpubImportResult {
  const RemoteTemporaryEpubImportFailed(this.failure);
  final RemoteTemporaryEpubImportFailure failure;
}

abstract interface class RemoteTemporaryEpubImporter {
  Future<RemoteTemporaryEpubImportResult> import(
    RemoteTemporaryEpubImportInput input,
  );
}

import 'dart:async';
import 'dart:io';

import 'package:bibliolife/features/import/data/services/import_file_picker.dart';
import 'package:bibliolife/features/catalog_sources/data/remote_cache_service.dart';
import 'package:bibliolife/features/book_details/domain/models/book_toc_snapshot.dart';
import 'package:bibliolife/features/import/domain/entities/import_result.dart';
import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';
import 'package:bibliolife/features/metadata/data/services/cover_storage_service.dart';
import 'package:bibliolife/features/metadata/domain/services/installed_book_cover_policy.dart';
import 'package:bibliolife/features/metadata/data/services/book_metadata_merger.dart';
import 'package:bibliolife/features/metadata/data/services/epub_metadata_diagnostics.dart';
import 'package:bibliolife/features/metadata/data/services/epub_metadata_normalizer.dart';
import 'package:bibliolife/features/metadata/data/services/epub_title_quality_evaluator.dart';
import 'package:bibliolife/features/metadata/domain/entities/metadata_extraction_result.dart';
import 'package:bibliolife/features/metadata/domain/entities/extracted_book_metadata.dart';
import 'package:bibliolife/features/metadata/domain/entities/trusted_remote_book_metadata.dart';
import 'package:bibliolife/features/metadata/domain/repositories/book_metadata_repository.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/book_cover_provenance.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:bibliolife_readium/bibliolife_readium.dart';
import 'package:flutter/foundation.dart';

class BookImporter {
  BookImporter({
    required this.filePicker,
    required this.libraryRepository,
    this.metadataRepository,
    this.coverStorageService,
    this.remoteCache,
    this.tocExtractor,
    Future<Directory> Function()? documentsDirectory,
    String Function()? idGenerator,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       _idGenerator = idGenerator ?? const Uuid().v4;

  final ImportFilePicker filePicker;
  final LibraryRepository libraryRepository;
  final BookMetadataRepository? metadataRepository;
  final CoverStorageService? coverStorageService;
  final RemoteCacheService? remoteCache;
  final ReadiumTocExtractor? tocExtractor;
  final Future<Directory> Function() _documentsDirectory;
  final String Function() _idGenerator;
  final Map<String, Future<void>> _onlinePromotions = {};

  Future<ImportResult> importFile() async {
    final pickedFile = await filePicker.pickBookFile();
    if (pickedFile == null) return const ImportCancelled();
    return importLocalFile(pickedFile);
  }

  /// Imports an already-local file through the same managed storage,
  /// metadata extraction and repository insertion path as the file picker.
  Future<ImportResult> importLocalFile(
    PickedImportFile pickedFile, {
    TrustedRemoteBookMetadata? remoteMetadata,
  }) async {
    var stage = 'started';
    try {
      final format = BookFormat.fromFileName(pickedFile.name);
      if (!BookFormat.supportedExtensions.contains(format.normalizedExtension)) {
        return ImportUnsupportedFormat(format);
      }

      final existingBook = await libraryRepository.findBookByOriginalFilePath(
        pickedFile.path,
      );
      if (existingBook != null) return const ImportDuplicate();

      final booksDirectory = Directory(
        path.join((await _documentsDirectory()).path, 'books'),
      );
      await booksDirectory.create(recursive: true);

      final bookId = _idGenerator();
      final destinationPath = path.join(
        booksDirectory.path,
        '$bookId.${format.normalizedExtension}',
      );
      final destination = File(destinationPath);
      if (await destination.exists()) return const ImportDuplicate();
      final partial = File('$destinationPath.part');

      final source = File(pickedFile.path);
      final fileSizeBytes = await source.length();
      try {
        await source.copy(partial.path);
        await partial.rename(destinationPath);
      } on FileSystemException {
        await _deleteIfPresent(partial);
        return const ImportCopyFailed();
      }

      final metadataResult = await _extractMetadata(destinationPath, format);
      if (metadataRepository != null &&
          _requiresValidatedImport(format) &&
          metadataResult is! MetadataExtractionSuccess) {
        await _deleteIfPresent(destination);
        return const ImportUnreadableFile();
      }
      final tocResult = await _extractToc(destinationPath, format);
      final parsedMetadata = switch (metadataResult) {
        MetadataExtractionSuccess(:final metadata) => metadata,
        _ => null,
      };
      final merged = const BookMetadataMerger().merge(
        parsedMetadata ?? _emptyMetadata,
        remoteMetadata,
      );
      final metadata = merged.metadata;
      // Defensive persistence boundary: remote and EPUB paths both pass the
      // same idempotent cleaner before a local row is ever created.
      final cleanedDescription = EpubMetadataNormalizer.description(
        metadata.description,
      );
      stage = 'parsed';
      EpubMetadataDiagnostics.logImportStage(stage);
      EpubMetadataDiagnostics.logImportStage('normalized');
      EpubMetadataDiagnostics.logImportStage('title_assessment_started');
      final titleSelection = _selectTitleSafely(
        metadataTitle: metadata.title,
        originalFilename: pickedFile.name,
      );
      EpubMetadataDiagnostics.logFilenameSource(
        source: 'platform_file',
        filename: pickedFile.name,
        assessment: titleSelection.filename,
      );
      stage = 'title_selected';
      EpubMetadataDiagnostics.logTitleSelection(titleSelection);
      EpubMetadataDiagnostics.logImportStage(stage);
      EpubMetadataDiagnostics.log(
        stage: 'DOMAIN',
        field: 'title',
        source: 'epub_parser',
        value: metadata.title,
      );
      EpubMetadataDiagnostics.log(
        stage: 'DOMAIN',
        field: 'author',
        source: 'epub_parser',
        value: metadata.authorDisplay,
      );
      EpubMetadataDiagnostics.log(
        stage: 'DOMAIN',
        field: 'description',
        source: 'epub_parser',
        value: cleanedDescription,
      );
      EpubMetadataDiagnostics.log(
        stage: 'DOMAIN',
        field: 'publisher',
        source: 'epub_parser',
        value: metadata.publisher,
      );
      final onlineCoverPath = await _promoteOnlineCover(
        bookId: bookId,
        coverUri: remoteMetadata?.coverLocation,
      );
      final coverPath = onlineCoverPath;
      final coverProvenance = onlineCoverPath == null
          ? BookCoverProvenance.none
          : BookCoverProvenance.online;

      final book = LibraryBook(
        id: bookId,
        title:
            titleSelection.title ??
            path.basenameWithoutExtension(pickedFile.name),
        sortTitle: metadata.sortTitle,
        author: metadata.authorDisplay,
        description: cleanedDescription,
        filePath: destinationPath,
        originalFilePath: pickedFile.path,
        fileName: pickedFile.name,
        fileExtension: format.normalizedExtension,
        format: format,
        mediaType: metadata.mediaType,
        coverPath: coverPath,
        coverProvenance: coverProvenance,
        language: metadata.language,
        publisher: metadata.publisher,
        publishedDate: metadata.publishedDate,
        isbn: metadata.isbn,
        pageCount: metadata.pageCount,
        fileSizeBytes: fileSizeBytes,
        dateAdded: DateTime.now(),
        lastOpenedAt: null,
        isFavorite: false,
        authors: metadata.authors,
        contributors: metadata.contributors,
        identifiers: metadata.identifiers,
        subjects: metadata.subjects,
        rights: metadata.rights,
        seriesName: metadata.seriesName,
        seriesIndex: metadata.seriesIndex,
        edition: metadata.edition,
        source: metadata.source,
        coverage: metadata.coverage,
        type: metadata.type,
        modifiedDate: metadata.modifiedDate,
        catalogSourceId: remoteMetadata?.sourceId,
        remotePublicationId: remoteMetadata?.publicationId,
        remotePublicationLocation: remoteMetadata?.publicationLocation
            ?.toString(),
        remoteAcquisitionLocation: remoteMetadata?.acquisitionLocation
            .toString(),
        metadataOrigins: merged.origins,
        tocJson: _tocJsonForImport(tocResult),
      );
      stage = 'domain_created';
      EpubMetadataDiagnostics.logImportStage(stage);

      try {
        stage = 'repository_insert_started';
        EpubMetadataDiagnostics.logImportStage(stage);
        await libraryRepository.addBook(book);
        stage = 'repository_inserted';
        EpubMetadataDiagnostics.logImportStage(stage);
        EpubMetadataDiagnostics.log(
          stage: 'PERSISTED',
          field: 'title',
          source: 'drift',
          value: book.title,
        );
        EpubMetadataDiagnostics.log(
          stage: 'PERSISTED',
          field: 'author',
          source: 'drift',
          value: book.author,
        );
        EpubMetadataDiagnostics.log(
          stage: 'PERSISTED',
          field: 'description',
          source: 'drift',
          value: book.description,
        );
        EpubMetadataDiagnostics.log(
          stage: 'PERSISTED',
          field: 'publisher',
          source: 'drift',
          value: book.publisher,
        );
      } catch (_) {
        await _deleteIfPresent(destination);
        await coverStorageService?.deleteStoredCover(coverPath);
        return const ImportDatabaseFailed();
      }

      if (onlineCoverPath == null &&
          metadata.coverBytes != null &&
          coverStorageService != null) {
        // The inserted row begins with the standard placeholder. Persisting a
        // valid EPUB image afterwards updates all local consumers reactively
        // without delaying import completion.
        unawaited(
          _persistEmbeddedCoverIfAllowed(
            book,
            bytes: metadata.coverBytes!,
            extension: metadata.coverExtension,
          ),
        );
      } else if (onlineCoverPath == null) {
        EpubMetadataDiagnostics.logCoverFailure('missing');
      }
      if (onlineCoverPath == null && remoteMetadata?.coverLocation != null) {
        unawaited(
          _promoteOnlineCoverLater(book, remoteMetadata!.coverLocation!),
        );
      }

      EpubMetadataDiagnostics.logImportStage('completed');
      return ImportSuccess(book);
    } on FileSystemException catch (error) {
      EpubMetadataDiagnostics.logImportFailure(stage, error);
      return const ImportCopyFailed();
    } catch (error) {
      EpubMetadataDiagnostics.logImportFailure(stage, error);
      return const ImportUnknownFailure();
    }
  }

  EpubTitleSelection _selectTitleSafely({
    required String? metadataTitle,
    required String? originalFilename,
  }) {
    try {
      return EpubTitleQualityEvaluator.select(
        metadataTitle: metadataTitle,
        filename: originalFilename,
      );
    } catch (error) {
      EpubMetadataDiagnostics.logImportFailure('title_assessment', error);
      return EpubTitleSelection(
        title: 'Unknown title',
        source: BookTitleSource.stableFallback,
        metadata: EpubTitleQualityEvaluator.assess(null),
        filename: EpubTitleQualityEvaluator.assess(null),
      );
    }
  }

  Future<MetadataExtractionResult?> _extractMetadata(
    String filePath,
    BookFormat format,
  ) async {
    if (metadataRepository == null) return null;
    try {
      return await metadataRepository!.extractMetadata(
        filePath: filePath,
        format: format,
      );
    } catch (_) {
      return const MetadataParsingFailed();
    }
  }

  Future<ReadiumTocExtractionResult?> _extractToc(
    String filePath,
    BookFormat format,
  ) async {
    if (format != BookFormat.epub || tocExtractor == null) return null;
    try {
      return await tocExtractor!.extractTableOfContents(filePath);
    } catch (error) {
      debugPrint('TOC extraction failed: ${error.runtimeType}');
      return const ReadiumTocExtractionFailure('unexpected_error');
    }
  }

  Future<void> removeImportedFile(LibraryBook book) async {
    final file = File(book.filePath);
    if (await file.exists()) await file.delete();
    await libraryRepository.deleteBook(book.id);
    await coverStorageService?.deleteStoredCover(book.coverPath);
  }

  /// Re-reads metadata from the managed EPUB without replacing user data.
  ///
  /// This provides a safe repair path for books imported before the XML
  /// decoding fix: reading progress, annotations, bookmarks, IDs and dates are
  /// all associated with the existing book ID and remain untouched.
  Future<LibraryBook?> refreshBookMetadata(String bookId) async {
    final existing = await libraryRepository.getBookById(bookId);
    if (existing == null || existing.format != BookFormat.epub) return null;
    final result = await _extractMetadata(existing.filePath, existing.format);
    if (result is! MetadataExtractionSuccess) return null;
    final tocResult = await _extractToc(existing.filePath, existing.format);
    final metadata = result.metadata;
    final titleSelection = EpubTitleQualityEvaluator.select(
      metadataTitle: metadata.title,
      filename: existing.fileName,
    );
    EpubMetadataDiagnostics.logTitleSelection(titleSelection);

    var coverPath = existing.coverPath;
    var coverProvenance = existing.coverProvenance;
    if (metadata.coverBytes != null && coverStorageService != null) {
      try {
        final hasValidCurrent = await coverStorageService!.hasValidStoredCover(
          existing.coverPath,
        );
        if (const InstalledBookCoverPolicy().mayReplace(
          current: existing.coverProvenance,
          currentFileIsValid: hasValidCurrent,
          incoming: BookCoverProvenance.embedded,
        )) {
          final stored = await coverStorageService!.storeValidatedCover(
            bookId: existing.id,
            bytes: metadata.coverBytes!,
            extension: metadata.coverExtension,
          );
          if (stored != null) {
            coverPath = stored;
            coverProvenance = BookCoverProvenance.embedded;
          }
        }
      } catch (_) {
        coverPath = existing.coverPath;
      }
    }
    final refreshed = LibraryBook(
      id: existing.id,
      // A differing stored title can be a user edit or a previously selected
      // filename fallback. Replace only the old auto-imported metadata value.
      title: existing.title == metadata.title
          ? (titleSelection.title ?? existing.title)
          : existing.title,
      sortTitle: metadata.sortTitle ?? existing.sortTitle,
      author: metadata.authorDisplay ?? existing.author,
      description:
          EpubMetadataNormalizer.description(metadata.description) ??
          EpubMetadataNormalizer.description(existing.description),
      filePath: existing.filePath,
      originalFilePath: existing.originalFilePath,
      fileName: existing.fileName,
      fileExtension: existing.fileExtension,
      format: existing.format,
      mediaType: metadata.mediaType ?? existing.mediaType,
      coverPath: coverPath,
      coverProvenance: coverProvenance,
      language: metadata.language ?? existing.language,
      publisher: metadata.publisher ?? existing.publisher,
      publishedDate: metadata.publishedDate ?? existing.publishedDate,
      isbn: metadata.isbn ?? existing.isbn,
      pageCount: existing.pageCount,
      fileSizeBytes: existing.fileSizeBytes,
      dateAdded: existing.dateAdded,
      lastOpenedAt: existing.lastOpenedAt,
      isFavorite: existing.isFavorite,
      authors: metadata.authors,
      contributors: metadata.contributors,
      identifiers: metadata.identifiers,
      subjects: metadata.subjects,
      rights: metadata.rights,
      seriesName: metadata.seriesName,
      seriesIndex: metadata.seriesIndex,
      edition: metadata.edition,
      source: metadata.source,
      coverage: metadata.coverage,
      type: metadata.type,
      modifiedDate: metadata.modifiedDate,
      catalogSourceId: existing.catalogSourceId,
      remotePublicationId: existing.remotePublicationId,
      remotePublicationLocation: existing.remotePublicationLocation,
      remoteAcquisitionLocation: existing.remoteAcquisitionLocation,
      metadataOrigins: {
        ...existing.metadataOrigins,
        for (final field in const [
          'title',
          'authors',
          'description',
          'language',
          'publisher',
          'publishedDate',
          'isbn',
          'subjects',
          'rights',
        ])
          if (_hasMetadataField(metadata, field)) field: 'epub',
      },
      tocJson: _tocJsonForRefresh(tocResult, existing.tocJson),
    );
    await libraryRepository.updateBook(refreshed);
    if (coverPath != existing.coverPath) {
      await coverStorageService?.deleteStoredCover(existing.coverPath);
    }
    return refreshed;
  }

  Future<String?> _promoteOnlineCover({
    required String bookId,
    required Uri? coverUri,
  }) async {
    if (coverUri == null ||
        remoteCache == null ||
        coverStorageService == null) {
      return null;
    }
    try {
      final cached = await remoteCache!.cachedCover(coverUri);
      if (cached == null || !await cached.exists()) return null;
      return coverStorageService!.storeValidatedCover(
        bookId: bookId,
        bytes: await cached.readAsBytes(),
      );
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _promoteOnlineCoverLater(LibraryBook imported, Uri coverUri) {
    final key = '${imported.id}\u0000$coverUri';
    return _onlinePromotions.putIfAbsent(key, () async {
      try {
        final cache = remoteCache;
        final storage = coverStorageService;
        if (cache == null || storage == null) return;
        final cached = await cache.cover(coverUri);
        if (cached == null || !await cached.exists()) return;
        final current =
            await libraryRepository.getBookById(imported.id) ?? imported;
        final currentIsValid = await storage.hasValidStoredCover(
          current.coverPath,
        );
        if (!const InstalledBookCoverPolicy().mayReplace(
          current: current.coverProvenance,
          currentFileIsValid: currentIsValid,
          incoming: BookCoverProvenance.online,
        )) {
          return;
        }
        final coverPath = await storage.storeValidatedCover(
          bookId: current.id,
          bytes: await cached.readAsBytes(),
        );
        if (coverPath == null) return;
        await libraryRepository.updateBook(
          current.withCover(
            coverPath: coverPath,
            provenance: BookCoverProvenance.online,
          ),
        );
        if (current.coverPath != null && current.coverPath != coverPath) {
          await storage.deleteStoredCover(current.coverPath);
        }
      } on Object {
        // A cold remote image remains best-effort. Import and embedded
        // fallback have already reached their terminal state.
      } finally {
        _onlinePromotions.remove(key);
      }
    });
  }

  Future<void> _persistEmbeddedCoverIfAllowed(
    LibraryBook imported, {
    required Uint8List bytes,
    required String? extension,
  }) async {
    final storage = coverStorageService;
    if (storage == null) return;
    try {
      final current =
          await libraryRepository.getBookById(imported.id) ?? imported;
      final validCurrent = await storage.hasValidStoredCover(current.coverPath);
      if (!const InstalledBookCoverPolicy().mayReplace(
        current: current.coverProvenance,
        currentFileIsValid: validCurrent,
        incoming: BookCoverProvenance.embedded,
      )) {
        return;
      }
      final coverPath = await storage.storeValidatedCover(
        bookId: current.id,
        bytes: bytes,
        extension: extension,
      );
      if (coverPath == null) {
        EpubMetadataDiagnostics.logCoverFailure('invalid_embedded');
        return;
      }
      final updated = current.withCover(
        coverPath: coverPath,
        provenance: BookCoverProvenance.embedded,
      );
      await libraryRepository.updateBook(updated);
      if (current.coverPath != null && current.coverPath != coverPath) {
        await storage.deleteStoredCover(current.coverPath);
      }
    } on Object {
      EpubMetadataDiagnostics.logCoverFailure('storage_failed');
    }
  }

  Future<void> _deleteIfPresent(File file) async {
    if (await file.exists()) await file.delete();
  }
}

bool _requiresValidatedImport(BookFormat format) => switch (format) {
  // Non-EPUB formats are handled by their existing downstream readers or
  // conversion pipeline and may not have an EPUB metadata representation.
  // Keep metadata validation strict only where it proves the EPUB is readable.
  BookFormat.epub => true,
  _ => false,
};

String? _tocJsonForImport(ReadiumTocExtractionResult? result) =>
    switch (result) {
      ReadiumTocExtractionSuccess(:final entries) => _snapshotFromReadium(
        entries,
      )?.encode(),
      _ => null,
    };

String? _tocJsonForRefresh(
  ReadiumTocExtractionResult? result,
  String? previous,
) => switch (result) {
  ReadiumTocExtractionSuccess(:final entries) => _snapshotFromReadium(
    entries,
  )?.encode(),
  ReadiumTocExtractionEmpty() => null,
  ReadiumTocExtractionFailure(:final code) => _preserveToc(previous, code),
  null => previous,
};

String? _preserveToc(String? previous, String code) {
  debugPrint(
    'TOC refresh failed: ${code.length <= 64 ? code : code.substring(0, 64)}',
  );
  return previous;
}

BookTocSnapshot? _snapshotFromReadium(List<ReadiumTocEntry> entries) {
  List<BookTocEntry> convert(List<ReadiumTocEntry> source) =>
      BookTocEntry.decodeEntries(
        source
            .map(
              (entry) => {
                'title': entry.title,
                'locatorJson': entry.locatorJson,
                'children': convert(
                  entry.children,
                ).map((child) => child.toJson()).toList(),
              },
            )
            .toList(),
      );
  final converted = convert(entries);
  return converted.isEmpty ? null : BookTocSnapshot(converted);
}

const _emptyMetadata = ExtractedBookMetadata(
  title: null,
  sortTitle: null,
  authors: [],
  description: null,
  language: null,
  publisher: null,
  publishedDate: null,
  isbn: null,
  coverBytes: null,
  coverExtension: null,
  mediaType: null,
);

bool _hasMetadataField(ExtractedBookMetadata value, String field) =>
    switch (field) {
      'title' => value.title != null,
      'authors' => value.authors.isNotEmpty,
      'description' => value.description != null,
      'language' => value.language != null,
      'publisher' => value.publisher != null,
      'publishedDate' => value.publishedDate != null,
      'isbn' => value.isbn != null,
      'subjects' => value.subjects.isNotEmpty,
      'rights' => value.rights != null,
      _ => false,
    };

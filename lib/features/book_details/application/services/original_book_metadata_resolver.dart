import 'dart:io';
import 'dart:typed_data';

import 'package:bibliolife/features/metadata/data/services/epub_title_quality_evaluator.dart';
import 'package:bibliolife/features/metadata/domain/entities/extracted_book_metadata.dart';
import 'package:bibliolife/features/metadata/domain/entities/metadata_extraction_result.dart';
import 'package:bibliolife/features/metadata/domain/repositories/book_metadata_repository.dart';
import 'package:bibliolife/features/metadata/data/services/cover_storage_service.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';

class OriginalBookMetadataResolver {
  const OriginalBookMetadataResolver({
    required this.metadataRepository,
    this.imageValidator = const FlutterCoverImageValidator(),
  });

  final BookMetadataRepository metadataRepository;
  final CoverImageValidator imageValidator;

  Future<OriginalBookMetadata> resolve(LibraryBook book) async {
    if (book.format == BookFormat.unknown ||
        BookFormat.fromFileName(book.filePath) != book.format) {
      throw const OriginalBookMetadataUnavailable();
    }
    final source = File(book.filePath);
    try {
      if (!await source.exists() || await source.length() == 0) {
        throw const OriginalBookMetadataUnavailable();
      }
    } on FileSystemException {
      throw const OriginalBookMetadataUnavailable();
    }

    final result = await metadataRepository.extractMetadata(
      filePath: book.filePath,
      format: book.format,
    );
    final ExtractedBookMetadata metadata;
    if (result is MetadataExtractionSuccess) {
      metadata = result.metadata;
    } else if (result is MetadataUnsupportedFormat &&
        (book.format == BookFormat.txt || book.format == BookFormat.cbr)) {
      // Import uses the original filename when these formats have no metadata
      // parser; author and cover remain absent, matching that import result.
      metadata = const ExtractedBookMetadata(
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
    } else {
      throw const OriginalBookMetadataUnavailable();
    }

    final selectedTitle = EpubTitleQualityEvaluator.select(
      metadataTitle: metadata.title,
      filename: book.fileName,
    );
    final title = selectedTitle.title?.trim();
    if (title == null ||
        title.isEmpty ||
        selectedTitle.source == BookTitleSource.stableFallback) {
      throw const OriginalBookMetadataUnavailable();
    }

    Uint8List? coverBytes = metadata.coverBytes;
    if (coverBytes != null) {
      final extension = metadata.coverExtension?.toLowerCase();
      if (coverBytes.isEmpty ||
          !await imageValidator.isDecodable(coverBytes) ||
          (extension != null &&
              !const {
                'jpg',
                'jpeg',
                'png',
                'webp',
                'gif',
              }.contains(extension))) {
        throw const OriginalBookMetadataUnavailable();
      }
    }
    return OriginalBookMetadata(
      title: title,
      author: metadata.authorDisplay,
      authors: List.unmodifiable(metadata.authors),
      coverBytes: coverBytes,
      coverExtension: coverBytes == null ? null : metadata.coverExtension,
    );
  }
}

class OriginalBookMetadata {
  const OriginalBookMetadata({
    required this.title,
    required this.author,
    required this.authors,
    required this.coverBytes,
    required this.coverExtension,
  });

  final String title;
  final String? author;
  final List<String> authors;
  final Uint8List? coverBytes;
  final String? coverExtension;
}

class OriginalBookMetadataUnavailable implements Exception {
  const OriginalBookMetadataUnavailable();
}

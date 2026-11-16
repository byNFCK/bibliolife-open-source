import 'dart:convert';
import 'dart:io';

import 'package:bibliolife/features/metadata/domain/entities/extracted_book_metadata.dart';
import 'package:bibliolife/features/metadata/domain/entities/metadata_extraction_result.dart';
import 'package:pdfx/pdfx.dart';

/// Inspects a PDF once during import; failures leave the readable source file
/// intact and are surfaced by the reader as a controlled error.
class PdfMetadataParser {
  Future<MetadataExtractionResult> parse(String filePath) async {
    PdfDocument? document;
    PdfPage? page;
    try {
      final info = await _readInfoDictionary(filePath);
      document = await PdfDocument.openFile(filePath);
      page = await document.getPage(1, autoCloseAndroid: false);
      final scale = (360 / page.width).clamp(0.1, 1.0);
      final image = await page.render(
        width: page.width * scale,
        height: page.height * scale,
        format: PdfPageImageFormat.jpeg,
        quality: 82,
        backgroundColor: '#FFFFFF',
      );
      return MetadataExtractionSuccess(
        ExtractedBookMetadata(
          title: info.title,
          sortTitle: null,
          authors: info.author == null ? const [] : [info.author!],
          description: null,
          language: null,
          publisher: null,
          publishedDate: null,
          isbn: null,
          coverBytes: image?.bytes,
          coverExtension: image == null ? null : 'jpg',
          mediaType: 'application/pdf',
          pageCount: document.pagesCount,
        ),
      );
    } on FileSystemException catch (error) {
      return MetadataFileReadFailed(diagnosticCause: error);
    } catch (error) {
      return MetadataParsingFailed(diagnosticCause: error);
    } finally {
      await page?.close();
      await document?.close();
    }
  }

  Future<_PdfInfo> _readInfoDictionary(String path) async {
    final file = File(path);
    final handle = await file.open();
    try {
      final data = await handle.read(
        (await handle.length()).clamp(0, 1024 * 1024),
      );
      final text = latin1.decode(data, allowInvalid: true);
      return _PdfInfo(_value(text, 'Title'), _value(text, 'Author'));
    } finally {
      await handle.close();
    }
  }

  String? _value(String text, String name) {
    final match = RegExp(
      '/$name\\s*\\(([^)]*)\\)',
      dotAll: true,
    ).firstMatch(text);
    final value = match
        ?.group(1)
        ?.replaceAll(r'\\(', '(')
        .replaceAll(r'\\)', ')')
        .trim();
    return value == null || value.isEmpty ? null : value;
  }
}

class _PdfInfo {
  const _PdfInfo(this.title, this.author);
  final String? title;
  final String? author;
}

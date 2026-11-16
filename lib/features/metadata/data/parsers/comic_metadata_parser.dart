import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bibliolife/features/metadata/domain/entities/extracted_book_metadata.dart';
import 'package:bibliolife/features/metadata/domain/entities/metadata_extraction_result.dart';

class ComicMetadataParser {
  Future<MetadataExtractionResult> parseCbz(String filePath) async {
    try {
      final archive = ZipDecoder().decodeStream(
        InputFileStream(filePath),
        verify: true,
      );
      final pages =
          archive.files
              .where((file) => !file.isDirectory && _isImage(file.name))
              .toList()
            ..sort((left, right) => naturalCompare(left.name, right.name));
      if (pages.isEmpty) return const MetadataMalformedPublication();
      final cover = pages.first.readBytes();
      return MetadataExtractionSuccess(
        ExtractedBookMetadata(
          title: null,
          sortTitle: null,
          authors: const [],
          description: null,
          language: null,
          publisher: null,
          publishedDate: null,
          isbn: null,
          coverBytes: cover,
          coverExtension: _extension(pages.first.name),
          mediaType: 'application/vnd.comicbook+zip',
          pageCount: pages.length,
        ),
      );
    } on FileSystemException catch (error) {
      return MetadataFileReadFailed(diagnosticCause: error);
    } on ArchiveException catch (error) {
      return MetadataParsingFailed(diagnosticCause: error);
    } catch (error) {
      return MetadataParsingFailed(diagnosticCause: error);
    }
  }
}

bool isComicImagePath(String value) => _isImage(value);
bool _isImage(String value) =>
    const {'jpg', 'jpeg', 'png', 'webp', 'gif'}.contains(_extension(value));
String _extension(String value) => value.split('.').last.toLowerCase();

/// Natural ordering is intentional: page 10 follows page 2, including nested
/// archive paths, without relying on platform collation.
int naturalCompare(String left, String right) {
  final a = left.toLowerCase();
  final b = right.toLowerCase();
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    final aDigit = _isDigit(a.codeUnitAt(i));
    final bDigit = _isDigit(b.codeUnitAt(j));
    if (aDigit && bDigit) {
      final startI = i;
      final startJ = j;
      while (i < a.length && _isDigit(a.codeUnitAt(i))) {
        i++;
      }
      while (j < b.length && _isDigit(b.codeUnitAt(j))) {
        j++;
      }
      final numberA = int.parse(a.substring(startI, i));
      final numberB = int.parse(b.substring(startJ, j));
      if (numberA != numberB) return numberA.compareTo(numberB);
      continue;
    }
    final comparison = a.codeUnitAt(i).compareTo(b.codeUnitAt(j));
    if (comparison != 0) return comparison;
    i++;
    j++;
  }
  return a.length.compareTo(b.length);
}

bool _isDigit(int value) => value >= 48 && value <= 57;

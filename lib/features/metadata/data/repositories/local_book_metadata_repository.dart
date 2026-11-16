import 'package:bibliolife/features/metadata/data/parsers/comic_metadata_parser.dart';
import 'package:bibliolife/features/metadata/data/parsers/epub_metadata_parser.dart';
import 'package:bibliolife/features/metadata/data/parsers/fb2_metadata_parser.dart';
import 'package:bibliolife/features/metadata/data/parsers/pdf_metadata_parser.dart';
import 'package:bibliolife/features/metadata/domain/entities/metadata_extraction_result.dart';
import 'package:bibliolife/features/metadata/domain/repositories/book_metadata_repository.dart';
import 'package:bibliolife/shared/models/book_format.dart';

class LocalBookMetadataRepository implements BookMetadataRepository {
  LocalBookMetadataRepository({
    EpubMetadataParser? epubMetadataParser,
    Fb2MetadataParser? fb2MetadataParser,
    ComicMetadataParser? comicMetadataParser,
    PdfMetadataParser? pdfMetadataParser,
  }) : _epubMetadataParser = epubMetadataParser ?? EpubMetadataParser(),
       _fb2MetadataParser = fb2MetadataParser ?? Fb2MetadataParser(),
       _comicMetadataParser = comicMetadataParser ?? ComicMetadataParser(),
       _pdfMetadataParser = pdfMetadataParser ?? PdfMetadataParser();

  final EpubMetadataParser _epubMetadataParser;
  final Fb2MetadataParser _fb2MetadataParser;
  final ComicMetadataParser _comicMetadataParser;
  final PdfMetadataParser _pdfMetadataParser;

  @override
  Future<MetadataExtractionResult> extractMetadata({
    required String filePath,
    required BookFormat format,
  }) {
    return switch (format) {
      BookFormat.epub => _epubMetadataParser.parse(filePath),
      BookFormat.fb2 => _fb2MetadataParser.parse(filePath),
      BookFormat.cbz => _comicMetadataParser.parseCbz(filePath),
      BookFormat.pdf => _pdfMetadataParser.parse(filePath),
      // CBR metadata becomes available after the same cache extraction used
      // for reading; importing it must not fail just because no cover exists.
      BookFormat.cbr ||
      BookFormat.txt ||
      BookFormat.unknown => Future.value(const MetadataUnsupportedFormat()),
    };
  }
}

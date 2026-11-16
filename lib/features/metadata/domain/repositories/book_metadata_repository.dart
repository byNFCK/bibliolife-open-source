import 'package:bibliolife/features/metadata/domain/entities/metadata_extraction_result.dart';
import 'package:bibliolife/shared/models/book_format.dart';

abstract interface class BookMetadataRepository {
  Future<MetadataExtractionResult> extractMetadata({
    required String filePath,
    required BookFormat format,
  });
}

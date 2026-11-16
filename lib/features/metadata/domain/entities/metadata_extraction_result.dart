import 'package:bibliolife/features/metadata/domain/entities/extracted_book_metadata.dart';

sealed class MetadataExtractionResult {
  const MetadataExtractionResult({this.diagnosticCause});

  final Object? diagnosticCause;
}

class MetadataExtractionSuccess extends MetadataExtractionResult {
  const MetadataExtractionSuccess(this.metadata) : super();

  final ExtractedBookMetadata metadata;
}

class MetadataUnsupportedFormat extends MetadataExtractionResult {
  const MetadataUnsupportedFormat() : super();
}

class MetadataMalformedPublication extends MetadataExtractionResult {
  const MetadataMalformedPublication({super.diagnosticCause});
}

class MetadataFileReadFailed extends MetadataExtractionResult {
  const MetadataFileReadFailed({super.diagnosticCause});
}

class MetadataParsingFailed extends MetadataExtractionResult {
  const MetadataParsingFailed({super.diagnosticCause});
}

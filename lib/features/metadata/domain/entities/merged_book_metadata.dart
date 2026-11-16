import 'package:bibliolife/features/metadata/domain/entities/extracted_book_metadata.dart';

class MergedBookMetadata {
  MergedBookMetadata({
    required this.metadata,
    required Map<String, String> origins,
  }) : origins = Map.unmodifiable(origins);

  final ExtractedBookMetadata metadata;
  final Map<String, String> origins;
}

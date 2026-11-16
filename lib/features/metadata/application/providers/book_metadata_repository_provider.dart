import 'package:bibliolife/features/metadata/data/repositories/local_book_metadata_repository.dart';
import 'package:bibliolife/features/metadata/domain/repositories/book_metadata_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final bookMetadataRepositoryProvider = Provider<BookMetadataRepository>(
  (ref) => LocalBookMetadataRepository(),
);

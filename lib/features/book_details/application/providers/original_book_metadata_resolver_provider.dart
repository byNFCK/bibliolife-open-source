import 'package:bibliolife/features/book_details/application/services/original_book_metadata_resolver.dart';
import 'package:bibliolife/features/metadata/application/providers/book_metadata_repository_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final originalBookMetadataResolverProvider =
    Provider<OriginalBookMetadataResolver>(
      (ref) => OriginalBookMetadataResolver(
        metadataRepository: ref.watch(bookMetadataRepositoryProvider),
      ),
    );

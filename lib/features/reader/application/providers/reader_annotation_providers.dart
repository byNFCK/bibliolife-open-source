import 'package:bibliolife/features/reader/application/providers/reader_annotation_repository_provider.dart';
import 'package:bibliolife/features/reader/domain/models/reader_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final readerAnnotationsForBookProvider =
    StreamProvider.family<List<ReaderAnnotation>, String>(
      (ref, bookId) =>
          ref.watch(readerAnnotationRepositoryProvider).watchForBook(bookId),
    );

final sortedReaderAnnotationsForBookProvider =
    Provider.family<AsyncValue<List<ReaderAnnotation>>, String>((ref, bookId) {
      return ref.watch(readerAnnotationsForBookProvider(bookId)).whenData((
        annotations,
      ) {
        final sorted = annotations.toList();
        sorted.sort((left, right) {
          final created = right.createdAt.compareTo(left.createdAt);
          return created != 0 ? created : left.id.compareTo(right.id);
        });
        return sorted;
      });
    });

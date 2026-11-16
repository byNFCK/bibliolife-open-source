import 'package:bibliolife/features/reader/application/providers/reader_annotation_repository_provider.dart';
import 'package:bibliolife/features/reader/domain/models/reader_annotation.dart';
import 'package:bibliolife/features/reader/domain/repositories/reader_annotation_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final readerAnnotationMutationControllerProvider =
    AsyncNotifierProvider<ReaderAnnotationMutationController, void>(
      ReaderAnnotationMutationController.new,
    );

class ReaderAnnotationMutationController extends AsyncNotifier<void> {
  @override
  void build() {}

  Future<ReaderAnnotation> insert(ReaderAnnotation annotation) =>
      _run((repository) => repository.insert(annotation));

  Future<ReaderAnnotation> upsert(ReaderAnnotation annotation) =>
      _run((repository) => repository.upsert(annotation));

  Future<ReaderAnnotation> updateNote({
    required String id,
    required String? note,
    required DateTime updatedAt,
  }) => _run(
    (repository) =>
        repository.updateNote(id: id, note: note, updatedAt: updatedAt),
  );

  Future<ReaderAnnotation> updateStyleAndColor({
    required String id,
    ReaderAnnotationStyle? style,
    ReaderAnnotationColor? color,
    required DateTime updatedAt,
  }) => _run(
    (repository) => repository.updateStyleAndColor(
      id: id,
      style: style,
      color: color,
      updatedAt: updatedAt,
    ),
  );

  Future<bool> deleteById(String id) =>
      _run((repository) => repository.deleteById(id));

  Future<bool> deleteByLocation({
    required String bookId,
    required String locationKey,
  }) => _run(
    (repository) =>
        repository.deleteByLocation(bookId: bookId, locationKey: locationKey),
  );

  Future<int> deleteAllForBook(String bookId) =>
      _run((repository) => repository.deleteAllForBook(bookId));

  Future<T> _run<T>(
    Future<T> Function(ReaderAnnotationRepository repository) command,
  ) async {
    state = const AsyncLoading();
    try {
      final result = await command(
        ref.read(readerAnnotationRepositoryProvider),
      );
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

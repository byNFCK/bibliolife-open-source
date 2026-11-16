import 'package:bibliolife/features/reader/domain/models/reader_annotation.dart';

abstract interface class ReaderAnnotationRepository {
  Stream<List<ReaderAnnotation>> watchForBook(String bookId);
  Future<List<ReaderAnnotation>> listForBook(String bookId);
  Future<ReaderAnnotation?> getById(String id);
  Future<ReaderAnnotation?> getByLocation({
    required String bookId,
    required String locationKey,
  });
  Future<ReaderAnnotation> insert(ReaderAnnotation annotation);
  Future<ReaderAnnotation> upsert(ReaderAnnotation annotation);
  Future<ReaderAnnotation> updateNote({
    required String id,
    required String? note,
    required DateTime updatedAt,
  });
  Future<ReaderAnnotation> updateStyleAndColor({
    required String id,
    ReaderAnnotationStyle? style,
    ReaderAnnotationColor? color,
    required DateTime updatedAt,
  });
  Future<bool> deleteById(String id);
  Future<bool> deleteByLocation({
    required String bookId,
    required String locationKey,
  });
  Future<int> deleteAllForBook(String bookId);
}

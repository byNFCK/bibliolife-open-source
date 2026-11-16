import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/reader/data/repositories/drift_reader_annotation_repository.dart';
import 'package:bibliolife/features/reader/domain/repositories/reader_annotation_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final readerAnnotationRepositoryProvider = Provider<ReaderAnnotationRepository>(
  (ref) {
    final database = ref.watch(appDatabaseProvider);
    return DriftReaderAnnotationRepository(database);
  },
);

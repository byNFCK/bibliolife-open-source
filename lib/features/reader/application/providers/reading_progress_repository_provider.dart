import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/reader/data/repositories/drift_reading_progress_repository.dart';
import 'package:bibliolife/features/reader/domain/repositories/reading_progress_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final readingProgressRepositoryProvider = Provider<ReadingProgressRepository>((
  ref,
) {
  final database = ref.watch(appDatabaseProvider);
  return DriftReadingProgressRepository(database.readingProgressDao);
});

import 'package:bibliolife/features/reader/application/providers/reading_progress_repository_provider.dart';
import 'package:bibliolife/features/reader/application/use_cases/delete_reading_progress.dart';
import 'package:bibliolife/features/reader/application/use_cases/save_reading_progress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final saveReadingProgressProvider = Provider<SaveReadingProgress>(
  (ref) => SaveReadingProgress(ref.watch(readingProgressRepositoryProvider)),
);
final deleteReadingProgressProvider = Provider<DeleteReadingProgress>(
  (ref) => DeleteReadingProgress(ref.watch(readingProgressRepositoryProvider)),
);

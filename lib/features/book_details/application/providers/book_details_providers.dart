import 'package:bibliolife/features/reader/application/providers/reading_progress_repository_provider.dart';
import 'package:bibliolife/features/reader/domain/models/reading_progress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final readingProgressForBookProvider =
    StreamProvider.family<ReadingProgress?, String>((ref, bookId) {
      return ref.watch(readingProgressRepositoryProvider).watchForBook(bookId);
    });

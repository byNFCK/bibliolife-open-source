import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/reader/domain/models/reading_progress.dart';
import 'package:drift/drift.dart';

extension ReadingProgressEntryMapper on ReadingProgressEntry {
  ReadingProgress toReadingProgress() {
    return ReadingProgress(
      bookId: bookId,
      locatorJson: locatorJson,
      progression: progression,
      currentChapterTitle: currentChapterTitle,
      currentPage: currentPage,
      totalPages: totalPages,
      updatedAt: updatedAt,
    );
  }
}

extension ReadingProgressMapper on ReadingProgress {
  ReadingProgressEntriesCompanion toReadingProgressCompanion() {
    return ReadingProgressEntriesCompanion.insert(
      bookId: bookId,
      locatorJson: Value(locatorJson),
      progression: Value(progression),
      currentChapterTitle: Value(currentChapterTitle),
      currentPage: Value(currentPage),
      totalPages: Value(totalPages),
      updatedAt: updatedAt,
    );
  }
}

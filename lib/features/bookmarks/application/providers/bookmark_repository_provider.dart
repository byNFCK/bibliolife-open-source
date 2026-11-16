import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/bookmarks/data/repositories/drift_bookmark_repository.dart';
import 'package:bibliolife/features/bookmarks/domain/repositories/bookmark_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final bookmarkRepositoryProvider = Provider<BookmarkRepository>((ref) {
  return DriftBookmarkRepository(ref.watch(appDatabaseProvider).bookmarksDao);
});

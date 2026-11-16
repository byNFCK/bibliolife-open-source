import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:bibliolife/features/library/application/providers/library_providers.dart';

import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// One listener per ProviderScope; recheck visible files after returning to the app.
final _localFileRefreshProvider = Provider<Object>((ref) {
  final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
  ref.onDispose(lifecycle.dispose);
  return Object();
});

typedef LocalBookFile = ({String path, BookFormat format, int size});

/// Derived from the imported library file, never from reading/download progress.
/// Shared by Grid/List instances of a file, without another database lookup.
final localBookFileAvailableProvider = FutureProvider.autoDispose
    .family<bool, LocalBookFile>((ref, source) async {
      ref.watch(_localFileRefreshProvider);
      if (source.path.trim().isEmpty ||
          source.format == BookFormat.unknown ||
          source.size <= 0 ||
          BookFormat.fromFileName(source.path) != source.format) {
        return false;
      }
      try {
        final file = File(source.path);
        final stat = await file.stat();
        if (stat.type != FileSystemEntityType.file ||
            stat.size != source.size) {
          return false;
        }
        final handle = await file.open();
        await handle.close();
        return true;
      } on FileSystemException {
        return false;
      } on ArgumentError {
        return false;
      }
    });

int? availableBookReadingProgress(
  WidgetRef ref,
  LibraryBook? book,
  int? percent,
) {
  if (book == null) return null;
  final available =
      ref
          .watch(
            localBookFileAvailableProvider((
              path: book.filePath,
              format: book.format,
              size: book.fileSizeBytes,
            )),
          )
          .asData
          ?.value ==
      true;
  return available ? (percent ?? 0).clamp(0, 100) : null;
}

// Read-only, shared exact provenance index. No title guesses, no requests.
final catalogLocalBooksProvider =
    Provider<Map<(String, String), LibraryBook?>?>((ref) {
      final books = ref.watch(allBooksProvider).asData?.value;
      if (books == null) return null;
      final result = <(String, String), LibraryBook?>{};
      for (final book in books) {
        final source = book.catalogSourceId;
        final remote = book.remotePublicationId;
        if (source == null ||
            source.isEmpty ||
            remote == null ||
            remote.isEmpty) {
          continue;
        }
        final key = (source, remote);
        result[key] = result.containsKey(key) ? null : book;
      }
      return result;
    });

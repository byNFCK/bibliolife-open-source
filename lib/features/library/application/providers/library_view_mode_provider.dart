import 'dart:async';
import 'dart:developer' as developer;

import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/library/data/repositories/drift_book_display_settings_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LibraryViewMode { grid, list }

final bookDisplaySettingsRepositoryProvider = Provider(
  (ref) => DriftBookDisplaySettingsRepository(ref.watch(appDatabaseProvider)),
);

// Reuse the existing application-scoped state for both Library and Settings.
final libraryViewModeProvider =
    NotifierProvider<LibraryViewModeNotifier, LibraryViewMode>(
      LibraryViewModeNotifier.new,
    );

class LibraryViewModeNotifier extends Notifier<LibraryViewMode> {
  int _revision = 0;
  LibraryViewMode _savedMode = LibraryViewMode.grid;
  Future<void> _pending = Future.value();
  late Future<void> ready;

  @override
  LibraryViewMode build() {
    ready = _load();
    _pending = ready;
    return LibraryViewMode.grid;
  }

  Future<void> _load() async {
    final revision = _revision;
    try {
      final stored = await ref
          .read(bookDisplaySettingsRepositoryProvider)
          .load();
      if (!ref.mounted) return;
      _savedMode = stored == 'list'
          ? LibraryViewMode.list
          : LibraryViewMode.grid;
      if (revision == _revision) state = _savedMode;
    } catch (error, stackTrace) {
      developer.log(
        'Could not load book display layout',
        name: 'BookDisplaySettings',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> toggle() => setMode(
    state == LibraryViewMode.grid ? LibraryViewMode.list : LibraryViewMode.grid,
  );

  Future<void> setMode(LibraryViewMode mode) {
    final revision = ++_revision;
    final repository = ref.read(bookDisplaySettingsRepositoryProvider);
    state = mode;
    // Serialize rapid changes so an older write cannot win on disk.
    final save = _pending.then((_) async {
      await repository.save(mode.name);
      _savedMode = mode;
    });
    _pending = save.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return save.catchError((Object error, StackTrace stack) {
      if (ref.mounted && revision == _revision) state = _savedMode;
      Error.throwWithStackTrace(error, stack);
    });
  }
}

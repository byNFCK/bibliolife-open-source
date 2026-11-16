import 'dart:async';

import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/library/data/repositories/drift_library_section_settings_repository.dart';
import 'package:bibliolife/features/library/domain/library_section.dart';
import 'package:bibliolife/features/library/domain/library_section_settings_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:bibliolife/features/library/domain/library_section.dart';

final librarySectionSettingsRepositoryProvider =
    Provider<LibrarySectionSettingsRepository>(
      (ref) => DriftLibrarySectionSettingsRepository(
        ref.watch(appDatabaseProvider).librarySectionSettingsDao,
      ),
    );

final defaultLibrarySectionProvider =
    AsyncNotifierProvider<DefaultLibrarySectionNotifier, LibrarySection>(
      DefaultLibrarySectionNotifier.new,
    );

class DefaultLibrarySectionNotifier extends AsyncNotifier<LibrarySection> {
  @override
  FutureOr<LibrarySection> build() =>
      ref.read(librarySectionSettingsRepositoryProvider).load();

  Future<void> setDefault(LibrarySection section) async {
    final previous = state;
    state = AsyncData(section);
    try {
      await ref.read(librarySectionSettingsRepositoryProvider).save(section);
    } catch (error, stackTrace) {
      state = previous;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

final librarySectionProvider =
    NotifierProvider<LibrarySectionNotifier, LibrarySection>(
      LibrarySectionNotifier.new,
    );

class LibrarySectionNotifier extends Notifier<LibrarySection> {
  var _initialized = false;

  @override
  LibrarySection build() => LibrarySection.allBooks;

  void select(LibrarySection section) {
    _initialized = true;
    if (state == section) return;
    state = section;
  }

  void initializeFromDefault(LibrarySection section) {
    if (_initialized) return;
    _initialized = true;
    state = section;
  }

  bool get isInitialized => _initialized;
}

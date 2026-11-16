import 'package:bibliolife/features/library/domain/library_section.dart';

abstract interface class LibrarySectionSettingsRepository {
  Future<LibrarySection> load();

  Future<void> save(LibrarySection section);
}

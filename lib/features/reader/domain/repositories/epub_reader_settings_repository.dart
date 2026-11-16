import 'package:bibliolife/features/reader/domain/models/epub_reader_settings.dart';

abstract interface class EpubReaderSettingsRepository {
  Future<EpubReaderSettings> load();
  Future<void> save(EpubReaderSettings settings);
  Future<void> reset();
}

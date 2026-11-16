import 'package:bibliolife/features/reader/domain/models/epub_reader_settings.dart';
import 'package:bibliolife/features/reader/domain/repositories/epub_reader_settings_repository.dart';

class FakeEpubReaderSettingsRepository implements EpubReaderSettingsRepository {
  FakeEpubReaderSettingsRepository({
    EpubReaderSettings? initial,
    this.loadError,
    this.saveError,
  }) : _settings = initial ?? EpubReaderSettings.defaults;

  EpubReaderSettings _settings;
  final Object? loadError;
  final Object? saveError;
  int loadCount = 0;
  int saveCount = 0;
  EpubReaderSettings? lastSaved;

  @override
  Future<EpubReaderSettings> load() async {
    loadCount += 1;
    if (loadError != null) throw loadError!;
    return _settings;
  }

  @override
  Future<void> reset() async {
    _settings = EpubReaderSettings.defaults;
  }

  @override
  Future<void> save(EpubReaderSettings settings) async {
    saveCount += 1;
    lastSaved = settings.normalized();
    if (saveError != null) throw saveError!;
    _settings = settings.normalized();
  }
}

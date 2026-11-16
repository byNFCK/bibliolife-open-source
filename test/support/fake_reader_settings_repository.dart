import 'package:bibliolife/features/reader/domain/models/reader_settings.dart';
import 'package:bibliolife/features/reader/domain/repositories/reader_settings_repository.dart';

class FakeReaderSettingsRepository implements ReaderSettingsRepository {
  FakeReaderSettingsRepository({
    Map<ReaderSettingsProfile, ReaderSettingsState>? initial,
  }) : values = {...?initial};

  final Map<ReaderSettingsProfile, ReaderSettingsState> values;
  int loadCount = 0;
  int saveCount = 0;

  @override
  Future<ReaderSettingsState?> load(ReaderSettingsProfile profile) async {
    loadCount++;
    return values[profile];
  }

  @override
  Future<void> save(ReaderSettingsState settings) async {
    saveCount++;
    values[settings.profile] = settings;
  }
}

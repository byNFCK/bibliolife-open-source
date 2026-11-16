import 'package:bibliolife/features/reader/domain/models/reader_settings.dart';

abstract interface class ReaderSettingsRepository {
  Future<ReaderSettingsState?> load(ReaderSettingsProfile profile);
  Future<void> save(ReaderSettingsState settings);
}

class EmptyReaderSettingsRepository implements ReaderSettingsRepository {
  const EmptyReaderSettingsRepository();

  @override
  Future<ReaderSettingsState?> load(ReaderSettingsProfile profile) async =>
      null;

  @override
  Future<void> save(ReaderSettingsState settings) async {}
}

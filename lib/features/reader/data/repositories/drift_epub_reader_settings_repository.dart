import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/reader/domain/models/epub_reader_settings.dart';
import 'package:bibliolife/features/reader/domain/repositories/epub_reader_settings_repository.dart';
import 'package:drift/drift.dart';

class DriftEpubReaderSettingsRepository
    implements EpubReaderSettingsRepository {
  const DriftEpubReaderSettingsRepository(this._dao);
  final EpubReaderSettingsDao _dao;

  @override
  Future<EpubReaderSettings> load() async {
    final row = await _dao.load();
    if (row == null) return EpubReaderSettings.defaults;
    return EpubReaderSettings.fromJson({
      'theme': row.theme,
      'fontSize': row.fontSize,
      'lineHeight': row.lineHeight,
      'pageMargins': row.pageMargins,
      'publisherStyles': row.publisherStyles,
    });
  }

  @override
  Future<void> save(EpubReaderSettings settings) {
    final value = settings.normalized();
    return _dao.upsert(
      EpubReaderSettingsEntriesCompanion(
        id: const Value(1),
        theme: Value(value.theme.name),
        fontSize: Value(value.fontSize),
        lineHeight: Value(value.lineHeight),
        pageMargins: Value(value.pageMargins),
        publisherStyles: Value(value.publisherStyles),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> reset() => _dao.deleteSettings();
}

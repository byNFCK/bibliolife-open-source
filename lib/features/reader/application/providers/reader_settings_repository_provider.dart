import 'package:bibliolife/features/reader/data/repositories/file_reader_settings_repository.dart';
import 'package:bibliolife/features/reader/domain/repositories/reader_settings_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final readerSettingsRepositoryProvider = Provider<ReaderSettingsRepository>(
  (ref) => FileReaderSettingsRepository(getApplicationSupportDirectory),
);

import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/reader/data/repositories/drift_epub_reader_settings_repository.dart';
import 'package:bibliolife/features/reader/domain/repositories/epub_reader_settings_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final epubReaderSettingsRepositoryProvider =
    Provider<EpubReaderSettingsRepository>(
      (ref) => DriftEpubReaderSettingsRepository(
        ref.watch(appDatabaseProvider).epubReaderSettingsDao,
      ),
    );

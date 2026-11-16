import 'package:bibliolife/features/reader/domain/models/epub_reader_settings.dart';
import 'package:bibliolife/features/reader/domain/models/reader_settings.dart';
import 'package:bibliolife_readium/bibliolife_readium.dart';

extension EpubReaderSettingsReadiumMapper on EpubReaderSettings {
  ReadiumEpubPreferences toReadiumPreferences() {
    final settings = normalized();
    return ReadiumEpubPreferences(
      theme: switch (settings.theme) {
        EpubReaderTheme.system => 'system',
        EpubReaderTheme.light => 'light',
        EpubReaderTheme.dark => 'dark',
        EpubReaderTheme.sepia => 'sepia',
      },
      fontFamily: settings.fontFamily.name,
      fontSize: settings.fontSize,
      fontWeight: settings.fontWeight,
      lineHeight: settings.lineHeight,
      pageMargins: settings.pageMargins,
      textAlignment: settings.textAlignment.name,
      scroll: settings.readingMode.name == 'continuous',
      columns: settings.columns.name,
      publisherStyles: settings.publisherStyles,
    );
  }
}

extension ReadiumPreferencesSettingsMapper on ReadiumEpubPreferences {
  EpubReaderSettings toEpubReaderSettings() => EpubReaderSettings(
    theme: switch (theme) {
      'system' => EpubReaderTheme.system,
      'light' => EpubReaderTheme.light,
      'dark' => EpubReaderTheme.dark,
      'sepia' => EpubReaderTheme.sepia,
      _ => EpubReaderTheme.system,
    },
    fontFamily: ReaderFontFamily.values.firstWhere(
      (value) => value.name == fontFamily,
      orElse: () => ReaderFontFamily.original,
    ),
    fontSize: fontSize,
    fontWeight: fontWeight,
    lineHeight: lineHeight,
    pageMargins: pageMargins,
    textAlignment: ReaderTextAlignment.values.firstWhere(
      (value) => value.name == textAlignment,
      orElse: () => ReaderTextAlignment.start,
    ),
    readingMode: scroll
        ? ReaderReadingMode.continuous
        : ReaderReadingMode.paginated,
    columns: ReaderColumnCount.values.firstWhere(
      (value) => value.name == columns,
      orElse: () => ReaderColumnCount.auto,
    ),
    publisherStyles: publisherStyles,
  ).normalized();
}

import 'package:bibliolife/features/reader/application/mappers/epub_reader_settings_readium_mapper.dart';
import 'package:bibliolife/features/reader/domain/models/epub_reader_settings.dart';
import 'package:bibliolife/features/reader/domain/models/reader_settings.dart';
import 'package:bibliolife_readium/bibliolife_readium.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const themes = <EpubReaderTheme>[
    EpubReaderTheme.system,
    EpubReaderTheme.light,
    EpubReaderTheme.dark,
    EpubReaderTheme.sepia,
  ];

  group('EpubReaderSettingsReadiumMapper', () {
    test('maps every expanded native reflowable preference', () {
      final preferences = const EpubReaderSettings(
        theme: EpubReaderTheme.sepia,
        fontFamily: ReaderFontFamily.dyslexic,
        fontSize: 1.4,
        fontWeight: 1.2,
        lineHeight: 1.8,
        pageMargins: 2,
        textAlignment: ReaderTextAlignment.justify,
        readingMode: ReaderReadingMode.continuous,
        columns: ReaderColumnCount.two,
        publisherStyles: false,
      ).toReadiumPreferences();

      expect(preferences.fontFamily, 'dyslexic');
      expect(preferences.fontWeight, 1.2);
      expect(preferences.textAlignment, 'justify');
      expect(preferences.scroll, isTrue);
      expect(preferences.columns, 'two');
      expect(
        preferences.toEpubReaderSettings().toReadiumPreferences(),
        preferences,
      );
    });
    test('maps defaults', () {
      expect(
        EpubReaderSettings.defaults.toReadiumPreferences(),
        const ReadiumEpubPreferences(),
      );
    });

    for (final theme in themes) {
      test('maps $theme and all scalar values to Readium preferences', () {
        final preferences = EpubReaderSettings(
          theme: theme,
          fontSize: 1.4,
          lineHeight: 1.8,
          pageMargins: 2.0,
          publisherStyles: false,
        ).toReadiumPreferences();

        expect(preferences.theme, theme.name);
        expect(preferences.fontSize, 1.4);
        expect(preferences.lineHeight, 1.8);
        expect(preferences.pageMargins, 2.0);
        expect(preferences.publisherStyles, isFalse);
      });
    }

    for (final theme in themes) {
      test('maps Readium $theme preferences back to settings', () {
        final settings = ReadiumEpubPreferences(
          theme: theme.name,
          fontSize: 1.4,
          lineHeight: 1.8,
          pageMargins: 2.0,
          publisherStyles: false,
        ).toEpubReaderSettings();

        expect(settings.theme, theme);
        expect(settings.fontSize, 1.4);
        expect(settings.lineHeight, 1.8);
        expect(settings.pageMargins, 2.0);
        expect(settings.publisherStyles, isFalse);
      });
    }

    for (final theme in themes) {
      test('round-trips normalized $theme settings', () {
        final settings = EpubReaderSettings(
          theme: theme,
          fontSize: 8,
          lineHeight: 0,
          pageMargins: -1,
          publisherStyles: false,
        );

        expect(
          settings.toReadiumPreferences().toEpubReaderSettings(),
          settings.normalized(),
        );
      });
    }

    test('unknown Readium themes normalize to system', () {
      expect(
        const ReadiumEpubPreferences(
          theme: 'unexpected',
        ).toEpubReaderSettings().theme,
        EpubReaderTheme.system,
      );
    });
  });
}

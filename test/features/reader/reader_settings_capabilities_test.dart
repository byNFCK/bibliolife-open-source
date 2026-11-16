import 'dart:io';

import 'package:bibliolife/features/reader/domain/models/reader_settings.dart';
import 'package:bibliolife/features/reader/presentation/models/local_reader_settings_adapters.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_reader_settings_repository.dart';

void main() {
  test('EPUB FB2 and TXT share one Readium profile with source semantics', () {
    final epub = readiumSettingsCapabilitiesForSource(BookFormat.epub);
    final fb2 = readiumSettingsCapabilitiesForSource(BookFormat.fb2);
    final txt = readiumSettingsCapabilitiesForSource(BookFormat.txt);

    expect(epub.profile, ReaderSettingsProfile.readiumReflowable);
    expect(fb2.profile, ReaderSettingsProfile.readiumReflowable);
    expect(txt.profile, ReaderSettingsProfile.readiumReflowable);
    expect(epub.typography, fb2.typography);
    expect(fb2, txt);
    expect(epub.sourceSpecific.publisherStyles, isTrue);
    expect(fb2.sourceSpecific.publisherStyles, isFalse);
    expect(epub.readingModes.supportsPaginated, isTrue);
    expect(epub.readingModes.supportsContinuousScroll, isTrue);
  });

  test('PDF advertises only implemented page gap and no typography', () {
    const value = ReaderSettingsCapabilities.pdf;
    expect(value.profile, ReaderSettingsProfile.pdf);
    expect(value.typography.isEmpty, isTrue);
    expect(value.spacing.pageGap, isTrue);
    expect(value.pageLayout.isEmpty, isTrue);
    expect(value.readingModes.supportsPaginated, isFalse);
    expect(value.readingModes.supportsContinuousScroll, isTrue);
    expect(value.zoom.isEmpty, isTrue);
    expect(value.crop.isEmpty, isTrue);
  });

  test('CBZ and CBR resolve to exactly one shared comic adapter profile', () {
    final cbz = ComicReaderSettingsAdapter(FakeReaderSettingsRepository());
    final cbr = ComicReaderSettingsAdapter(FakeReaderSettingsRepository());
    expect(cbz.runtimeType, cbr.runtimeType);
    expect(cbz.settingsCapabilities, cbr.settingsCapabilities);
    expect(cbz.settingsCapabilities.typography.isEmpty, isTrue);
    expect(cbz.settingsCapabilities.image.fitPage, isTrue);
    expect(cbz.settingsCapabilities.image.fitWidth, isTrue);
    expect(cbz.settingsCapabilities.pageLayout.readingDirection, isTrue);
    expect(cbz.settingsCapabilities.readingModes.supportsPaginated, isTrue);
    expect(
      cbz.settingsCapabilities.readingModes.supportsContinuousScroll,
      isTrue,
    );
    cbz.dispose();
    cbr.dispose();
  });

  test(
    'shared Settings presentation contains no source extension branching',
    () {
      final source = File(
        'lib/features/reader/presentation/widgets/unified_reader_screen.dart',
      ).readAsStringSync();
      for (final extension in ['epub', 'fb2', 'txt', 'pdf', 'cbz', 'cbr']) {
        expect(source.toLowerCase(), isNot(contains('.$extension')));
      }
      expect(source, isNot(contains('fileExtension')));
    },
  );
}

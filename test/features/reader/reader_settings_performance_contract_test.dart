import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'presentation settings do not reopen PDF or re-extract Comic archives',
    () {
      final source = File(
        'lib/features/reader/presentation/screens/local_reader_body.dart',
      ).readAsStringSync();

      expect(RegExp(r'PdfDocument\.openFile').allMatches(source), hasLength(1));
      expect(
        RegExp(r'ComicArchiveService\(\)\.prepare').allMatches(source),
        hasLength(1),
      );
      expect(
        source,
        contains('padding: widget.ui.readerSettings?.state.spacing?.pageGap'),
      );
      expect(
        source,
        contains('page.readingMode == ReaderReadingMode.continuous'),
      );
      expect(
        source,
        contains('page.readingDirection == ReaderReadingDirection.rightToLeft'),
      );
      expect(source, contains('fit == ReaderImageFit.width'));
      expect(
        RegExp(r'_scheduleLogicalPageRestore\(\);').allMatches(source),
        hasLength(2),
        reason:
            'Comic restores the logical page after both settings changes and initial archive load',
      );
    },
  );

  test(
    'Readium preview path updates preferences without rebuilding a controller',
    () {
      final source = File(
        'lib/features/reader/presentation/models/readium_epub_reader_controller.dart',
      ).readAsStringSync();
      expect(RegExp(r'_controllerBuilder\(').allMatches(source), hasLength(1));
      expect(source, contains('controller.applyPreferences('));
      expect(source, isNot(contains('ReflowableReadiumPublicationService')));
    },
  );
}

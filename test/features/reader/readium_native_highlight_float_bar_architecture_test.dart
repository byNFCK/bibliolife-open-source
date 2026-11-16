import 'dart:io';

import 'package:bibliolife/features/reader/domain/models/reader_capabilities.dart';
import 'package:bibliolife/features/reader/domain/models/reader_kind.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'EPUB uses the unified Readium viewport and native interaction owner',
    () {
      expect(readerKindFor(BookFormat.epub), ReaderKind.epub);
      expect(
        readerPresentationFor(BookFormat.epub),
        ReaderPresentation.readiumFlutter,
      );

      final capabilities = ReaderCapabilities.forKind(ReaderKind.epub);
      expect(capabilities.supportsNativeContentTap, isTrue);
      expect(capabilities.supportsHighlights, isTrue);
      expect(capabilities.supportsDecorationActivation, isTrue);
      expect(capabilities.supportsSearch, isTrue);
    },
  );

  test(
    'direct decoration activation has no Flutter editor route while saved items retains it',
    () {
      final localBody = File(
        'lib/features/reader/presentation/screens/local_reader_body.dart',
      ).readAsStringSync();
      final coordinator = File(
        'lib/features/reader/application/services/readium_epub_annotation_coordinator.dart',
      ).readAsStringSync();
      final savedItems = File(
        'lib/features/reader/presentation/widgets/reader_saved_items_sheet.dart',
      ).readAsStringSync();
      final platformView = File(
        'packages/bibliolife_readium/android/src/main/kotlin/app/bibliolife/reader/readium/ReadiumPlatformView.kt',
      ).readAsStringSync();

      expect(localBody, isNot(contains('ReaderAnnotationEditorSheet')));
      expect(coordinator, isNot(contains('decorationActivations.listen')));
      expect(coordinator, contains('annotationActionRequests.listen'));
      expect(savedItems, contains('ReaderAnnotationEditorSheet'));
      expect(
        'ReaderHighlightToolbarPresenter('.allMatches(platformView),
        hasLength(1),
      );
      expect(
        platformView,
        contains('ReadiumPersistentHighlightActivationListener'),
      );
      expect(
        platformView,
        contains(
          'ReadiumDecorationGroup.SEARCH_RESULT.nativeName, activationListener',
        ),
      );
    },
  );
}

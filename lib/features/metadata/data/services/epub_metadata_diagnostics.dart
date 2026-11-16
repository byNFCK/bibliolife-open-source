import 'dart:developer' as developer;

import 'package:bibliolife/features/metadata/data/services/epub_title_quality_evaluator.dart';

/// Debug-only, privacy-safe metadata boundary diagnostics.
class EpubMetadataDiagnostics {
  const EpubMetadataDiagnostics._();

  static void log({
    required String stage,
    required String field,
    required String source,
    required String? value,
  }) {
    assert(() {
      final safeValue = value ?? '';
      final prefix = safeValue.runes
          .take(24)
          .map((rune) => 'U+${rune.toRadixString(16).padLeft(4, '0')}')
          .join(' ');
      final suspicious = RegExp(r'[ÐÑРСâ�]').hasMatch(safeValue);
      developer.log(
        'field=$field source=$source length=${safeValue.runes.length} '
        'suspicious=$suspicious replacement=${safeValue.contains('\uFFFD')} '
        'prefix=$prefix',
        name: 'EPUB_METADATA_$stage',
      );
      return true;
    }());
  }

  static void logTitleSelection(EpubTitleSelection selection) {
    assert(() {
      developer.log(
        'metadataQuality=${selection.metadata.quality.name} '
        'issues=${selection.metadata.issues.map((issue) => issue.name).join(',')} '
        'confidence=${selection.metadata.confidence.toStringAsFixed(2)} '
        'filenameQuality=${selection.filename.quality.name}',
        name: 'EPUB_TITLE_ASSESSED',
      );
      developer.log(
        'source=${selection.source?.name ?? 'none'}',
        name: 'EPUB_TITLE_SELECTED',
      );
      return true;
    }());
  }

  static void logImportStage(String stage) {
    assert(() {
      developer.log('stage=$stage', name: 'EPUB_IMPORT_STAGE');
      return true;
    }());
  }

  static void logImportFailure(String stage, Object error) {
    assert(() {
      developer.log(
        'stage=$stage exceptionType=${error.runtimeType} reason=handled_import_failure',
        name: 'EPUB_IMPORT_FAILED',
      );
      return true;
    }());
  }

  static void logCoverFailure(String reason) {
    assert(() {
      developer.log('reason=$reason', name: 'EPUB_COVER_IMPORT_FAILED');
      return true;
    }());
  }

  static void logFilenameSource({
    required String source,
    required String? filename,
    required EpubTitleAssessment assessment,
  }) {
    assert(() {
      final prefix = (filename ?? '').runes
          .take(12)
          .map((rune) => 'U+${rune.toRadixString(16).padLeft(4, '0')}')
          .join(' ');
      developer.log(
        'source=$source originalAvailable=${filename?.isNotEmpty == true} '
        'quality=${assessment.quality.name} derivedLength=${filename?.runes.length ?? 0} '
        'prefix=$prefix',
        name: 'EPUB_FILENAME_SOURCE',
      );
      return true;
    }());
  }
}

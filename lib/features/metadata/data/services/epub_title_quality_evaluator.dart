import 'package:bibliolife/features/metadata/data/services/epub_metadata_normalizer.dart';

enum EpubTitleQuality { valid, suspicious, unusable }

enum EpubTitleIssue {
  empty,
  controlCharacters,
  replacementCharacters,
  uuidLike,
  hashLike,
  longAlphanumericToken,
  identifierLike,
  mojibake,
  placeholderTitle,
}

enum BookTitleSource {
  epubMetadata,
  recoveredMetadata,
  filenameFallback,
  stableFallback,
}

class EpubTitleAssessment {
  const EpubTitleAssessment({
    required this.quality,
    required this.issues,
    required this.confidence,
  });

  final EpubTitleQuality quality;
  final Set<EpubTitleIssue> issues;
  final double confidence;
}

class EpubTitleSelection {
  const EpubTitleSelection({
    required this.title,
    required this.source,
    required this.metadata,
    required this.filename,
  });

  final String? title;
  final BookTitleSource? source;
  final EpubTitleAssessment metadata;
  final EpubTitleAssessment filename;
}

/// Conservative, Unicode-safe validation of a decoded EPUB title.
class EpubTitleQualityEvaluator {
  const EpubTitleQualityEvaluator._();

  static const unusableThreshold = 0.9;

  static EpubTitleAssessment assess(String? value) {
    final rawValue = value ?? '';
    final title = EpubMetadataNormalizer.text(value);
    final issues = <EpubTitleIssue>{};
    if (title == null) {
      return const EpubTitleAssessment(
        quality: EpubTitleQuality.unusable,
        issues: {EpubTitleIssue.empty},
        confidence: 1,
      );
    }
    if (rawValue.runes.any(
      (rune) => rune < 0x20 && rune != 0x09 && rune != 0x0a,
    )) {
      issues.add(EpubTitleIssue.controlCharacters);
    }
    if (title.contains('\uFFFD')) {
      issues.add(EpubTitleIssue.replacementCharacters);
    }

    final compact = title.replaceAll(RegExp(r'\s+'), '');
    final lower = title.toLowerCase();
    if (_uuid.hasMatch(title) || _urnUuid.hasMatch(title)) {
      issues.add(EpubTitleIssue.uuidLike);
    } else if (RegExp(
      r'^[0-9a-f]{32}(?:[0-9a-f]{32})?$',
      caseSensitive: false,
    ).hasMatch(compact)) {
      issues.add(EpubTitleIssue.hashLike);
    } else if (_identifier.hasMatch(title) ||
        RegExp(r'^\d{13}$').hasMatch(compact)) {
      issues.add(EpubTitleIssue.identifierLike);
    } else if (_machineToken.hasMatch(title)) {
      issues.add(EpubTitleIssue.longAlphanumericToken);
    }
    if (_placeholders.contains(lower)) {
      issues.add(EpubTitleIssue.placeholderTitle);
    }
    if (RegExp(r'[ÐÑРСâ�]').allMatches(title).length >= 2) {
      issues.add(EpubTitleIssue.mojibake);
    }

    // The classifier is Unicode-aware: Cyrillic letters themselves are never
    // mojibake evidence. Keep only byte-looking Latin-1 marker characters.
    issues.remove(EpubTitleIssue.mojibake);
    if (RegExp('[\u00d0\u00d1\u00e2\uFFFD]').allMatches(title).length >= 2) {
      issues.add(EpubTitleIssue.mojibake);
    }

    final definitive = issues.intersection({
      EpubTitleIssue.empty,
      EpubTitleIssue.controlCharacters,
      EpubTitleIssue.replacementCharacters,
      EpubTitleIssue.uuidLike,
      EpubTitleIssue.hashLike,
      EpubTitleIssue.identifierLike,
      EpubTitleIssue.longAlphanumericToken,
      EpubTitleIssue.placeholderTitle,
      EpubTitleIssue.mojibake,
    });
    if (definitive.isNotEmpty) {
      return EpubTitleAssessment(
        quality: EpubTitleQuality.unusable,
        issues: Set.unmodifiable(issues),
        confidence: 0.96,
      );
    }
    return EpubTitleAssessment(
      quality: EpubTitleQuality.valid,
      issues: Set.unmodifiable(issues),
      confidence: 1,
    );
  }

  static EpubTitleSelection select({
    required String? metadataTitle,
    required String? filename,
  }) {
    final normalized = EpubMetadataNormalizer.text(metadataTitle);
    final recovered = normalized == null
        ? null
        : recoverUtf8MojibakeIfConfident(normalized);
    final metadata = assess(recovered);
    final filenameTitle = deriveTitleFromFilename(filename);
    final filenameAssessment = assess(filenameTitle);
    if (metadata.quality == EpubTitleQuality.valid && recovered != null) {
      return EpubTitleSelection(
        title: recovered,
        source: recovered == normalized
            ? BookTitleSource.epubMetadata
            : BookTitleSource.recoveredMetadata,
        metadata: metadata,
        filename: filenameAssessment,
      );
    }
    if (metadata.quality == EpubTitleQuality.unusable &&
        metadata.confidence >= unusableThreshold &&
        filenameAssessment.quality == EpubTitleQuality.valid &&
        filenameTitle != null) {
      return EpubTitleSelection(
        title: filenameTitle,
        source: BookTitleSource.filenameFallback,
        metadata: metadata,
        filename: filenameAssessment,
      );
    }
    return EpubTitleSelection(
      title: recovered ?? 'Unknown title',
      source: recovered == null
          ? BookTitleSource.stableFallback
          : BookTitleSource.epubMetadata,
      metadata: metadata,
      filename: filenameAssessment,
    );
  }

  static String? deriveTitleFromFilename(String? filename) {
    if (filename == null || filename.isEmpty) return null;
    final finalSegment = filename.replaceAll('\\', '/').split('/').last;
    var decoded = finalSegment;
    // A display name is already Unicode in the common picker path. Decode
    // only explicit percent encoding and never let malformed URI input abort
    // title selection.
    if (finalSegment.contains('%')) {
      try {
        decoded = Uri.decodeComponent(finalSegment);
      } on FormatException {
        decoded = finalSegment;
      } on ArgumentError {
        decoded = finalSegment;
      }
    }
    final withoutExtension = decoded.replaceFirst(
      RegExp(r'\.epub$', caseSensitive: false),
      '',
    );
    return EpubMetadataNormalizer.text(
      withoutExtension
          .replaceAll(RegExp(r'[_]+'), ' ')
          .replaceAll(RegExp(r'-{2,}'), ' ')
          .replaceAll(RegExp(r'\.{2,}'), ' '),
    );
  }

  static final _uuid = RegExp(
    r'^\{?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}?$',
    caseSensitive: false,
  );
  static final _urnUuid = RegExp(
    r'^urn:uuid:[0-9a-f-]{36}$',
    caseSensitive: false,
  );
  static final _identifier = RegExp(
    r'^(?:book|item)[_-]\d{6,}$|^[a-z][a-z0-9]*(?:\.[a-z][a-z0-9]*){2,}(?:\.\d+)?$',
    caseSensitive: false,
  );
  static final _machineToken = RegExp(
    r'^(?=.{20,}$)(?=.*[a-z])(?=.*[A-Z])(?=.*\d)[A-Za-z\d]+$',
  );
  static const _placeholders = {
    'unknown',
    'untitled',
    'no title',
    'ebook',
    'book',
    'document',
    'default',
  };
}

import 'package:xml/xml.dart';

/// Pure, conservative cleanup for descriptions from EPUB and remote catalogs.
class BookDescriptionSanitizer {
  const BookDescriptionSanitizer._();

  static const maxDescriptionLength = 20000;

  static final _generatedSummaryMarker = RegExp(
    r'^\s*\(?\s*this\s+is\s+an\s+automatically\s+generated\s+summary\s*[.!]?\s*\)?\s*$',
    caseSensitive: false,
  );

  static final _generatedSummaryMarkerInline = RegExp(
    r'\(?\s*this\s+is\s+an\s+automatically\s+generated\s+summary\s*[.!]?\s*\)?',
    caseSensitive: false,
  );

  static final _metadataLine = RegExp(
    r'^\s*(?:[-*•]\s*)?(?:reading\s+level|authors?|downloads?(?:\s+count)?|languages?|subjects?|loc\s*(?:class|no\.)|library\s+of\s+congress\s+classification|release\s+date|posting\s+date|updated|copyright\s+status|rights|credits|produced\s+by|ebook\s*(?:-|\s*)no\.?|project\s+gutenberg\s+release\s+number)\s*(?::\s*.*)?$',
    caseSensitive: false,
  );

  static final _bibliographicLine = RegExp(
    r'^\s*(?:[-*]\s*)?(?:title|notes?|reading\s+level|authors?|downloads?(?:\s+count)?|languages?|subjects?|keywords?|identifiers?|isbn|publisher|source|file(?:\s+name|\s+size)?|media\s+type|encoding|modified|publication\s+date|loc\s*(?:class|no\.)|library\s+of\s+congress\s+classification|release\s+date|posting\s+date|updated|copyright\s+status|rights|credits?|produced\s+by|ebook\s*(?:-|\s*)no\.?|project\s+gutenberg\s+release\s+number)\s*(?::\s*.*)?$',
    caseSensitive: false,
  );

  static final _inlineSummary = RegExp(
    r'(?:^|\s)summary\s*:\s*',
    caseSensitive: false,
  );

  static final _standaloneLink = RegExp(
    r'^\s*(?:(?:wikipedia|more\s+information|project\s+gutenberg|source)\s*:\s*)?https?://\S+\s*$',
    caseSensitive: false,
  );

  static final _editionNote = RegExp(
    r'^\s*(?:(?:the|this)\s+edition\s+has\s+(?:an?\s+)?(?:image|images|illustration|illustrations).*|illustrated\s+edition.*)\s*$',
    caseSensitive: false,
  );

  static final _productionNote = RegExp(
    r'^\s*(?:credits?|produced|transcribed)\s*(?::|\s+by\b).*$',
    caseSensitive: false,
  );

  /// Strips unsafe markup, normalizes text, and removes only recognized
  /// Gutenberg-style generated tails.
  static String? sanitize(String? value) {
    final cleaned = _clean(value);
    if (cleaned == null) return null;
    final plainText = cleaned.contains('<') ? _stripMarkup(cleaned) : cleaned;
    var candidate = _clean(plainText);
    final summary = candidate == null
        ? null
        : _inlineSummary.firstMatch(candidate);
    if (summary != null) {
      candidate = _clean(candidate!.substring(summary.end));
    }
    candidate = _removeLeadingBibliography(candidate);
    candidate = _removeTrailingBibliography(candidate);
    if (_isBibliographicDump(candidate)) return null;
    return _truncate(candidate);
  }

  static String? _removeLeadingBibliography(String? value) {
    if (value == null) return null;
    final lines = value.split('\n');
    var index = 0;
    while (index < lines.length) {
      final line = lines[index].trim();
      if (line.isEmpty) {
        index++;
        continue;
      }
      final metadata = _bibliographicLine.hasMatch(line);
      final labelOnly = metadata && !line.contains(':');
      if (metadata ||
          _standaloneLink.hasMatch(line) ||
          _editionNote.hasMatch(line) ||
          _productionNote.hasMatch(line)) {
        index++;
        if (labelOnly && index < lines.length) {
          final valueLine = lines[index].trim();
          if (valueLine.isNotEmpty && valueLine.length <= 200) index++;
        }
        continue;
      }
      break;
    }
    return _clean(lines.skip(index).join('\n'));
  }

  static bool _isBibliographicDump(String? value) {
    if (value == null) return false;
    final lines = value
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    return lines.length >= 2 && lines.every(_bibliographicLine.hasMatch);
  }

  static String? _stripMarkup(String value) {
    try {
      final document = XmlDocument.parse('<description>$value</description>');
      return _clean(_plainText(document.rootElement));
    } on XmlException {
      return value;
    }
  }

  static String? _removeTrailingBibliography(String? value) {
    if (value == null) return null;
    // Gutenberg's OPDS feed can place its marker and the bibliographic labels
    // on one physical line. A marker is an explicit boundary, so prose before
    // it is always safe to retain; prose after a leading marker is still
    // evaluated by the conservative trailing-block rule below.
    final markerMatch = _generatedSummaryMarkerInline.firstMatch(value);
    if (markerMatch != null) {
      final before = value.substring(0, markerMatch.start).trimRight();
      if (before.isNotEmpty) return _clean(before);
      value = value.substring(markerMatch.end).trimLeft();
    }
    final lines = value.split('\n');
    final markerIndex = lines.indexWhere(_generatedSummaryMarker.hasMatch);
    if (markerIndex > 0) return _clean(lines.take(markerIndex).join('\n'));
    if (markerIndex == 0) {
      lines.removeAt(0);
      while (lines.isNotEmpty && lines.first.trim().isEmpty) {
        lines.removeAt(0);
      }
    }

    // A tail is eligible only when two or more complete metadata-label lines
    // occur in the final compact region. This deliberately leaves isolated
    // prose such as "Rights reserved." untouched.
    var start = lines.length;
    var labels = 0;
    for (var index = lines.length - 1; index >= 0; index--) {
      final line = lines[index];
      if (line.trim().isEmpty) {
        if (labels > 0) break;
        continue;
      }
      if (_metadataLine.hasMatch(line)) {
        labels++;
        start = index;
        continue;
      }
      // A label may use the next line as its value. Only accept that value
      // when the immediately preceding line is itself a known label; otherwise
      // a short final prose paragraph could be swallowed into the tail.
      final precedingIsLabel =
          index > 0 && _metadataLine.hasMatch(lines[index - 1]);
      if (line.length <= 160 && precedingIsLabel) {
        start = index;
        continue;
      }
      break;
    }
    if (labels >= 2) return _clean(lines.take(start).join('\n'));
    return _clean(lines.join('\n'));
  }

  static String? _truncate(String? value) {
    if (value == null || value.length <= maxDescriptionLength) return value;
    return value.substring(0, maxDescriptionLength).trimRight();
  }

  static String? _clean(String? value) {
    if (value == null) return null;
    final buffer = StringBuffer();
    for (final codePoint in value.runes) {
      final allowedControl =
          codePoint == 0x0a || codePoint == 0x0d || codePoint == 0x09;
      if (codePoint >= 0x20 || allowedControl) buffer.writeCharCode(codePoint);
    }
    final result = buffer
        .toString()
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return result.isEmpty ? null : result;
  }

  static String _plainText(XmlNode node) {
    final buffer = StringBuffer();
    void visit(XmlNode current) {
      if (current is XmlElement &&
          const {
            'script',
            'style',
          }.contains(current.name.local.toLowerCase())) {
        return;
      }
      if (current is XmlText) {
        buffer.write(current.value);
        return;
      }
      if (current is XmlElement &&
          const {
            'p',
            'div',
            'br',
            'li',
            'tr',
            'td',
            'th',
          }.contains(current.name.local) &&
          buffer.isNotEmpty) {
        buffer.write('\n');
      }
      for (final child in current.children) {
        visit(child);
      }
    }

    visit(node);
    return buffer.toString();
  }
}

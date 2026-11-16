class ReadiumEpubPreferences {
  const ReadiumEpubPreferences({
    this.theme = 'system',
    this.fontFamily = 'original',
    this.fontSize = 1.0,
    this.fontWeight = 1.0,
    this.lineHeight = 1.5,
    this.pageMargins = 1.0,
    this.textAlignment = 'start',
    this.scroll = false,
    this.columns = 'auto',
    this.publisherStyles = true,
  });
  static const defaults = ReadiumEpubPreferences();
  final String theme;
  final String fontFamily;
  final double fontSize, fontWeight, lineHeight, pageMargins;
  final String textAlignment;
  final bool scroll;
  final String columns;
  final bool publisherStyles;
  ReadiumEpubPreferences normalized() => ReadiumEpubPreferences(
    theme: const {'system', 'light', 'dark', 'sepia'}.contains(theme)
        ? theme
        : 'system',
    fontFamily:
        const {
          'original',
          'serif',
          'sansSerif',
          'dyslexic',
          'monospace',
        }.contains(fontFamily)
        ? fontFamily
        : 'original',
    fontSize: _number(fontSize, 1, .5, 3),
    fontWeight: _number(fontWeight, 1, 0, 2.5),
    lineHeight: _number(lineHeight, 1.5, 1, 2.5),
    pageMargins: _number(pageMargins, 1, 0, 4),
    textAlignment: const {'start', 'justify'}.contains(textAlignment)
        ? textAlignment
        : 'start',
    scroll: scroll,
    columns: const {'auto', 'one', 'two'}.contains(columns) ? columns : 'auto',
    publisherStyles: publisherStyles,
  );
  Map<String, Object> toMap() {
    final v = normalized();
    return {
      'theme': v.theme,
      'fontFamily': v.fontFamily,
      'fontSize': v.fontSize,
      'fontWeight': v.fontWeight,
      'lineHeight': v.lineHeight,
      'pageMargins': v.pageMargins,
      'textAlignment': v.textAlignment,
      'scroll': v.scroll,
      'columns': v.columns,
      'publisherStyles': v.publisherStyles,
    };
  }

  static ReadiumEpubPreferences? fromMap(Object? value) {
    if (value is! Map) return null;
    return ReadiumEpubPreferences(
      theme: value['theme'] is String ? value['theme'] as String : 'system',
      fontFamily: value['fontFamily'] is String
          ? value['fontFamily'] as String
          : 'original',
      fontSize: value['fontSize'] is num
          ? (value['fontSize'] as num).toDouble()
          : 1,
      fontWeight: value['fontWeight'] is num
          ? (value['fontWeight'] as num).toDouble()
          : 1,
      lineHeight: value['lineHeight'] is num
          ? (value['lineHeight'] as num).toDouble()
          : 1.5,
      pageMargins: value['pageMargins'] is num
          ? (value['pageMargins'] as num).toDouble()
          : 1,
      textAlignment: value['textAlignment'] is String
          ? value['textAlignment'] as String
          : 'start',
      scroll: value['scroll'] is bool ? value['scroll'] as bool : false,
      columns: value['columns'] is String ? value['columns'] as String : 'auto',
      publisherStyles: value['publisherStyles'] is bool
          ? value['publisherStyles'] as bool
          : true,
    ).normalized();
  }

  static double _number(double v, double fallback, double low, double high) =>
      v.isFinite ? v.clamp(low, high).toDouble() : fallback;
  @override
  bool operator ==(Object other) =>
      other is ReadiumEpubPreferences &&
      other.theme == theme &&
      other.fontFamily == fontFamily &&
      other.fontSize == fontSize &&
      other.fontWeight == fontWeight &&
      other.lineHeight == lineHeight &&
      other.pageMargins == pageMargins &&
      other.textAlignment == textAlignment &&
      other.scroll == scroll &&
      other.columns == columns &&
      other.publisherStyles == publisherStyles;
  @override
  int get hashCode => Object.hash(
    theme,
    fontFamily,
    fontSize,
    fontWeight,
    lineHeight,
    pageMargins,
    textAlignment,
    scroll,
    columns,
    publisherStyles,
  );
}

/// Selection payload shared by the Flutter-owned annotation coordinator.
/// Native selection presentation emits the same locator/text contract through
/// the per-PlatformView bridge.
class ReaderSelectionPlatformEvent {
  const ReaderSelectionPlatformEvent({
    required this.locatorJson,
    required this.selectedText,
    required this.href,
    this.textBefore,
    this.textAfter,
    this.progression,
    this.totalProgression,
  });

  final String locatorJson;
  final String selectedText;
  final String? textBefore;
  final String? textAfter;
  final String href;
  final double? progression;
  final double? totalProgression;

  Map<String, Object?> toMap() => {
    'locatorJson': locatorJson,
    'selectedText': selectedText,
    'textBefore': textBefore,
    'textAfter': textAfter,
    'href': href,
    'progression': progression,
    'totalProgression': totalProgression,
  };
}

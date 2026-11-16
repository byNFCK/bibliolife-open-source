import 'package:bibliolife/features/reader/domain/models/reader_settings.dart';

enum EpubReaderTheme { system, light, dark, sepia }

class EpubReaderSettings {
  const EpubReaderSettings({
    this.theme = EpubReaderTheme.system,
    this.fontFamily = ReaderFontFamily.original,
    this.fontSize = 1.0,
    this.fontWeight = 1.0,
    this.lineHeight = 1.5,
    this.pageMargins = 1.0,
    this.textAlignment = ReaderTextAlignment.start,
    this.readingMode = ReaderReadingMode.paginated,
    this.columns = ReaderColumnCount.auto,
    this.publisherStyles = true,
  });

  static const defaults = EpubReaderSettings();
  static const minFontSize = 0.5, maxFontSize = 3.0;
  static const minFontWeight = 0.0, maxFontWeight = 2.5;
  static const minLineHeight = 1.0, maxLineHeight = 2.5;
  static const minPageMargins = 0.0, maxPageMargins = 4.0;
  final EpubReaderTheme theme;
  final ReaderFontFamily fontFamily;
  final double fontSize, fontWeight, lineHeight, pageMargins;
  final ReaderTextAlignment textAlignment;
  final ReaderReadingMode readingMode;
  final ReaderColumnCount columns;
  final bool publisherStyles;

  EpubReaderSettings normalized() => EpubReaderSettings(
    theme: theme,
    fontFamily: fontFamily,
    fontSize: _clamp(fontSize, 1.0, minFontSize, maxFontSize),
    fontWeight: _clamp(fontWeight, 1.0, minFontWeight, maxFontWeight),
    lineHeight: _clamp(lineHeight, 1.5, minLineHeight, maxLineHeight),
    pageMargins: _clamp(pageMargins, 1.0, minPageMargins, maxPageMargins),
    textAlignment: textAlignment,
    readingMode: readingMode,
    columns: columns,
    publisherStyles: publisherStyles,
  );
  EpubReaderSettings copyWith({
    EpubReaderTheme? theme,
    ReaderFontFamily? fontFamily,
    double? fontSize,
    double? fontWeight,
    double? lineHeight,
    double? pageMargins,
    ReaderTextAlignment? textAlignment,
    ReaderReadingMode? readingMode,
    ReaderColumnCount? columns,
    bool? publisherStyles,
  }) => EpubReaderSettings(
    theme: theme ?? this.theme,
    fontFamily: fontFamily ?? this.fontFamily,
    fontSize: fontSize ?? this.fontSize,
    fontWeight: fontWeight ?? this.fontWeight,
    lineHeight: lineHeight ?? this.lineHeight,
    pageMargins: pageMargins ?? this.pageMargins,
    textAlignment: textAlignment ?? this.textAlignment,
    readingMode: readingMode ?? this.readingMode,
    columns: columns ?? this.columns,
    publisherStyles: publisherStyles ?? this.publisherStyles,
  ).normalized();
  Map<String, Object> toJson() {
    final s = normalized();
    return {
      'theme': s.theme.name,
      'fontFamily': s.fontFamily.name,
      'fontSize': s.fontSize,
      'fontWeight': s.fontWeight,
      'lineHeight': s.lineHeight,
      'pageMargins': s.pageMargins,
      'textAlignment': s.textAlignment.name,
      'readingMode': s.readingMode.name,
      'columns': s.columns.name,
      'publisherStyles': s.publisherStyles,
    };
  }

  factory EpubReaderSettings.fromJson(Map<String, Object?> json) =>
      EpubReaderSettings(
        theme:
            EpubReaderTheme.values
                .where((v) => v.name == json['theme'])
                .firstOrNull ??
            EpubReaderTheme.system,
        fontFamily: _enumValue(
          ReaderFontFamily.values,
          json['fontFamily'],
          ReaderFontFamily.original,
        ),
        fontSize: _number(json['fontSize'], 1.0),
        fontWeight: _number(json['fontWeight'], 1.0),
        lineHeight: _number(json['lineHeight'], 1.5),
        pageMargins: _number(json['pageMargins'], 1.0),
        textAlignment: _enumValue(
          ReaderTextAlignment.values,
          json['textAlignment'],
          ReaderTextAlignment.start,
        ),
        readingMode: _enumValue(
          ReaderReadingMode.values,
          json['readingMode'],
          ReaderReadingMode.paginated,
        ),
        columns: _enumValue(
          ReaderColumnCount.values,
          json['columns'],
          ReaderColumnCount.auto,
        ),
        publisherStyles: json['publisherStyles'] is bool
            ? json['publisherStyles']! as bool
            : true,
      ).normalized();
  static double _number(Object? v, double fallback) =>
      v is num && v.toDouble().isFinite ? v.toDouble() : fallback;
  static T _enumValue<T extends Enum>(
    List<T> values,
    Object? name,
    T fallback,
  ) => values.where((value) => value.name == name).firstOrNull ?? fallback;
  static double _clamp(double v, double fallback, double low, double high) =>
      !v.isFinite ? fallback : v.clamp(low, high).toDouble();
  @override
  bool operator ==(Object other) =>
      other is EpubReaderSettings &&
      other.theme == theme &&
      other.fontFamily == fontFamily &&
      other.fontSize == fontSize &&
      other.fontWeight == fontWeight &&
      other.lineHeight == lineHeight &&
      other.pageMargins == pageMargins &&
      other.textAlignment == textAlignment &&
      other.readingMode == readingMode &&
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
    readingMode,
    columns,
    publisherStyles,
  );
}

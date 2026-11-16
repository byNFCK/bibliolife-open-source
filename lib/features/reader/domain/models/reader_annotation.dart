enum ReaderAnnotationStyle {
  highlight('highlight'),
  underline('underline');

  const ReaderAnnotationStyle(this.storageValue);
  final String storageValue;
  static ReaderAnnotationStyle? tryParse(String value) {
    for (final item in values) {
      if (item.storageValue == value) return item;
    }
    return null;
  }
}

enum ReaderAnnotationColor {
  yellow('yellow'),
  green('green'),
  blue('blue'),
  pink('pink'),
  purple('purple');

  const ReaderAnnotationColor(this.storageValue);
  final String storageValue;
  static ReaderAnnotationColor? tryParse(String value) {
    for (final item in values) {
      if (item.storageValue == value) return item;
    }
    return null;
  }
}

class ReaderAnnotation {
  const ReaderAnnotation({
    required this.id,
    required this.bookId,
    required this.locatorJson,
    required this.locationKey,
    required this.selectedText,
    this.textBefore,
    this.textAfter,
    this.note,
    this.style = ReaderAnnotationStyle.highlight,
    this.color = ReaderAnnotationColor.yellow,
    required this.href,
    this.progression,
    this.totalProgression,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id, bookId, locatorJson, locationKey, selectedText, href;
  final String? textBefore, textAfter, note;
  final ReaderAnnotationStyle style;
  final ReaderAnnotationColor color;
  final double? progression, totalProgression;
  final DateTime createdAt, updatedAt;
  @override
  bool operator ==(Object other) =>
      other is ReaderAnnotation &&
      other.id == id &&
      other.bookId == bookId &&
      other.locatorJson == locatorJson &&
      other.locationKey == locationKey &&
      other.selectedText == selectedText &&
      other.textBefore == textBefore &&
      other.textAfter == textAfter &&
      other.note == note &&
      other.style == style &&
      other.color == color &&
      other.href == href &&
      other.progression == progression &&
      other.totalProgression == totalProgression &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;
  @override
  int get hashCode => Object.hashAll([
    id,
    bookId,
    locatorJson,
    locationKey,
    selectedText,
    textBefore,
    textAfter,
    note,
    style,
    color,
    href,
    progression,
    totalProgression,
    createdAt,
    updatedAt,
  ]);
}

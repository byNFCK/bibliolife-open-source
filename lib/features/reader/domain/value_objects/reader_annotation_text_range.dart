import 'dart:convert';

enum ReaderAnnotationRangeRelation {
  disjoint,
  exact,
  contains,
  containedBy,
  partialOverlap,
  notComparable,
}

enum ReaderAnnotationRangeCapability {
  comparableRange,
  exactIdentityOnly,
  unsupported,
}

/// Comparable half-open EPUB CFI range. Unsupported locator forms are safe
/// `notComparable` values: text, progression and raw JSON are never guessed.
final class ReaderAnnotationTextRange {
  const ReaderAnnotationTextRange._(this.href, this.start, this.end);

  final String href;
  final List<int> start;
  final List<int> end;

  static ReaderAnnotationTextRange? tryParse(String locatorJson) {
    try {
      final value = jsonDecode(locatorJson);
      if (value is! Map) return null;
      final href = value['href'];
      final locations = value['locations'];
      if (href is! String || locations is! Map) return null;
      final fragments = locations['fragments'];
      if (fragments is! List) return null;
      for (final fragment in fragments) {
        if (fragment is! String) continue;
        final match = RegExp(
          r'^epubcfi\([^,]+,([^,]+),([^\)]+)\)$',
        ).firstMatch(fragment.trim());
        if (match == null) continue;
        final start = _boundary(match.group(1)!);
        final end = _boundary(match.group(2)!);
        if (start != null && end != null && _compare(start, end) < 0) {
          return ReaderAnnotationTextRange._(href.trim(), start, end);
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  static ReaderAnnotationRangeCapability capabilityFor(String locatorJson) =>
      tryParse(locatorJson) != null
      ? ReaderAnnotationRangeCapability.comparableRange
      : ReaderAnnotationRangeCapability.exactIdentityOnly;

  ReaderAnnotationRangeRelation relationTo(ReaderAnnotationTextRange other) {
    if (href != other.href) return ReaderAnnotationRangeRelation.notComparable;
    if (_compare(start, other.start) == 0 && _compare(end, other.end) == 0) {
      return ReaderAnnotationRangeRelation.exact;
    }
    if (_compare(start, other.end) >= 0 || _compare(other.start, end) >= 0) {
      return ReaderAnnotationRangeRelation.disjoint;
    }
    if (_compare(start, other.start) <= 0 && _compare(end, other.end) >= 0) {
      return ReaderAnnotationRangeRelation.contains;
    }
    if (_compare(other.start, start) <= 0 && _compare(other.end, end) >= 0) {
      return ReaderAnnotationRangeRelation.containedBy;
    }
    return ReaderAnnotationRangeRelation.partialOverlap;
  }

  static List<int>? _boundary(String value) {
    final values = RegExp(
      r'\d+',
    ).allMatches(value).map((m) => int.parse(m.group(0)!)).toList();
    return values.isEmpty ? null : values;
  }

  static int _compare(List<int> left, List<int> right) {
    for (var index = 0; index < left.length && index < right.length; index++) {
      final result = left[index].compareTo(right[index]);
      if (result != 0) return result;
    }
    return left.length.compareTo(right.length);
  }
}

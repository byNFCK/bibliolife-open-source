import 'dart:convert';

/// A format-neutral reading location used by the shared bookmark pipeline.
sealed class ReaderBookmarkTarget {
  const ReaderBookmarkTarget();

  /// Stable identity used for in-memory and repository deduplication.
  String get fingerprint;
}

/// An EPUB location whose serialized Readium locator is the source of truth.
final class ReaderLocatorBookmarkTarget extends ReaderBookmarkTarget {
  const ReaderLocatorBookmarkTarget({
    required this.locatorJson,
    this.progression,
    this.chapterTitle,
    this.href,
  });

  final String locatorJson;
  final double? progression;
  final String? chapterTitle;
  final String? href;

  static ReaderLocatorBookmarkTarget? tryParse({
    required String locatorJson,
    double? progression,
    String? chapterTitle,
    String? href,
  }) {
    final trimmed = locatorJson.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return null;
      final rawHref = decoded['href'];
      final locatorHref = rawHref is String ? _nonBlank(rawHref) : null;
      if (locatorHref == null) return null;
      if (progression != null &&
          (!progression.isFinite || progression < 0 || progression > 1)) {
        return null;
      }
      return ReaderLocatorBookmarkTarget(
        locatorJson: trimmed,
        progression: progression,
        chapterTitle: _nonBlank(chapterTitle),
        href: _nonBlank(href) ?? locatorHref,
      );
    } on FormatException {
      return null;
    }
  }

  @override
  String get fingerprint => 'locator:${_canonicalJson(locatorJson)}';

  @override
  bool operator ==(Object other) =>
      other is ReaderLocatorBookmarkTarget &&
      other.locatorJson == locatorJson &&
      other.progression == progression &&
      other.chapterTitle == chapterTitle &&
      other.href == href;

  @override
  int get hashCode => Object.hash(locatorJson, progression, chapterTitle, href);
}

/// A page-based location retained for readers whose authoritative position is
/// a page index (for example PDF and comics).
final class ReaderPageBookmarkTarget extends ReaderBookmarkTarget {
  const ReaderPageBookmarkTarget({required this.pageIndex});

  final int pageIndex;

  @override
  String get fingerprint => 'page:$pageIndex';

  @override
  bool operator ==(Object other) =>
      other is ReaderPageBookmarkTarget && other.pageIndex == pageIndex;

  @override
  int get hashCode => pageIndex.hashCode;
}

String? _nonBlank(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

/// JSON object ordering is not semantically meaningful in a Readium locator.
/// Sorting object keys gives equivalent serialized locators one identity while
/// leaving the original bytes untouched for persistence and navigation.
String _canonicalJson(String source) {
  try {
    return jsonEncode(_canonicalValue(jsonDecode(source.trim())));
  } on Object {
    return source.trim();
  }
}

Object? _canonicalValue(Object? value) {
  if (value is Map) {
    final entries = <String, Object?>{};
    for (final entry in value.entries) {
      entries['${entry.key}'] = _canonicalValue(entry.value);
    }
    final keys = entries.keys.toList()..sort();
    return <String, Object?>{for (final key in keys) key: entries[key]};
  }
  if (value is List) {
    return value.map(_canonicalValue).toList(growable: false);
  }
  return value;
}

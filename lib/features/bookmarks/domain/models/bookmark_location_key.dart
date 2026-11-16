import 'dart:convert';

class BookmarkLocationKey {
  const BookmarkLocationKey._(this.bookId, this.value, this.readerKind);
  final String bookId;
  final String value;
  final String? readerKind;

  static BookmarkLocationKey? fromValues({
    required String bookId,
    required String locatorJson,
    String? href,
    int? position,
    double? progression,
    String? readerKind,
  }) {
    final normalizedBook = bookId.trim();
    if (normalizedBook.isEmpty) return null;
    final normalizedKind = readerKind?.trim();
    if (normalizedKind == 'epub' || _looksLikeReadiumLocator(locatorJson)) {
      final canonical = _canonicalLocator(locatorJson);
      if (canonical == null) return null;
      return BookmarkLocationKey._(
        normalizedBook,
        'l:$canonical',
        normalizedKind,
      );
    }
    if (position != null && position >= 1) {
      return BookmarkLocationKey._(
        normalizedBook,
        'p:$position',
        normalizedKind,
      );
    }
    String? rawHref = href?.trim();
    if (rawHref == null || rawHref.isEmpty) {
      try {
        rawHref = (jsonDecode(locatorJson) as Map)['href'] as String?;
      } catch (_) {}
    }
    final normalizedHref = _href(rawHref);
    if (normalizedHref != null) {
      return BookmarkLocationKey._(
        normalizedBook,
        'h:$normalizedHref',
        normalizedKind,
      );
    }
    if (progression != null &&
        progression.isFinite &&
        progression >= 0 &&
        progression <= 1) {
      return BookmarkLocationKey._(
        normalizedBook,
        'g:${progression.toStringAsFixed(6)}',
        normalizedKind,
      );
    }
    return null;
  }

  static String? _href(String? value) {
    final source = value?.trim();
    if (source == null || source.isEmpty) return null;
    final parts = source.split('#');
    final path = parts.first
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^\./+'), '');
    final fragment = parts.length > 1 ? parts.sublist(1).join('#').trim() : '';
    if (path.isEmpty && fragment.isEmpty) return null;
    return fragment.isEmpty ? path : '$path#$fragment';
  }

  @override
  bool operator ==(Object other) =>
      other is BookmarkLocationKey &&
      other.bookId == bookId &&
      other.value == value &&
      other.readerKind == readerKind;
  @override
  int get hashCode => Object.hash(bookId, value, readerKind);
}

String? _canonicalLocator(String source) {
  final trimmed = source.trim();
  if (trimmed.isEmpty) return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return null;
    return jsonEncode(_canonicalValue(decoded));
  } on FormatException {
    return null;
  }
}

bool _looksLikeReadiumLocator(String source) {
  try {
    final decoded = jsonDecode(source.trim());
    if (decoded is! Map) return false;
    return decoded['locations'] is Map || decoded['type'] is String;
  } on FormatException {
    return false;
  }
}

Object? _canonicalValue(Object? value) {
  if (value is Map) {
    final values = <String, Object?>{
      for (final entry in value.entries)
        '${entry.key}': _canonicalValue(entry.value),
    };
    final keys = values.keys.toList()..sort();
    return <String, Object?>{for (final key in keys) key: values[key]};
  }
  if (value is List) return value.map(_canonicalValue).toList(growable: false);
  return value;
}

import 'dart:convert';

final class BookTocEntry {
  const BookTocEntry({
    required this.title,
    required this.locatorJson,
    this.children = const [],
  });
  final String title;
  final String locatorJson;
  final List<BookTocEntry> children;

  Map<String, Object> toJson() => {
    'title': title,
    'locatorJson': locatorJson,
    'children': children.map((entry) => entry.toJson()).toList(),
  };

  static List<BookTocEntry> decodeEntries(Object? values) {
    if (values is! List) return const [];
    final output = <BookTocEntry>[];
    for (final value in values) {
      if (value is! Map) continue;
      final children = decodeEntries(value['children']);
      final title = _normalize(value['title']);
      final locator = _normalize(value['locatorJson']);
      if (title == null || locator == null) {
        output.addAll(children);
      } else {
        output.add(
          BookTocEntry(
            title: title,
            locatorJson: locator,
            children: List.unmodifiable(children),
          ),
        );
      }
    }
    return List.unmodifiable(output);
  }
}

final class BookTocSnapshot {
  const BookTocSnapshot(this.entries);
  final List<BookTocEntry> entries;
  bool get isUsable => entries.isNotEmpty;
  String encode() => jsonEncode({
    'version': 1,
    'entries': entries.map((entry) => entry.toJson()).toList(),
  });

  static BookTocSnapshot? decode(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) return null;
      final entries = BookTocEntry.decodeEntries(decoded['entries']);
      return entries.isEmpty ? null : BookTocSnapshot(entries);
    } on FormatException {
      return null;
    }
  }
}

String? _normalize(Object? value) {
  if (value is! String) return null;
  final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return normalized.isEmpty ? null : normalized;
}

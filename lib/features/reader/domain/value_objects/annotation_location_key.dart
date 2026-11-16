import 'dart:convert';
import 'package:crypto/crypto.dart';

final class AnnotationLocationKey {
  static String build({
    required String bookId,
    required String href,
    required List<String>? fragments,
    required double? progression,
    required String selectedText,
  }) {
    String requiredValue(String value, String name) {
      final normalized = value.trim();
      if (normalized.isEmpty) throw ArgumentError.value(value, name);
      return normalized;
    }

    final book = requiredValue(bookId, 'bookId');
    final link = requiredValue(href, 'href');
    final text = selectedText
        .replaceAll(RegExp(r'[\t\r\n]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) throw ArgumentError.value(selectedText, 'selectedText');
    if (progression != null &&
        (!progression.isFinite || progression < 0 || progression > 1)) {
      throw ArgumentError.value(progression, 'progression');
    }
    String field(String name, String value) =>
        '${utf8.encode(name).length}:$name${utf8.encode(value).length}:$value';
    final parts = (fragments ?? const <String>[])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final progress = progression == null
        ? 'null'
        : (progression == 0 ? 0.0 : progression).toStringAsFixed(6);
    // Readium's progression may differ minutely for the same text range. A
    // non-empty fragment sequence is the precise range identity; progression
    // is retained only when no range fragment is available.
    final payload = [
      'v=2',
      field('bookId', book),
      field('href', link),
      'fragments=${parts.length}',
      ...parts.map((e) => field('fragment', e)),
      if (parts.isEmpty) field('progression', progress),
      field('selectedText', text),
    ].join('\n');
    return 'v2:${sha256.convert(utf8.encode(payload))}';
  }
}

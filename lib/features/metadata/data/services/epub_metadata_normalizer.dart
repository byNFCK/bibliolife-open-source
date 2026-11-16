import 'dart:convert';

import 'package:bibliolife/features/metadata/data/services/book_description_sanitizer.dart';

/// Performs lossless cleanup after the XML parser has produced Unicode text.
///
/// It deliberately never performs a charset conversion. EPUB XML bytes are
/// decoded once by the parser; values reaching this class are Unicode strings.
class EpubMetadataNormalizer {
  const EpubMetadataNormalizer._();
  static const maxDescriptionLength =
      BookDescriptionSanitizer.maxDescriptionLength;

  static String? text(String? value) => _clean(value);

  static String? description(String? value) =>
      BookDescriptionSanitizer.sanitize(value);

  static String? language(String? value) {
    final cleaned = _clean(value);
    if (cleaned == null ||
        !RegExp(r'^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$').hasMatch(cleaned)) {
      return null;
    }
    final parts = cleaned.split('-');
    return [
      parts.first.toLowerCase(),
      for (final part in parts.skip(1))
        part.length == 2 ? part.toUpperCase() : part,
    ].join('-');
  }

  static String? publicationDate(String? value) {
    final cleaned = _clean(value);
    if (cleaned == null ||
        !RegExp(
          r'^\d{4}(?:-(?:0[1-9]|1[0-2])(?:-(?:0[1-9]|[12]\d|3[01]))?)?(?:T.+Z|[+-]\d\d:\d\d)?$',
        ).hasMatch(cleaned)) {
      return null;
    }
    if (cleaned.length >= 10 && DateTime.tryParse(cleaned) == null) return null;
    return cleaned;
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
}

/// Repairs UTF-8-as-Latin-1 only when it is demonstrably Cyrillic mojibake.
/// It is intentionally not part of normal import parsing.
String recoverUtf8MojibakeIfConfident(String value) {
  if (!RegExp(r'[ÐÑРСâ]').hasMatch(value) ||
      value.runes.any((rune) => rune > 0xff)) {
    return value;
  }
  try {
    final candidate = const Utf8Decoder(
      allowMalformed: false,
    ).convert(value.runes.toList());
    final originalSignals = RegExp(r'[ÐÑРСâ�]').allMatches(value).length;
    final candidateSignals = RegExp(r'[ÐÑРСâ�]').allMatches(candidate).length;
    final hasCyrillic = RegExp(r'[\u0400-\u052f]').hasMatch(candidate);
    return hasCyrillic && candidateSignals < originalSignals
        ? candidate
        : value;
  } on FormatException {
    return value;
  }
}

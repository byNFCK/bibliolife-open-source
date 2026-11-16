import 'dart:convert';
import 'dart:typed_data';

import 'package:bibliolife/features/catalog_sources/data/payload_parser_failure.dart';
import 'package:bibliolife/features/catalog_sources/data/parser_diagnostics.dart';

/// Isolate-safe result of parsing a Google Books response.
class ParsedGoogleBooksPage {
  const ParsedGoogleBooksPage({
    required this.totalItems,
    required this.books,
    required this.skippedItemCount,
    required this.diagnostics,
  });

  final int totalItems;
  final List<ParsedGoogleBook> books;
  final int skippedItemCount;
  final ParserDiagnostics diagnostics;
}

/// Only the fields consumed by the existing Google Books mapper are retained.
/// All URI-like values remain strings until domain mapping on the caller.
class ParsedGoogleBook {
  const ParsedGoogleBook({
    required this.id,
    required this.volume,
    required this.access,
    required this.sale,
  });

  final String id;
  final Map<String, Object?> volume;
  final Map<String, Object?> access;
  final Map<String, Object?> sale;
}

ParsedGoogleBooksPage parseGoogleBooksPayload(
  Uint8List bytes, {
  required bool details,
}) {
  final decodeWatch = Stopwatch()..start();
  final String text;
  try {
    text = utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    throw const PayloadParserException(
      PayloadParserFailureKind.invalidUtf8,
      'Google Books response is not valid UTF-8.',
    );
  }
  decodeWatch.stop();
  final parseWatch = Stopwatch()..start();
  final Object? root;
  try {
    root = jsonDecode(text);
  } on FormatException {
    throw const PayloadParserException(
      PayloadParserFailureKind.malformedJson,
      'Google Books returned invalid JSON.',
    );
  }
  parseWatch.stop();
  if (root is! Map) {
    throw const PayloadParserException(
      PayloadParserFailureKind.unexpectedTopLevelShape,
      'Google Books response is not an object.',
    );
  }
  final map = root.cast<Object?, Object?>();
  final rawItems = details
      ? [map]
      : (map['items'] is List ? map['items'] as List : const <Object?>[]);
  final extractWatch = Stopwatch()..start();
  final books = <ParsedGoogleBook>[];
  var skipped = 0;
  for (var index = 0; index < rawItems.length; index++) {
    final item = rawItems[index];
    if (item is! Map) {
      skipped++;
      continue;
    }
    final value = item.cast<Object?, Object?>();
    final id = _text(value['id']);
    final volume = _map(value['volumeInfo']);
    final title = volume == null ? null : _text(volume['title']);
    if (id == null || volume == null || title == null) {
      skipped++;
      continue;
    }
    books.add(
      ParsedGoogleBook(
        id: id,
        volume: _googleVolume(volume),
        access: _googleAccess(_map(value['accessInfo'])),
        sale: _googleSale(_map(value['saleInfo'])),
      ),
    );
  }
  extractWatch.stop();
  return ParsedGoogleBooksPage(
    totalItems: (map['totalItems'] as num?)?.toInt() ?? 0,
    books: List.unmodifiable(books),
    skippedItemCount: skipped,
    diagnostics: ParserDiagnostics(
      parserType: 'googleBooksJson',
      encodedByteCount: bytes.length,
      decodeMicros: decodeWatch.elapsedMicroseconds,
      parseMicros: parseWatch.elapsedMicroseconds,
      extractMicros: extractWatch.elapsedMicroseconds,
      itemCount: books.length,
      skippedItemCount: skipped,
    ),
  );
}

Map<String, Object?> _googleVolume(Map<Object?, Object?> value) => {
  for (final key in const [
    'title',
    'subtitle',
    'authors',
    'description',
    'publisher',
    'language',
    'publishedDate',
    'pageCount',
    'industryIdentifiers',
    'categories',
    'maturityRating',
    'previewLink',
    'infoLink',
    'imageLinks',
  ])
    if (value.containsKey(key)) key: _copy(value[key]),
};

Map<String, Object?> _googleAccess(Map<Object?, Object?>? value) =>
    value == null
    ? const {}
    : {
        for (final key in const [
          'viewability',
          'embeddable',
          'publicDomain',
          'textToSpeechPermission',
          'accessViewStatus',
          'country',
          'webReaderLink',
          'epub',
          'pdf',
        ])
          if (value.containsKey(key)) key: _copy(value[key]),
      };

Map<String, Object?> _googleSale(Map<Object?, Object?>? value) => value == null
    ? const {}
    : {
        for (final key in const [
          'saleability',
          'isEbook',
          'listPrice',
          'retailPrice',
          'buyLink',
        ])
          if (value.containsKey(key)) key: _copy(value[key]),
      };

Map<Object?, Object?>? _map(Object? value) =>
    value is Map ? value.cast<Object?, Object?>() : null;

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

Object? _copy(Object? value) => switch (value) {
  Map map => Map.unmodifiable({
    for (final entry in map.entries) '${entry.key}': _copy(entry.value),
  }),
  List list => List.unmodifiable(list.map(_copy)),
  String _ || num _ || bool _ || null => value,
  _ => null,
};

import 'dart:convert';
import 'dart:typed_data';

import 'package:bibliolife/features/catalog_sources/data/payload_parser_failure.dart';
import 'package:bibliolife/features/catalog_sources/data/parser_diagnostics.dart';

class ParsedOpenLibraryPage {
  const ParsedOpenLibraryPage({
    required this.start,
    required this.numFound,
    required this.documents,
    required this.skippedDocumentCount,
    required this.diagnostics,
  });

  final int start;
  final int numFound;
  final List<ParsedOpenLibraryDocument> documents;
  final int skippedDocumentCount;
  final ParserDiagnostics diagnostics;
}

class ParsedOpenLibraryDocument {
  const ParsedOpenLibraryDocument(this.fields);

  final Map<String, Object?> fields;
}

ParsedOpenLibraryPage parseOpenLibraryPayload(Uint8List bytes) {
  final decodeWatch = Stopwatch()..start();
  final String text;
  try {
    text = utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    throw const PayloadParserException(
      PayloadParserFailureKind.invalidUtf8,
      'Open Library response is not valid UTF-8.',
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
      'Open Library returned invalid JSON.',
    );
  }
  parseWatch.stop();
  if (root is! Map) {
    throw const PayloadParserException(
      PayloadParserFailureKind.unexpectedTopLevelShape,
      'Open Library search response is not a JSON object.',
    );
  }
  final map = root.cast<Object?, Object?>();
  // The public weekly trending endpoint returns `works`, while normal Search
  // returns `docs`. Both intentionally flow through the same metadata mapper.
  final docs = map['docs'] ?? map['works'];
  if (docs is! List) {
    throw const PayloadParserException(
      PayloadParserFailureKind.missingRequiredField,
      'Open Library response has no works array.',
    );
  }
  final extractWatch = Stopwatch()..start();
  final parsed = <ParsedOpenLibraryDocument>[];
  var skipped = 0;
  for (final raw in docs) {
    if (raw is! Map) {
      skipped++;
      continue;
    }
    final document = raw.cast<Object?, Object?>();
    if (_text(document['key']) == null || _text(document['title']) == null) {
      skipped++;
      continue;
    }
    parsed.add(
      ParsedOpenLibraryDocument(
        Map.unmodifiable({
          for (final key in const [
            'key',
            'title',
            'subtitle',
            'author_name',
            'author_key',
            'cover_i',
            'cover_edition_key',
            'publisher',
            'language',
            'first_publish_year',
            'publish_year',
            'number_of_pages_median',
            'subject',
            'isbn',
            'lccn',
            'oclc',
            'ia',
            'edition_key',
            'edition_count',
            'ebook_access',
            'has_fulltext',
          ])
            if (document.containsKey(key)) key: _copy(document[key]),
        }),
      ),
    );
  }
  extractWatch.stop();
  return ParsedOpenLibraryPage(
    start: (map['start'] as num?)?.toInt() ?? 0,
    numFound: (map['numFound'] as num?)?.toInt() ?? 0,
    documents: List.unmodifiable(parsed),
    skippedDocumentCount: skipped,
    diagnostics: ParserDiagnostics(
      parserType: 'openLibraryJson',
      encodedByteCount: bytes.length,
      decodeMicros: decodeWatch.elapsedMicroseconds,
      parseMicros: parseWatch.elapsedMicroseconds,
      extractMicros: extractWatch.elapsedMicroseconds,
      itemCount: parsed.length,
      skippedItemCount: skipped,
    ),
  );
}

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

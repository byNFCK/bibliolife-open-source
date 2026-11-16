import 'dart:convert';
import 'dart:typed_data';

import 'package:bibliolife/features/catalog_sources/data/payload_parser_failure.dart';
import 'package:bibliolife/features/catalog_sources/data/parser_diagnostics.dart';

class ParsedInternetArchiveMetadata {
  const ParsedInternetArchiveMetadata({
    required this.borrowOnly,
    required this.files,
    required this.diagnostics,
  });

  final bool borrowOnly;
  final List<ParsedInternetArchiveFile> files;
  final ParserDiagnostics diagnostics;
}

class ParsedInternetArchiveFile {
  const ParsedInternetArchiveFile({
    required this.name,
    required this.isPrivate,
  });

  final String name;
  final bool isPrivate;
}

ParsedInternetArchiveMetadata parseInternetArchiveMetadata(Uint8List bytes) {
  final decodeWatch = Stopwatch()..start();
  final String text;
  try {
    text = utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    throw const PayloadParserException(
      PayloadParserFailureKind.invalidUtf8,
      'Internet Archive response is not valid UTF-8.',
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
      'Internet Archive returned invalid JSON.',
    );
  }
  parseWatch.stop();
  if (root is! Map) {
    throw const PayloadParserException(
      PayloadParserFailureKind.unexpectedTopLevelShape,
      'Internet Archive metadata is not an object.',
    );
  }
  final extractWatch = Stopwatch()..start();
  final map = root.cast<Object?, Object?>();
  final metadata = map['metadata'] is Map
      ? (map['metadata'] as Map).cast<Object?, Object?>()
      : const <Object?, Object?>{};
  final restricted = '${metadata['access-restricted'] ?? ''}'.toLowerCase();
  final lending = '${metadata['lending___status'] ?? ''}'.toLowerCase();
  final files = <ParsedInternetArchiveFile>[];
  final rawFiles = map['files'];
  var skipped = 0;
  if (rawFiles is List) {
    for (final raw in rawFiles) {
      if (raw is! Map || raw['name'] is! String) {
        skipped++;
        continue;
      }
      final name = raw['name'] as String;
      files.add(
        ParsedInternetArchiveFile(
          name: name,
          isPrivate:
              '${raw['private'] ?? ''}'.toLowerCase() == 'true' ||
              '${raw['private'] ?? ''}' == '1',
        ),
      );
    }
  }
  extractWatch.stop();
  return ParsedInternetArchiveMetadata(
    borrowOnly:
        restricted == 'true' ||
        restricted == '1' ||
        lending.contains('borrow') ||
        lending.contains('loan'),
    files: List.unmodifiable(files),
    diagnostics: ParserDiagnostics(
      parserType: 'internetArchiveJson',
      encodedByteCount: bytes.length,
      decodeMicros: decodeWatch.elapsedMicroseconds,
      parseMicros: parseWatch.elapsedMicroseconds,
      extractMicros: extractWatch.elapsedMicroseconds,
      itemCount: rawFiles is List ? rawFiles.length : 0,
      skippedItemCount: skipped,
    ),
  );
}

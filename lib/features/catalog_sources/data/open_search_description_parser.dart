import 'dart:convert';
import 'dart:typed_data';

import 'package:bibliolife/features/catalog_sources/data/payload_parser_failure.dart';
import 'package:bibliolife/features/catalog_sources/data/parser_diagnostics.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:xml/xml.dart';

class OpenSearchDescriptionParser {
  const OpenSearchDescriptionParser();

  RemoteCatalogLocation parseTemplate({
    required String body,
    required RemoteCatalogLocation descriptionLocation,
  }) {
    try {
      return RemoteCatalogLocation.parse(
        parseOpenSearchDescriptionPayload(
          Uint8List.fromList(utf8.encode(body)),
          baseUri: descriptionLocation.toString(),
        ).template,
      );
    } on PayloadParserException catch (error) {
      if (error.kind == PayloadParserFailureKind.unsupportedTemplate) {
        throw RemoteCatalogException.unsupportedSearchTemplate(error.detail);
      }
      throw RemoteCatalogException.malformedSearchDescription(error.detail);
    }
  }
}

/// Transferable OpenSearch result.  URI construction is intentionally delayed
/// until the adapter maps this DTO to its domain location.
class ParsedOpenSearchDescription {
  const ParsedOpenSearchDescription(this.template, this.diagnostics);

  final String template;
  final ParserDiagnostics diagnostics;
}

ParsedOpenSearchDescription parseOpenSearchDescriptionPayload(
  Uint8List bytes, {
  required String baseUri,
}) {
  final decodeWatch = Stopwatch()..start();
  final String body;
  try {
    body = utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    throw const PayloadParserException(
      PayloadParserFailureKind.invalidUtf8,
      'The OpenSearch description is not valid UTF-8.',
    );
  }
  decodeWatch.stop();
  final parseWatch = Stopwatch()..start();
  final XmlDocument document;
  try {
    document = XmlDocument.parse(body);
  } on XmlException {
    throw const PayloadParserException(
      PayloadParserFailureKind.malformedXml,
      'The OpenSearch description is malformed.',
    );
  }
  parseWatch.stop();
  final extractWatch = Stopwatch()..start();
  var inspected = 0;
  if (document.rootElement.name.local != 'OpenSearchDescription') {
    throw const PayloadParserException(
      PayloadParserFailureKind.unexpectedTopLevelShape,
      'The response is not an OpenSearch description.',
    );
  }
  for (final element in document.rootElement.descendantElements) {
    if (element.name.local != 'Url') continue;
    inspected++;
    final type = element.getAttribute('type')?.toLowerCase();
    final template = element.getAttribute('template');
    if (template == null || (type != null && !type.contains('atom+xml'))) {
      continue;
    }
    try {
      final resolvedUri = Uri.parse(baseUri).resolve(template);
      // Gutenberg's live OpenSearch document still advertises its Atom
      // template with http. The catalog itself is HTTPS, so upgrade only the
      // scheme before applying the app's HTTPS-only location policy.
      final secureUri = resolvedUri.scheme.toLowerCase() == 'http'
          ? resolvedUri.replace(scheme: 'https')
          : resolvedUri;
      final resolved = RemoteCatalogLocation.fromUri(secureUri).toString();
      if (!resolved.toLowerCase().contains('%7bsearchterms%7d')) {
        throw const PayloadParserException(
          PayloadParserFailureKind.unsupportedTemplate,
          'The search template has no searchTerms parameter.',
        );
      }
      extractWatch.stop();
      return ParsedOpenSearchDescription(
        resolved,
        ParserDiagnostics(
          parserType: 'openSearchXml',
          encodedByteCount: bytes.length,
          decodeMicros: decodeWatch.elapsedMicroseconds,
          parseMicros: parseWatch.elapsedMicroseconds,
          extractMicros: extractWatch.elapsedMicroseconds,
          itemCount: inspected,
          skippedItemCount: inspected - 1,
        ),
      );
    } on FormatException {
      throw const PayloadParserException(
        PayloadParserFailureKind.unsupportedTemplate,
        'The search template is not a valid HTTPS location.',
      );
    }
  }
  throw const PayloadParserException(
    PayloadParserFailureKind.unsupportedTemplate,
    'No supported Atom search template was found.',
  );
}

/// A small, sendable description of a payload failure.
///
/// Parsers deliberately never expose an original response body or an exception
/// object: both would make the future isolate boundary fragile (and could leak
/// credentials embedded in an upstream error response).
enum PayloadParserFailureKind {
  invalidUtf8,
  malformedJson,
  malformedXml,
  unexpectedTopLevelShape,
  missingRequiredField,
  unsupportedTemplate,
  sourceApiError,
}

class PayloadParserException implements Exception {
  const PayloadParserException(this.kind, this.detail, {this.itemIndex});

  final PayloadParserFailureKind kind;
  final String detail;
  final int? itemIndex;

  @override
  String toString() => 'PayloadParserException(${kind.name})';
}

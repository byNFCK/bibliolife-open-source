/// Sendable measurements produced by a pure payload parser.
class ParserDiagnostics {
  const ParserDiagnostics({
    required this.parserType,
    required this.encodedByteCount,
    required this.decodeMicros,
    required this.parseMicros,
    required this.extractMicros,
    required this.itemCount,
    required this.skippedItemCount,
    this.execution = 'local',
    this.failureStage,
    this.failureCategory,
  });

  final String parserType;
  final int encodedByteCount;
  final int decodeMicros;
  final int parseMicros;
  final int extractMicros;
  final int itemCount;
  final int skippedItemCount;
  final String execution;
  final String? failureStage;
  final String? failureCategory;
}

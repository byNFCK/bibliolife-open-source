enum RemoteAcquisitionKind { generic, openAccess, borrow, buy, sample, unknown }

class RemoteAcquisition {
  RemoteAcquisition({
    required this.relation,
    required this.href,
    required this.mediaType,
    this.title,
    this.sizeBytes,
    Iterable<String> indirectMediaTypes = const [],
    this.requiresAuthentication = false,
    this.isSecure = true,
    this.isMalformed = false,
  }) : indirectMediaTypes = List.unmodifiable(indirectMediaTypes);

  final String relation;
  final String href;
  final String? mediaType;
  final String? title;
  final int? sizeBytes;
  final List<String> indirectMediaTypes;
  final bool requiresAuthentication;
  final bool isSecure;
  final bool isMalformed;

  RemoteAcquisitionKind get kind {
    final value = relation.toLowerCase();
    if (value.endsWith('/open-access')) return RemoteAcquisitionKind.openAccess;
    if (value.endsWith('/borrow')) return RemoteAcquisitionKind.borrow;
    if (value.endsWith('/buy')) return RemoteAcquisitionKind.buy;
    if (value.endsWith('/sample')) return RemoteAcquisitionKind.sample;
    if (value == 'http://opds-spec.org/acquisition') {
      return RemoteAcquisitionKind.generic;
    }
    return RemoteAcquisitionKind.unknown;
  }

  bool get isIndirect => indirectMediaTypes.isNotEmpty;
  String? get expectedFinalMediaType =>
      isIndirect ? indirectMediaTypes.last : mediaType;
  bool get advertisesEpub =>
      expectedFinalMediaType?.toLowerCase() == 'application/epub+zip';
  bool get isDirectSupportedEpub =>
      !isIndirect &&
      mediaType?.toLowerCase() == 'application/epub+zip' &&
      isSecure &&
      !isMalformed &&
      !requiresAuthentication;
}

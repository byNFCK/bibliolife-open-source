enum CatalogSourceUrlFailure {
  emptyUrl,
  malformedUrl,
  unsupportedScheme,
  insecureHttp,
  missingHost,
}

class CatalogSourceUrlResult {
  const CatalogSourceUrlResult._(this.uri, this.failure);
  final Uri? uri;
  final CatalogSourceUrlFailure? failure;
  bool get isValid => uri != null;
}

class CatalogSourceUrlNormalizer {
  const CatalogSourceUrlNormalizer._();
  static CatalogSourceUrlResult normalize(String input) {
    final raw = input.trim();
    if (raw.isEmpty) {
      return const CatalogSourceUrlResult._(
        null,
        CatalogSourceUrlFailure.emptyUrl,
      );
    }
    Uri uri;
    try {
      uri = Uri.parse(raw);
    } catch (_) {
      return const CatalogSourceUrlResult._(
        null,
        CatalogSourceUrlFailure.malformedUrl,
      );
    }
    if (uri.scheme.toLowerCase() != 'https') {
      return CatalogSourceUrlResult._(
        null,
        uri.scheme.toLowerCase() == 'http'
            ? CatalogSourceUrlFailure.insecureHttp
            : CatalogSourceUrlFailure.unsupportedScheme,
      );
    }
    if (uri.host.isEmpty) {
      return const CatalogSourceUrlResult._(
        null,
        CatalogSourceUrlFailure.missingHost,
      );
    }
    return CatalogSourceUrlResult._(
      Uri(
        scheme: 'https',
        host: uri.host.toLowerCase(),
        port: uri.hasPort && uri.port != 443 ? uri.port : null,
        path: uri.path.isEmpty ? '/' : uri.path,
        query: uri.hasQuery ? uri.query : null,
      ),
      null,
    );
  }
}

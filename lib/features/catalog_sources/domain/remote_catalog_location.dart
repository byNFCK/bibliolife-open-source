class RemoteCatalogLocation {
  RemoteCatalogLocation._(this._canonicalUri);

  final Uri _canonicalUri;

  factory RemoteCatalogLocation.parse(String value) =>
      RemoteCatalogLocation.fromUri(Uri.parse(value.trim()));

  factory RemoteCatalogLocation.fromUri(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty) {
      throw const FormatException(
        'Remote catalog locations must be absolute HTTPS locations.',
      );
    }
    return RemoteCatalogLocation._(
      Uri(
        scheme: 'https',
        host: uri.host.toLowerCase(),
        port: uri.hasPort && uri.port != 443 ? uri.port : null,
        path: uri.path.isEmpty ? '/' : uri.path,
        query: uri.hasQuery ? uri.query : null,
      ),
    );
  }

  RemoteCatalogLocation resolve(String reference) =>
      RemoteCatalogLocation.fromUri(_canonicalUri.resolve(reference.trim()));

  Uri get uri => _canonicalUri;

  @override
  String toString() => _canonicalUri.toString();

  @override
  bool operator ==(Object other) =>
      other is RemoteCatalogLocation && other._canonicalUri == _canonicalUri;

  @override
  int get hashCode => _canonicalUri.hashCode;
}

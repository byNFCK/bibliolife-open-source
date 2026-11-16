import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';

abstract final class RemoteHomePublicationIdentity {
  static String? canonical({
    required String sourceId,
    required RemoteCatalogPublicationSummary publication,
  }) {
    final remoteId = canonicalRemoteId(
      sourceId: sourceId,
      remotePublicationId: publication.remoteId,
    );
    if (remoteId != null) return remoteId;
    final details = _canonicalUri(publication.detailsLocation?.uri);
    if (details != null) return '$sourceId\u0000details:$details';
    for (final acquisition in publication.acquisitions) {
      final uri = Uri.tryParse(acquisition.href);
      final canonical = _canonicalUri(uri);
      if (canonical != null) return '$sourceId\u0000acquisition:$canonical';
    }
    return null;
  }

  static String? canonicalRemoteId({
    required String sourceId,
    required String remotePublicationId,
  }) {
    final value = remotePublicationId.trim();
    if (value.isEmpty) return null;
    if (sourceId.toLowerCase().contains('gutenberg')) {
      final ebookId = _gutenbergEbookId(value);
      if (ebookId != null) return '$sourceId\u0000gutenberg:$ebookId';
    }
    final uri = Uri.tryParse(value);
    final canonicalUri = _canonicalUri(uri);
    return '$sourceId\u0000id:${canonicalUri ?? value}';
  }

  static String? _gutenbergEbookId(String value) {
    final numeric = RegExp(r'^\d+$').firstMatch(value);
    if (numeric != null) return numeric.group(0);
    final uriPath = Uri.tryParse(value)?.path;
    final pathId = RegExp(
      r'(?:^|/)ebooks/(\d+)(?!\d)',
      caseSensitive: false,
    ).firstMatch(uriPath ?? value)?.group(1);
    if (pathId != null) return pathId;
    return RegExp(
      r'(?:^|:)gutenberg:(\d+)(?!\d)',
      caseSensitive: false,
    ).firstMatch(value)?.group(1);
  }

  static String? _canonicalUri(Uri? uri) {
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    var path = uri.path;
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return uri
        .replace(
          scheme: uri.scheme.toLowerCase(),
          host: uri.host.toLowerCase(),
          path: path,
          fragment: '',
        )
        .toString();
  }
}

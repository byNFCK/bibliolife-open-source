import 'dart:typed_data';

import 'package:bibliolife/core/network/request_cancellation.dart';
import 'package:bibliolife/features/catalog_sources/data/http_opds_remote_catalog_transport.dart';
import 'package:bibliolife/features/catalog_sources/data/internet_archive_metadata_parser.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_payload_parser_dispatcher.dart';
import 'package:bibliolife/features/catalog_sources/data/payload_parser_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/internet_archive_acquisition.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';

/// Looks up an Internet Archive identifier in its metadata API.  A download URL
/// is formed only after the API has supplied a concrete public EPUB filename.
class HttpInternetArchiveAcquisitionResolver
    implements InternetArchiveAcquisitionResolver {
  HttpInternetArchiveAcquisitionResolver({
    HttpCatalogClient? client,
    this.parserDispatcher,
  }) : _client = client ?? IoHttpCatalogClient();

  final HttpCatalogClient _client;
  final MetadataPayloadParserDispatcher? parserDispatcher;

  @override
  Future<InternetArchiveAcquisitionResult> resolve(
    Iterable<String> identifiers,
  ) async {
    for (final raw in identifiers) {
      throwIfMetadataRequestCancelled();
      final identifier = raw.trim();
      if (!_safeIdentifier(identifier)) continue;
      final response = await _client.get(
        location: RemoteCatalogLocation.fromUri(
          Uri.https('archive.org', '/metadata/$identifier'),
        ),
        headers: const {'Accept': 'application/json'},
        timeout: const Duration(seconds: 15),
        maximumResponseBytes: 2 * 1024 * 1024,
        maximumRedirects: 5,
      );
      if (response.statusCode == 401 || response.statusCode == 403) {
        return InternetArchiveAcquisitionResult.borrowingRequired(
          identifier: identifier,
        );
      }
      if (response.statusCode != 200) continue;
      throwIfMetadataRequestCancelled();
      final bytes = Uint8List.fromList(response.bodyBytes);
      late final ParsedInternetArchiveMetadata parsed;
      try {
        parsed = parserDispatcher == null
            ? parseInternetArchiveMetadata(bytes)
            : await parserDispatcher!.internetArchive(
                bytes,
                sourceId: identifier,
              );
      } on PayloadParserException {
        return const InternetArchiveAcquisitionResult.metadataOnly();
      }
      throwIfMetadataRequestCancelled();
      if (parsed.borrowOnly) {
        return InternetArchiveAcquisitionResult.borrowingRequired(
          identifier: identifier,
        );
      }
      final file = _publicFile(parsed.files);
      if (file != null) {
        final uri = Uri.https(
          'archive.org',
          '/download/$identifier/${file.$1}',
        );
        return switch (file.$2) {
          'application/epub+zip' => InternetArchiveAcquisitionResult.directEpub(
            identifier: identifier,
            uri: uri,
          ),
          'application/pdf' => InternetArchiveAcquisitionResult.directPdf(
            identifier: identifier,
            uri: uri,
          ),
          _ => const InternetArchiveAcquisitionResult.metadataOnly(),
        };
      }
    }
    return const InternetArchiveAcquisitionResult.metadataOnly();
  }

  bool _safeIdentifier(String value) =>
      value.isNotEmpty && RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value);

  (String, String)? _publicFile(Iterable<ParsedInternetArchiveFile> files) {
    for (final item in files) {
      final name = item.name;
      final lowerName = name.toLowerCase();
      final mediaType = switch (true) {
        _ when lowerName.endsWith('.epub') => 'application/epub+zip',
        _ when lowerName.endsWith('.pdf') => 'application/pdf',
        _ => null,
      };
      if (mediaType == null ||
          _isLcpProtectedFile(lowerName) ||
          name.contains('/') ||
          name.contains('..') ||
          item.isPrivate) {
        continue;
      }
      return (name, mediaType);
    }
    return null;
  }

  bool _isLcpProtectedFile(String fileName) =>
      RegExp(r'(^|[_.-])lcp([_.-]|$)').hasMatch(fileName);
}

import 'dart:typed_data';

import 'package:bibliolife/core/network/request_cancellation.dart';
import 'package:bibliolife/core/performance/online_pipeline_performance.dart';
import 'package:bibliolife/features/catalog_sources/data/google_books_payload_parser.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_parser_executor.dart';
import 'package:bibliolife/features/catalog_sources/data/metadata_parsing_policy.dart';
import 'package:bibliolife/features/catalog_sources/data/open_library_payload_parser.dart';
import 'package:bibliolife/features/catalog_sources/data/open_search_description_parser.dart';
import 'package:bibliolife/features/catalog_sources/data/opds1_atom_parser.dart';
import 'package:bibliolife/features/catalog_sources/data/internet_archive_metadata_parser.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';

class MetadataPayloadParserDispatcher {
  const MetadataPayloadParserDispatcher(this.policy, this.executor);
  final MetadataParsingPolicy policy;
  final MetadataParserExecutor executor;

  Future<ParsedGoogleBooksPage> google(
    Uint8List bytes, {
    required String sourceId,
    required bool details,
  }) => _run(
    type: MetadataParserType.googleBooks,
    bytes: bytes,
    sourceId: sourceId,
    details: details,
    local: () => parseGoogleBooksPayload(bytes, details: details),
  );
  Future<ParsedOpenLibraryPage> openLibrary(
    Uint8List bytes, {
    required String sourceId,
  }) => _run(
    type: MetadataParserType.openLibrary,
    bytes: bytes,
    sourceId: sourceId,
    local: () => parseOpenLibraryPayload(bytes),
  );
  Future<ParsedOpdsFeed> opds(
    Uint8List bytes, {
    required String sourceId,
    required RemoteCatalogLocation location,
    required bool search,
  }) => _run(
    type: MetadataParserType.opds,
    bytes: bytes,
    sourceId: sourceId,
    baseUri: location.toString(),
    local: () => const Opds1AtomParser().parseBytes(
      sourceId: sourceId,
      location: location,
      bytes: bytes,
      isSearchResult: search,
    ),
  );
  Future<ParsedOpenSearchDescription> openSearch(
    Uint8List bytes, {
    required String sourceId,
    required String baseUri,
  }) => _run(
    type: MetadataParserType.openSearch,
    bytes: bytes,
    sourceId: sourceId,
    baseUri: baseUri,
    local: () => parseOpenSearchDescriptionPayload(bytes, baseUri: baseUri),
  );
  Future<ParsedInternetArchiveMetadata> internetArchive(
    Uint8List bytes, {
    required String sourceId,
  }) => _run(
    type: MetadataParserType.internetArchive,
    bytes: bytes,
    sourceId: sourceId,
    local: () => parseInternetArchiveMetadata(bytes),
  );

  Future<T> _run<T>({
    required MetadataParserType type,
    required Uint8List bytes,
    required String sourceId,
    String? baseUri,
    bool details = false,
    required T Function() local,
  }) async {
    throwIfMetadataRequestCancelled();
    final background = policy.shouldUseBackground(type, bytes.length);
    if (type != MetadataParserType.googleBooks) {
      onlinePerformanceMarker(
        'parser_execution',
        fields: {
          'source': sourceId,
          'type': type.name,
          'mode': background ? 'background' : 'local',
        },
      );
    }
    if (!background) return local();
    final token = MetadataRequestScope.current?.token;
    if (token == null) return local();
    final result = await executor.submit(
      MetadataParserJob(
        id: '$sourceId-${DateTime.now().microsecondsSinceEpoch}',
        type: type,
        bytes: bytes,
        sourceId: sourceId,
        baseUri: baseUri,
        details: details,
      ),
      token,
    );
    throwIfMetadataRequestCancelled();
    return result as T;
  }
}

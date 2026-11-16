import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_access_hint.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';

class BookSourceRecord {
  BookSourceRecord({
    required this.sourceId,
    required this.remoteId,
    required this.sourcePriority,
    required this.publication,
  });

  factory BookSourceRecord.fromPublication({
    required String sourceId,
    required int sourcePriority,
    required RemoteCatalogPublicationSummary publication,
  }) => BookSourceRecord(
      sourceId: sourceId,
      remoteId: publication.remoteId,
      sourcePriority: sourcePriority,
      publication: publication,
    );

  final String sourceId;
  final String remoteId;
  final int sourcePriority;
  final RemoteCatalogPublicationSummary publication;

  String get title => publication.title;
  List<String> get identifiers => publication.identifiers;
  List<RemoteCatalogLocation> get imageCandidates =>
      publication.imageCandidates;
  List<RemoteCatalogAccessHint> get accessHints => publication.accessHints;
  Map<String, String> get accessMetadata => publication.accessMetadata;
  Map<String, String> get sourceMetadata => publication.sourceMetadata;
  Map<String, List<String>> get sourceLists => publication.sourceLists;
  List<RemoteCatalogLocation> get sourceLinks => publication.sourceLinks;
  RemoteCatalogLocation? get detailsLocation => publication.detailsLocation;
}

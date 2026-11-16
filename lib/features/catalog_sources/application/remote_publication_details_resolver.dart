import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download_plan.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_access_hint.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:flutter/foundation.dart';

enum RemotePublicationAvailability { downloadable, metadataOnly, unavailable }

class RemotePublicationDetailsResolution {
  const RemotePublicationDetailsResolution._({
    required this.publication,
    required this.availability,
    this.unavailableMessage,
  });

  factory RemotePublicationDetailsResolution.downloadable(
    RemoteCatalogPublicationSummary publication,
  ) => RemotePublicationDetailsResolution._(
    publication: publication,
    availability: RemotePublicationAvailability.downloadable,
  );

  factory RemotePublicationDetailsResolution.unavailable(
    RemoteCatalogPublicationSummary publication,
    String message,
  ) => RemotePublicationDetailsResolution._(
    publication: publication,
    availability: RemotePublicationAvailability.unavailable,
    unavailableMessage: message,
  );

  factory RemotePublicationDetailsResolution.metadataOnly(
    RemoteCatalogPublicationSummary publication,
    String message,
  ) => RemotePublicationDetailsResolution._(
    publication: publication,
    availability: RemotePublicationAvailability.metadataOnly,
    unavailableMessage: message,
  );

  final RemoteCatalogPublicationSummary publication;
  final RemotePublicationAvailability availability;
  final String? unavailableMessage;
}

/// Resolves lightweight search records before download planning. Search result
/// identity is preserved; only metadata and acquisitions are enriched.
class RemotePublicationDetailsResolver {
  RemotePublicationDetailsResolver(this._sources, this._gateway);

  final CatalogSourceRepository _sources;
  final RemoteCatalogGateway _gateway;

  Future<RemotePublicationDetailsResolution> resolve({
    required String sourceId,
    required RemoteCatalogPublicationSummary publication,
  }) async {
    if (_hasSupportedEpub(sourceId, publication)) {
      return RemotePublicationDetailsResolution.downloadable(publication);
    }

    final source = await _sources.getById(sourceId);
    if (source == null) {
      throw StateError('The online library is no longer available.');
    }
    if (source.type == CatalogSourceType.openLibrary) {
      _log(
        'REMOTE_DETAILS_METADATA_ONLY source=$sourceId remoteId=${publication.remoteId} reason=openLibraryWorkHasNoDirectEpub',
      );
      return RemotePublicationDetailsResolution.metadataOnly(
        publication,
        'Open Library lists this work, but does not provide a downloadable EPUB for it.',
      );
    }
    final details = publication.detailsLocation;
    if (details == null) {
      return RemotePublicationDetailsResolution.metadataOnly(
        publication,
        'This library did not provide a downloadable EPUB for this title.',
      );
    }

    _log(
      'REMOTE_DETAILS_HYDRATE source=$sourceId remoteId=${publication.remoteId} location=$details',
    );
    final page = await _gateway.loadPage(
      source: source.isEnabled ? source : source.copyWith(isEnabled: true),
      location: details,
    );
    final hydrated = _matchingPublication(page.publications, publication);
    if (hydrated == null) {
      throw StateError('The library did not return details for this title.');
    }
    final resolved = _merge(publication, hydrated);
    if (_hasSupportedEpub(sourceId, resolved)) {
      _log(
        'REMOTE_DETAILS_RESOLVED source=$sourceId remoteId=${publication.remoteId} acquisitions=${resolved.acquisitions.length}',
      );
      return RemotePublicationDetailsResolution.downloadable(resolved);
    }
    if (source.type == CatalogSourceType.googleBooks) {
      final preview = resolved.accessHints.any(
        (hint) =>
            hint.type == RemoteCatalogAccessType.preview ||
            hint.type == RemoteCatalogAccessType.externalRead,
      );
      return RemotePublicationDetailsResolution.metadataOnly(
        resolved,
        preview
            ? 'Google Books loaded this book’s metadata. Preview information is available, but no verified direct EPUB download is offered.'
            : 'Google Books loaded this book’s metadata, but does not offer a verified direct EPUB download.',
      );
    }
    return RemotePublicationDetailsResolution.unavailable(
      resolved,
      '${source.name} did not provide a downloadable EPUB for this title.',
    );
  }

  bool _hasSupportedEpub(
    String sourceId,
    RemoteCatalogPublicationSummary publication,
  ) {
    final plan = const RemoteBookDownloadPlanner()
        .create(sourceId: sourceId, publication: publication)
        .plan;
    return plan?.acquisitionUri != null && plan!.supported && !plan.isIndirect;
  }

  RemoteCatalogPublicationSummary? _matchingPublication(
    List<RemoteCatalogPublicationSummary> publications,
    RemoteCatalogPublicationSummary searchResult,
  ) {
    for (final publication in publications) {
      if (publication.remoteId == searchResult.remoteId) return publication;
    }
    if (publications.length == 1) return publications.single;
    final sameTitle = publications
        .where(
          (publication) =>
              publication.title.trim().toLowerCase() ==
              searchResult.title.trim().toLowerCase(),
        )
        .toList(growable: false);
    if (sameTitle.isEmpty) return null;
    final first = sameTitle.first;
    // Gutenberg details may contain several EPUB renditions as independent
    // entries with variant entry IDs. Combine their acquisitions so the
    // established EPUB selector can choose the best direct rendition.
    return RemoteCatalogPublicationSummary(
      remoteId: first.remoteId,
      title: first.title,
      subtitle: first.subtitle,
      authors: first.authors,
      coverLocation: first.coverLocation,
      imageCandidates: first.imageCandidates,
      summary: first.summary,
      acquisitions: [
        for (final publication in sameTitle) ...publication.acquisitions,
      ],
      publisher: first.publisher,
      language: first.language,
      publishedDate: first.publishedDate,
      identifiers: first.identifiers,
      subjects: first.subjects,
      rights: first.rights,
      detailsLocation: first.detailsLocation,
      pageCount: first.pageCount,
      accessHints: first.accessHints,
      accessMetadata: first.accessMetadata,
    );
  }

  RemoteCatalogPublicationSummary _merge(
    RemoteCatalogPublicationSummary searchResult,
    RemoteCatalogPublicationSummary details,
  ) => RemoteCatalogPublicationSummary(
    remoteId: searchResult.remoteId,
    title: details.title.isNotEmpty ? details.title : searchResult.title,
    subtitle: details.subtitle ?? searchResult.subtitle,
    authors: details.authors.isNotEmpty
        ? details.authors
        : searchResult.authors,
    coverLocation: details.coverLocation ?? searchResult.coverLocation,
    imageCandidates: details.imageCandidates.isNotEmpty
        ? details.imageCandidates
        : searchResult.imageCandidates,
    summary: details.summary ?? searchResult.summary,
    acquisitions: details.acquisitions,
    publisher: details.publisher ?? searchResult.publisher,
    language: details.language ?? searchResult.language,
    publishedDate: details.publishedDate ?? searchResult.publishedDate,
    identifiers: details.identifiers.isNotEmpty
        ? details.identifiers
        : searchResult.identifiers,
    subjects: details.subjects.isNotEmpty
        ? details.subjects
        : searchResult.subjects,
    rights: details.rights ?? searchResult.rights,
    detailsLocation: details.detailsLocation ?? searchResult.detailsLocation,
    pageCount: details.pageCount ?? searchResult.pageCount,
    accessHints: details.accessHints.isNotEmpty
        ? details.accessHints
        : searchResult.accessHints,
    accessMetadata: {...searchResult.accessMetadata, ...details.accessMetadata},
  );

  void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }
}

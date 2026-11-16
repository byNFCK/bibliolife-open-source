import 'package:bibliolife/features/catalog_sources/application/remote_publication_details_resolver.dart';
import 'package:bibliolife/features/catalog_sources/data/built_in_catalog_sources.dart';
import 'package:bibliolife/features/catalog_sources/domain/canonical_acquisition_resolution.dart';
import 'package:bibliolife/features/catalog_sources/domain/canonical_book.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/internet_archive_acquisition.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download_plan.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_access_hint.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/metadata/domain/entities/trusted_remote_book_metadata.dart';
import 'package:flutter/foundation.dart';

/// Selects one safe action for a canonical work while retaining all lower
/// priority source candidates for diagnostics and future UI affordances.
class CanonicalAcquisitionResolver {
  CanonicalAcquisitionResolver(
    this._sources,
    this._gateway,
    this._internetArchive, {
    this._debugLog,
  });

  final CatalogSourceRepository _sources;
  final RemoteCatalogGateway _gateway;
  final InternetArchiveAcquisitionResolver _internetArchive;
  final void Function(String)? _debugLog;

  Future<AcquisitionResolution> resolve(CanonicalBook book) async {
    _log('ACQUISITION_RESOLUTION_STARTED canonicalId=${book.canonicalId}');
    final candidates = <ResolvedAcquisition>[];
    final failures = <AcquisitionSourceFailure>[];
    final publications = <String, RemoteCatalogPublicationSummary>{};
    final details = RemotePublicationDetailsResolver(_sources, _gateway);
    final internetArchiveSource = await _sources.getById(
      internetArchiveCatalogSourceId,
    );
    final internetArchiveEnabled = internetArchiveSource?.isEnabled ?? false;

    final records = [...book.sources]
      ..sort(
        (a, b) => _sourceRank(
          a.sourceId,
          a.sourcePriority,
        ).compareTo(_sourceRank(b.sourceId, b.sourcePriority)),
      );
    for (final record in records) {
      final source = await _sources.getById(record.sourceId);
      if (source == null) {
        failures.add(
          AcquisitionSourceFailure(
            sourceId: record.sourceId,
            sourceRemoteId: record.remoteId,
            error: StateError('Source was removed.'),
            recoverable: false,
          ),
        );
        continue;
      }
      try {
        final resolved = await details.resolve(
          sourceId: source.id,
          publication: record.publication,
        );
        publications[source.id] = resolved.publication;
        candidates.addAll(
          _candidatesForPublication(
            source: source,
            publication: resolved.publication,
            canonical: book,
          ),
        );
      } on Object catch (error) {
        failures.add(
          AcquisitionSourceFailure(
            sourceId: source.id,
            sourceRemoteId: record.remoteId,
            error: error,
            recoverable: true,
          ),
        );
        _log(
          'ACQUISITION_CANDIDATE_REJECTED canonicalId=${book.canonicalId} sourceId=${source.id} remoteId=${record.remoteId} reason=detailsFailure',
        );
      }
      if (source.type == CatalogSourceType.openLibrary &&
          internetArchiveEnabled &&
          internetArchiveSource != null) {
        try {
          final archive = await _internetArchive.resolve(
            record.publication.sourceLists['openLibrary.internetArchiveIds'] ??
                const [],
          );
          final candidate = _internetArchiveCandidate(
            internetArchiveSource,
            record.publication,
            book,
            archive,
          );
          if (candidate != null) {
            candidates.add(candidate);
            publications[internetArchiveSource.id] = record.publication;
          }
        } on Object catch (error) {
          failures.add(
            AcquisitionSourceFailure(
              sourceId: source.id,
              sourceRemoteId: record.remoteId,
              error: error,
              recoverable: true,
            ),
          );
          _log(
            'ACQUISITION_CANDIDATE_REJECTED canonicalId=${book.canonicalId} sourceId=${source.id} remoteId=${record.remoteId} reason=internetArchiveFailure',
          );
        }
      }
    }

    final direct =
        candidates.where((item) => item.isVerifiedDirectEpub).toList()
          ..sort((a, b) => a.priority.compareTo(b.priority));
    if (direct.isNotEmpty) {
      final selected = direct.first;
      _log(
        'ACQUISITION_SELECTED canonicalId=${book.canonicalId} sourceId=${selected.sourceId} remoteId=${selected.sourceRemoteId} priority=${selected.priority} validation=${selected.validationState.name}',
      );
      return AcquisitionResolution(
        availability: direct.length > 1
            ? AcquisitionAvailability.multipleDirectEpubCandidates
            : AcquisitionAvailability.directEpubAvailable,
        candidates: candidates,
        failures: failures,
        selected: selected,
        selectedPublication: publications[selected.sourceId],
      );
    }

    final actions =
        candidates
            .where(
              (item) =>
                  item.uri != null ||
                  item.accessType ==
                      RemoteCatalogAccessType.authenticatedDownload,
            )
            .toList()
          ..sort((a, b) => a.priority.compareTo(b.priority));
    final selected = actions.firstOrNull;
    final availability = _nonDownloadAvailability(selected, failures);
    if (selected != null) {
      _log(
        'ACQUISITION_SELECTED canonicalId=${book.canonicalId} sourceId=${selected.sourceId} remoteId=${selected.sourceRemoteId} accessType=${selected.accessType.name} priority=${selected.priority}',
      );
    } else {
      _log(
        'ACQUISITION_NO_DIRECT_FILE canonicalId=${book.canonicalId} failures=${failures.length}',
      );
    }
    return AcquisitionResolution(
      availability: availability,
      candidates: candidates,
      failures: failures,
      selected: selected,
      selectedPublication: selected == null
          ? null
          : publications[selected.sourceId],
    );
  }

  List<ResolvedAcquisition> _candidatesForPublication({
    required CatalogSource source,
    required RemoteCatalogPublicationSummary publication,
    required CanonicalBook canonical,
  }) {
    final result = <ResolvedAcquisition>[];
    final directHint = publication.accessHints.where(
      (hint) =>
          hint.type == RemoteCatalogAccessType.directDownload &&
          hint.uri != null &&
          hint.mediaType?.toLowerCase() == 'application/epub+zip' &&
          hint.isFullBook &&
          hint.isDrmFree == true &&
          !hint.requiresAuthentication,
    );
    for (final hint in directHint) {
      final plan = _planFromHint(source, publication, hint, canonical);
      if (plan == null) continue;
      result.add(
        ResolvedAcquisition(
          sourceId: source.id,
          sourceRemoteId: publication.remoteId,
          uri: hint.uri,
          mediaType: hint.mediaType,
          accessType: hint.type,
          fullBook: true,
          drmFree: true,
          requiresAuthentication: false,
          validationState: AcquisitionValidationState.metadataVerified,
          priority: _directPriority(source, null),
          provenance: '${source.name} access metadata',
          plan: plan,
        ),
      );
      _log(
        'ACQUISITION_CANDIDATE_VALIDATED canonicalId=${canonical.canonicalId} sourceId=${source.id} remoteId=${publication.remoteId} mediaType=application/epub+zip validation=metadataVerified',
      );
    }
    final basePlan = const RemoteBookDownloadPlanner()
        .create(sourceId: source.id, publication: publication)
        .plan;
    final planned = basePlan == null
        ? null
        : _withCanonicalMetadata(basePlan, canonical, publication);
    if (planned != null && planned.supported && !planned.isIndirect) {
      final withImages = _hasImages(planned);
      result.add(
        ResolvedAcquisition(
          sourceId: source.id,
          sourceRemoteId: publication.remoteId,
          uri: planned.acquisitionUri,
          mediaType: planned.declaredMediaType,
          accessType: RemoteCatalogAccessType.directDownload,
          fullBook: true,
          drmFree: true,
          requiresAuthentication: false,
          validationState: AcquisitionValidationState.metadataVerified,
          priority: _directPriority(source, withImages),
          provenance: '${source.name} direct acquisition',
          plan: planned,
        ),
      );
      _log(
        'ACQUISITION_CANDIDATE_VALIDATED canonicalId=${canonical.canonicalId} sourceId=${source.id} remoteId=${publication.remoteId} mediaType=application/epub+zip validation=metadataVerified',
      );
    }
    for (final hint in publication.accessHints) {
      if (hint.uri == null ||
          hint.type == RemoteCatalogAccessType.directDownload) {
        continue;
      }
      result.add(
        ResolvedAcquisition(
          sourceId: source.id,
          sourceRemoteId: publication.remoteId,
          uri: hint.uri,
          mediaType: hint.mediaType,
          accessType: hint.type,
          fullBook: hint.isFullBook,
          drmFree: hint.isDrmFree == true,
          requiresAuthentication: hint.requiresAuthentication,
          validationState: AcquisitionValidationState.metadataClassified,
          priority: _actionPriority(hint.type),
          provenance: '${source.name} access metadata',
        ),
      );
      _log(
        'ACQUISITION_CANDIDATE_DISCOVERED canonicalId=${canonical.canonicalId} sourceId=${source.id} remoteId=${publication.remoteId} accessType=${hint.type.name}',
      );
    }
    return result;
  }

  ResolvedAcquisition? _internetArchiveCandidate(
    CatalogSource source,
    RemoteCatalogPublicationSummary publication,
    CanonicalBook canonical,
    InternetArchiveAcquisitionResult result,
  ) {
    switch (result.availability) {
      case InternetArchiveAvailability.directEpub:
      case InternetArchiveAvailability.directPdf:
        final uri = result.uri;
        if (uri == null || result.identifier == null) return null;
        final plan = _planForDirectUri(
          source: source,
          publication: publication,
          uri: uri,
          provenanceId: result.identifier!,
          canonical: canonical,
        );
        _log(
          'ACQUISITION_CANDIDATE_VALIDATED canonicalId=${canonical.canonicalId} sourceId=${source.id} remoteId=${result.identifier} mediaType=application/epub+zip validation=metadataVerified',
        );
        return ResolvedAcquisition(
          sourceId: source.id,
          sourceRemoteId: result.identifier!,
          uri: uri,
          mediaType: result.mediaType,
          accessType: RemoteCatalogAccessType.directDownload,
          fullBook: true,
          drmFree: true,
          requiresAuthentication: false,
          validationState: AcquisitionValidationState.metadataVerified,
          priority: 40,
          provenance: 'Internet Archive metadata file entry',
          plan: plan,
        );
      case InternetArchiveAvailability.borrowingRequired:
        return ResolvedAcquisition(
          sourceId: source.id,
          sourceRemoteId: result.identifier ?? publication.remoteId,
          accessType: RemoteCatalogAccessType.authenticatedDownload,
          fullBook: true,
          drmFree: false,
          requiresAuthentication: true,
          validationState: AcquisitionValidationState.metadataClassified,
          priority: 60,
          provenance: 'Internet Archive lending metadata',
        );
      case InternetArchiveAvailability.metadataOnly:
        return null;
    }
  }

  RemoteBookDownloadPlan? _planFromHint(
    CatalogSource source,
    RemoteCatalogPublicationSummary publication,
    RemoteCatalogAccessHint hint,
    CanonicalBook canonical,
  ) {
    final uri = hint.uri;
    if (uri == null || uri.scheme.toLowerCase() != 'https') return null;
    return _planForDirectUri(
      source: source,
      publication: publication,
      uri: uri,
      provenanceId: publication.remoteId,
      canonical: canonical,
    );
  }

  RemoteBookDownloadPlan _planForDirectUri({
    required CatalogSource source,
    required RemoteCatalogPublicationSummary publication,
    required Uri uri,
    required String provenanceId,
    required CanonicalBook canonical,
  }) => RemoteBookDownloadPlan(
    sourceId: source.id,
    publicationRemoteId: provenanceId,
    publicationTitle: publication.title,
    authors: publication.authors,
    acquisitionUri: uri,
    declaredMediaType: 'application/epub+zip',
    acquisitionRelation: 'http://opds-spec.org/acquisition/open-access',
    isIndirect: false,
    expectedFinalMediaType: 'application/epub+zip',
    expectedSizeBytes: null,
    suggestedFilename: suggestEpubFilename(publication.title),
    requiresAuthentication: false,
    supported: true,
    unsupportedReason: null,
    remoteMetadata: _canonicalMetadata(
      canonical,
      publication,
      sourceId: source.id,
      publicationId: provenanceId,
      acquisitionUri: uri,
    ),
  );

  RemoteBookDownloadPlan _withCanonicalMetadata(
    RemoteBookDownloadPlan plan,
    CanonicalBook canonical,
    RemoteCatalogPublicationSummary publication,
  ) => RemoteBookDownloadPlan(
    sourceId: plan.sourceId,
    publicationRemoteId: plan.publicationRemoteId,
    publicationTitle: canonical.title ?? plan.publicationTitle,
    authors: canonical.authors.isEmpty ? plan.authors : canonical.authors,
    acquisitionUri: plan.acquisitionUri,
    declaredMediaType: plan.declaredMediaType,
    acquisitionRelation: plan.acquisitionRelation,
    isIndirect: plan.isIndirect,
    expectedFinalMediaType: plan.expectedFinalMediaType,
    expectedSizeBytes: plan.expectedSizeBytes,
    suggestedFilename: plan.suggestedFilename,
    requiresAuthentication: plan.requiresAuthentication,
    supported: plan.supported,
    unsupportedReason: plan.unsupportedReason,
    remoteMetadata: _canonicalMetadata(
      canonical,
      publication,
      sourceId: plan.sourceId,
      publicationId: plan.publicationRemoteId,
      acquisitionUri: plan.acquisitionUri!,
    ),
  );

  TrustedRemoteBookMetadata _canonicalMetadata(
    CanonicalBook canonical,
    RemoteCatalogPublicationSummary publication, {
    required String sourceId,
    required String publicationId,
    required Uri acquisitionUri,
  }) => TrustedRemoteBookMetadata(
    sourceId: sourceId,
    publicationId: publicationId,
    title: canonical.title ?? publication.title,
    authors: canonical.authors.isEmpty
        ? publication.authors
        : canonical.authors,
    description: canonical.description ?? publication.summary,
    publisher: canonical.publisher ?? publication.publisher,
    language: canonical.language ?? publication.language,
    publishedDate: canonical.publishedDate ?? publication.publishedDate,
    identifiers: {
      ...publication.identifiers,
      ...canonical.identifiers.isbn13,
      ...canonical.identifiers.isbn10,
      ...canonical.identifiers.other,
    }.toList(growable: false),
    subjects: canonical.categories.isEmpty
        ? publication.subjects
        : canonical.categories,
    rights: publication.rights,
    publicationLocation: publication.detailsLocation?.uri,
    acquisitionLocation: acquisitionUri,
  );

  AcquisitionAvailability _nonDownloadAvailability(
    ResolvedAcquisition? selected,
    List<AcquisitionSourceFailure> failures,
  ) => switch (selected?.accessType) {
    RemoteCatalogAccessType.authenticatedDownload =>
      AcquisitionAvailability.borrowingRequired,
    RemoteCatalogAccessType.externalRead =>
      AcquisitionAvailability.externalReadingAvailable,
    RemoteCatalogAccessType.preview ||
    RemoteCatalogAccessType.sample => AcquisitionAvailability.previewAvailable,
    RemoteCatalogAccessType.purchase =>
      AcquisitionAvailability.purchaseAvailable,
    _ when selected == null && failures.isNotEmpty =>
      AcquisitionAvailability.allAcquisitionSourcesFailed,
    _ => AcquisitionAvailability.metadataOnly,
  };

  int _sourceRank(String sourceId, int configured) {
    if (sourceId.contains('google')) return 0;
    if (sourceId.contains('gutenberg')) return 10;
    if (sourceId.contains('open-library')) return 20;
    return 30 + configured;
  }

  int _directPriority(CatalogSource source, bool? withImages) =>
      switch (source.type) {
        CatalogSourceType.googleBooks => 0,
        _ when source.id.contains('gutenberg') && withImages == true => 10,
        _ when source.id.contains('gutenberg') => 20,
        CatalogSourceType.openLibrary => 40,
        _ => 50,
      };

  bool _hasImages(RemoteBookDownloadPlan plan) =>
      plan.suggestedFilename.toLowerCase().contains('images') ||
      (plan.acquisitionUri?.path.toLowerCase().contains('images') ?? false);

  int _actionPriority(RemoteCatalogAccessType type) => switch (type) {
    RemoteCatalogAccessType.authenticatedDownload => 60,
    RemoteCatalogAccessType.externalRead => 70,
    RemoteCatalogAccessType.preview || RemoteCatalogAccessType.sample => 80,
    RemoteCatalogAccessType.purchase => 90,
    _ => 100,
  };

  void _log(String message) {
    if (!kDebugMode) return;
    final log = _debugLog;
    if (log != null) {
      log(message);
    } else {
      debugPrint(message);
    }
  }
}

import 'package:bibliolife/features/catalog_sources/domain/remote_book_download_plan.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_access_hint.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';

/// The action that can safely be offered for a canonical work.  This is not a
/// boolean because a catalogue may describe a preview, a loan, and a purchase
/// alongside a downloadable file.
enum AcquisitionAvailability {
  directEpubAvailable,
  multipleDirectEpubCandidates,
  previewAvailable,
  externalReadingAvailable,
  borrowingRequired,
  purchaseAvailable,
  metadataOnly,
  recoverableSourceFailure,
  allAcquisitionSourcesFailed,
}

enum AcquisitionValidationState {
  metadataClassified,
  metadataVerified,
  downloadValidated,
  rejected,
}

class ResolvedAcquisition {
  const ResolvedAcquisition({
    required this.sourceId,
    required this.sourceRemoteId,
    required this.accessType,
    required this.fullBook,
    required this.drmFree,
    required this.requiresAuthentication,
    required this.validationState,
    required this.priority,
    required this.provenance,
    this.uri,
    this.mediaType,
    this.plan,
  });

  final String sourceId;
  final String sourceRemoteId;
  final Uri? uri;
  final String? mediaType;
  final RemoteCatalogAccessType accessType;
  final bool fullBook;
  final bool drmFree;
  final bool requiresAuthentication;
  final AcquisitionValidationState validationState;
  final int priority;
  final String provenance;
  final RemoteBookDownloadPlan? plan;

  bool get isVerifiedDirectEpub =>
      accessType == RemoteCatalogAccessType.directDownload &&
      fullBook &&
      drmFree &&
      !requiresAuthentication &&
      validationState == AcquisitionValidationState.metadataVerified &&
      plan != null;
}

class AcquisitionSourceFailure {
  const AcquisitionSourceFailure({
    required this.sourceId,
    required this.sourceRemoteId,
    required this.error,
    required this.recoverable,
  });

  final String sourceId;
  final String sourceRemoteId;
  final Object error;
  final bool recoverable;
}

class AcquisitionResolution {
  AcquisitionResolution({
    required this.availability,
    required Iterable<ResolvedAcquisition> candidates,
    required Iterable<AcquisitionSourceFailure> failures,
    this.selected,
    this.selectedPublication,
  }) : candidates = List.unmodifiable(candidates),
       failures = List.unmodifiable(failures);

  final AcquisitionAvailability availability;
  final List<ResolvedAcquisition> candidates;
  final List<AcquisitionSourceFailure> failures;
  final ResolvedAcquisition? selected;
  final RemoteCatalogPublicationSummary? selectedPublication;

  RemoteBookDownloadPlan? get downloadPlan => selected?.plan;
  bool get hasDirectDownload => selected?.isVerifiedDirectEpub ?? false;
}

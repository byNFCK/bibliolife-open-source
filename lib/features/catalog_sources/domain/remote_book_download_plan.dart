import 'package:bibliolife/features/catalog_sources/domain/remote_acquisition.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/metadata/domain/entities/trusted_remote_book_metadata.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_render_profile.dart';

enum RemoteDownloadUnsupportedReason {
  noAcquisitions,
  noSupportedEpub,
  insecureAcquisition,
  authenticationRequired,
  unsupportedMediaType,
  malformedLocation,
  indirectResolutionRequired,
  missingPublicationMetadata,
}

class RemoteBookDownloadPlan {
  RemoteBookDownloadPlan({
    required this.sourceId,
    required this.publicationRemoteId,
    required this.publicationTitle,
    required Iterable<String> authors,
    required this.acquisitionUri,
    required this.declaredMediaType,
    required this.acquisitionRelation,
    required this.isIndirect,
    required this.expectedFinalMediaType,
    required this.expectedSizeBytes,
    required this.suggestedFilename,
    required this.requiresAuthentication,
    required this.supported,
    required this.unsupportedReason,
    this.remoteMetadata,
  }) : authors = List.unmodifiable(authors);

  final String sourceId;
  final String publicationRemoteId;
  final String publicationTitle;
  final List<String> authors;
  final Uri? acquisitionUri;
  final String? declaredMediaType;
  final String acquisitionRelation;
  final bool isIndirect;
  final String? expectedFinalMediaType;
  final int? expectedSizeBytes;
  final String suggestedFilename;
  final bool requiresAuthentication;
  final bool supported;
  final RemoteDownloadUnsupportedReason? unsupportedReason;
  final TrustedRemoteBookMetadata? remoteMetadata;
}

class RemoteBookDownloadPlanningResult {
  const RemoteBookDownloadPlanningResult._({
    this.plan,
    this.reason,
    this.inspectedAcquisition,
  });

  const RemoteBookDownloadPlanningResult.supported(RemoteBookDownloadPlan plan)
    : this._(plan: plan);

  const RemoteBookDownloadPlanningResult.unsupported(
    RemoteDownloadUnsupportedReason reason, {
    RemoteAcquisition? acquisition,
  }) : this._(reason: reason, inspectedAcquisition: acquisition);

  final RemoteBookDownloadPlan? plan;
  final RemoteDownloadUnsupportedReason? reason;
  final RemoteAcquisition? inspectedAcquisition;
  bool get isSupported => plan?.supported ?? false;
}

class RemoteBookDownloadPlanner {
  const RemoteBookDownloadPlanner();

  RemoteBookDownloadPlanningResult create({
    required String sourceId,
    required RemoteCatalogPublicationSummary publication,
  }) {
    if (publication.remoteId.trim().isEmpty ||
        publication.title.trim().isEmpty) {
      return const RemoteBookDownloadPlanningResult.unsupported(
        RemoteDownloadUnsupportedReason.missingPublicationMetadata,
      );
    }
    if (publication.acquisitions.isEmpty) {
      return const RemoteBookDownloadPlanningResult.unsupported(
        RemoteDownloadUnsupportedReason.noAcquisitions,
      );
    }

    final selected = const PreferredEpubAcquisitionSelector().select(
      publication.acquisitions,
    );
    if (selected == null) {
      final first = publication.acquisitions.first;
      return RemoteBookDownloadPlanningResult.unsupported(
        _reason(first),
        acquisition: first,
      );
    }
    final uri = Uri.tryParse(selected.href);
    final selectedCover = selectRemoteCoverForProfile(
      preferred: publication.coverLocation,
      candidates: publication.imageCandidates,
      sourceId: sourceId,
      profile: BookCoverRenderProfile.details,
    );
    final indirect = selected.isIndirect;
    final supported = selected.advertisesEpub;
    return RemoteBookDownloadPlanningResult.supported(
      RemoteBookDownloadPlan(
        sourceId: sourceId,
        publicationRemoteId: publication.remoteId,
        publicationTitle: publication.title,
        authors: List.unmodifiable(publication.authors),
        acquisitionUri: uri,
        declaredMediaType: selected.mediaType,
        acquisitionRelation: selected.relation,
        isIndirect: indirect,
        expectedFinalMediaType: selected.expectedFinalMediaType,
        expectedSizeBytes: selected.sizeBytes,
        suggestedFilename: suggestEpubFilename(publication.title),
        requiresAuthentication: selected.requiresAuthentication,
        supported: supported,
        unsupportedReason: indirect
            ? RemoteDownloadUnsupportedReason.indirectResolutionRequired
            : null,
        remoteMetadata: uri == null
            ? null
            : TrustedRemoteBookMetadata(
                sourceId: sourceId,
                publicationId: publication.remoteId,
                title: publication.title,
                authors: publication.authors,
                description: publication.summary,
                publisher: publication.publisher,
                language: publication.language,
                publishedDate: publication.publishedDate,
                identifiers: publication.identifiers,
                subjects: publication.subjects,
                rights: publication.rights,
                publicationLocation: publication.detailsLocation?.uri,
                coverLocation: selectedCover?.uri,
                acquisitionLocation: uri,
              ),
      ),
    );
  }

  RemoteDownloadUnsupportedReason _reason(RemoteAcquisition value) {
    if (value.isMalformed) {
      return RemoteDownloadUnsupportedReason.malformedLocation;
    }
    if (!value.isSecure) {
      return RemoteDownloadUnsupportedReason.insecureAcquisition;
    }
    if (value.requiresAuthentication) {
      return RemoteDownloadUnsupportedReason.authenticationRequired;
    }
    return RemoteDownloadUnsupportedReason.unsupportedMediaType;
  }
}

class PreferredEpubAcquisitionSelector {
  const PreferredEpubAcquisitionSelector();

  RemoteAcquisition? select(Iterable<RemoteAcquisition> acquisitions) {
    final candidates = acquisitions
        .where(
          (value) =>
              value.advertisesEpub &&
              value.isSecure &&
              !value.isMalformed &&
              !value.requiresAuthentication,
        )
        .toList(growable: false);
    if (candidates.isEmpty) return null;
    final indexed = candidates.indexed.toList()
      ..sort((a, b) {
        final rank = _rank(a.$2).compareTo(_rank(b.$2));
        return rank != 0 ? rank : a.$1.compareTo(b.$1);
      });
    return indexed.first.$2;
  }

  int _rank(RemoteAcquisition value) {
    final variant = _variantRank(value);
    final direct = value.isIndirect ? 20 : 0;
    final relation = switch (value.kind) {
      RemoteAcquisitionKind.openAccess => 0,
      RemoteAcquisitionKind.generic => 1,
      _ => 2,
    };
    return variant * 100 + direct + relation;
  }

  int _variantRank(RemoteAcquisition value) {
    final hint = '${value.title ?? ''} ${value.href}'.toLowerCase();
    if (RegExp(
      r'(\bwith[\s_-]*images?\b|[\s_-]images?\.epub(?:$|[?#]))',
    ).hasMatch(hint)) {
      return 0;
    }
    if (RegExp(
      r'(\bno[\s_-]*images?\b|[\s_-]text\.epub(?:$|[?#]))',
    ).hasMatch(hint)) {
      return 2;
    }
    return 1;
  }
}

String suggestEpubFilename(String title) {
  var value = title
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '')
      .replaceAll(RegExp(r'\.{2,}'), '.')
      .trim()
      .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
  if (value.isEmpty) value = 'remote-book';
  const reserved = {
    'CON',
    'PRN',
    'AUX',
    'NUL',
    'COM1',
    'COM2',
    'COM3',
    'COM4',
    'COM5',
    'COM6',
    'COM7',
    'COM8',
    'COM9',
    'LPT1',
    'LPT2',
    'LPT3',
    'LPT4',
    'LPT5',
    'LPT6',
    'LPT7',
    'LPT8',
    'LPT9',
  };
  if (reserved.contains(value.toUpperCase())) value = '_$value';
  const maxBaseLength = 120;
  if (value.length > maxBaseLength) {
    value = value.substring(0, maxBaseLength).trimRight();
  }
  return '$value.epub';
}

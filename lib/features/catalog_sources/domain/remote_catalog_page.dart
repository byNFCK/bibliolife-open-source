import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_acquisition.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_access_hint.dart';
import 'package:bibliolife/features/home/domain/models/home_feed_ranking.dart';

class RemoteCatalogPage {
  RemoteCatalogPage({
    required this.sourceId,
    required this.location,
    required this.title,
    Iterable<RemoteCatalogNavigationLink> navigation = const [],
    Iterable<RemoteCatalogPublicationSummary> publications = const [],
    this.nextPageLocation,
    this.searchCapability = const RemoteCatalogSearchCapability.unsupported(),
    this.homeRanking,
  }) : navigation = List.unmodifiable(navigation),
       publications = List.unmodifiable(publications);

  final String sourceId;
  final RemoteCatalogLocation location;
  final String title;
  final List<RemoteCatalogNavigationLink> navigation;
  final List<RemoteCatalogPublicationSummary> publications;
  final RemoteCatalogLocation? nextPageLocation;
  final RemoteCatalogSearchCapability searchCapability;
  final HomeFeedRanking? homeRanking;
}

class RemoteCatalogNavigationLink {
  const RemoteCatalogNavigationLink({
    required this.title,
    required this.location,
  });

  final String title;
  final RemoteCatalogLocation location;
}

class RemoteCatalogPublicationSummary {
  RemoteCatalogPublicationSummary({
    required this.remoteId,
    required this.title,
    Iterable<String> authors = const [],
    this.coverLocation,
    this.summary,
    bool hasAcquisition = false,
    Iterable<RemoteAcquisition> acquisitions = const [],
    this.publisher,
    this.language,
    this.publishedDate,
    Iterable<String> identifiers = const [],
    Iterable<String> subjects = const [],
    this.rights,
    this.detailsLocation,
    this.subtitle,
    this.pageCount,
    Iterable<RemoteCatalogLocation> imageCandidates = const [],
    Iterable<RemoteCatalogAccessHint> accessHints = const [],
    Map<String, String> accessMetadata = const {},
    Map<String, String> sourceMetadata = const {},
    Map<String, Iterable<String>> sourceLists = const {},
    Iterable<RemoteCatalogLocation> sourceLinks = const [],
    this.homeRanking,
  }) : authors = List.unmodifiable(authors),
       acquisitions = List.unmodifiable(acquisitions),
       identifiers = List.unmodifiable(identifiers),
       imageCandidates = List.unmodifiable(imageCandidates),
       accessHints = List.unmodifiable(accessHints),
       accessMetadata = Map.unmodifiable(accessMetadata),
       sourceMetadata = Map.unmodifiable(sourceMetadata),
       sourceLists = Map.unmodifiable({
         for (final entry in sourceLists.entries)
           entry.key: List<String>.unmodifiable(entry.value),
       }),
       sourceLinks = List.unmodifiable(sourceLinks),
       subjects = List.unmodifiable(subjects),
       _legacyHasAcquisition = hasAcquisition;

  final String remoteId;
  final String title;
  final List<String> authors;
  final RemoteCatalogLocation? coverLocation;
  final String? summary;
  final List<RemoteAcquisition> acquisitions;
  final String? publisher;
  final String? language;
  final String? publishedDate;
  final List<String> identifiers;
  final List<String> subjects;
  final String? rights;
  final RemoteCatalogLocation? detailsLocation;
  final String? subtitle;
  final int? pageCount;
  final List<RemoteCatalogLocation> imageCandidates;
  final List<RemoteCatalogAccessHint> accessHints;

  /// Source-provided access and sale attributes normalized to safe strings.
  final Map<String, String> accessMetadata;

  /// Source-specific, optional metadata retained for enrichment and routing.
  final Map<String, String> sourceMetadata;
  final Map<String, List<String>> sourceLists;
  final List<RemoteCatalogLocation> sourceLinks;
  final HomeFeedPublicationRanking? homeRanking;
  final bool _legacyHasAcquisition;
  bool get hasAcquisition => acquisitions.isNotEmpty || _legacyHasAcquisition;

  RemoteCatalogPublicationSummary copyWith({
    Iterable<RemoteCatalogAccessHint>? accessHints,
    HomeFeedPublicationRanking? homeRanking,
  }) => RemoteCatalogPublicationSummary(
    remoteId: remoteId,
    title: title,
    authors: authors,
    coverLocation: coverLocation,
    summary: summary,
    hasAcquisition: _legacyHasAcquisition,
    acquisitions: acquisitions,
    publisher: publisher,
    language: language,
    publishedDate: publishedDate,
    identifiers: identifiers,
    subjects: subjects,
    rights: rights,
    detailsLocation: detailsLocation,
    subtitle: subtitle,
    pageCount: pageCount,
    imageCandidates: imageCandidates,
    accessHints: accessHints ?? this.accessHints,
    accessMetadata: accessMetadata,
    sourceMetadata: sourceMetadata,
    sourceLists: sourceLists,
    sourceLinks: sourceLinks,
    homeRanking: homeRanking ?? this.homeRanking,
  );
}

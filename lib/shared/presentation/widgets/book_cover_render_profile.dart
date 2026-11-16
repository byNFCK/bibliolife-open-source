import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';

enum BookCoverRenderProfile {
  searchGrid,
  compactList,
  onlineHome,
  localLibraryGrid,
  localLibraryList,
  details,
  readerThumbnail,
}

extension BookCoverRenderProfileX on BookCoverRenderProfile {
  int get cacheWidth => switch (this) {
    BookCoverRenderProfile.searchGrid ||
    BookCoverRenderProfile.localLibraryGrid ||
    BookCoverRenderProfile.onlineHome => 240,
    BookCoverRenderProfile.compactList ||
    BookCoverRenderProfile.localLibraryList => 280,
    BookCoverRenderProfile.readerThumbnail => 160,
    BookCoverRenderProfile.details => 480,
  };

  int get cacheHeight => switch (this) {
    BookCoverRenderProfile.searchGrid ||
    BookCoverRenderProfile.localLibraryGrid ||
    BookCoverRenderProfile.onlineHome => 360,
    BookCoverRenderProfile.compactList ||
    BookCoverRenderProfile.localLibraryList => 420,
    BookCoverRenderProfile.readerThumbnail => 240,
    BookCoverRenderProfile.details => 720,
  };

  bool get usesLargeRemoteAsset => this == BookCoverRenderProfile.details;
}

RemoteCatalogLocation? selectRemoteCoverForProfile({
  required RemoteCatalogLocation? preferred,
  required Iterable<RemoteCatalogLocation> candidates,
  required String? sourceId,
  required BookCoverRenderProfile profile,
}) {
  final unique = <Uri>{};
  final options = [
    ?preferred,
    ...candidates,
  ].where((item) => unique.add(item.uri)).toList(growable: false);
  if (options.isEmpty) return null;
  final source = sourceId?.toLowerCase() ?? '';
  if (source.contains('google') ||
      options.first.uri.host.toLowerCase().contains('google')) {
    // Google imageLinks are kept in descending source quality. A small card
    // chooses thumbnail/small; details prefers medium when available.
    final index = profile.usesLargeRemoteAsset
        ? (options.length > 2 ? 2 : 0)
        : (options.length > 1 ? options.length - 2 : 0);
    return options[index];
  }
  final selected = options.first;
  if (selected.uri.host.toLowerCase() == 'covers.openlibrary.org') {
    final match = RegExp(
      r'-[SML](\.[a-z]+)$',
      caseSensitive: false,
    ).firstMatch(selected.uri.path);
    final path = match == null
        ? selected.uri.path
        : '${selected.uri.path.substring(0, match.start)}-${profile.usesLargeRemoteAsset ? 'L' : 'M'}${match.group(1)}';
    return RemoteCatalogLocation.fromUri(selected.uri.replace(path: path));
  }
  return selected;
}

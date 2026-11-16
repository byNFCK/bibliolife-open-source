import 'dart:io';

sealed class BookCoverReference {
  const BookCoverReference();

  const factory BookCoverReference.local(String path) = LocalBookCover;
  const factory BookCoverReference.remote(
    Uri uri, {
    String? sourceId,
    String? remoteId,
    String? canonicalId,
  }) = RemoteBookCover;
  const factory BookCoverReference.asset(String assetName) = AssetBookCover;
  const factory BookCoverReference.missing() = MissingBookCover;
}

class LocalBookCover extends BookCoverReference {
  const LocalBookCover(this.path);

  final String path;

  File get file => File(path);

  @override
  bool operator ==(Object other) =>
      other is LocalBookCover && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

class RemoteBookCover extends BookCoverReference {
  const RemoteBookCover(
    this.uri, {
    this.sourceId,
    this.remoteId,
    this.canonicalId,
  });

  final Uri uri;
  final String? sourceId;
  final String? remoteId;
  final String? canonicalId;

  @override
  bool operator ==(Object other) =>
      other is RemoteBookCover && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}

class AssetBookCover extends BookCoverReference {
  const AssetBookCover(this.assetName);

  final String assetName;

  @override
  bool operator ==(Object other) =>
      other is AssetBookCover && other.assetName == assetName;

  @override
  int get hashCode => assetName.hashCode;
}

class MissingBookCover extends BookCoverReference {
  const MissingBookCover();

  @override
  bool operator ==(Object other) => other is MissingBookCover;

  @override
  int get hashCode => 0x4d495353;
}

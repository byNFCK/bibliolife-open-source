import 'dart:convert';

import 'package:bibliolife/features/metadata/domain/entities/trusted_remote_book_metadata.dart';

const trustedRemoteMetadataSnapshotVersion = 2;
const maximumTrustedRemoteMetadataSnapshotBytes = 64 * 1024;

String encodeTrustedRemoteMetadataSnapshot(TrustedRemoteBookMetadata metadata) {
  return jsonEncode(<String, Object?>{
    'version': trustedRemoteMetadataSnapshotVersion,
    'sourceId': metadata.sourceId,
    'publicationId': metadata.publicationId,
    'title': metadata.title,
    'authors': metadata.authors,
    'description': metadata.description,
    'publisher': metadata.publisher,
    'language': metadata.language,
    'publishedDate': metadata.publishedDate,
    'identifiers': metadata.identifiers,
    'subjects': metadata.subjects,
    'rights': metadata.rights,
    'publicationLocation': metadata.publicationLocation?.toString(),
    'coverLocation': metadata.coverLocation?.toString(),
    'acquisitionLocation': metadata.acquisitionLocation.toString(),
  });
}

TrustedRemoteBookMetadata? decodeTrustedRemoteMetadataSnapshot(String? value) {
  if (value == null ||
      utf8.encode(value).length > maximumTrustedRemoteMetadataSnapshotBytes) {
    return null;
  }
  try {
    final json = jsonDecode(value);
    if (json is! Map<String, dynamic> ||
        (json['version'] != 1 &&
            json['version'] != trustedRemoteMetadataSnapshotVersion)) {
      return null;
    }
    final sourceId = json['sourceId'];
    final publicationId = json['publicationId'];
    final title = json['title'];
    final acquisition = Uri.tryParse(
      json['acquisitionLocation'] as String? ?? '',
    );
    if (sourceId is! String ||
        publicationId is! String ||
        title is! String ||
        acquisition == null ||
        !acquisition.hasScheme) {
      return null;
    }
    return TrustedRemoteBookMetadata(
      sourceId: sourceId,
      publicationId: publicationId,
      title: title,
      authors: _strings(json['authors']),
      description: _string(json['description']),
      publisher: _string(json['publisher']),
      language: _string(json['language']),
      publishedDate: _string(json['publishedDate']),
      identifiers: _strings(json['identifiers']),
      subjects: _strings(json['subjects']),
      rights: _string(json['rights']),
      publicationLocation: _uri(json['publicationLocation']),
      coverLocation: _uri(json['coverLocation']),
      acquisitionLocation: acquisition,
    );
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}

String? _string(Object? value) => value is String ? value : null;

List<String> _strings(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const [];

Uri? _uri(Object? value) =>
    value is String && value.isNotEmpty ? Uri.tryParse(value) : null;

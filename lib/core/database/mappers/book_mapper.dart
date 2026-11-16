import 'dart:convert';

import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/book_cover_provenance.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:drift/drift.dart';

extension BookMapper on Book {
  LibraryBook toLibraryBook() {
    return LibraryBook(
      id: id,
      title: title,
      sortTitle: sortTitle,
      author: author,
      description: description,
      filePath: filePath,
      originalFilePath: originalFilePath,
      fileName: fileName,
      fileExtension: fileExtension,
      format: BookFormat.fromExtension(fileExtension),
      mediaType: mediaType,
      coverPath: coverPath,
      coverProvenance: BookCoverProvenance.parse(coverProvenance),
      language: language,
      publisher: publisher,
      publishedDate: publishedDate,
      isbn: isbn,
      pageCount: pageCount,
      fileSizeBytes: fileSizeBytes,
      dateAdded: dateAdded,
      lastOpenedAt: lastOpenedAt,
      isFavorite: isFavorite,
      authors: _decodeList(authorsJson),
      contributors: _decodeList(contributorsJson),
      identifiers: _decodeList(identifiersJson),
      subjects: _decodeList(subjectsJson),
      rights: rights,
      seriesName: seriesName,
      seriesIndex: seriesIndex,
      edition: edition,
      source: source,
      coverage: coverage,
      type: type,
      modifiedDate: modifiedDate,
      catalogSourceId: catalogSourceId,
      remotePublicationId: remotePublicationId,
      remotePublicationLocation: remotePublicationLocation,
      remoteAcquisitionLocation: remoteAcquisitionLocation,
      metadataOrigins: _decodeMap(metadataOriginsJson),
      tocJson: tocJson,
    );
  }
}

extension LibraryBookMapper on LibraryBook {
  BooksCompanion toBooksCompanion() {
    return BooksCompanion.insert(
      id: id,
      title: title,
      sortTitle: Value(sortTitle),
      author: Value(author),
      description: Value(description),
      filePath: filePath,
      originalFilePath: Value(originalFilePath),
      fileName: fileName,
      fileExtension: fileExtension,
      mediaType: Value(mediaType),
      coverPath: Value(coverPath),
      coverProvenance: Value(coverProvenance.name),
      language: Value(language),
      publisher: Value(publisher),
      publishedDate: Value(publishedDate),
      isbn: Value(isbn),
      pageCount: Value(pageCount),
      fileSizeBytes: fileSizeBytes,
      dateAdded: dateAdded,
      lastOpenedAt: Value(lastOpenedAt),
      isFavorite: Value(isFavorite),
      authorsJson: Value(_encodeList(authors)),
      contributorsJson: Value(_encodeList(contributors)),
      identifiersJson: Value(_encodeList(identifiers)),
      subjectsJson: Value(_encodeList(subjects)),
      rights: Value(rights),
      seriesName: Value(seriesName),
      seriesIndex: Value(seriesIndex),
      edition: Value(edition),
      source: Value(source),
      coverage: Value(coverage),
      type: Value(type),
      modifiedDate: Value(modifiedDate),
      catalogSourceId: Value(catalogSourceId),
      remotePublicationId: Value(remotePublicationId),
      remotePublicationLocation: Value(remotePublicationLocation),
      remoteAcquisitionLocation: Value(remoteAcquisitionLocation),
      metadataOriginsJson: Value(_encodeMap(metadataOrigins)),
      tocJson: Value(tocJson),
    );
  }

  Book toDriftBook() {
    return Book(
      id: id,
      title: title,
      sortTitle: sortTitle,
      author: author,
      description: description,
      filePath: filePath,
      originalFilePath: originalFilePath,
      fileName: fileName,
      fileExtension: fileExtension,
      mediaType: mediaType,
      coverPath: coverPath,
      coverProvenance: coverProvenance.name,
      language: language,
      publisher: publisher,
      publishedDate: publishedDate,
      isbn: isbn,
      pageCount: pageCount,
      fileSizeBytes: fileSizeBytes,
      dateAdded: dateAdded,
      lastOpenedAt: lastOpenedAt,
      isFavorite: isFavorite,
      authorsJson: _encodeList(authors),
      contributorsJson: _encodeList(contributors),
      identifiersJson: _encodeList(identifiers),
      subjectsJson: _encodeList(subjects),
      rights: rights,
      seriesName: seriesName,
      seriesIndex: seriesIndex,
      edition: edition,
      source: source,
      coverage: coverage,
      type: type,
      modifiedDate: modifiedDate,
      catalogSourceId: catalogSourceId,
      remotePublicationId: remotePublicationId,
      remotePublicationLocation: remotePublicationLocation,
      remoteAcquisitionLocation: remoteAcquisitionLocation,
      metadataOriginsJson: _encodeMap(metadataOrigins),
      tocJson: tocJson,
    );
  }
}

String? _encodeList(List<String> values) =>
    values.isEmpty ? null : jsonEncode(values);

List<String> _decodeList(String? value) {
  if (value == null || value.isEmpty) return const [];
  try {
    return List.unmodifiable((jsonDecode(value) as List).whereType<String>());
  } on FormatException {
    return const [];
  }
}

String? _encodeMap(Map<String, String> value) =>
    value.isEmpty ? null : jsonEncode(value);

Map<String, String> _decodeMap(String? value) {
  if (value == null || value.isEmpty) return const {};
  try {
    return Map.unmodifiable(
      (jsonDecode(value) as Map).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
    );
  } on FormatException {
    return const {};
  }
}

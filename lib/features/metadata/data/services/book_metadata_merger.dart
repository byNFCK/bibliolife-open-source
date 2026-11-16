import 'package:bibliolife/features/metadata/data/services/epub_metadata_normalizer.dart';
import 'package:bibliolife/features/metadata/data/services/isbn_extractor.dart';
import 'package:bibliolife/features/metadata/domain/entities/extracted_book_metadata.dart';
import 'package:bibliolife/features/metadata/domain/entities/merged_book_metadata.dart';
import 'package:bibliolife/features/metadata/domain/entities/trusted_remote_book_metadata.dart';

class BookMetadataMerger {
  const BookMetadataMerger();

  MergedBookMetadata merge(
    ExtractedBookMetadata epub,
    TrustedRemoteBookMetadata? remote,
  ) {
    final origins = <String, String>{};
    T? choose<T>(String field, T? epubValue, T? remoteValue) {
      if (epubValue != null) {
        origins[field] = 'epub';
        return epubValue;
      }
      if (remoteValue != null) origins[field] = 'remote';
      return remoteValue;
    }

    final remoteAuthors = remote?.authors
        .map(EpubMetadataNormalizer.text)
        .whereType<String>()
        .toList();
    final authors = epub.authors.isNotEmpty
        ? epub.authors
        : (remoteAuthors ?? const []);
    if (authors.isNotEmpty) {
      origins['authors'] = epub.authors.isNotEmpty ? 'epub' : 'remote';
    }
    final remoteIsbn = remote == null
        ? null
        : IsbnExtractor.selectBest(
            remote.identifiers.expand(
              (value) => IsbnExtractor.extractCandidates(
                value,
                source: IsbnSource.packageMetadata,
              ),
            ),
          );
    final isbn = _bestIsbn(epub.isbn, remoteIsbn);
    if (isbn != null) {
      origins['isbn'] = isbn == epub.isbn ? 'epub' : 'remote';
    }
    final publishedDate = _preciseDate(
      epub.publishedDate,
      EpubMetadataNormalizer.publicationDate(remote?.publishedDate),
    );
    if (publishedDate != null) {
      origins['publishedDate'] = publishedDate == epub.publishedDate
          ? 'epub'
          : 'remote';
    }
    final subjects = <String>[
      ...epub.subjects,
      ...?remote?.subjects,
    ].map(EpubMetadataNormalizer.text).whereType<String>().toSet().toList();
    if (subjects.isNotEmpty) {
      origins['subjects'] = epub.subjects.isNotEmpty && remote != null
          ? 'epub+remote'
          : epub.subjects.isNotEmpty
          ? 'epub'
          : 'remote';
    }
    final remoteDescription = EpubMetadataNormalizer.description(
      remote?.description,
    );
    final epubDescription = EpubMetadataNormalizer.description(
      epub.description,
    );
    final description = remoteDescription ?? epubDescription;
    if (description != null) {
      origins['description'] = remoteDescription != null ? 'remote' : 'epub';
    }
    return MergedBookMetadata(
      metadata: ExtractedBookMetadata(
        title: choose(
          'title',
          EpubMetadataNormalizer.text(epub.title),
          EpubMetadataNormalizer.text(remote?.title),
        ),
        sortTitle: epub.sortTitle,
        authors: authors,
        description: description,
        language: choose(
          'language',
          EpubMetadataNormalizer.language(epub.language),
          EpubMetadataNormalizer.language(remote?.language),
        ),
        publisher: choose(
          'publisher',
          EpubMetadataNormalizer.text(epub.publisher),
          EpubMetadataNormalizer.text(remote?.publisher),
        ),
        publishedDate: publishedDate,
        isbn: isbn,
        coverBytes: epub.coverBytes,
        coverExtension: epub.coverExtension,
        mediaType: epub.mediaType,
        contributors: epub.contributors,
        identifiers: List.unmodifiable({
          ...epub.identifiers,
          ...?remote?.identifiers,
        }),
        subjects: List.unmodifiable(subjects),
        rights: choose(
          'rights',
          EpubMetadataNormalizer.text(epub.rights),
          EpubMetadataNormalizer.text(remote?.rights),
        ),
        seriesName: epub.seriesName,
        seriesIndex: epub.seriesIndex,
        edition: epub.edition,
        source: epub.source,
        coverage: epub.coverage,
        type: epub.type,
        modifiedDate: epub.modifiedDate,
      ),
      origins: origins,
    );
  }

  String? _bestIsbn(String? epub, String? remote) {
    if (epub?.length == 13) return epub;
    if (remote?.length == 13) return remote;
    return epub ?? remote;
  }

  String? _preciseDate(String? epub, String? remote) {
    if (epub == null) return remote;
    if (remote == null) return epub;
    return remote.length > epub.length ? remote : epub;
  }
}

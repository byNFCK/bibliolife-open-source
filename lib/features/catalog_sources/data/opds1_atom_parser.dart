import 'dart:convert';
import 'dart:typed_data';

import 'package:bibliolife/features/catalog_sources/data/payload_parser_failure.dart';
import 'package:bibliolife/features/catalog_sources/data/parser_diagnostics.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_location.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_acquisition.dart';
import 'package:xml/xml.dart';
import 'package:bibliolife/features/metadata/data/services/epub_metadata_normalizer.dart';

class Opds1AtomParser {
  const Opds1AtomParser();

  /// The single byte-oriented parser entry point used by the transport today.
  /// The XML DOM is scoped to [parse] and is never retained by the returned
  /// page. Phase 4.4B can execute this entry point off-isolate without adding
  /// another XML parsing path.
  ParsedOpdsFeed parseBytes({
    required String sourceId,
    required RemoteCatalogLocation location,
    required Uint8List bytes,
    bool isSearchResult = false,
  }) => parsePayloadBytes(
    sourceId: sourceId,
    location: location.toString(),
    bytes: bytes,
    isSearchResult: isSearchResult,
  );

  /// Pure byte entry point. Its result is deliberately composed of immutable
  /// strings, numbers, booleans and lists, so a future executor can send it
  /// across an isolate boundary unchanged.
  ParsedOpdsFeed parsePayloadBytes({
    required String sourceId,
    required String location,
    required Uint8List bytes,
    bool isSearchResult = false,
  }) {
    final decodeWatch = Stopwatch()..start();
    final String body;
    try {
      body = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const PayloadParserException(
        PayloadParserFailureKind.invalidUtf8,
        'The OPDS response is not valid UTF-8.',
      );
    }
    decodeWatch.stop();
    final parseWatch = Stopwatch()..start();
    final XmlDocument document;
    try {
      document = XmlDocument.parse(body);
    } on XmlException {
      throw const RemoteCatalogException.malformedCatalogResponse(
        'The response is not well-formed XML.',
      );
    }
    parseWatch.stop();
    final extractWatch = Stopwatch()..start();
    final feed = _extractFeed(
      sourceId: sourceId,
      location: location,
      document: document,
      isSearchResult: isSearchResult,
    );
    extractWatch.stop();
    return ParsedOpdsFeed(
      sourceId: feed.sourceId,
      location: feed.location,
      title: feed.title,
      navigation: feed.navigation,
      publications: feed.publications,
      nextPageLocation: feed.nextPageLocation,
      searchKind: feed.searchKind,
      searchLocation: feed.searchLocation,
      diagnostics: ParserDiagnostics(
        parserType: 'opds1Atom',
        encodedByteCount: bytes.length,
        decodeMicros: decodeWatch.elapsedMicroseconds,
        parseMicros: parseWatch.elapsedMicroseconds,
        extractMicros: extractWatch.elapsedMicroseconds,
        itemCount: feed.publications.length + feed.navigation.length,
        skippedItemCount: 0,
      ),
    );
  }

  RemoteCatalogPage parse({
    required String sourceId,
    required RemoteCatalogLocation location,
    required String body,
    bool isSearchResult = false,
  }) => mapParsedOpdsFeedToDomain(
    parsePayloadBytes(
      sourceId: sourceId,
      location: location.toString(),
      bytes: Uint8List.fromList(utf8.encode(body)),
      isSearchResult: isSearchResult,
    ),
  );

  ParsedOpdsFeed _extractFeed({
    required String sourceId,
    required String location,
    required XmlDocument document,
    bool isSearchResult = false,
  }) {
    final feed = document.rootElement;
    if (feed.name.local != 'feed') {
      throw const RemoteCatalogException.unsupportedCatalogFormat(
        'The response root is not an Atom feed.',
      );
    }

    final title = _childText(feed, 'title');
    if (title == null) {
      throw const RemoteCatalogException.malformedCatalogResponse(
        'The Atom feed has no title.',
      );
    }

    final navigation = <ParsedOpdsNavigationLink>[];
    final publications = <ParsedOpdsPublication>[];
    String? nextPageLocation;
    var searchKind = 'unsupported';
    String? searchLocation;

    for (final link in _children(feed, 'link')) {
      final rel = _relations(link);
      final resolved = _resolve(location, link.getAttribute('href'));
      if (resolved == null) continue;
      if (rel.contains('next')) {
        nextPageLocation ??= resolved;
      } else if (_isSearch(rel)) {
        final type = link.getAttribute('type')?.toLowerCase();
        if (type == 'application/opensearchdescription+xml') {
          searchKind = 'openSearchDescription';
          searchLocation = resolved;
        } else if (searchKind == 'unsupported') {
          searchKind = 'directTemplate';
          searchLocation = resolved;
        }
      } else if (_isNavigation(rel)) {
        final linkTitle = _clean(link.getAttribute('title'));
        if (linkTitle != null) {
          navigation.add(ParsedOpdsNavigationLink(linkTitle, resolved));
        }
      }
    }

    for (final entry in _children(feed, 'entry')) {
      final entryTitle = _childText(entry, 'title');
      final entryId = _childText(entry, 'id');
      final entryContent = _childText(entry, 'content');
      final links = _children(entry, 'link').toList(growable: false);
      final acquisitions = _acquisitions(
        location,
        links,
        acceptsStandardEbooksEnclosures: sourceId == 'builtin-standard-ebooks',
      );
      final hasAcquisition = acquisitions.isNotEmpty;

      if (hasAcquisition) {
        if (entryTitle == null || entryId == null) {
          continue;
        }
        final authors = _children(entry, 'author')
            .map((author) => _childText(author, 'name'))
            .whereType<String>()
            .toList(growable: false);
        String? cover;
        String? details;
        for (final link in links) {
          if (cover == null && _relations(link).any(_isCover)) {
            cover = _resolve(location, link.getAttribute('href'));
          }
          final relations = _relations(link);
          if (details == null &&
              (relations.contains('alternate') ||
                  relations.any((rel) => rel.endsWith('/alternate')))) {
            details = _resolve(location, link.getAttribute('href'));
          }
        }
        publications.add(
          ParsedOpdsPublication(
            remoteId: entryId,
            title: entryTitle,
            authors: authors,
            coverLocation: cover,
            summary: EpubMetadataNormalizer.description(
              _childText(entry, 'summary') ?? _childText(entry, 'content'),
            ),
            acquisitions: acquisitions,
            publisher: _childText(entry, 'publisher'),
            language: EpubMetadataNormalizer.language(
              _childText(entry, 'language'),
            ),
            publishedDate: EpubMetadataNormalizer.publicationDate(
              _childText(entry, 'issued') ??
                  _childText(entry, 'published') ??
                  _childText(entry, 'date'),
            ),
            identifiers: _children(entry, 'identifier')
                .map((element) => _clean(element.innerText))
                .whereType<String>()
                .toList(growable: false),
            subjects: _children(entry, 'category')
                .map(
                  (element) =>
                      _clean(element.getAttribute('label')) ??
                      _clean(element.getAttribute('term')),
                )
                .whereType<String>()
                .toList(growable: false),
            rights: _childText(entry, 'rights'),
            detailsLocation: details,
            imageCandidates: cover == null ? const [] : [cover],
          ),
        );
        continue;
      }

      if (entryTitle == null) continue;
      // Gutenberg's search feed mixes audiobooks into its book results. They
      // expose no EPUB acquisition, so do not surface a guaranteed dead-end.
      if (isSearchResult &&
          entryContent?.toLowerCase().contains('category: sound') == true) {
        continue;
      }
      if (isSearchResult && entryId != null) {
        String? details;
        String? cover;
        for (final link in links) {
          if (cover == null && _relations(link).any(_isCover)) {
            cover = _resolve(location, link.getAttribute('href'));
          }
          final candidate = _resolve(location, link.getAttribute('href'));
          if (candidate == null ||
              !(Uri.tryParse(candidate)?.host.endsWith('gutenberg.org') ??
                  false) ||
              !(Uri.tryParse(candidate)?.path.startsWith('/ebooks/') ??
                  false) ||
              !(Uri.tryParse(candidate)?.path.endsWith('.opds') ?? false)) {
            continue;
          }
          details = candidate;
          break;
        }
        if (details != null) {
          final searchAcquisition = _gutenbergSearchEpub(details);
          publications.add(
            ParsedOpdsPublication(
              remoteId: entryId,
              title: entryTitle,
              authors: [entryContent ?? 'Unknown author'],
              coverLocation: cover,
              imageCandidates: cover == null ? const [] : [cover],
              acquisitions: searchAcquisition == null
                  ? const []
                  : [searchAcquisition],
              publisher: null,
              language: null,
              publishedDate: null,
              identifiers: const [],
              subjects: const [],
              rights: null,
              summary: _childText(entry, 'summary'),
              detailsLocation: details,
            ),
          );
          continue;
        }
      }
      for (final link in links) {
        final rel = _relations(link);
        if (!_isNavigation(rel)) continue;
        final resolved = _resolve(location, link.getAttribute('href'));
        if (resolved != null) {
          navigation.add(ParsedOpdsNavigationLink(entryTitle, resolved));
          break;
        }
      }
    }

    return ParsedOpdsFeed(
      sourceId: sourceId,
      location: location,
      title: title,
      navigation: navigation,
      publications: publications,
      nextPageLocation: nextPageLocation,
      searchKind: searchKind,
      searchLocation: searchLocation,
      diagnostics: const ParserDiagnostics(
        parserType: 'opds1Atom',
        encodedByteCount: 0,
        decodeMicros: 0,
        parseMicros: 0,
        extractMicros: 0,
        itemCount: 0,
        skippedItemCount: 0,
      ),
    );
  }

  ParsedOpdsAcquisition? _gutenbergSearchEpub(String details) {
    final uri = Uri.tryParse(details);
    if (uri == null ||
        !uri.host.endsWith('gutenberg.org') ||
        uri.scheme.toLowerCase() != 'https') {
      return null;
    }
    final match = RegExp(r'^/ebooks/(\d+)\.opds$').firstMatch(uri.path);
    if (match == null) return null;
    final id = match.group(1)!;
    return ParsedOpdsAcquisition(
      relation: 'http://opds-spec.org/acquisition/open-access',
      href: uri
          .replace(path: '/ebooks/$id.epub.images', query: null, fragment: null)
          .toString(),
      mediaType: 'application/epub+zip',
      title: null,
      sizeBytes: null,
      indirectMediaTypes: const [],
      requiresAuthentication: false,
      isSecure: true,
      isMalformed: false,
    );
  }

  Iterable<XmlElement> _children(XmlElement parent, String localName) =>
      parent.childElements.where((element) => element.name.local == localName);

  String? _childText(XmlElement parent, String localName) {
    for (final child in _children(parent, localName)) {
      final value = _clean(child.innerText);
      if (value != null) return value;
    }
    return null;
  }

  Set<String> _relations(XmlElement link) {
    final value = _clean(link.getAttribute('rel')) ?? 'alternate';
    return value
        .split(RegExp(r'\s+'))
        .map((part) => part.toLowerCase())
        .toSet();
  }

  bool _isNavigation(Set<String> relations) => relations.any(
    (rel) =>
        rel == 'subsection' ||
        rel == 'collection' ||
        rel.endsWith('/subsection') ||
        rel.endsWith('/navigation'),
  );

  bool _isAcquisition(String rel) =>
      rel == 'http://opds-spec.org/acquisition' ||
      rel.startsWith('http://opds-spec.org/acquisition/');

  List<ParsedOpdsAcquisition> _acquisitions(
    String base,
    List<XmlElement> links, {
    required bool acceptsStandardEbooksEnclosures,
  }) {
    final result = <ParsedOpdsAcquisition>[];
    final seen = <String>{};
    for (final link in links) {
      final relations = _relations(link).where(_isAcquisition).toList();
      final mediaType = _clean(link.getAttribute('type'))?.toLowerCase();
      if (acceptsStandardEbooksEnclosures &&
          relations.isEmpty &&
          _relations(link).contains('enclosure') &&
          mediaType == 'application/epub+zip') {
        // Standard Ebooks publishes its public new-release feed as Atom,
        // where direct EPUBs use the standard Atom enclosure relation rather
        // than an OPDS acquisition relation. This is deliberately scoped to
        // the built-in source so ordinary Atom feeds cannot bypass OPDS rules.
        relations.add('http://opds-spec.org/acquisition/open-access');
      }
      for (final relation in relations) {
        final rawHref = _clean(link.getAttribute('href'));
        Uri? resolved;
        if (rawHref != null) {
          try {
            resolved = Uri.parse(base).resolve(rawHref);
          } on FormatException {
            resolved = null;
          }
        }
        final malformed =
            rawHref == null || resolved == null || resolved.host.isEmpty;
        final href = resolved?.toString() ?? rawHref ?? '';
        final indirect = link.descendantElements
            .where((element) => element.name.local == 'indirectAcquisition')
            .map(
              (element) => _clean(element.getAttribute('type'))?.toLowerCase(),
            )
            .whereType<String>()
            .toList(growable: false);
        final size = int.tryParse(_clean(link.getAttribute('length')) ?? '');
        final authentication = link.attributes.any(
          (attribute) =>
              attribute.name.local.toLowerCase().contains('authentication') &&
              attribute.value.trim().toLowerCase() != 'false',
        );
        final acquisition = ParsedOpdsAcquisition(
          relation: relation,
          href: href,
          mediaType: mediaType,
          title: _clean(link.getAttribute('title')),
          sizeBytes: size,
          indirectMediaTypes: indirect,
          requiresAuthentication: authentication,
          isSecure: resolved?.scheme.toLowerCase() == 'https',
          isMalformed: malformed,
        );
        final key = '$href\u0000$mediaType\u0000$relation';
        if (seen.add(key)) result.add(acquisition);
      }
    }
    return result;
  }

  bool _isCover(String rel) =>
      rel == 'http://opds-spec.org/image' ||
      rel == 'http://opds-spec.org/image/thumbnail' ||
      rel == 'http://opds-spec.org/cover' ||
      rel == 'http://opds-spec.org/thumbnail';

  bool _isSearch(Set<String> relations) => relations.any(
    (rel) =>
        rel == 'search' ||
        rel == 'http://opds-spec.org/search' ||
        rel.endsWith('/search'),
  );

  String? _resolve(String base, String? reference) {
    final value = _clean(reference);
    if (value == null) return null;
    try {
      return RemoteCatalogLocation.fromUri(
        Uri.parse(base).resolve(value),
      ).toString();
    } on FormatException {
      return null;
    }
  }

  String? _clean(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }
}

/// Compact OPDS result retained after the XML document has been released.
class ParsedOpdsFeed {
  const ParsedOpdsFeed({
    required this.sourceId,
    required this.location,
    required this.title,
    required this.navigation,
    required this.publications,
    required this.nextPageLocation,
    required this.searchKind,
    required this.searchLocation,
    required this.diagnostics,
  });

  final String sourceId;
  final String location;
  final String title;
  final List<ParsedOpdsNavigationLink> navigation;
  final List<ParsedOpdsPublication> publications;
  final String? nextPageLocation;
  final String searchKind;
  final String? searchLocation;
  final ParserDiagnostics diagnostics;
}

class ParsedOpdsNavigationLink {
  const ParsedOpdsNavigationLink(this.title, this.location);

  final String title;
  final String location;
}

class ParsedOpdsPublication {
  const ParsedOpdsPublication({
    required this.remoteId,
    required this.title,
    required this.authors,
    required this.coverLocation,
    required this.summary,
    required this.acquisitions,
    required this.publisher,
    required this.language,
    required this.publishedDate,
    required this.identifiers,
    required this.subjects,
    required this.rights,
    required this.detailsLocation,
    required this.imageCandidates,
  });

  final String remoteId;
  final String title;
  final List<String> authors;
  final String? coverLocation;
  final String? summary;
  final List<ParsedOpdsAcquisition> acquisitions;
  final String? publisher;
  final String? language;
  final String? publishedDate;
  final List<String> identifiers;
  final List<String> subjects;
  final String? rights;
  final String? detailsLocation;
  final List<String> imageCandidates;
}

class ParsedOpdsAcquisition {
  const ParsedOpdsAcquisition({
    required this.relation,
    required this.href,
    required this.mediaType,
    required this.title,
    required this.sizeBytes,
    required this.indirectMediaTypes,
    required this.requiresAuthentication,
    required this.isSecure,
    required this.isMalformed,
  });

  final String relation;
  final String href;
  final String? mediaType;
  final String? title;
  final int? sizeBytes;
  final List<String> indirectMediaTypes;
  final bool requiresAuthentication;
  final bool isSecure;
  final bool isMalformed;
}

/// The only OPDS DTO-to-domain mapping boundary.
RemoteCatalogPage mapParsedOpdsFeedToDomain(ParsedOpdsFeed feed) {
  final capability = switch (feed.searchKind) {
    'directTemplate' when feed.searchLocation != null =>
      RemoteCatalogSearchCapability.directTemplate(
        RemoteCatalogLocation.parse(feed.searchLocation!),
      ),
    'openSearchDescription' when feed.searchLocation != null =>
      RemoteCatalogSearchCapability.openSearchDescription(
        RemoteCatalogLocation.parse(feed.searchLocation!),
      ),
    _ => const RemoteCatalogSearchCapability.unsupported(),
  };
  return RemoteCatalogPage(
    sourceId: feed.sourceId,
    location: RemoteCatalogLocation.parse(feed.location),
    title: feed.title,
    navigation: [
      for (final link in feed.navigation)
        RemoteCatalogNavigationLink(
          title: link.title,
          location: RemoteCatalogLocation.parse(link.location),
        ),
    ],
    publications: [
      for (final item in feed.publications)
        RemoteCatalogPublicationSummary(
          remoteId: item.remoteId,
          title: item.title,
          authors: item.authors,
          coverLocation: item.coverLocation == null
              ? null
              : RemoteCatalogLocation.parse(item.coverLocation!),
          summary: item.summary,
          acquisitions: [
            for (final value in item.acquisitions)
              RemoteAcquisition(
                relation: value.relation,
                href: value.href,
                mediaType: value.mediaType,
                title: value.title,
                sizeBytes: value.sizeBytes,
                indirectMediaTypes: value.indirectMediaTypes,
                requiresAuthentication: value.requiresAuthentication,
                isSecure: value.isSecure,
                isMalformed: value.isMalformed,
              ),
          ],
          publisher: item.publisher,
          language: item.language,
          publishedDate: item.publishedDate,
          identifiers: item.identifiers,
          subjects: item.subjects,
          rights: item.rights,
          detailsLocation: item.detailsLocation == null
              ? null
              : RemoteCatalogLocation.parse(item.detailsLocation!),
          imageCandidates: [
            for (final value in item.imageCandidates)
              RemoteCatalogLocation.parse(value),
          ],
        ),
    ],
    nextPageLocation: feed.nextPageLocation == null
        ? null
        : RemoteCatalogLocation.parse(feed.nextPageLocation!),
    searchCapability: capability,
  );
}

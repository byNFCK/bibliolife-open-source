import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bibliolife/features/metadata/data/services/epub_metadata_normalizer.dart';
import 'package:bibliolife/features/metadata/data/services/epub_metadata_diagnostics.dart';
import 'package:bibliolife/features/metadata/data/services/isbn_extractor.dart';
import 'package:bibliolife/features/metadata/domain/entities/extracted_book_metadata.dart';
import 'package:bibliolife/features/metadata/domain/entities/metadata_extraction_result.dart';
import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';

class EpubMetadataParser {
  static const maxEpubBytes = 100 * 1024 * 1024;
  static const maxArchiveEntries = 10000;
  static const maxXmlBytes = 2 * 1024 * 1024;
  static const maxCoverBytes = 15 * 1024 * 1024;
  static const maxIsbnDocumentBytes = 1024 * 1024;
  static const maxIsbnTextLength = 100000;

  Future<MetadataExtractionResult> parse(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.length() > maxEpubBytes) {
        return const MetadataFileReadFailed();
      }
      final archive = ZipDecoder().decodeBytes(
        await file.readAsBytes(),
        verify: true,
      );
      if (archive.files.length > maxArchiveEntries) {
        return const MetadataMalformedPublication();
      }
      final entries = <String, ArchiveFile>{};
      for (final entry in archive.files) {
        final normalized = _safeArchivePath(entry.name);
        if (normalized == null) {
          return const MetadataMalformedPublication();
        }
        entries[normalized] = entry;
      }

      final containerBytes = _readEntry(
        entries['META-INF/container.xml'],
        maxXmlBytes,
      );
      if (containerBytes == null) return const MetadataMalformedPublication();
      final container = XmlDocument.parse(_decodeXml(containerBytes));
      final rootFile = _elements(
        container,
        'rootfile',
      ).cast<XmlElement>().firstOrNull;
      final opfPath = rootFile?.getAttribute('full-path');
      final normalizedOpfPath = opfPath == null
          ? null
          : _safeArchivePath(opfPath);
      if (normalizedOpfPath == null) {
        return const MetadataMalformedPublication();
      }

      final opfBytes = _readEntry(entries[normalizedOpfPath], maxXmlBytes);
      if (opfBytes == null) return const MetadataMalformedPublication();
      final opf = XmlDocument.parse(_decodeXml(opfBytes));

      return MetadataExtractionSuccess(
        _extractMetadata(opf, normalizedOpfPath, entries),
      );
    } on FileSystemException catch (error) {
      return MetadataFileReadFailed(diagnosticCause: error);
    } on XmlException catch (error) {
      return MetadataParsingFailed(diagnosticCause: error);
    } on ArchiveException catch (error) {
      return MetadataParsingFailed(diagnosticCause: error);
    } catch (error) {
      return MetadataParsingFailed(diagnosticCause: error);
    }
  }

  ExtractedBookMetadata _extractMetadata(
    XmlDocument opf,
    String opfPath,
    Map<String, ArchiveFile> entries,
  ) {
    final metadata = _elements(opf, 'metadata').cast<XmlElement>().firstOrNull;
    final manifest = _elements(opf, 'manifest').cast<XmlElement>().firstOrNull;
    final metadataElements = metadata == null
        ? const <XmlElement>[]
        : _childElements(metadata);
    final refinements = <String, Map<String, String>>{};
    for (final meta in metadataElements.where(
      (element) => _localName(element) == 'meta',
    )) {
      final refines = meta.getAttribute('refines');
      final property = meta.getAttribute('property');
      if (refines != null && property != null) {
        refinements.putIfAbsent(
          refines.replaceFirst('#', ''),
          () => {},
        )[property] = _text(
          meta,
        );
      }
    }

    final titles = metadataElements
        .where((element) => _localName(element) == 'title')
        .toList();
    final primaryTitle = titles.firstWhere(
      (element) =>
          refinements[element.getAttribute('id')]?['title-type'] == 'main',
      orElse: () =>
          titles.isEmpty ? XmlElement(XmlName.parts('empty')) : titles.first,
    );
    final title = _localName(primaryTitle) == 'empty'
        ? null
        : _nullableText(primaryTitle);
    final sortTitle = refinements[primaryTitle.getAttribute('id')]?['file-as'];

    final creators = metadataElements
        .where((element) => _localName(element) == 'creator')
        .toList();
    final authors = <String>[];
    for (final creator in creators) {
      final role = refinements[creator.getAttribute('id')]?['role']
          ?.toLowerCase();
      if (role != null && role != 'aut' && role != 'author') continue;
      final name = _nullableText(creator);
      if (name != null) authors.add(name);
    }
    final contributors = _allText(metadataElements, 'contributor');

    final identifiers = metadataElements
        .where((element) => _localName(element) == 'identifier')
        .map(_text)
        .map(EpubMetadataNormalizer.text)
        .whereType<String>()
        .toList();
    final calibreIdentifiers = metadataElements
        .where(
          (element) =>
              _localName(element) == 'meta' &&
              element.getAttribute('name')?.toLowerCase() ==
                  'calibre:identifier',
        )
        .map((element) => element.getAttribute('content') ?? '')
        .toList();
    final isbn =
        _findIsbn(identifiers.followedBy(calibreIdentifiers)) ??
        _findSpineIsbn(opf, manifest, opfPath, entries);
    final cover = _findCover(manifest, metadataElements, opfPath, entries);
    final series = _seriesMetadata(metadataElements, refinements);
    final modifiedDate = metadataElements
        .where(
          (element) =>
              _localName(element) == 'meta' &&
              element.getAttribute('property')?.toLowerCase() ==
                  'dcterms:modified',
        )
        .map(_nullableText)
        .whereType<String>()
        .firstOrNull;

    final result = ExtractedBookMetadata(
      title: EpubMetadataNormalizer.text(title),
      sortTitle: EpubMetadataNormalizer.text(sortTitle),
      authors: List.unmodifiable(
        authors.map(EpubMetadataNormalizer.text).whereType<String>(),
      ),
      description: EpubMetadataNormalizer.description(
        _firstText(metadataElements, 'description'),
      ),
      language: EpubMetadataNormalizer.language(
        _firstText(metadataElements, 'language'),
      ),
      publisher: EpubMetadataNormalizer.text(
        _firstText(metadataElements, 'publisher'),
      ),
      publishedDate: EpubMetadataNormalizer.publicationDate(
        _firstText(metadataElements, 'date'),
      ),
      isbn: isbn,
      coverBytes: cover?.bytes,
      coverExtension: cover?.extension,
      mediaType: cover?.mediaType,
      contributors: contributors,
      identifiers: List.unmodifiable(identifiers),
      subjects: _allText(metadataElements, 'subject'),
      rights: EpubMetadataNormalizer.text(
        _firstText(metadataElements, 'rights'),
      ),
      seriesName: series.name,
      seriesIndex: series.index,
      edition: _metaValue(metadataElements, const {'edition', 'version'}),
      source: EpubMetadataNormalizer.text(
        _firstText(metadataElements, 'source'),
      ),
      coverage: EpubMetadataNormalizer.text(
        _firstText(metadataElements, 'coverage'),
      ),
      type: EpubMetadataNormalizer.text(_firstText(metadataElements, 'type')),
      modifiedDate: EpubMetadataNormalizer.publicationDate(modifiedDate),
    );
    EpubMetadataDiagnostics.log(
      stage: 'SOURCE',
      field: 'title',
      source: 'opf_fallback',
      value: result.title,
    );
    EpubMetadataDiagnostics.log(
      stage: 'SOURCE',
      field: 'author',
      source: 'opf_fallback',
      value: result.authorDisplay,
    );
    EpubMetadataDiagnostics.log(
      stage: 'SOURCE',
      field: 'description',
      source: 'opf_fallback',
      value: result.description,
    );
    EpubMetadataDiagnostics.log(
      stage: 'SOURCE',
      field: 'publisher',
      source: 'opf_fallback',
      value: result.publisher,
    );
    return result;
  }

  _Cover? _findCover(
    XmlElement? manifest,
    List<XmlElement> metadata,
    String opfPath,
    Map<String, ArchiveFile> entries,
  ) {
    if (manifest == null) return null;
    final items = _childElements(
      manifest,
    ).where((element) => _localName(element) == 'item').toList();
    XmlElement? selected = items.firstWhere(
      (item) => (item.getAttribute('properties') ?? '')
          .split(RegExp(r'\s+'))
          .contains('cover-image'),
      orElse: () => XmlElement(XmlName.parts('empty')),
    );
    if (_localName(selected) == 'empty') {
      final coverMeta = metadata.firstWhere(
        (element) =>
            _localName(element) == 'meta' &&
            element.getAttribute('name')?.toLowerCase() == 'cover',
        orElse: () => XmlElement(XmlName.parts('empty')),
      );
      final coverId = coverMeta.getAttribute('content');
      if (coverId != null) {
        selected = items.firstWhere(
          (item) => item.getAttribute('id') == coverId,
          orElse: () => XmlElement(XmlName.parts('empty')),
        );
      }
    }
    if (_localName(selected) == 'empty') {
      selected = items.firstWhere(
        (item) => RegExp(
          r'cover',
          caseSensitive: false,
        ).hasMatch('${item.getAttribute('id')} ${item.getAttribute('href')}'),
        orElse: () => XmlElement(XmlName.parts('empty')),
      );
    }
    if (_localName(selected) == 'empty') return null;
    final href = selected.getAttribute('href');
    if (href == null) return null;
    final coverPath = _resolveRelativePath(opfPath, href);
    if (coverPath == null) return null;
    final extension = path.posix
        .extension(coverPath)
        .replaceFirst('.', '')
        .toLowerCase();
    if (!const {'jpg', 'jpeg', 'png', 'webp', 'gif'}.contains(extension)) {
      return null;
    }
    final bytes = _readEntry(entries[coverPath], maxCoverBytes);
    if (bytes == null) return null;
    return _Cover(bytes, extension, selected.getAttribute('media-type'));
  }

  String? _findSpineIsbn(
    XmlDocument opf,
    XmlElement? manifest,
    String opfPath,
    Map<String, ArchiveFile> entries,
  ) {
    if (manifest == null) return null;
    try {
      final itemsById = {
        for (final item in _childElements(
          manifest,
        ).where((element) => _localName(element) == 'item'))
          if (item.getAttribute('id') != null) item.getAttribute('id')!: item,
      };
      final spine = _elements(opf, 'spine').cast<XmlElement>().firstOrNull;
      if (spine == null) return null;
      final paths = <String>[];
      for (final itemref in _childElements(
        spine,
      ).where((element) => _localName(element) == 'itemref')) {
        if (itemref.getAttribute('linear')?.toLowerCase() == 'no') continue;
        final item = itemsById[itemref.getAttribute('idref')];
        final href = item?.getAttribute('href');
        final mediaType = item?.getAttribute('media-type')?.toLowerCase();
        if (href == null ||
            mediaType == null ||
            !(mediaType.contains('xhtml') || mediaType == 'text/html')) {
          continue;
        }
        final resolved = _resolveRelativePath(opfPath, href);
        if (resolved != null && !paths.contains(resolved)) paths.add(resolved);
      }
      final front = paths.take(3).toList();
      final frontIsbn = _scanIsbnDocuments(
        front,
        entries,
        IsbnSource.frontMatter,
      );
      if (frontIsbn != null) return frontIsbn;
      final back = paths.reversed
          .where((item) => !front.contains(item))
          .take(3)
          .toList();
      return _scanIsbnDocuments(back, entries, IsbnSource.backMatter);
    } catch (_) {
      return null;
    }
  }

  String? _scanIsbnDocuments(
    Iterable<String> paths,
    Map<String, ArchiveFile> entries,
    IsbnSource source,
  ) {
    for (final resourcePath in paths) {
      try {
        final bytes = _readEntry(entries[resourcePath], maxIsbnDocumentBytes);
        if (bytes == null) continue;
        final document = XmlDocument.parse(_decodeXml(bytes));
        final text = document.descendants
            .whereType<XmlText>()
            .where((node) {
              final parent = node.parent;
              return parent is! XmlElement ||
                  !const {'script', 'style', 'svg'}.contains(parent.name.local);
            })
            .map((node) => node.value)
            .join(' ');
        final limited = text.length > maxIsbnTextLength
            ? text.substring(0, maxIsbnTextLength)
            : text;
        final isbn = IsbnExtractor.selectBest(
          IsbnExtractor.extractCandidates(limited, source: source),
        );
        if (isbn != null) return isbn;
      } catch (_) {
        // Optional content documents must never make EPUB import fail.
      }
    }
    return null;
  }

  static Iterable<XmlElement> _elements(XmlNode node, String localName) => node
      .descendants
      .whereType<XmlElement>()
      .where((element) => _localName(element) == localName);
  static List<XmlElement> _childElements(XmlElement element) =>
      element.childElements.toList();
  static String _localName(XmlElement element) => element.name.local;
  static String _text(XmlElement element) => element.innerText.trim();
  static String? _nullableText(XmlElement element) =>
      _nullableString(_text(element));
  static String? _nullableString(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
  static String? _firstText(List<XmlElement> elements, String localName) =>
      _nullableText(
        elements.firstWhere(
          (element) => _localName(element) == localName,
          orElse: () => XmlElement(XmlName.parts('empty')),
        ),
      );

  static List<String> _allText(List<XmlElement> elements, String localName) =>
      List.unmodifiable(
        elements
            .where((element) => _localName(element) == localName)
            .map(_nullableText)
            .whereType<String>()
            .map(EpubMetadataNormalizer.text)
            .whereType<String>()
            .toSet(),
      );

  static String? _metaValue(List<XmlElement> elements, Set<String> names) {
    for (final element in elements.where(
      (element) => _localName(element) == 'meta',
    )) {
      final key =
          element.getAttribute('property')?.toLowerCase() ??
          element.getAttribute('name')?.toLowerCase();
      if (key == null || !names.any((name) => key.endsWith(name))) continue;
      return EpubMetadataNormalizer.text(
        element.getAttribute('content') ?? _text(element),
      );
    }
    return null;
  }

  static _SeriesMetadata _seriesMetadata(
    List<XmlElement> elements,
    Map<String, Map<String, String>> refinements,
  ) {
    for (final element in elements.where(
      (element) =>
          _localName(element) == 'meta' &&
          element.getAttribute('property') == 'belongs-to-collection',
    )) {
      final refinement = refinements[element.getAttribute('id')];
      if (refinement?['collection-type']?.toLowerCase() != 'series') continue;
      return _SeriesMetadata(
        EpubMetadataNormalizer.text(_text(element)),
        double.tryParse(refinement?['group-position'] ?? ''),
      );
    }
    final name = elements
        .where(
          (element) =>
              _localName(element) == 'meta' &&
              element.getAttribute('name')?.toLowerCase() == 'calibre:series',
        )
        .map((element) => element.getAttribute('content'))
        .whereType<String>()
        .firstOrNull;
    final index = elements
        .where(
          (element) =>
              _localName(element) == 'meta' &&
              element.getAttribute('name')?.toLowerCase() ==
                  'calibre:series_index',
        )
        .map((element) => element.getAttribute('content'))
        .whereType<String>()
        .firstOrNull;
    return _SeriesMetadata(
      EpubMetadataNormalizer.text(name),
      double.tryParse(index ?? ''),
    );
  }

  static Uint8List? _readEntry(ArchiveFile? entry, int maxBytes) {
    if (entry == null || entry.size > maxBytes) return null;
    final bytes = entry.readBytes();
    return bytes == null || bytes.length > maxBytes ? null : bytes;
  }

  /// Decodes XML bytes exactly once, honoring a BOM and XML declaration.
  static String _decodeXml(Uint8List bytes) {
    if (_startsWith(bytes, const [0xff, 0xfe])) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: true);
    }
    if (_startsWith(bytes, const [0xfe, 0xff])) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: false);
    }
    final declaration = latin1.decode(
      bytes.sublist(0, bytes.length.clamp(0, 512)),
    );
    final encoding = RegExp(
      r'''<\?xml[^>]*\bencoding\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(declaration)?.group(1)?.toLowerCase().replaceAll('_', '-');
    if (encoding == 'iso-8859-1' ||
        encoding == 'latin-1' ||
        encoding == 'us-ascii') {
      return latin1.decode(bytes);
    }
    if (encoding == 'windows-1252') return _decodeWindows1252(bytes);
    if (encoding != null && encoding != 'utf-8' && encoding != 'utf8') {
      throw const FormatException('Unsupported EPUB XML encoding');
    }
    final start = _startsWith(bytes, const [0xef, 0xbb, 0xbf]) ? 3 : 0;
    return utf8.decode(bytes.sublist(start), allowMalformed: false);
  }

  static bool _startsWith(Uint8List value, List<int> prefix) =>
      value.length >= prefix.length &&
      List.generate(
        prefix.length,
        (index) => value[index] == prefix[index],
      ).every((matches) => matches);

  static String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
    if (bytes.length.isOdd) throw const FormatException('Invalid UTF-16 XML');
    final codeUnits = <int>[];
    for (var index = 0; index < bytes.length; index += 2) {
      codeUnits.add(
        littleEndian
            ? bytes[index] | bytes[index + 1] << 8
            : bytes[index] << 8 | bytes[index + 1],
      );
    }
    return String.fromCharCodes(codeUnits);
  }

  static String _decodeWindows1252(Uint8List bytes) {
    const replacements = <int, int>{
      0x80: 0x20ac,
      0x82: 0x201a,
      0x83: 0x0192,
      0x84: 0x201e,
      0x85: 0x2026,
      0x86: 0x2020,
      0x87: 0x2021,
      0x88: 0x02c6,
      0x89: 0x2030,
      0x8a: 0x0160,
      0x8b: 0x2039,
      0x8c: 0x0152,
      0x8e: 0x017d,
      0x91: 0x2018,
      0x92: 0x2019,
      0x93: 0x201c,
      0x94: 0x201d,
      0x95: 0x2022,
      0x96: 0x2013,
      0x97: 0x2014,
      0x98: 0x02dc,
      0x99: 0x2122,
      0x9a: 0x0161,
      0x9b: 0x203a,
      0x9c: 0x0153,
      0x9e: 0x017e,
      0x9f: 0x0178,
    };
    return String.fromCharCodes(
      bytes.map((byte) => replacements[byte] ?? byte),
    );
  }

  static String? _safeArchivePath(String rawPath) {
    final decoded = Uri.decodeComponent(rawPath.replaceAll('\\', '/'));
    if (decoded.startsWith('/') || decoded.split('/').contains('..')) {
      return null;
    }
    final normalized = path.posix.normalize(decoded);
    return normalized == '.' || normalized.startsWith('../')
        ? null
        : normalized;
  }

  static String? _resolveRelativePath(String basePath, String href) {
    final decoded = Uri.decodeComponent(href.replaceAll('\\', '/'));
    return _safeArchivePath(
      path.posix.join(path.posix.dirname(basePath), decoded),
    );
  }

  static String? _findIsbn(Iterable<String> values) {
    return IsbnExtractor.selectBest(
      values.expand(
        (value) => IsbnExtractor.extractCandidates(
          value,
          source: IsbnSource.packageMetadata,
        ),
      ),
    );
  }
}

class _Cover {
  const _Cover(this.bytes, this.extension, this.mediaType);
  final Uint8List bytes;
  final String extension;
  final String? mediaType;
}

class _SeriesMetadata {
  const _SeriesMetadata(this.name, this.index);
  final String? name;
  final double? index;
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bibliolife/features/metadata/domain/entities/extracted_book_metadata.dart';
import 'package:bibliolife/features/metadata/domain/entities/metadata_extraction_result.dart';
import 'package:xml/xml.dart';

/// Bounded FictionBook 2 parser used during import. Rendering has its own
/// parser, but both deliberately share no platform or WebView dependency.
class Fb2MetadataParser {
  static const _maxBytes = 20 * 1024 * 1024;
  static const _maxCoverBytes = 15 * 1024 * 1024;

  Future<MetadataExtractionResult> parse(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists() || await file.length() > _maxBytes) {
        return const MetadataFileReadFailed();
      }
      final document = XmlDocument.parse(
        utf8.decode(await file.readAsBytes(), allowMalformed: false),
      );
      final description = _first(document, 'description');
      final titleInfo = description == null
          ? null
          : _first(description, 'title-info');
      final title = titleInfo == null
          ? null
          : _text(_first(titleInfo, 'book-title'));
      final authors = titleInfo == null
          ? const <String>[]
          : _children(
              titleInfo,
              'author',
            ).map(_author).whereType<String>().toList();
      final annotation = titleInfo == null
          ? null
          : _text(_first(titleInfo, 'annotation'));
      final language = titleInfo == null
          ? null
          : _text(_first(titleInfo, 'lang'));
      final subjects = titleInfo == null
          ? const <String>[]
          : _children(
              titleInfo,
              'genre',
            ).map(_text).whereType<String>().toList();
      final coverId = titleInfo == null
          ? null
          : _first(titleInfo, 'coverpage')?.descendants
                .whereType<XmlElement>()
                .firstWhere(
                  (element) => _name(element) == 'image',
                  orElse: () => XmlElement(XmlName.parts('missing')),
                )
                .attributes
                .where((attribute) => attribute.name.local == 'href')
                .map((attribute) => attribute.value.replaceFirst('#', ''))
                .firstOrNull;
      final cover = coverId == null ? null : _binary(document, coverId);
      return MetadataExtractionSuccess(
        ExtractedBookMetadata(
          title: title,
          sortTitle: null,
          authors: authors,
          description: annotation,
          language: language,
          publisher: null,
          publishedDate: null,
          isbn: null,
          coverBytes: cover?.bytes,
          coverExtension: cover?.extension,
          mediaType: 'application/x-fictionbook+xml',
          subjects: subjects,
        ),
      );
    } on FileSystemException catch (error) {
      return MetadataFileReadFailed(diagnosticCause: error);
    } on FormatException catch (error) {
      return MetadataParsingFailed(diagnosticCause: error);
    } on XmlException catch (error) {
      return MetadataParsingFailed(diagnosticCause: error);
    } catch (error) {
      return MetadataParsingFailed(diagnosticCause: error);
    }
  }

  _Fb2Binary? _binary(XmlDocument document, String id) {
    final element = document.descendants.whereType<XmlElement>().firstWhere(
      (candidate) =>
          _name(candidate) == 'binary' && candidate.getAttribute('id') == id,
      orElse: () => XmlElement(XmlName.parts('missing')),
    );
    if (_name(element) == 'missing') return null;
    try {
      final bytes = base64.decode(
        element.innerText.replaceAll(RegExp(r'\s+'), ''),
      );
      if (bytes.isEmpty || bytes.length > _maxCoverBytes) return null;
      final contentType = element.getAttribute('content-type')?.toLowerCase();
      return _Fb2Binary(bytes, _extensionFor(contentType));
    } on FormatException {
      return null;
    }
  }
}

class _Fb2Binary {
  const _Fb2Binary(this.bytes, this.extension);
  final Uint8List bytes;
  final String extension;
}

String _name(XmlNode node) => node is XmlElement ? node.name.local : '';
XmlElement? _first(XmlNode root, String local) => root.descendants
    .whereType<XmlElement>()
    .cast<XmlElement?>()
    .firstWhere((element) => _name(element!) == local, orElse: () => null);
Iterable<XmlElement> _children(XmlElement root, String local) => root.children
    .whereType<XmlElement>()
    .where((element) => _name(element) == local);
String? _text(XmlElement? element) {
  final value = element?.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
  return value == null || value.isEmpty ? null : value;
}

String? _author(XmlElement element) {
  final parts = [
    'first-name',
    'middle-name',
    'last-name',
  ].map((name) => _text(_first(element, name))).whereType<String>();
  final full = parts.join(' ').trim();
  return full.isEmpty ? _text(_first(element, 'nickname')) : full;
}

String _extensionFor(String? contentType) => switch (contentType) {
  'image/jpeg' => 'jpg',
  'image/png' => 'png',
  'image/webp' => 'webp',
  'image/gif' => 'gif',
  _ => 'png',
};

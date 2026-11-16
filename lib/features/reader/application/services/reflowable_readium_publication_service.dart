import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:bibliolife/features/reader/application/services/reflowable_book_loader.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

typedef ReaderCacheDirectoryProvider = Future<Directory> Function();
const _reflowableConversionVersion = 3;

/// Adapts FB2 and plain text books to the same Readium EPUB runtime used by
/// native EPUB files. The generated publication is deterministic for a source
/// revision, so saved Readium locators and annotation decorations remain
/// stable between reader sessions.
class ReflowableReadiumPublicationService {
  ReflowableReadiumPublicationService({
    ReflowableBookLoader? loader,
    ReaderCacheDirectoryProvider? cacheDirectory,
  }) : _loader = loader ?? ReflowableBookLoader(),
       _cacheDirectory = cacheDirectory ?? getApplicationCacheDirectory;

  final ReflowableBookLoader _loader;
  final ReaderCacheDirectoryProvider _cacheDirectory;

  Future<String> prepare(
    LibraryBook book, {
    void Function(String stage, String result, Map<String, Object?> facts)?
    onDiagnostic,
  }) async {
    var currentStage = 'file_access';
    void report(
      String stage,
      String result, [
      Map<String, Object?> facts = const {},
    ]) {
      currentStage = stage;
      try {
        onDiagnostic?.call(stage, result, facts);
      } on Object {
        // Observers cannot change conversion or cache behavior.
      }
    }

    try {
      return await _prepare(book, report);
    } catch (error) {
      report(currentStage, 'failed', {
        'errorCode': error is ReflowableReadiumPublicationException
            ? error.code
            : '${currentStage}_failed',
        'exceptionType': error.runtimeType.toString(),
      });
      rethrow;
    }
  }

  Future<String> _prepare(
    LibraryBook book,
    void Function(String, String, [Map<String, Object?>]) report,
  ) async {
    report('file_access', 'started');
    if (book.format != BookFormat.fb2 && book.format != BookFormat.txt) {
      throw const ReflowableReadiumPublicationException('unsupported_format');
    }
    final source = File(book.filePath);
    if (!await source.exists()) {
      throw const ReflowableReadiumPublicationException('file_not_found');
    }

    final stat = await source.stat();
    final signature =
        'v$_reflowableConversionVersion-${stat.size}-${stat.modified.millisecondsSinceEpoch}';
    report('file_access', 'success', {'fileExists': true});
    report('cache_resolution', 'started');
    final publicationId = sha256
        .convert(utf8.encode('${book.id}:$signature'))
        .toString();
    final publicationFacts = <String, Object?>{
      'generatedPublicationId': publicationId,
      'generatedResourceHref': 'text/content.xhtml',
    };
    final root = Directory(
      path.join(
        (await _cacheDirectory()).path,
        'bibliolife-readium-reflowable',
        _safeBookId(book.id),
      ),
    );
    final revision = Directory(path.join(root.path, signature));
    final output = File(path.join(revision.path, 'publication.epub'));

    if (await output.exists() && await output.length() > 0) {
      report('cache_resolution', 'success', {
        ...publicationFacts,
        'conversionCacheStatus': 'hit',
      });
      return output.path;
    }
    report('cache_resolution', 'success', {
      ...publicationFacts,
      'conversionCacheStatus': 'miss',
    });

    await _removeStaleRevisions(root, signature);
    report('text_decode', 'started');
    final content = await _loader.load(book);
    report('text_decode', 'success');
    report('epub_conversion', 'started');
    await revision.create(recursive: true);
    final temporary = File(path.join(revision.path, 'publication.epub.tmp'));
    try {
      final bytes = _buildEpub(book, content, stat.modified.toUtc());
      await temporary.writeAsBytes(bytes, flush: true);
      if (await output.exists()) await output.delete();
      await temporary.rename(output.path);
      report('epub_conversion', 'success', {
        ...publicationFacts,
        'conversionCacheStatus': 'regenerated',
      });
      return output.path;
    } on Object {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<void> _removeStaleRevisions(Directory root, String keep) async {
    if (!await root.exists()) return;
    await for (final entry in root.list(followLinks: false)) {
      if (entry is Directory && path.basename(entry.path) != keep) {
        await entry.delete(recursive: true);
      }
    }
  }
}

class ReflowableReadiumPublicationException implements Exception {
  const ReflowableReadiumPublicationException(this.code);
  final String code;
}

Uint8List _buildEpub(
  LibraryBook book,
  ReflowableBook content,
  DateTime modified,
) {
  final archive = Archive();
  final mimetype = ArchiveFile.string('mimetype', 'application/epub+zip')
    ..compression = CompressionType.none;
  archive.addFile(mimetype);
  archive.addFile(
    ArchiveFile.string(
      'META-INF/container.xml',
      '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''',
    ),
  );

  final images = <_PublicationImage>[];
  for (var index = 0; index < content.blocks.length; index++) {
    final bytes = content.blocks[index].image;
    if (bytes == null) continue;
    final type = _imageType(bytes);
    if (type == null) continue;
    images.add(
      _PublicationImage(
        blockIndex: index,
        href: 'images/image-$index.${type.extension}',
        mediaType: type.mediaType,
        bytes: bytes,
      ),
    );
  }

  archive.addFile(
    ArchiveFile.string(
      'OEBPS/content.opf',
      _packageDocument(book, images, modified),
    ),
  );
  archive.addFile(
    ArchiveFile.string('OEBPS/nav.xhtml', _navigationDocument(book, content)),
  );
  archive.addFile(
    ArchiveFile.string(
      'OEBPS/text/content.xhtml',
      _contentDocument(book, content, images),
    ),
  );
  for (final image in images) {
    archive.addFile(
      ArchiveFile(
        image.href.replaceFirst('images/', 'OEBPS/images/'),
        image.bytes.length,
        image.bytes,
      ),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

String _packageDocument(
  LibraryBook book,
  List<_PublicationImage> images,
  DateTime modified,
) {
  final imageItems = images
      .map(
        (image) =>
            '<item id="image-${image.blockIndex}" href="${_xmlAttribute(image.href)}" media-type="${image.mediaType}"/>',
      )
      .join('\n    ');
  final author = _nonBlank(book.author);
  return '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="book-id">urn:bibliolife:${_xmlText(book.id)}</dc:identifier>
    <dc:title>${_xmlText(book.title)}</dc:title>
    <dc:language>${_xmlText(_nonBlank(book.language) ?? 'und')}</dc:language>
    ${author == null ? '' : '<dc:creator>${_xmlText(author)}</dc:creator>'}
    <meta property="dcterms:modified">${modified.toIso8601String()}</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="content" href="text/content.xhtml" media-type="application/xhtml+xml"/>
    $imageItems
  </manifest>
  <spine><itemref idref="content"/></spine>
</package>''';
}

String _navigationDocument(LibraryBook book, ReflowableBook content) {
  final headings = <({int index, String title})>[];
  for (var index = 0; index < content.blocks.length; index++) {
    final block = content.blocks[index];
    if (block.kind != ReflowBlockKind.heading) continue;
    final title = block.spans.map((span) => span.text).join().trim();
    if (title.isNotEmpty) headings.add((index: index, title: title));
  }
  final entries = headings.isEmpty
      ? '<li><a href="text/content.xhtml#block-0">${_xmlText(book.title)}</a></li>'
      : headings
            .map(
              (heading) =>
                  '<li><a href="text/content.xhtml#block-${heading.index}">${_xmlText(heading.title)}</a></li>',
            )
            .join('\n      ');
  return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="${_xmlAttribute(_nonBlank(book.language) ?? 'und')}">
<head><title>${_xmlText(book.title)}</title></head>
<body><nav epub:type="toc" id="toc"><h1>${_xmlText(book.title)}</h1><ol>
      $entries
    </ol></nav></body>
</html>''';
}

String _contentDocument(
  LibraryBook book,
  ReflowableBook content,
  List<_PublicationImage> images,
) {
  final imageByBlock = <int, _PublicationImage>{
    for (final image in images) image.blockIndex: image,
  };
  final blocks = <String>[];
  for (var index = 0; index < content.blocks.length; index++) {
    final block = content.blocks[index];
    final id = 'block-$index';
    if (block.kind == ReflowBlockKind.image) {
      final image = imageByBlock[index];
      if (image != null) {
        blocks.add(
          '<figure id="$id"><img src="../${_xmlAttribute(image.href)}" alt=""/></figure>',
        );
      }
      continue;
    }
    if (block.kind == ReflowBlockKind.spacer) {
      blocks.add(
        '<p id="$id" class="empty-line" aria-hidden="true">&#160;</p>',
      );
      continue;
    }
    final text = block.spans.map(_spanMarkup).join();
    final markup = switch (block.kind) {
      ReflowBlockKind.heading => '<h1 id="$id">$text</h1>',
      ReflowBlockKind.quote => '<blockquote id="$id"><p>$text</p></blockquote>',
      ReflowBlockKind.poem => '<p id="$id" class="poem">$text</p>',
      _ => '<p id="$id">$text</p>',
    };
    blocks.add(markup);
  }
  if (blocks.isEmpty) blocks.add('<p id="block-0"></p>');
  return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" lang="${_xmlAttribute(_nonBlank(book.language) ?? 'und')}">
<head>
  <meta charset="UTF-8"/>
  <title>${_xmlText(book.title)}</title>
  <style>p,h1,blockquote,figure{margin-top:0;margin-bottom:1em}.poem{white-space:pre-wrap}img{max-width:100%;height:auto}</style>
</head>
<body>${blocks.join('\n')}</body>
</html>''';
}

String _spanMarkup(ReflowSpan span) {
  var value = _xmlText(span.text);
  if (span.italic) value = '<em>$value</em>';
  if (span.bold) value = '<strong>$value</strong>';
  return value;
}

_ImageType? _imageType(Uint8List bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47) {
    return const _ImageType('png', 'image/png');
  }
  if (bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8) {
    return const _ImageType('jpg', 'image/jpeg');
  }
  if (bytes.length >= 6 && ascii.decode(bytes.sublist(0, 3)) == 'GIF') {
    return const _ImageType('gif', 'image/gif');
  }
  if (bytes.length >= 12 &&
      ascii.decode(bytes.sublist(0, 4)) == 'RIFF' &&
      ascii.decode(bytes.sublist(8, 12)) == 'WEBP') {
    return const _ImageType('webp', 'image/webp');
  }
  return null;
}

String _safeBookId(String value) =>
    base64Url.encode(utf8.encode(value)).replaceAll('=', '');
String _xmlText(String value) =>
    const HtmlEscape(HtmlEscapeMode.element).convert(value);
String _xmlAttribute(String value) =>
    const HtmlEscape(HtmlEscapeMode.attribute).convert(value);
String? _nonBlank(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

class _PublicationImage {
  const _PublicationImage({
    required this.blockIndex,
    required this.href,
    required this.mediaType,
    required this.bytes,
  });
  final int blockIndex;
  final String href;
  final String mediaType;
  final Uint8List bytes;
}

class _ImageType {
  const _ImageType(this.extension, this.mediaType);
  final String extension;
  final String mediaType;
}

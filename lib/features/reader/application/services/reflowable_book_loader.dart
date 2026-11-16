import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:xml/xml.dart';

enum ReflowBlockKind { paragraph, heading, quote, poem, spacer, image }

class ReflowSpan {
  const ReflowSpan(this.text, {this.italic = false, this.bold = false});
  final String text;
  final bool italic;
  final bool bold;
}

class ReflowBlock {
  const ReflowBlock.text(this.kind, this.spans) : image = null;
  const ReflowBlock.image(this.image)
    : kind = ReflowBlockKind.image,
      spans = const [];
  final ReflowBlockKind kind;
  final List<ReflowSpan> spans;
  final Uint8List? image;
}

class ReflowableBook {
  const ReflowableBook({required this.blocks});
  final List<ReflowBlock> blocks;
}

class ReflowableBookLoader {
  Future<ReflowableBook> load(LibraryBook book) => switch (book.format) {
    BookFormat.txt => _loadText(book.filePath),
    BookFormat.fb2 => _loadFb2(book.filePath),
    _ => Future.error(const ReflowableBookException()),
  };

  Future<ReflowableBook> _loadText(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final text = decodePlainText(bytes);
      final blocks = <ReflowBlock>[];
      for (final line
          in text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
        if (line.trim().isEmpty) {
          blocks.add(const ReflowBlock.text(ReflowBlockKind.spacer, []));
        } else {
          blocks.add(
            ReflowBlock.text(ReflowBlockKind.paragraph, [ReflowSpan(line)]),
          );
        }
      }
      return ReflowableBook(
        blocks: blocks.isEmpty
            ? const [
                ReflowBlock.text(ReflowBlockKind.paragraph, [ReflowSpan('')]),
              ]
            : List.unmodifiable(blocks),
      );
    } on FileSystemException {
      throw const ReflowableBookException();
    }
  }

  Future<ReflowableBook> _loadFb2(String filePath) async {
    try {
      final document = XmlDocument.parse(
        decodeFb2Xml(await File(filePath).readAsBytes()),
      );
      final images = <String, Uint8List>{};
      for (final binary in document.descendants.whereType<XmlElement>().where(
        (e) => e.name.local == 'binary',
      )) {
        final id = binary.getAttribute('id');
        if (id == null) continue;
        try {
          images[id] = base64.decode(
            binary.innerText.replaceAll(RegExp(r'\s+'), ''),
          );
        } on FormatException {
          // Broken embedded images do not make the textual book unreadable.
        }
      }
      final blocks = <ReflowBlock>[];
      final bodies = document.descendants.whereType<XmlElement>().where(
        (e) => e.name.local == 'body',
      );
      for (final body in bodies) {
        for (final node in body.children.whereType<XmlElement>()) {
          _appendFb2(node, blocks, images);
        }
      }
      if (blocks.isEmpty) throw const ReflowableBookException();
      return ReflowableBook(blocks: List.unmodifiable(blocks));
    } on FormatException {
      throw const ReflowableBookException();
    } on XmlException {
      throw const ReflowableBookException();
    } on FileSystemException {
      throw const ReflowableBookException();
    }
  }

  void _appendFb2(
    XmlElement element,
    List<ReflowBlock> output,
    Map<String, Uint8List> images,
  ) {
    final name = element.name.local;
    if (name == 'section' ||
        name == 'body' ||
        name == 'poem' ||
        name == 'stanza') {
      for (final child in element.children.whereType<XmlElement>()) {
        _appendFb2(child, output, images);
      }
      return;
    }
    if (name == 'empty-line') {
      output.add(const ReflowBlock.text(ReflowBlockKind.spacer, []));
      return;
    }
    if (name == 'image') {
      final href = element.attributes
          .where((attribute) => attribute.name.local == 'href')
          .map((attribute) => attribute.value.replaceFirst('#', ''))
          .firstOrNull;
      final bytes = href == null ? null : images[href];
      if (bytes != null && bytes.isNotEmpty) {
        output.add(ReflowBlock.image(bytes));
      }
      return;
    }
    final kind = switch (name) {
      'title' || 'subtitle' => ReflowBlockKind.heading,
      'cite' => ReflowBlockKind.quote,
      'v' => ReflowBlockKind.poem,
      'p' => ReflowBlockKind.paragraph,
      _ => null,
    };
    if (kind != null) {
      final spans = _spans(element);
      if (spans.isNotEmpty) {
        output.add(ReflowBlock.text(kind, spans));
      }
      return;
    }
    for (final child in element.children.whereType<XmlElement>()) {
      _appendFb2(child, output, images);
    }
  }

  List<ReflowSpan> _spans(
    XmlNode node, {
    bool italic = false,
    bool bold = false,
  }) {
    final spans = <ReflowSpan>[];
    for (final child in node.children) {
      if (child is XmlText) {
        if (child.value.isNotEmpty) {
          spans.add(ReflowSpan(child.value, italic: italic, bold: bold));
        }
      } else if (child is XmlElement) {
        final name = child.name.local;
        spans.addAll(
          _spans(
            child,
            italic: italic || name == 'emphasis',
            bold: bold || name == 'strong',
          ),
        );
      }
    }
    return spans;
  }
}

class ReflowableBookException implements Exception {
  const ReflowableBookException();
}

/// Strict decoding avoids presenting damaged text as a book full of U+FFFD.
String decodePlainText(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf) {
    return utf8.decode(bytes.sublist(3), allowMalformed: false);
  }
  if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: false);
  }
  try {
    return utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    final decoded = _decodeWindows1251(bytes);
    if (_unreadable(decoded)) {
      throw const FormatException('Unsupported text encoding');
    }
    return decoded;
  }
}

/// FB2 permits an XML-declared legacy encoding. Decode the source bytes before
/// handing the Unicode string to the XML parser instead of assuming UTF-8.
String decodeFb2Xml(Uint8List bytes) {
  if (bytes.length >= 2 &&
      ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
          (bytes[0] == 0xfe && bytes[1] == 0xff))) {
    return decodePlainText(bytes);
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x00 &&
      bytes[1] == 0x3c &&
      bytes[2] == 0x00 &&
      bytes[3] == 0x3f) {
    return _decodeUtf16(bytes, littleEndian: false);
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x3c &&
      bytes[1] == 0x00 &&
      bytes[2] == 0x3f &&
      bytes[3] == 0x00) {
    return _decodeUtf16(bytes, littleEndian: true);
  }

  final prefix = latin1.decode(bytes.take(512).toList(), allowInvalid: true);
  final declared = RegExp(
    r'''encoding\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  ).firstMatch(prefix)?.group(1)?.toLowerCase().replaceAll('_', '-');
  if (declared == 'windows-1251' ||
      declared == 'windows1251' ||
      declared == 'cp1251') {
    return _decodeWindows1251(bytes);
  }
  return decodePlainText(bytes);
}

String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
  if (bytes.length.isOdd) {
    throw const FormatException('Malformed UTF-16');
  }
  final units = <int>[];
  for (var index = 0; index < bytes.length; index += 2) {
    units.add(
      littleEndian
          ? bytes[index] | (bytes[index + 1] << 8)
          : (bytes[index] << 8) | bytes[index + 1],
    );
  }
  final decoded = String.fromCharCodes(units);
  if (_unreadable(decoded)) throw const FormatException('Unreadable UTF-16');
  return decoded;
}

String _decodeWindows1251(Uint8List bytes) {
  const table =
      'ЂЃ‚ѓ„…†‡€‰Љ‹ЊЌЋЏђ‘’“”•–—™љ›њќћџ ЎўЈ¤Ґ¦§Ё©Є«¬­®Ї°±Ііґµ¶·ё№є»јЅѕїАБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдежзийклмнопрстуфхцчшщъыьэюя';
  final buffer = StringBuffer();
  for (final value in bytes) {
    final character = switch (value) {
      < 0x80 => String.fromCharCode(value),
      >= 0xc0 => String.fromCharCode(
        (value < 0xe0 ? 0x0410 : 0x0430) + (value & 0x1f),
      ),
      0xa8 => 'Ё',
      0xb8 => 'ё',
      _ => table[value - 0x80],
    };
    buffer.write(character);
  }
  return buffer.toString();
}

bool _unreadable(String value) {
  if (value.contains('\ufffd') || value.isEmpty) return true;
  final controls = value.runes
      .where((rune) => rune < 32 && rune != 9 && rune != 10 && rune != 13)
      .length;
  return controls > value.length ~/ 20;
}

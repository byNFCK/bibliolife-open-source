import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

sealed class ReadiumTocExtractionResult {
  const ReadiumTocExtractionResult();
  static ReadiumTocExtractionResult fromMap(Object? value) {
    if (value is! Map) {
      return const ReadiumTocExtractionFailure('invalid_result');
    }
    if (value['status'] == 'empty') return const ReadiumTocExtractionEmpty();
    if (value['status'] != 'success') {
      return ReadiumTocExtractionFailure(
        value['failure'] is String ? value['failure'] as String : 'unknown',
      );
    }
    return ReadiumTocExtractionSuccess(
      List.unmodifiable(
        ((value['entries'] as List?) ?? const [])
            .map(ReadiumTocEntry.fromMap)
            .whereType<ReadiumTocEntry>(),
      ),
    );
  }
}

final class ReadiumTocExtractionSuccess extends ReadiumTocExtractionResult {
  const ReadiumTocExtractionSuccess(this.entries);
  final List<ReadiumTocEntry> entries;
}

final class ReadiumTocExtractionEmpty extends ReadiumTocExtractionResult {
  const ReadiumTocExtractionEmpty();
}

final class ReadiumTocExtractionFailure extends ReadiumTocExtractionResult {
  const ReadiumTocExtractionFailure(this.code);
  final String code;
}

final class ReadiumTocEntry {
  const ReadiumTocEntry({
    required this.title,
    required this.locatorJson,
    this.children = const [],
  });
  final String title;
  final String locatorJson;
  final List<ReadiumTocEntry> children;

  static ReadiumTocEntry? fromMap(Object? value) {
    if (value is! Map ||
        value['title'] is! String ||
        value['locatorJson'] is! String) {
      return null;
    }
    final title = (value['title'] as String).trim();
    final locator = (value['locatorJson'] as String).trim();
    if (title.isEmpty || locator.isEmpty) return null;
    return ReadiumTocEntry(
      title: title,
      locatorJson: locator,
      children: List.unmodifiable(
        ((value['children'] as List?) ?? const [])
            .map(ReadiumTocEntry.fromMap)
            .whereType<ReadiumTocEntry>(),
      ),
    );
  }
}

abstract interface class ReadiumTocExtractor {
  bool get isSupported;
  Future<ReadiumTocExtractionResult> extractTableOfContents(String filePath);
}

class MethodChannelReadiumTocExtractor implements ReadiumTocExtractor {
  MethodChannelReadiumTocExtractor({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('app.bibliolife.reader/readium');
  final MethodChannel _channel;
  @override
  bool get isSupported => defaultTargetPlatform == TargetPlatform.android;
  @override
  Future<ReadiumTocExtractionResult> extractTableOfContents(
    String filePath,
  ) async {
    if (!isSupported) {
      return const ReadiumTocExtractionFailure('unsupported_platform');
    }
    try {
      return ReadiumTocExtractionResult.fromMap(
        await _channel.invokeMethod<Object?>('extractTableOfContents', {
          'filePath': filePath,
        }),
      );
    } on PlatformException catch (error) {
      return ReadiumTocExtractionFailure(error.code);
    } on MissingPluginException {
      return const ReadiumTocExtractionFailure('plugin_unavailable');
    }
  }
}

import 'dart:convert';

import 'package:bibliolife/features/reader/domain/models/reader_annotation.dart';
import 'package:bibliolife/features/reader/domain/value_objects/annotation_location_key.dart';
import 'package:bibliolife_readium/bibliolife_readium.dart';
import 'package:uuid/uuid.dart';

/// Prepares a new annotation from a native Readium selection without saving it.
class ReaderAnnotationDraftFactory {
  ReaderAnnotationDraftFactory({
    String Function()? idGenerator,
    DateTime Function()? clock,
  }) : _idGenerator = idGenerator ?? const Uuid().v4,
       _clock = clock ?? DateTime.now;

  final String Function() _idGenerator;
  final DateTime Function() _clock;

  ReaderAnnotation create({
    required String bookId,
    required ReaderSelectionPlatformEvent selection,
    required ReaderAnnotationStyle style,
    required ReaderAnnotationColor color,
    String? note,
  }) {
    _requireNonBlank(bookId, 'bookId');
    _requireNonBlank(selection.selectedText, 'selectedText');
    _requireNonBlank(selection.href, 'href');
    _validateProgression(selection.progression, 'progression');
    _validateProgression(selection.totalProgression, 'totalProgression');

    final id = _idGenerator();
    _requireNonBlank(id, 'id');
    final fragments = _parseFragments(selection.locatorJson);
    final now = _clock();

    return ReaderAnnotation(
      id: id,
      bookId: bookId,
      locatorJson: selection.locatorJson,
      locationKey: AnnotationLocationKey.build(
        bookId: bookId,
        href: selection.href,
        fragments: fragments,
        progression: selection.progression,
        selectedText: selection.selectedText,
      ),
      selectedText: selection.selectedText,
      textBefore: selection.textBefore,
      textAfter: selection.textAfter,
      note: _normalizeCreationNote(note),
      style: style,
      color: color,
      href: selection.href,
      progression: selection.progression,
      totalProgression: selection.totalProgression,
      createdAt: now,
      updatedAt: now,
    );
  }

  static List<String> _parseFragments(String locatorJson) {
    final Object? decoded;
    try {
      decoded = jsonDecode(locatorJson);
    } on FormatException {
      throw const FormatException('Invalid Readium locator JSON');
    }
    if (decoded is! Map) {
      throw const FormatException('Invalid Readium locator JSON');
    }
    final locations = decoded['locations'];
    if (locations is! Map) {
      throw const FormatException('Missing Readium locator locations');
    }
    final fragments = locations['fragments'];
    if (fragments == null) return const [];
    if (fragments is! List ||
        fragments.any((fragment) => fragment is! String)) {
      throw const FormatException('Invalid Readium locator fragments');
    }
    return List<String>.from(fragments);
  }

  static void _requireNonBlank(String value, String name) {
    if (value.trim().isEmpty) throw ArgumentError.value(value, name);
  }

  static void _validateProgression(double? value, String name) {
    if (value != null && (!value.isFinite || value < 0 || value > 1)) {
      throw ArgumentError.value(value, name);
    }
  }

  static String? _normalizeCreationNote(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

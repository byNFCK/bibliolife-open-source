import 'dart:convert';

import 'package:bibliolife/shared/models/book_format.dart';

class ReaderLaunchRequest {
  const ReaderLaunchRequest({
    required this.bookId,
    this.initialLocatorJson,
    this.formatHint,
    this.source = 'other',
  });
  final String bookId;
  final String? initialLocatorJson;
  final BookFormat? formatHint;
  final String source;

  bool get hasValidExplicitLocator {
    final locator = initialLocatorJson?.trim();
    if (locator == null || locator.isEmpty) return false;
    try {
      return jsonDecode(locator) is Map<String, dynamic>;
    } on FormatException {
      return false;
    }
  }

  String? get validExplicitLocator =>
      hasValidExplicitLocator ? initialLocatorJson!.trim() : null;
}

import 'dart:math' as math;

import 'package:bibliolife/features/reader/domain/models/reading_progress.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:bibliolife_readium/bibliolife_readium.dart';

String normalizeBookDetailsText(String? value) =>
    value?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';

int readingProgressPercent(double? progression) {
  if (progression == null || !progression.isFinite) return 0;
  return (progression.clamp(0.0, 1.0) * 100).round();
}

String? readingPageLabel(ReadingProgress? progress) {
  final locatorJson = progress?.locatorJson;
  final current =
      progress?.currentPage ??
      (locatorJson == null
          ? null
          : ReadiumLocator.tryParse(locatorJson)?.locations.position);
  if (current == null || current < 1) return null;
  final total = progress?.totalPages;
  return total != null && total >= current && total > 0
      ? '$current/$total'
      : '$current';
}

String? formatBookFileSummary(LibraryBook book) {
  final format = _formatLabel(book.format, book.fileExtension);
  final size = formatFileSize(book.fileSizeBytes);
  if (format == null) return size;
  if (size == null) return format;
  return '$format · $size';
}

String? formatFileSize(int bytes) {
  if (bytes <= 0) return null;
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

String? _formatLabel(BookFormat format, String extension) {
  final normalized = format.normalizedExtension.trim().isNotEmpty
      ? format.normalizedExtension.trim()
      : extension.trim().replaceFirst(RegExp(r'^\.+'), '');
  if (normalized.isEmpty || format == BookFormat.unknown && extension.isEmpty) {
    return null;
  }
  return normalized.substring(0, math.min(normalized.length, 16)).toUpperCase();
}

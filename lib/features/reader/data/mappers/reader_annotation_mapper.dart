import 'package:bibliolife/core/database/app_database.dart' as db;
import 'package:bibliolife/features/reader/domain/models/reader_annotation.dart';
import 'package:drift/drift.dart';

extension DriftReaderAnnotationMapper on db.ReaderAnnotation {
  ReaderAnnotation toDomain() {
    final style = ReaderAnnotationStyle.tryParse(this.style);
    final color = ReaderAnnotationColor.tryParse(this.color);
    if (style == null) throw FormatException('Invalid annotation style');
    if (color == null) throw FormatException('Invalid annotation color');
    return ReaderAnnotation(
      id: id,
      bookId: bookId,
      locatorJson: locatorJson,
      locationKey: locationKey,
      selectedText: selectedText,
      textBefore: textBefore,
      textAfter: textAfter,
      note: note,
      style: style,
      color: color,
      href: href,
      progression: progression,
      totalProgression: totalProgression,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

extension DomainReaderAnnotationMapper on ReaderAnnotation {
  db.ReaderAnnotationsCompanion toReaderAnnotationsCompanion() =>
      db.ReaderAnnotationsCompanion.insert(
        id: id,
        bookId: bookId,
        locatorJson: locatorJson,
        locationKey: locationKey,
        selectedText: selectedText,
        textBefore: Value(textBefore),
        textAfter: Value(textAfter),
        note: Value(note),
        style: Value(style.storageValue),
        color: Value(color.storageValue),
        href: href,
        progression: Value(progression),
        totalProgression: Value(totalProgression),
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

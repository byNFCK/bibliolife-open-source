import 'package:bibliolife/core/database/app_database.dart' as db;
import 'package:bibliolife/features/reader/data/mappers/reader_annotation_mapper.dart';
import 'package:bibliolife/features/reader/domain/models/reader_annotation.dart'
    as domain;
import 'package:bibliolife/features/reader/domain/repositories/reader_annotation_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart' show SqliteException;

class DriftReaderAnnotationRepository implements ReaderAnnotationRepository {
  DriftReaderAnnotationRepository(this._database, {this.beforeUpsertInsert});

  final db.AppDatabase _database;
  final Future<void> Function()? beforeUpsertInsert;
  String _required(String value, String name) {
    if (value.trim().isEmpty) throw ArgumentError.value(value, name);
    return value;
  }

  @override
  Stream<List<domain.ReaderAnnotation>> watchForBook(String bookId) {
    final query = _database.select(_database.readerAnnotations)
      ..where((t) => t.bookId.equals(_required(bookId, 'bookId')));
    query.orderBy([
      (t) => OrderingTerm(expression: t.totalProgression.isNull()),
      (t) => OrderingTerm.asc(t.totalProgression),
      (t) => OrderingTerm.asc(t.href),
      (t) => OrderingTerm(expression: t.progression.isNull()),
      (t) => OrderingTerm.asc(t.progression),
      (t) => OrderingTerm.asc(t.createdAt),
      (t) => OrderingTerm.asc(t.id),
    ]);
    return query.watch().map(
      (rows) => rows
          .map((row) {
            try {
              return row.toDomain();
            } catch (_) {
              // A corrupt legacy row must not prevent valid annotations from restoring.
              return null;
            }
          })
          .whereType<domain.ReaderAnnotation>()
          .toList(),
    );
  }

  @override
  Future<List<domain.ReaderAnnotation>> listForBook(String bookId) async {
    final query = _database.select(_database.readerAnnotations)
      ..where((t) => t.bookId.equals(_required(bookId, 'bookId')));
    query.orderBy([
      (t) => OrderingTerm(expression: t.totalProgression.isNull()),
      (t) => OrderingTerm.asc(t.totalProgression),
      (t) => OrderingTerm.asc(t.href),
      (t) => OrderingTerm(expression: t.progression.isNull()),
      (t) => OrderingTerm.asc(t.progression),
      (t) => OrderingTerm.asc(t.createdAt),
      (t) => OrderingTerm.asc(t.id),
    ]);
    return (await query.get())
        .map((row) {
          try {
            return row.toDomain();
          } catch (_) {
            return null;
          }
        })
        .whereType<domain.ReaderAnnotation>()
        .toList();
  }

  @override
  Future<domain.ReaderAnnotation?> getById(String id) async =>
      (await (_database.select(
            _database.readerAnnotations,
          )..where((t) => t.id.equals(_required(id, 'id')))).getSingleOrNull())
          ?.toDomain();
  @override
  Future<domain.ReaderAnnotation?> getByLocation({
    required String bookId,
    required String locationKey,
  }) async =>
      (await (_database.select(_database.readerAnnotations)..where(
                (t) => Expression.and([
                  t.bookId.equals(_required(bookId, 'bookId')),
                  t.locationKey.equals(_required(locationKey, 'locationKey')),
                ]),
              ))
              .getSingleOrNull())
          ?.toDomain();
  @override
  Future<domain.ReaderAnnotation> insert(
    domain.ReaderAnnotation annotation,
  ) async {
    _valid(annotation);
    await _database
        .into(_database.readerAnnotations)
        .insert(annotation.toReaderAnnotationsCompanion());
    return (await getById(annotation.id))!;
  }

  @override
  Future<domain.ReaderAnnotation> updateNote({
    required String id,
    required String? note,
    required DateTime updatedAt,
  }) async {
    final canonicalId = _required(id, 'id');
    final updatedRows =
        await (_database.update(
          _database.readerAnnotations,
        )..where((table) => table.id.equals(canonicalId))).write(
          db.ReaderAnnotationsCompanion(
            note: Value(_normalizeNote(note)),
            updatedAt: Value(updatedAt),
          ),
        );
    if (updatedRows == 0) {
      throw StateError('Reader annotation not found');
    }
    final stored = await getById(canonicalId);
    if (stored == null) {
      throw StateError('Reader annotation not found');
    }
    return stored;
  }

  @override
  Future<domain.ReaderAnnotation> updateStyleAndColor({
    required String id,
    domain.ReaderAnnotationStyle? style,
    domain.ReaderAnnotationColor? color,
    required DateTime updatedAt,
  }) async {
    final canonicalId = _required(id, 'id');
    if (style == null && color == null) {
      throw ArgumentError('Style or color is required');
    }
    final updatedRows =
        await (_database.update(
          _database.readerAnnotations,
        )..where((table) => table.id.equals(canonicalId))).write(
          db.ReaderAnnotationsCompanion(
            style: style == null
                ? const Value.absent()
                : Value(style.storageValue),
            color: color == null
                ? const Value.absent()
                : Value(color.storageValue),
            updatedAt: Value(updatedAt),
          ),
        );
    if (updatedRows == 0) {
      throw StateError('Reader annotation not found');
    }
    final stored = await getById(canonicalId);
    if (stored == null) {
      throw StateError('Reader annotation not found');
    }
    return stored;
  }

  @override
  Future<bool> deleteById(String id) async {
    final deletedRows = await (_database.delete(
      _database.readerAnnotations,
    )..where((table) => table.id.equals(_required(id, 'id')))).go();
    return deletedRows == 1;
  }

  @override
  Future<bool> deleteByLocation({
    required String bookId,
    required String locationKey,
  }) async {
    final deletedRows =
        await (_database.delete(_database.readerAnnotations)..where(
              (table) => Expression.and([
                table.bookId.equals(_required(bookId, 'bookId')),
                table.locationKey.equals(_required(locationKey, 'locationKey')),
              ]),
            ))
            .go();
    return deletedRows == 1;
  }

  @override
  Future<int> deleteAllForBook(String bookId) async => await (_database.delete(
    _database.readerAnnotations,
  )..where((table) => table.bookId.equals(_required(bookId, 'bookId')))).go();

  @override
  Future<domain.ReaderAnnotation> upsert(domain.ReaderAnnotation annotation) =>
      _database.transaction(() async {
        _valid(annotation);
        final existing = await getByLocation(
          bookId: annotation.bookId,
          locationKey: annotation.locationKey,
        );
        if (existing != null) {
          return _updateExistingAnnotation(existing, annotation);
        }

        await beforeUpsertInsert?.call();
        try {
          await _database
              .into(_database.readerAnnotations)
              .insert(annotation.toReaderAnnotationsCompanion());
        } on SqliteException catch (error) {
          if (!_isConstraintViolation(error)) rethrow;
          final canonical = await getByLocation(
            bookId: annotation.bookId,
            locationKey: annotation.locationKey,
          );
          if (canonical == null) rethrow;
          return _updateExistingAnnotation(canonical, annotation);
        }
        return (await getById(annotation.id))!;
      });

  Future<domain.ReaderAnnotation> _updateExistingAnnotation(
    domain.ReaderAnnotation existing,
    domain.ReaderAnnotation incoming,
  ) async {
    await (_database.update(
      _database.readerAnnotations,
    )..where((table) => table.id.equals(existing.id))).write(
      db.ReaderAnnotationsCompanion(
        locatorJson: Value(incoming.locatorJson),
        selectedText: Value(incoming.selectedText),
        textBefore: Value(incoming.textBefore),
        textAfter: Value(incoming.textAfter),
        note: Value(
          _resolveUpsertNote(existing: existing.note, incoming: incoming.note),
        ),
        style: Value(incoming.style.storageValue),
        color: Value(incoming.color.storageValue),
        href: Value(incoming.href),
        progression: Value(incoming.progression),
        totalProgression: Value(incoming.totalProgression),
        updatedAt: Value(incoming.updatedAt),
      ),
    );
    return (await getById(existing.id))!;
  }

  bool _isConstraintViolation(SqliteException error) => error.resultCode == 19;

  void _valid(domain.ReaderAnnotation value) {
    _required(value.id, 'id');
    _required(value.bookId, 'bookId');
    _required(value.locatorJson, 'locatorJson');
    _required(value.locationKey, 'locationKey');
    _required(value.selectedText, 'selectedText');
    _required(value.href, 'href');
    for (final number in [value.progression, value.totalProgression]) {
      if (number != null && (!number.isFinite || number < 0 || number > 1)) {
        throw ArgumentError.value(number, 'progression');
      }
    }
  }

  String? _resolveUpsertNote({
    required String? existing,
    required String? incoming,
  }) {
    if (incoming == null) {
      return existing;
    }
    final trimmed = incoming.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _normalizeNote(String? note) {
    if (note == null) {
      return null;
    }
    final trimmed = note.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

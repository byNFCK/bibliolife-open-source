import 'package:drift/drift.dart';

class CatalogSourcesEntries extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get baseUrl => text().unique()();
  TextColumn get type => text()();
  BoolColumn get isBuiltIn => boolean()();
  BoolColumn get isEnabled => boolean()();
  BoolColumn get supportsSearch => boolean()();
  BoolColumn get supportsNavigation => boolean()();
  BoolColumn get supportsAcquisition => boolean()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get lastSuccessfulAccessAt => dateTime().nullable()();
  DateTimeColumn get lastCheckedAt => dateTime().nullable()();
  TextColumn get health => text().nullable()();
  TextColumn get lastErrorCode => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

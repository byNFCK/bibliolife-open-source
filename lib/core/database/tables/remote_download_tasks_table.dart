import 'package:drift/drift.dart';

class RemoteDownloadTasks extends Table {
  TextColumn get id => text()();
  TextColumn get sourceId => text()();
  TextColumn get publicationRemoteId => text()();
  TextColumn get title => text()();
  TextColumn get authorsJson => text()();
  TextColumn get acquisitionUri => text()();
  TextColumn get declaredMediaType => text().nullable()();
  TextColumn get expectedFinalMediaType => text().nullable()();
  TextColumn get suggestedFilename => text()();
  IntColumn get expectedSizeBytes => integer().nullable()();
  IntColumn get downloadedBytes => integer().withDefault(const Constant(0))();
  IntColumn get totalBytes => integer().nullable()();
  TextColumn get state => text()();
  TextColumn get temporaryFilePath => text().nullable()();
  TextColumn get sha256 => text().nullable()();
  TextColumn get failureCategory => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get importedBookId => text().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  IntColumn get attemptId => integer().withDefault(const Constant(0))();
  TextColumn get remoteMetadataJson => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

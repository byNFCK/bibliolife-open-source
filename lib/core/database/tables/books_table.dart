import 'package:drift/drift.dart';

class Books extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get sortTitle => text().nullable()();
  TextColumn get author => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get filePath => text()();
  TextColumn get originalFilePath => text().nullable()();
  TextColumn get fileName => text()();
  TextColumn get fileExtension => text()();
  TextColumn get mediaType => text().nullable()();
  TextColumn get coverPath => text().nullable()();
  TextColumn get coverProvenance =>
      text().withDefault(const Constant('none'))();
  TextColumn get language => text().nullable()();
  TextColumn get publisher => text().nullable()();
  TextColumn get publishedDate => text().nullable()();
  TextColumn get isbn => text().nullable()();
  IntColumn get pageCount => integer().nullable()();
  IntColumn get fileSizeBytes => integer()();
  DateTimeColumn get dateAdded => dateTime()();
  DateTimeColumn get lastOpenedAt => dateTime().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  TextColumn get authorsJson => text().nullable()();
  TextColumn get contributorsJson => text().nullable()();
  TextColumn get identifiersJson => text().nullable()();
  TextColumn get subjectsJson => text().nullable()();
  TextColumn get rights => text().nullable()();
  TextColumn get seriesName => text().nullable()();
  RealColumn get seriesIndex => real().nullable()();
  TextColumn get edition => text().nullable()();
  TextColumn get source => text().nullable()();
  TextColumn get coverage => text().nullable()();
  TextColumn get type => text().nullable()();
  TextColumn get modifiedDate => text().nullable()();
  TextColumn get catalogSourceId => text().nullable()();
  TextColumn get remotePublicationId => text().nullable()();
  TextColumn get remotePublicationLocation => text().nullable()();
  TextColumn get remoteAcquisitionLocation => text().nullable()();
  TextColumn get metadataOriginsJson => text().nullable()();
  TextColumn get tocJson => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {filePath},
    {originalFilePath},
  ];
}

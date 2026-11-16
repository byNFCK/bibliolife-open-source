// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $BookDisplaySettingsEntriesTable extends BookDisplaySettingsEntries
    with TableInfo<$BookDisplaySettingsEntriesTable, BookDisplaySettingsEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookDisplaySettingsEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _layoutMeta = const VerificationMeta('layout');
  @override
  late final GeneratedColumn<String> layout = GeneratedColumn<String>(
    'layout',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('grid'),
  );
  @override
  List<GeneratedColumn> get $columns => [id, layout];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'book_display_settings_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookDisplaySettingsEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('layout')) {
      context.handle(
        _layoutMeta,
        layout.isAcceptableOrUnknown(data['layout']!, _layoutMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BookDisplaySettingsEntry map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookDisplaySettingsEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      layout: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}layout'],
      )!,
    );
  }

  @override
  $BookDisplaySettingsEntriesTable createAlias(String alias) {
    return $BookDisplaySettingsEntriesTable(attachedDatabase, alias);
  }
}

class BookDisplaySettingsEntry extends DataClass
    implements Insertable<BookDisplaySettingsEntry> {
  final int id;
  final String layout;
  const BookDisplaySettingsEntry({required this.id, required this.layout});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['layout'] = Variable<String>(layout);
    return map;
  }

  BookDisplaySettingsEntriesCompanion toCompanion(bool nullToAbsent) {
    return BookDisplaySettingsEntriesCompanion(
      id: Value(id),
      layout: Value(layout),
    );
  }

  factory BookDisplaySettingsEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookDisplaySettingsEntry(
      id: serializer.fromJson<int>(json['id']),
      layout: serializer.fromJson<String>(json['layout']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'layout': serializer.toJson<String>(layout),
    };
  }

  BookDisplaySettingsEntry copyWith({int? id, String? layout}) =>
      BookDisplaySettingsEntry(
        id: id ?? this.id,
        layout: layout ?? this.layout,
      );
  BookDisplaySettingsEntry copyWithCompanion(
    BookDisplaySettingsEntriesCompanion data,
  ) {
    return BookDisplaySettingsEntry(
      id: data.id.present ? data.id.value : this.id,
      layout: data.layout.present ? data.layout.value : this.layout,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookDisplaySettingsEntry(')
          ..write('id: $id, ')
          ..write('layout: $layout')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, layout);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookDisplaySettingsEntry &&
          other.id == this.id &&
          other.layout == this.layout);
}

class BookDisplaySettingsEntriesCompanion
    extends UpdateCompanion<BookDisplaySettingsEntry> {
  final Value<int> id;
  final Value<String> layout;
  const BookDisplaySettingsEntriesCompanion({
    this.id = const Value.absent(),
    this.layout = const Value.absent(),
  });
  BookDisplaySettingsEntriesCompanion.insert({
    this.id = const Value.absent(),
    this.layout = const Value.absent(),
  });
  static Insertable<BookDisplaySettingsEntry> custom({
    Expression<int>? id,
    Expression<String>? layout,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (layout != null) 'layout': layout,
    });
  }

  BookDisplaySettingsEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? layout,
  }) {
    return BookDisplaySettingsEntriesCompanion(
      id: id ?? this.id,
      layout: layout ?? this.layout,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (layout.present) {
      map['layout'] = Variable<String>(layout.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookDisplaySettingsEntriesCompanion(')
          ..write('id: $id, ')
          ..write('layout: $layout')
          ..write(')'))
        .toString();
  }
}

class $BooksTable extends Books with TableInfo<$BooksTable, Book> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BooksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortTitleMeta = const VerificationMeta(
    'sortTitle',
  );
  @override
  late final GeneratedColumn<String> sortTitle = GeneratedColumn<String>(
    'sort_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
    'author',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originalFilePathMeta = const VerificationMeta(
    'originalFilePath',
  );
  @override
  late final GeneratedColumn<String> originalFilePath = GeneratedColumn<String>(
    'original_file_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileExtensionMeta = const VerificationMeta(
    'fileExtension',
  );
  @override
  late final GeneratedColumn<String> fileExtension = GeneratedColumn<String>(
    'file_extension',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaTypeMeta = const VerificationMeta(
    'mediaType',
  );
  @override
  late final GeneratedColumn<String> mediaType = GeneratedColumn<String>(
    'media_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverPathMeta = const VerificationMeta(
    'coverPath',
  );
  @override
  late final GeneratedColumn<String> coverPath = GeneratedColumn<String>(
    'cover_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverProvenanceMeta = const VerificationMeta(
    'coverProvenance',
  );
  @override
  late final GeneratedColumn<String> coverProvenance = GeneratedColumn<String>(
    'cover_provenance',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('none'),
  );
  static const VerificationMeta _languageMeta = const VerificationMeta(
    'language',
  );
  @override
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _publisherMeta = const VerificationMeta(
    'publisher',
  );
  @override
  late final GeneratedColumn<String> publisher = GeneratedColumn<String>(
    'publisher',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _publishedDateMeta = const VerificationMeta(
    'publishedDate',
  );
  @override
  late final GeneratedColumn<String> publishedDate = GeneratedColumn<String>(
    'published_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isbnMeta = const VerificationMeta('isbn');
  @override
  late final GeneratedColumn<String> isbn = GeneratedColumn<String>(
    'isbn',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pageCountMeta = const VerificationMeta(
    'pageCount',
  );
  @override
  late final GeneratedColumn<int> pageCount = GeneratedColumn<int>(
    'page_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileSizeBytesMeta = const VerificationMeta(
    'fileSizeBytes',
  );
  @override
  late final GeneratedColumn<int> fileSizeBytes = GeneratedColumn<int>(
    'file_size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateAddedMeta = const VerificationMeta(
    'dateAdded',
  );
  @override
  late final GeneratedColumn<DateTime> dateAdded = GeneratedColumn<DateTime>(
    'date_added',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastOpenedAtMeta = const VerificationMeta(
    'lastOpenedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastOpenedAt = GeneratedColumn<DateTime>(
    'last_opened_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isFavoriteMeta = const VerificationMeta(
    'isFavorite',
  );
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
    'is_favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _authorsJsonMeta = const VerificationMeta(
    'authorsJson',
  );
  @override
  late final GeneratedColumn<String> authorsJson = GeneratedColumn<String>(
    'authors_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contributorsJsonMeta = const VerificationMeta(
    'contributorsJson',
  );
  @override
  late final GeneratedColumn<String> contributorsJson = GeneratedColumn<String>(
    'contributors_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _identifiersJsonMeta = const VerificationMeta(
    'identifiersJson',
  );
  @override
  late final GeneratedColumn<String> identifiersJson = GeneratedColumn<String>(
    'identifiers_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _subjectsJsonMeta = const VerificationMeta(
    'subjectsJson',
  );
  @override
  late final GeneratedColumn<String> subjectsJson = GeneratedColumn<String>(
    'subjects_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rightsMeta = const VerificationMeta('rights');
  @override
  late final GeneratedColumn<String> rights = GeneratedColumn<String>(
    'rights',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _seriesNameMeta = const VerificationMeta(
    'seriesName',
  );
  @override
  late final GeneratedColumn<String> seriesName = GeneratedColumn<String>(
    'series_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _seriesIndexMeta = const VerificationMeta(
    'seriesIndex',
  );
  @override
  late final GeneratedColumn<double> seriesIndex = GeneratedColumn<double>(
    'series_index',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _editionMeta = const VerificationMeta(
    'edition',
  );
  @override
  late final GeneratedColumn<String> edition = GeneratedColumn<String>(
    'edition',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverageMeta = const VerificationMeta(
    'coverage',
  );
  @override
  late final GeneratedColumn<String> coverage = GeneratedColumn<String>(
    'coverage',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modifiedDateMeta = const VerificationMeta(
    'modifiedDate',
  );
  @override
  late final GeneratedColumn<String> modifiedDate = GeneratedColumn<String>(
    'modified_date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _catalogSourceIdMeta = const VerificationMeta(
    'catalogSourceId',
  );
  @override
  late final GeneratedColumn<String> catalogSourceId = GeneratedColumn<String>(
    'catalog_source_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _remotePublicationIdMeta =
      const VerificationMeta('remotePublicationId');
  @override
  late final GeneratedColumn<String> remotePublicationId =
      GeneratedColumn<String>(
        'remote_publication_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _remotePublicationLocationMeta =
      const VerificationMeta('remotePublicationLocation');
  @override
  late final GeneratedColumn<String> remotePublicationLocation =
      GeneratedColumn<String>(
        'remote_publication_location',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _remoteAcquisitionLocationMeta =
      const VerificationMeta('remoteAcquisitionLocation');
  @override
  late final GeneratedColumn<String> remoteAcquisitionLocation =
      GeneratedColumn<String>(
        'remote_acquisition_location',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _metadataOriginsJsonMeta =
      const VerificationMeta('metadataOriginsJson');
  @override
  late final GeneratedColumn<String> metadataOriginsJson =
      GeneratedColumn<String>(
        'metadata_origins_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _tocJsonMeta = const VerificationMeta(
    'tocJson',
  );
  @override
  late final GeneratedColumn<String> tocJson = GeneratedColumn<String>(
    'toc_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    sortTitle,
    author,
    description,
    filePath,
    originalFilePath,
    fileName,
    fileExtension,
    mediaType,
    coverPath,
    coverProvenance,
    language,
    publisher,
    publishedDate,
    isbn,
    pageCount,
    fileSizeBytes,
    dateAdded,
    lastOpenedAt,
    isFavorite,
    authorsJson,
    contributorsJson,
    identifiersJson,
    subjectsJson,
    rights,
    seriesName,
    seriesIndex,
    edition,
    source,
    coverage,
    type,
    modifiedDate,
    catalogSourceId,
    remotePublicationId,
    remotePublicationLocation,
    remoteAcquisitionLocation,
    metadataOriginsJson,
    tocJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'books';
  @override
  VerificationContext validateIntegrity(
    Insertable<Book> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('sort_title')) {
      context.handle(
        _sortTitleMeta,
        sortTitle.isAcceptableOrUnknown(data['sort_title']!, _sortTitleMeta),
      );
    }
    if (data.containsKey('author')) {
      context.handle(
        _authorMeta,
        author.isAcceptableOrUnknown(data['author']!, _authorMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('original_file_path')) {
      context.handle(
        _originalFilePathMeta,
        originalFilePath.isAcceptableOrUnknown(
          data['original_file_path']!,
          _originalFilePathMeta,
        ),
      );
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('file_extension')) {
      context.handle(
        _fileExtensionMeta,
        fileExtension.isAcceptableOrUnknown(
          data['file_extension']!,
          _fileExtensionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fileExtensionMeta);
    }
    if (data.containsKey('media_type')) {
      context.handle(
        _mediaTypeMeta,
        mediaType.isAcceptableOrUnknown(data['media_type']!, _mediaTypeMeta),
      );
    }
    if (data.containsKey('cover_path')) {
      context.handle(
        _coverPathMeta,
        coverPath.isAcceptableOrUnknown(data['cover_path']!, _coverPathMeta),
      );
    }
    if (data.containsKey('cover_provenance')) {
      context.handle(
        _coverProvenanceMeta,
        coverProvenance.isAcceptableOrUnknown(
          data['cover_provenance']!,
          _coverProvenanceMeta,
        ),
      );
    }
    if (data.containsKey('language')) {
      context.handle(
        _languageMeta,
        language.isAcceptableOrUnknown(data['language']!, _languageMeta),
      );
    }
    if (data.containsKey('publisher')) {
      context.handle(
        _publisherMeta,
        publisher.isAcceptableOrUnknown(data['publisher']!, _publisherMeta),
      );
    }
    if (data.containsKey('published_date')) {
      context.handle(
        _publishedDateMeta,
        publishedDate.isAcceptableOrUnknown(
          data['published_date']!,
          _publishedDateMeta,
        ),
      );
    }
    if (data.containsKey('isbn')) {
      context.handle(
        _isbnMeta,
        isbn.isAcceptableOrUnknown(data['isbn']!, _isbnMeta),
      );
    }
    if (data.containsKey('page_count')) {
      context.handle(
        _pageCountMeta,
        pageCount.isAcceptableOrUnknown(data['page_count']!, _pageCountMeta),
      );
    }
    if (data.containsKey('file_size_bytes')) {
      context.handle(
        _fileSizeBytesMeta,
        fileSizeBytes.isAcceptableOrUnknown(
          data['file_size_bytes']!,
          _fileSizeBytesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fileSizeBytesMeta);
    }
    if (data.containsKey('date_added')) {
      context.handle(
        _dateAddedMeta,
        dateAdded.isAcceptableOrUnknown(data['date_added']!, _dateAddedMeta),
      );
    } else if (isInserting) {
      context.missing(_dateAddedMeta);
    }
    if (data.containsKey('last_opened_at')) {
      context.handle(
        _lastOpenedAtMeta,
        lastOpenedAt.isAcceptableOrUnknown(
          data['last_opened_at']!,
          _lastOpenedAtMeta,
        ),
      );
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
        _isFavoriteMeta,
        isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta),
      );
    }
    if (data.containsKey('authors_json')) {
      context.handle(
        _authorsJsonMeta,
        authorsJson.isAcceptableOrUnknown(
          data['authors_json']!,
          _authorsJsonMeta,
        ),
      );
    }
    if (data.containsKey('contributors_json')) {
      context.handle(
        _contributorsJsonMeta,
        contributorsJson.isAcceptableOrUnknown(
          data['contributors_json']!,
          _contributorsJsonMeta,
        ),
      );
    }
    if (data.containsKey('identifiers_json')) {
      context.handle(
        _identifiersJsonMeta,
        identifiersJson.isAcceptableOrUnknown(
          data['identifiers_json']!,
          _identifiersJsonMeta,
        ),
      );
    }
    if (data.containsKey('subjects_json')) {
      context.handle(
        _subjectsJsonMeta,
        subjectsJson.isAcceptableOrUnknown(
          data['subjects_json']!,
          _subjectsJsonMeta,
        ),
      );
    }
    if (data.containsKey('rights')) {
      context.handle(
        _rightsMeta,
        rights.isAcceptableOrUnknown(data['rights']!, _rightsMeta),
      );
    }
    if (data.containsKey('series_name')) {
      context.handle(
        _seriesNameMeta,
        seriesName.isAcceptableOrUnknown(data['series_name']!, _seriesNameMeta),
      );
    }
    if (data.containsKey('series_index')) {
      context.handle(
        _seriesIndexMeta,
        seriesIndex.isAcceptableOrUnknown(
          data['series_index']!,
          _seriesIndexMeta,
        ),
      );
    }
    if (data.containsKey('edition')) {
      context.handle(
        _editionMeta,
        edition.isAcceptableOrUnknown(data['edition']!, _editionMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('coverage')) {
      context.handle(
        _coverageMeta,
        coverage.isAcceptableOrUnknown(data['coverage']!, _coverageMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('modified_date')) {
      context.handle(
        _modifiedDateMeta,
        modifiedDate.isAcceptableOrUnknown(
          data['modified_date']!,
          _modifiedDateMeta,
        ),
      );
    }
    if (data.containsKey('catalog_source_id')) {
      context.handle(
        _catalogSourceIdMeta,
        catalogSourceId.isAcceptableOrUnknown(
          data['catalog_source_id']!,
          _catalogSourceIdMeta,
        ),
      );
    }
    if (data.containsKey('remote_publication_id')) {
      context.handle(
        _remotePublicationIdMeta,
        remotePublicationId.isAcceptableOrUnknown(
          data['remote_publication_id']!,
          _remotePublicationIdMeta,
        ),
      );
    }
    if (data.containsKey('remote_publication_location')) {
      context.handle(
        _remotePublicationLocationMeta,
        remotePublicationLocation.isAcceptableOrUnknown(
          data['remote_publication_location']!,
          _remotePublicationLocationMeta,
        ),
      );
    }
    if (data.containsKey('remote_acquisition_location')) {
      context.handle(
        _remoteAcquisitionLocationMeta,
        remoteAcquisitionLocation.isAcceptableOrUnknown(
          data['remote_acquisition_location']!,
          _remoteAcquisitionLocationMeta,
        ),
      );
    }
    if (data.containsKey('metadata_origins_json')) {
      context.handle(
        _metadataOriginsJsonMeta,
        metadataOriginsJson.isAcceptableOrUnknown(
          data['metadata_origins_json']!,
          _metadataOriginsJsonMeta,
        ),
      );
    }
    if (data.containsKey('toc_json')) {
      context.handle(
        _tocJsonMeta,
        tocJson.isAcceptableOrUnknown(data['toc_json']!, _tocJsonMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {filePath},
    {originalFilePath},
  ];
  @override
  Book map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Book(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      sortTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sort_title'],
      ),
      author: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      originalFilePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_file_path'],
      ),
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      fileExtension: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_extension'],
      )!,
      mediaType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_type'],
      ),
      coverPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_path'],
      ),
      coverProvenance: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_provenance'],
      )!,
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      ),
      publisher: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}publisher'],
      ),
      publishedDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}published_date'],
      ),
      isbn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}isbn'],
      ),
      pageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_count'],
      ),
      fileSizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size_bytes'],
      )!,
      dateAdded: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date_added'],
      )!,
      lastOpenedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_opened_at'],
      ),
      isFavorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_favorite'],
      )!,
      authorsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}authors_json'],
      ),
      contributorsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contributors_json'],
      ),
      identifiersJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identifiers_json'],
      ),
      subjectsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subjects_json'],
      ),
      rights: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rights'],
      ),
      seriesName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}series_name'],
      ),
      seriesIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}series_index'],
      ),
      edition: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}edition'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      ),
      coverage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coverage'],
      ),
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      ),
      modifiedDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}modified_date'],
      ),
      catalogSourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}catalog_source_id'],
      ),
      remotePublicationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_publication_id'],
      ),
      remotePublicationLocation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_publication_location'],
      ),
      remoteAcquisitionLocation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_acquisition_location'],
      ),
      metadataOriginsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata_origins_json'],
      ),
      tocJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}toc_json'],
      ),
    );
  }

  @override
  $BooksTable createAlias(String alias) {
    return $BooksTable(attachedDatabase, alias);
  }
}

class Book extends DataClass implements Insertable<Book> {
  final String id;
  final String title;
  final String? sortTitle;
  final String? author;
  final String? description;
  final String filePath;
  final String? originalFilePath;
  final String fileName;
  final String fileExtension;
  final String? mediaType;
  final String? coverPath;
  final String coverProvenance;
  final String? language;
  final String? publisher;
  final String? publishedDate;
  final String? isbn;
  final int? pageCount;
  final int fileSizeBytes;
  final DateTime dateAdded;
  final DateTime? lastOpenedAt;
  final bool isFavorite;
  final String? authorsJson;
  final String? contributorsJson;
  final String? identifiersJson;
  final String? subjectsJson;
  final String? rights;
  final String? seriesName;
  final double? seriesIndex;
  final String? edition;
  final String? source;
  final String? coverage;
  final String? type;
  final String? modifiedDate;
  final String? catalogSourceId;
  final String? remotePublicationId;
  final String? remotePublicationLocation;
  final String? remoteAcquisitionLocation;
  final String? metadataOriginsJson;
  final String? tocJson;
  const Book({
    required this.id,
    required this.title,
    this.sortTitle,
    this.author,
    this.description,
    required this.filePath,
    this.originalFilePath,
    required this.fileName,
    required this.fileExtension,
    this.mediaType,
    this.coverPath,
    required this.coverProvenance,
    this.language,
    this.publisher,
    this.publishedDate,
    this.isbn,
    this.pageCount,
    required this.fileSizeBytes,
    required this.dateAdded,
    this.lastOpenedAt,
    required this.isFavorite,
    this.authorsJson,
    this.contributorsJson,
    this.identifiersJson,
    this.subjectsJson,
    this.rights,
    this.seriesName,
    this.seriesIndex,
    this.edition,
    this.source,
    this.coverage,
    this.type,
    this.modifiedDate,
    this.catalogSourceId,
    this.remotePublicationId,
    this.remotePublicationLocation,
    this.remoteAcquisitionLocation,
    this.metadataOriginsJson,
    this.tocJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || sortTitle != null) {
      map['sort_title'] = Variable<String>(sortTitle);
    }
    if (!nullToAbsent || author != null) {
      map['author'] = Variable<String>(author);
    }
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['file_path'] = Variable<String>(filePath);
    if (!nullToAbsent || originalFilePath != null) {
      map['original_file_path'] = Variable<String>(originalFilePath);
    }
    map['file_name'] = Variable<String>(fileName);
    map['file_extension'] = Variable<String>(fileExtension);
    if (!nullToAbsent || mediaType != null) {
      map['media_type'] = Variable<String>(mediaType);
    }
    if (!nullToAbsent || coverPath != null) {
      map['cover_path'] = Variable<String>(coverPath);
    }
    map['cover_provenance'] = Variable<String>(coverProvenance);
    if (!nullToAbsent || language != null) {
      map['language'] = Variable<String>(language);
    }
    if (!nullToAbsent || publisher != null) {
      map['publisher'] = Variable<String>(publisher);
    }
    if (!nullToAbsent || publishedDate != null) {
      map['published_date'] = Variable<String>(publishedDate);
    }
    if (!nullToAbsent || isbn != null) {
      map['isbn'] = Variable<String>(isbn);
    }
    if (!nullToAbsent || pageCount != null) {
      map['page_count'] = Variable<int>(pageCount);
    }
    map['file_size_bytes'] = Variable<int>(fileSizeBytes);
    map['date_added'] = Variable<DateTime>(dateAdded);
    if (!nullToAbsent || lastOpenedAt != null) {
      map['last_opened_at'] = Variable<DateTime>(lastOpenedAt);
    }
    map['is_favorite'] = Variable<bool>(isFavorite);
    if (!nullToAbsent || authorsJson != null) {
      map['authors_json'] = Variable<String>(authorsJson);
    }
    if (!nullToAbsent || contributorsJson != null) {
      map['contributors_json'] = Variable<String>(contributorsJson);
    }
    if (!nullToAbsent || identifiersJson != null) {
      map['identifiers_json'] = Variable<String>(identifiersJson);
    }
    if (!nullToAbsent || subjectsJson != null) {
      map['subjects_json'] = Variable<String>(subjectsJson);
    }
    if (!nullToAbsent || rights != null) {
      map['rights'] = Variable<String>(rights);
    }
    if (!nullToAbsent || seriesName != null) {
      map['series_name'] = Variable<String>(seriesName);
    }
    if (!nullToAbsent || seriesIndex != null) {
      map['series_index'] = Variable<double>(seriesIndex);
    }
    if (!nullToAbsent || edition != null) {
      map['edition'] = Variable<String>(edition);
    }
    if (!nullToAbsent || source != null) {
      map['source'] = Variable<String>(source);
    }
    if (!nullToAbsent || coverage != null) {
      map['coverage'] = Variable<String>(coverage);
    }
    if (!nullToAbsent || type != null) {
      map['type'] = Variable<String>(type);
    }
    if (!nullToAbsent || modifiedDate != null) {
      map['modified_date'] = Variable<String>(modifiedDate);
    }
    if (!nullToAbsent || catalogSourceId != null) {
      map['catalog_source_id'] = Variable<String>(catalogSourceId);
    }
    if (!nullToAbsent || remotePublicationId != null) {
      map['remote_publication_id'] = Variable<String>(remotePublicationId);
    }
    if (!nullToAbsent || remotePublicationLocation != null) {
      map['remote_publication_location'] = Variable<String>(
        remotePublicationLocation,
      );
    }
    if (!nullToAbsent || remoteAcquisitionLocation != null) {
      map['remote_acquisition_location'] = Variable<String>(
        remoteAcquisitionLocation,
      );
    }
    if (!nullToAbsent || metadataOriginsJson != null) {
      map['metadata_origins_json'] = Variable<String>(metadataOriginsJson);
    }
    if (!nullToAbsent || tocJson != null) {
      map['toc_json'] = Variable<String>(tocJson);
    }
    return map;
  }

  BooksCompanion toCompanion(bool nullToAbsent) {
    return BooksCompanion(
      id: Value(id),
      title: Value(title),
      sortTitle: sortTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(sortTitle),
      author: author == null && nullToAbsent
          ? const Value.absent()
          : Value(author),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      filePath: Value(filePath),
      originalFilePath: originalFilePath == null && nullToAbsent
          ? const Value.absent()
          : Value(originalFilePath),
      fileName: Value(fileName),
      fileExtension: Value(fileExtension),
      mediaType: mediaType == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaType),
      coverPath: coverPath == null && nullToAbsent
          ? const Value.absent()
          : Value(coverPath),
      coverProvenance: Value(coverProvenance),
      language: language == null && nullToAbsent
          ? const Value.absent()
          : Value(language),
      publisher: publisher == null && nullToAbsent
          ? const Value.absent()
          : Value(publisher),
      publishedDate: publishedDate == null && nullToAbsent
          ? const Value.absent()
          : Value(publishedDate),
      isbn: isbn == null && nullToAbsent ? const Value.absent() : Value(isbn),
      pageCount: pageCount == null && nullToAbsent
          ? const Value.absent()
          : Value(pageCount),
      fileSizeBytes: Value(fileSizeBytes),
      dateAdded: Value(dateAdded),
      lastOpenedAt: lastOpenedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastOpenedAt),
      isFavorite: Value(isFavorite),
      authorsJson: authorsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(authorsJson),
      contributorsJson: contributorsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(contributorsJson),
      identifiersJson: identifiersJson == null && nullToAbsent
          ? const Value.absent()
          : Value(identifiersJson),
      subjectsJson: subjectsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(subjectsJson),
      rights: rights == null && nullToAbsent
          ? const Value.absent()
          : Value(rights),
      seriesName: seriesName == null && nullToAbsent
          ? const Value.absent()
          : Value(seriesName),
      seriesIndex: seriesIndex == null && nullToAbsent
          ? const Value.absent()
          : Value(seriesIndex),
      edition: edition == null && nullToAbsent
          ? const Value.absent()
          : Value(edition),
      source: source == null && nullToAbsent
          ? const Value.absent()
          : Value(source),
      coverage: coverage == null && nullToAbsent
          ? const Value.absent()
          : Value(coverage),
      type: type == null && nullToAbsent ? const Value.absent() : Value(type),
      modifiedDate: modifiedDate == null && nullToAbsent
          ? const Value.absent()
          : Value(modifiedDate),
      catalogSourceId: catalogSourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(catalogSourceId),
      remotePublicationId: remotePublicationId == null && nullToAbsent
          ? const Value.absent()
          : Value(remotePublicationId),
      remotePublicationLocation:
          remotePublicationLocation == null && nullToAbsent
          ? const Value.absent()
          : Value(remotePublicationLocation),
      remoteAcquisitionLocation:
          remoteAcquisitionLocation == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteAcquisitionLocation),
      metadataOriginsJson: metadataOriginsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(metadataOriginsJson),
      tocJson: tocJson == null && nullToAbsent
          ? const Value.absent()
          : Value(tocJson),
    );
  }

  factory Book.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Book(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      sortTitle: serializer.fromJson<String?>(json['sortTitle']),
      author: serializer.fromJson<String?>(json['author']),
      description: serializer.fromJson<String?>(json['description']),
      filePath: serializer.fromJson<String>(json['filePath']),
      originalFilePath: serializer.fromJson<String?>(json['originalFilePath']),
      fileName: serializer.fromJson<String>(json['fileName']),
      fileExtension: serializer.fromJson<String>(json['fileExtension']),
      mediaType: serializer.fromJson<String?>(json['mediaType']),
      coverPath: serializer.fromJson<String?>(json['coverPath']),
      coverProvenance: serializer.fromJson<String>(json['coverProvenance']),
      language: serializer.fromJson<String?>(json['language']),
      publisher: serializer.fromJson<String?>(json['publisher']),
      publishedDate: serializer.fromJson<String?>(json['publishedDate']),
      isbn: serializer.fromJson<String?>(json['isbn']),
      pageCount: serializer.fromJson<int?>(json['pageCount']),
      fileSizeBytes: serializer.fromJson<int>(json['fileSizeBytes']),
      dateAdded: serializer.fromJson<DateTime>(json['dateAdded']),
      lastOpenedAt: serializer.fromJson<DateTime?>(json['lastOpenedAt']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      authorsJson: serializer.fromJson<String?>(json['authorsJson']),
      contributorsJson: serializer.fromJson<String?>(json['contributorsJson']),
      identifiersJson: serializer.fromJson<String?>(json['identifiersJson']),
      subjectsJson: serializer.fromJson<String?>(json['subjectsJson']),
      rights: serializer.fromJson<String?>(json['rights']),
      seriesName: serializer.fromJson<String?>(json['seriesName']),
      seriesIndex: serializer.fromJson<double?>(json['seriesIndex']),
      edition: serializer.fromJson<String?>(json['edition']),
      source: serializer.fromJson<String?>(json['source']),
      coverage: serializer.fromJson<String?>(json['coverage']),
      type: serializer.fromJson<String?>(json['type']),
      modifiedDate: serializer.fromJson<String?>(json['modifiedDate']),
      catalogSourceId: serializer.fromJson<String?>(json['catalogSourceId']),
      remotePublicationId: serializer.fromJson<String?>(
        json['remotePublicationId'],
      ),
      remotePublicationLocation: serializer.fromJson<String?>(
        json['remotePublicationLocation'],
      ),
      remoteAcquisitionLocation: serializer.fromJson<String?>(
        json['remoteAcquisitionLocation'],
      ),
      metadataOriginsJson: serializer.fromJson<String?>(
        json['metadataOriginsJson'],
      ),
      tocJson: serializer.fromJson<String?>(json['tocJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'sortTitle': serializer.toJson<String?>(sortTitle),
      'author': serializer.toJson<String?>(author),
      'description': serializer.toJson<String?>(description),
      'filePath': serializer.toJson<String>(filePath),
      'originalFilePath': serializer.toJson<String?>(originalFilePath),
      'fileName': serializer.toJson<String>(fileName),
      'fileExtension': serializer.toJson<String>(fileExtension),
      'mediaType': serializer.toJson<String?>(mediaType),
      'coverPath': serializer.toJson<String?>(coverPath),
      'coverProvenance': serializer.toJson<String>(coverProvenance),
      'language': serializer.toJson<String?>(language),
      'publisher': serializer.toJson<String?>(publisher),
      'publishedDate': serializer.toJson<String?>(publishedDate),
      'isbn': serializer.toJson<String?>(isbn),
      'pageCount': serializer.toJson<int?>(pageCount),
      'fileSizeBytes': serializer.toJson<int>(fileSizeBytes),
      'dateAdded': serializer.toJson<DateTime>(dateAdded),
      'lastOpenedAt': serializer.toJson<DateTime?>(lastOpenedAt),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'authorsJson': serializer.toJson<String?>(authorsJson),
      'contributorsJson': serializer.toJson<String?>(contributorsJson),
      'identifiersJson': serializer.toJson<String?>(identifiersJson),
      'subjectsJson': serializer.toJson<String?>(subjectsJson),
      'rights': serializer.toJson<String?>(rights),
      'seriesName': serializer.toJson<String?>(seriesName),
      'seriesIndex': serializer.toJson<double?>(seriesIndex),
      'edition': serializer.toJson<String?>(edition),
      'source': serializer.toJson<String?>(source),
      'coverage': serializer.toJson<String?>(coverage),
      'type': serializer.toJson<String?>(type),
      'modifiedDate': serializer.toJson<String?>(modifiedDate),
      'catalogSourceId': serializer.toJson<String?>(catalogSourceId),
      'remotePublicationId': serializer.toJson<String?>(remotePublicationId),
      'remotePublicationLocation': serializer.toJson<String?>(
        remotePublicationLocation,
      ),
      'remoteAcquisitionLocation': serializer.toJson<String?>(
        remoteAcquisitionLocation,
      ),
      'metadataOriginsJson': serializer.toJson<String?>(metadataOriginsJson),
      'tocJson': serializer.toJson<String?>(tocJson),
    };
  }

  Book copyWith({
    String? id,
    String? title,
    Value<String?> sortTitle = const Value.absent(),
    Value<String?> author = const Value.absent(),
    Value<String?> description = const Value.absent(),
    String? filePath,
    Value<String?> originalFilePath = const Value.absent(),
    String? fileName,
    String? fileExtension,
    Value<String?> mediaType = const Value.absent(),
    Value<String?> coverPath = const Value.absent(),
    String? coverProvenance,
    Value<String?> language = const Value.absent(),
    Value<String?> publisher = const Value.absent(),
    Value<String?> publishedDate = const Value.absent(),
    Value<String?> isbn = const Value.absent(),
    Value<int?> pageCount = const Value.absent(),
    int? fileSizeBytes,
    DateTime? dateAdded,
    Value<DateTime?> lastOpenedAt = const Value.absent(),
    bool? isFavorite,
    Value<String?> authorsJson = const Value.absent(),
    Value<String?> contributorsJson = const Value.absent(),
    Value<String?> identifiersJson = const Value.absent(),
    Value<String?> subjectsJson = const Value.absent(),
    Value<String?> rights = const Value.absent(),
    Value<String?> seriesName = const Value.absent(),
    Value<double?> seriesIndex = const Value.absent(),
    Value<String?> edition = const Value.absent(),
    Value<String?> source = const Value.absent(),
    Value<String?> coverage = const Value.absent(),
    Value<String?> type = const Value.absent(),
    Value<String?> modifiedDate = const Value.absent(),
    Value<String?> catalogSourceId = const Value.absent(),
    Value<String?> remotePublicationId = const Value.absent(),
    Value<String?> remotePublicationLocation = const Value.absent(),
    Value<String?> remoteAcquisitionLocation = const Value.absent(),
    Value<String?> metadataOriginsJson = const Value.absent(),
    Value<String?> tocJson = const Value.absent(),
  }) => Book(
    id: id ?? this.id,
    title: title ?? this.title,
    sortTitle: sortTitle.present ? sortTitle.value : this.sortTitle,
    author: author.present ? author.value : this.author,
    description: description.present ? description.value : this.description,
    filePath: filePath ?? this.filePath,
    originalFilePath: originalFilePath.present
        ? originalFilePath.value
        : this.originalFilePath,
    fileName: fileName ?? this.fileName,
    fileExtension: fileExtension ?? this.fileExtension,
    mediaType: mediaType.present ? mediaType.value : this.mediaType,
    coverPath: coverPath.present ? coverPath.value : this.coverPath,
    coverProvenance: coverProvenance ?? this.coverProvenance,
    language: language.present ? language.value : this.language,
    publisher: publisher.present ? publisher.value : this.publisher,
    publishedDate: publishedDate.present
        ? publishedDate.value
        : this.publishedDate,
    isbn: isbn.present ? isbn.value : this.isbn,
    pageCount: pageCount.present ? pageCount.value : this.pageCount,
    fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
    dateAdded: dateAdded ?? this.dateAdded,
    lastOpenedAt: lastOpenedAt.present ? lastOpenedAt.value : this.lastOpenedAt,
    isFavorite: isFavorite ?? this.isFavorite,
    authorsJson: authorsJson.present ? authorsJson.value : this.authorsJson,
    contributorsJson: contributorsJson.present
        ? contributorsJson.value
        : this.contributorsJson,
    identifiersJson: identifiersJson.present
        ? identifiersJson.value
        : this.identifiersJson,
    subjectsJson: subjectsJson.present ? subjectsJson.value : this.subjectsJson,
    rights: rights.present ? rights.value : this.rights,
    seriesName: seriesName.present ? seriesName.value : this.seriesName,
    seriesIndex: seriesIndex.present ? seriesIndex.value : this.seriesIndex,
    edition: edition.present ? edition.value : this.edition,
    source: source.present ? source.value : this.source,
    coverage: coverage.present ? coverage.value : this.coverage,
    type: type.present ? type.value : this.type,
    modifiedDate: modifiedDate.present ? modifiedDate.value : this.modifiedDate,
    catalogSourceId: catalogSourceId.present
        ? catalogSourceId.value
        : this.catalogSourceId,
    remotePublicationId: remotePublicationId.present
        ? remotePublicationId.value
        : this.remotePublicationId,
    remotePublicationLocation: remotePublicationLocation.present
        ? remotePublicationLocation.value
        : this.remotePublicationLocation,
    remoteAcquisitionLocation: remoteAcquisitionLocation.present
        ? remoteAcquisitionLocation.value
        : this.remoteAcquisitionLocation,
    metadataOriginsJson: metadataOriginsJson.present
        ? metadataOriginsJson.value
        : this.metadataOriginsJson,
    tocJson: tocJson.present ? tocJson.value : this.tocJson,
  );
  Book copyWithCompanion(BooksCompanion data) {
    return Book(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      sortTitle: data.sortTitle.present ? data.sortTitle.value : this.sortTitle,
      author: data.author.present ? data.author.value : this.author,
      description: data.description.present
          ? data.description.value
          : this.description,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      originalFilePath: data.originalFilePath.present
          ? data.originalFilePath.value
          : this.originalFilePath,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      fileExtension: data.fileExtension.present
          ? data.fileExtension.value
          : this.fileExtension,
      mediaType: data.mediaType.present ? data.mediaType.value : this.mediaType,
      coverPath: data.coverPath.present ? data.coverPath.value : this.coverPath,
      coverProvenance: data.coverProvenance.present
          ? data.coverProvenance.value
          : this.coverProvenance,
      language: data.language.present ? data.language.value : this.language,
      publisher: data.publisher.present ? data.publisher.value : this.publisher,
      publishedDate: data.publishedDate.present
          ? data.publishedDate.value
          : this.publishedDate,
      isbn: data.isbn.present ? data.isbn.value : this.isbn,
      pageCount: data.pageCount.present ? data.pageCount.value : this.pageCount,
      fileSizeBytes: data.fileSizeBytes.present
          ? data.fileSizeBytes.value
          : this.fileSizeBytes,
      dateAdded: data.dateAdded.present ? data.dateAdded.value : this.dateAdded,
      lastOpenedAt: data.lastOpenedAt.present
          ? data.lastOpenedAt.value
          : this.lastOpenedAt,
      isFavorite: data.isFavorite.present
          ? data.isFavorite.value
          : this.isFavorite,
      authorsJson: data.authorsJson.present
          ? data.authorsJson.value
          : this.authorsJson,
      contributorsJson: data.contributorsJson.present
          ? data.contributorsJson.value
          : this.contributorsJson,
      identifiersJson: data.identifiersJson.present
          ? data.identifiersJson.value
          : this.identifiersJson,
      subjectsJson: data.subjectsJson.present
          ? data.subjectsJson.value
          : this.subjectsJson,
      rights: data.rights.present ? data.rights.value : this.rights,
      seriesName: data.seriesName.present
          ? data.seriesName.value
          : this.seriesName,
      seriesIndex: data.seriesIndex.present
          ? data.seriesIndex.value
          : this.seriesIndex,
      edition: data.edition.present ? data.edition.value : this.edition,
      source: data.source.present ? data.source.value : this.source,
      coverage: data.coverage.present ? data.coverage.value : this.coverage,
      type: data.type.present ? data.type.value : this.type,
      modifiedDate: data.modifiedDate.present
          ? data.modifiedDate.value
          : this.modifiedDate,
      catalogSourceId: data.catalogSourceId.present
          ? data.catalogSourceId.value
          : this.catalogSourceId,
      remotePublicationId: data.remotePublicationId.present
          ? data.remotePublicationId.value
          : this.remotePublicationId,
      remotePublicationLocation: data.remotePublicationLocation.present
          ? data.remotePublicationLocation.value
          : this.remotePublicationLocation,
      remoteAcquisitionLocation: data.remoteAcquisitionLocation.present
          ? data.remoteAcquisitionLocation.value
          : this.remoteAcquisitionLocation,
      metadataOriginsJson: data.metadataOriginsJson.present
          ? data.metadataOriginsJson.value
          : this.metadataOriginsJson,
      tocJson: data.tocJson.present ? data.tocJson.value : this.tocJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Book(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('sortTitle: $sortTitle, ')
          ..write('author: $author, ')
          ..write('description: $description, ')
          ..write('filePath: $filePath, ')
          ..write('originalFilePath: $originalFilePath, ')
          ..write('fileName: $fileName, ')
          ..write('fileExtension: $fileExtension, ')
          ..write('mediaType: $mediaType, ')
          ..write('coverPath: $coverPath, ')
          ..write('coverProvenance: $coverProvenance, ')
          ..write('language: $language, ')
          ..write('publisher: $publisher, ')
          ..write('publishedDate: $publishedDate, ')
          ..write('isbn: $isbn, ')
          ..write('pageCount: $pageCount, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('dateAdded: $dateAdded, ')
          ..write('lastOpenedAt: $lastOpenedAt, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('authorsJson: $authorsJson, ')
          ..write('contributorsJson: $contributorsJson, ')
          ..write('identifiersJson: $identifiersJson, ')
          ..write('subjectsJson: $subjectsJson, ')
          ..write('rights: $rights, ')
          ..write('seriesName: $seriesName, ')
          ..write('seriesIndex: $seriesIndex, ')
          ..write('edition: $edition, ')
          ..write('source: $source, ')
          ..write('coverage: $coverage, ')
          ..write('type: $type, ')
          ..write('modifiedDate: $modifiedDate, ')
          ..write('catalogSourceId: $catalogSourceId, ')
          ..write('remotePublicationId: $remotePublicationId, ')
          ..write('remotePublicationLocation: $remotePublicationLocation, ')
          ..write('remoteAcquisitionLocation: $remoteAcquisitionLocation, ')
          ..write('metadataOriginsJson: $metadataOriginsJson, ')
          ..write('tocJson: $tocJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    title,
    sortTitle,
    author,
    description,
    filePath,
    originalFilePath,
    fileName,
    fileExtension,
    mediaType,
    coverPath,
    coverProvenance,
    language,
    publisher,
    publishedDate,
    isbn,
    pageCount,
    fileSizeBytes,
    dateAdded,
    lastOpenedAt,
    isFavorite,
    authorsJson,
    contributorsJson,
    identifiersJson,
    subjectsJson,
    rights,
    seriesName,
    seriesIndex,
    edition,
    source,
    coverage,
    type,
    modifiedDate,
    catalogSourceId,
    remotePublicationId,
    remotePublicationLocation,
    remoteAcquisitionLocation,
    metadataOriginsJson,
    tocJson,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Book &&
          other.id == this.id &&
          other.title == this.title &&
          other.sortTitle == this.sortTitle &&
          other.author == this.author &&
          other.description == this.description &&
          other.filePath == this.filePath &&
          other.originalFilePath == this.originalFilePath &&
          other.fileName == this.fileName &&
          other.fileExtension == this.fileExtension &&
          other.mediaType == this.mediaType &&
          other.coverPath == this.coverPath &&
          other.coverProvenance == this.coverProvenance &&
          other.language == this.language &&
          other.publisher == this.publisher &&
          other.publishedDate == this.publishedDate &&
          other.isbn == this.isbn &&
          other.pageCount == this.pageCount &&
          other.fileSizeBytes == this.fileSizeBytes &&
          other.dateAdded == this.dateAdded &&
          other.lastOpenedAt == this.lastOpenedAt &&
          other.isFavorite == this.isFavorite &&
          other.authorsJson == this.authorsJson &&
          other.contributorsJson == this.contributorsJson &&
          other.identifiersJson == this.identifiersJson &&
          other.subjectsJson == this.subjectsJson &&
          other.rights == this.rights &&
          other.seriesName == this.seriesName &&
          other.seriesIndex == this.seriesIndex &&
          other.edition == this.edition &&
          other.source == this.source &&
          other.coverage == this.coverage &&
          other.type == this.type &&
          other.modifiedDate == this.modifiedDate &&
          other.catalogSourceId == this.catalogSourceId &&
          other.remotePublicationId == this.remotePublicationId &&
          other.remotePublicationLocation == this.remotePublicationLocation &&
          other.remoteAcquisitionLocation == this.remoteAcquisitionLocation &&
          other.metadataOriginsJson == this.metadataOriginsJson &&
          other.tocJson == this.tocJson);
}

class BooksCompanion extends UpdateCompanion<Book> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> sortTitle;
  final Value<String?> author;
  final Value<String?> description;
  final Value<String> filePath;
  final Value<String?> originalFilePath;
  final Value<String> fileName;
  final Value<String> fileExtension;
  final Value<String?> mediaType;
  final Value<String?> coverPath;
  final Value<String> coverProvenance;
  final Value<String?> language;
  final Value<String?> publisher;
  final Value<String?> publishedDate;
  final Value<String?> isbn;
  final Value<int?> pageCount;
  final Value<int> fileSizeBytes;
  final Value<DateTime> dateAdded;
  final Value<DateTime?> lastOpenedAt;
  final Value<bool> isFavorite;
  final Value<String?> authorsJson;
  final Value<String?> contributorsJson;
  final Value<String?> identifiersJson;
  final Value<String?> subjectsJson;
  final Value<String?> rights;
  final Value<String?> seriesName;
  final Value<double?> seriesIndex;
  final Value<String?> edition;
  final Value<String?> source;
  final Value<String?> coverage;
  final Value<String?> type;
  final Value<String?> modifiedDate;
  final Value<String?> catalogSourceId;
  final Value<String?> remotePublicationId;
  final Value<String?> remotePublicationLocation;
  final Value<String?> remoteAcquisitionLocation;
  final Value<String?> metadataOriginsJson;
  final Value<String?> tocJson;
  final Value<int> rowid;
  const BooksCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.sortTitle = const Value.absent(),
    this.author = const Value.absent(),
    this.description = const Value.absent(),
    this.filePath = const Value.absent(),
    this.originalFilePath = const Value.absent(),
    this.fileName = const Value.absent(),
    this.fileExtension = const Value.absent(),
    this.mediaType = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.coverProvenance = const Value.absent(),
    this.language = const Value.absent(),
    this.publisher = const Value.absent(),
    this.publishedDate = const Value.absent(),
    this.isbn = const Value.absent(),
    this.pageCount = const Value.absent(),
    this.fileSizeBytes = const Value.absent(),
    this.dateAdded = const Value.absent(),
    this.lastOpenedAt = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.authorsJson = const Value.absent(),
    this.contributorsJson = const Value.absent(),
    this.identifiersJson = const Value.absent(),
    this.subjectsJson = const Value.absent(),
    this.rights = const Value.absent(),
    this.seriesName = const Value.absent(),
    this.seriesIndex = const Value.absent(),
    this.edition = const Value.absent(),
    this.source = const Value.absent(),
    this.coverage = const Value.absent(),
    this.type = const Value.absent(),
    this.modifiedDate = const Value.absent(),
    this.catalogSourceId = const Value.absent(),
    this.remotePublicationId = const Value.absent(),
    this.remotePublicationLocation = const Value.absent(),
    this.remoteAcquisitionLocation = const Value.absent(),
    this.metadataOriginsJson = const Value.absent(),
    this.tocJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BooksCompanion.insert({
    required String id,
    required String title,
    this.sortTitle = const Value.absent(),
    this.author = const Value.absent(),
    this.description = const Value.absent(),
    required String filePath,
    this.originalFilePath = const Value.absent(),
    required String fileName,
    required String fileExtension,
    this.mediaType = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.coverProvenance = const Value.absent(),
    this.language = const Value.absent(),
    this.publisher = const Value.absent(),
    this.publishedDate = const Value.absent(),
    this.isbn = const Value.absent(),
    this.pageCount = const Value.absent(),
    required int fileSizeBytes,
    required DateTime dateAdded,
    this.lastOpenedAt = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.authorsJson = const Value.absent(),
    this.contributorsJson = const Value.absent(),
    this.identifiersJson = const Value.absent(),
    this.subjectsJson = const Value.absent(),
    this.rights = const Value.absent(),
    this.seriesName = const Value.absent(),
    this.seriesIndex = const Value.absent(),
    this.edition = const Value.absent(),
    this.source = const Value.absent(),
    this.coverage = const Value.absent(),
    this.type = const Value.absent(),
    this.modifiedDate = const Value.absent(),
    this.catalogSourceId = const Value.absent(),
    this.remotePublicationId = const Value.absent(),
    this.remotePublicationLocation = const Value.absent(),
    this.remoteAcquisitionLocation = const Value.absent(),
    this.metadataOriginsJson = const Value.absent(),
    this.tocJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       filePath = Value(filePath),
       fileName = Value(fileName),
       fileExtension = Value(fileExtension),
       fileSizeBytes = Value(fileSizeBytes),
       dateAdded = Value(dateAdded);
  static Insertable<Book> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? sortTitle,
    Expression<String>? author,
    Expression<String>? description,
    Expression<String>? filePath,
    Expression<String>? originalFilePath,
    Expression<String>? fileName,
    Expression<String>? fileExtension,
    Expression<String>? mediaType,
    Expression<String>? coverPath,
    Expression<String>? coverProvenance,
    Expression<String>? language,
    Expression<String>? publisher,
    Expression<String>? publishedDate,
    Expression<String>? isbn,
    Expression<int>? pageCount,
    Expression<int>? fileSizeBytes,
    Expression<DateTime>? dateAdded,
    Expression<DateTime>? lastOpenedAt,
    Expression<bool>? isFavorite,
    Expression<String>? authorsJson,
    Expression<String>? contributorsJson,
    Expression<String>? identifiersJson,
    Expression<String>? subjectsJson,
    Expression<String>? rights,
    Expression<String>? seriesName,
    Expression<double>? seriesIndex,
    Expression<String>? edition,
    Expression<String>? source,
    Expression<String>? coverage,
    Expression<String>? type,
    Expression<String>? modifiedDate,
    Expression<String>? catalogSourceId,
    Expression<String>? remotePublicationId,
    Expression<String>? remotePublicationLocation,
    Expression<String>? remoteAcquisitionLocation,
    Expression<String>? metadataOriginsJson,
    Expression<String>? tocJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (sortTitle != null) 'sort_title': sortTitle,
      if (author != null) 'author': author,
      if (description != null) 'description': description,
      if (filePath != null) 'file_path': filePath,
      if (originalFilePath != null) 'original_file_path': originalFilePath,
      if (fileName != null) 'file_name': fileName,
      if (fileExtension != null) 'file_extension': fileExtension,
      if (mediaType != null) 'media_type': mediaType,
      if (coverPath != null) 'cover_path': coverPath,
      if (coverProvenance != null) 'cover_provenance': coverProvenance,
      if (language != null) 'language': language,
      if (publisher != null) 'publisher': publisher,
      if (publishedDate != null) 'published_date': publishedDate,
      if (isbn != null) 'isbn': isbn,
      if (pageCount != null) 'page_count': pageCount,
      if (fileSizeBytes != null) 'file_size_bytes': fileSizeBytes,
      if (dateAdded != null) 'date_added': dateAdded,
      if (lastOpenedAt != null) 'last_opened_at': lastOpenedAt,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (authorsJson != null) 'authors_json': authorsJson,
      if (contributorsJson != null) 'contributors_json': contributorsJson,
      if (identifiersJson != null) 'identifiers_json': identifiersJson,
      if (subjectsJson != null) 'subjects_json': subjectsJson,
      if (rights != null) 'rights': rights,
      if (seriesName != null) 'series_name': seriesName,
      if (seriesIndex != null) 'series_index': seriesIndex,
      if (edition != null) 'edition': edition,
      if (source != null) 'source': source,
      if (coverage != null) 'coverage': coverage,
      if (type != null) 'type': type,
      if (modifiedDate != null) 'modified_date': modifiedDate,
      if (catalogSourceId != null) 'catalog_source_id': catalogSourceId,
      if (remotePublicationId != null)
        'remote_publication_id': remotePublicationId,
      if (remotePublicationLocation != null)
        'remote_publication_location': remotePublicationLocation,
      if (remoteAcquisitionLocation != null)
        'remote_acquisition_location': remoteAcquisitionLocation,
      if (metadataOriginsJson != null)
        'metadata_origins_json': metadataOriginsJson,
      if (tocJson != null) 'toc_json': tocJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BooksCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String?>? sortTitle,
    Value<String?>? author,
    Value<String?>? description,
    Value<String>? filePath,
    Value<String?>? originalFilePath,
    Value<String>? fileName,
    Value<String>? fileExtension,
    Value<String?>? mediaType,
    Value<String?>? coverPath,
    Value<String>? coverProvenance,
    Value<String?>? language,
    Value<String?>? publisher,
    Value<String?>? publishedDate,
    Value<String?>? isbn,
    Value<int?>? pageCount,
    Value<int>? fileSizeBytes,
    Value<DateTime>? dateAdded,
    Value<DateTime?>? lastOpenedAt,
    Value<bool>? isFavorite,
    Value<String?>? authorsJson,
    Value<String?>? contributorsJson,
    Value<String?>? identifiersJson,
    Value<String?>? subjectsJson,
    Value<String?>? rights,
    Value<String?>? seriesName,
    Value<double?>? seriesIndex,
    Value<String?>? edition,
    Value<String?>? source,
    Value<String?>? coverage,
    Value<String?>? type,
    Value<String?>? modifiedDate,
    Value<String?>? catalogSourceId,
    Value<String?>? remotePublicationId,
    Value<String?>? remotePublicationLocation,
    Value<String?>? remoteAcquisitionLocation,
    Value<String?>? metadataOriginsJson,
    Value<String?>? tocJson,
    Value<int>? rowid,
  }) {
    return BooksCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      sortTitle: sortTitle ?? this.sortTitle,
      author: author ?? this.author,
      description: description ?? this.description,
      filePath: filePath ?? this.filePath,
      originalFilePath: originalFilePath ?? this.originalFilePath,
      fileName: fileName ?? this.fileName,
      fileExtension: fileExtension ?? this.fileExtension,
      mediaType: mediaType ?? this.mediaType,
      coverPath: coverPath ?? this.coverPath,
      coverProvenance: coverProvenance ?? this.coverProvenance,
      language: language ?? this.language,
      publisher: publisher ?? this.publisher,
      publishedDate: publishedDate ?? this.publishedDate,
      isbn: isbn ?? this.isbn,
      pageCount: pageCount ?? this.pageCount,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      dateAdded: dateAdded ?? this.dateAdded,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      authorsJson: authorsJson ?? this.authorsJson,
      contributorsJson: contributorsJson ?? this.contributorsJson,
      identifiersJson: identifiersJson ?? this.identifiersJson,
      subjectsJson: subjectsJson ?? this.subjectsJson,
      rights: rights ?? this.rights,
      seriesName: seriesName ?? this.seriesName,
      seriesIndex: seriesIndex ?? this.seriesIndex,
      edition: edition ?? this.edition,
      source: source ?? this.source,
      coverage: coverage ?? this.coverage,
      type: type ?? this.type,
      modifiedDate: modifiedDate ?? this.modifiedDate,
      catalogSourceId: catalogSourceId ?? this.catalogSourceId,
      remotePublicationId: remotePublicationId ?? this.remotePublicationId,
      remotePublicationLocation:
          remotePublicationLocation ?? this.remotePublicationLocation,
      remoteAcquisitionLocation:
          remoteAcquisitionLocation ?? this.remoteAcquisitionLocation,
      metadataOriginsJson: metadataOriginsJson ?? this.metadataOriginsJson,
      tocJson: tocJson ?? this.tocJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (sortTitle.present) {
      map['sort_title'] = Variable<String>(sortTitle.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (originalFilePath.present) {
      map['original_file_path'] = Variable<String>(originalFilePath.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (fileExtension.present) {
      map['file_extension'] = Variable<String>(fileExtension.value);
    }
    if (mediaType.present) {
      map['media_type'] = Variable<String>(mediaType.value);
    }
    if (coverPath.present) {
      map['cover_path'] = Variable<String>(coverPath.value);
    }
    if (coverProvenance.present) {
      map['cover_provenance'] = Variable<String>(coverProvenance.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (publisher.present) {
      map['publisher'] = Variable<String>(publisher.value);
    }
    if (publishedDate.present) {
      map['published_date'] = Variable<String>(publishedDate.value);
    }
    if (isbn.present) {
      map['isbn'] = Variable<String>(isbn.value);
    }
    if (pageCount.present) {
      map['page_count'] = Variable<int>(pageCount.value);
    }
    if (fileSizeBytes.present) {
      map['file_size_bytes'] = Variable<int>(fileSizeBytes.value);
    }
    if (dateAdded.present) {
      map['date_added'] = Variable<DateTime>(dateAdded.value);
    }
    if (lastOpenedAt.present) {
      map['last_opened_at'] = Variable<DateTime>(lastOpenedAt.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (authorsJson.present) {
      map['authors_json'] = Variable<String>(authorsJson.value);
    }
    if (contributorsJson.present) {
      map['contributors_json'] = Variable<String>(contributorsJson.value);
    }
    if (identifiersJson.present) {
      map['identifiers_json'] = Variable<String>(identifiersJson.value);
    }
    if (subjectsJson.present) {
      map['subjects_json'] = Variable<String>(subjectsJson.value);
    }
    if (rights.present) {
      map['rights'] = Variable<String>(rights.value);
    }
    if (seriesName.present) {
      map['series_name'] = Variable<String>(seriesName.value);
    }
    if (seriesIndex.present) {
      map['series_index'] = Variable<double>(seriesIndex.value);
    }
    if (edition.present) {
      map['edition'] = Variable<String>(edition.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (coverage.present) {
      map['coverage'] = Variable<String>(coverage.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (modifiedDate.present) {
      map['modified_date'] = Variable<String>(modifiedDate.value);
    }
    if (catalogSourceId.present) {
      map['catalog_source_id'] = Variable<String>(catalogSourceId.value);
    }
    if (remotePublicationId.present) {
      map['remote_publication_id'] = Variable<String>(
        remotePublicationId.value,
      );
    }
    if (remotePublicationLocation.present) {
      map['remote_publication_location'] = Variable<String>(
        remotePublicationLocation.value,
      );
    }
    if (remoteAcquisitionLocation.present) {
      map['remote_acquisition_location'] = Variable<String>(
        remoteAcquisitionLocation.value,
      );
    }
    if (metadataOriginsJson.present) {
      map['metadata_origins_json'] = Variable<String>(
        metadataOriginsJson.value,
      );
    }
    if (tocJson.present) {
      map['toc_json'] = Variable<String>(tocJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BooksCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('sortTitle: $sortTitle, ')
          ..write('author: $author, ')
          ..write('description: $description, ')
          ..write('filePath: $filePath, ')
          ..write('originalFilePath: $originalFilePath, ')
          ..write('fileName: $fileName, ')
          ..write('fileExtension: $fileExtension, ')
          ..write('mediaType: $mediaType, ')
          ..write('coverPath: $coverPath, ')
          ..write('coverProvenance: $coverProvenance, ')
          ..write('language: $language, ')
          ..write('publisher: $publisher, ')
          ..write('publishedDate: $publishedDate, ')
          ..write('isbn: $isbn, ')
          ..write('pageCount: $pageCount, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('dateAdded: $dateAdded, ')
          ..write('lastOpenedAt: $lastOpenedAt, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('authorsJson: $authorsJson, ')
          ..write('contributorsJson: $contributorsJson, ')
          ..write('identifiersJson: $identifiersJson, ')
          ..write('subjectsJson: $subjectsJson, ')
          ..write('rights: $rights, ')
          ..write('seriesName: $seriesName, ')
          ..write('seriesIndex: $seriesIndex, ')
          ..write('edition: $edition, ')
          ..write('source: $source, ')
          ..write('coverage: $coverage, ')
          ..write('type: $type, ')
          ..write('modifiedDate: $modifiedDate, ')
          ..write('catalogSourceId: $catalogSourceId, ')
          ..write('remotePublicationId: $remotePublicationId, ')
          ..write('remotePublicationLocation: $remotePublicationLocation, ')
          ..write('remoteAcquisitionLocation: $remoteAcquisitionLocation, ')
          ..write('metadataOriginsJson: $metadataOriginsJson, ')
          ..write('tocJson: $tocJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReadingProgressEntriesTable extends ReadingProgressEntries
    with TableInfo<$ReadingProgressEntriesTable, ReadingProgressEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReadingProgressEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _locatorJsonMeta = const VerificationMeta(
    'locatorJson',
  );
  @override
  late final GeneratedColumn<String> locatorJson = GeneratedColumn<String>(
    'locator_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _progressionMeta = const VerificationMeta(
    'progression',
  );
  @override
  late final GeneratedColumn<double> progression = GeneratedColumn<double>(
    'progression',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _currentChapterTitleMeta =
      const VerificationMeta('currentChapterTitle');
  @override
  late final GeneratedColumn<String> currentChapterTitle =
      GeneratedColumn<String>(
        'current_chapter_title',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _currentPageMeta = const VerificationMeta(
    'currentPage',
  );
  @override
  late final GeneratedColumn<int> currentPage = GeneratedColumn<int>(
    'current_page',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalPagesMeta = const VerificationMeta(
    'totalPages',
  );
  @override
  late final GeneratedColumn<int> totalPages = GeneratedColumn<int>(
    'total_pages',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    bookId,
    locatorJson,
    progression,
    currentChapterTitle,
    currentPage,
    totalPages,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reading_progress_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReadingProgressEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('locator_json')) {
      context.handle(
        _locatorJsonMeta,
        locatorJson.isAcceptableOrUnknown(
          data['locator_json']!,
          _locatorJsonMeta,
        ),
      );
    }
    if (data.containsKey('progression')) {
      context.handle(
        _progressionMeta,
        progression.isAcceptableOrUnknown(
          data['progression']!,
          _progressionMeta,
        ),
      );
    }
    if (data.containsKey('current_chapter_title')) {
      context.handle(
        _currentChapterTitleMeta,
        currentChapterTitle.isAcceptableOrUnknown(
          data['current_chapter_title']!,
          _currentChapterTitleMeta,
        ),
      );
    }
    if (data.containsKey('current_page')) {
      context.handle(
        _currentPageMeta,
        currentPage.isAcceptableOrUnknown(
          data['current_page']!,
          _currentPageMeta,
        ),
      );
    }
    if (data.containsKey('total_pages')) {
      context.handle(
        _totalPagesMeta,
        totalPages.isAcceptableOrUnknown(data['total_pages']!, _totalPagesMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookId};
  @override
  ReadingProgressEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReadingProgressEntry(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      locatorJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}locator_json'],
      ),
      progression: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}progression'],
      )!,
      currentChapterTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_chapter_title'],
      ),
      currentPage: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_page'],
      ),
      totalPages: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_pages'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ReadingProgressEntriesTable createAlias(String alias) {
    return $ReadingProgressEntriesTable(attachedDatabase, alias);
  }
}

class ReadingProgressEntry extends DataClass
    implements Insertable<ReadingProgressEntry> {
  final String bookId;
  final String? locatorJson;
  final double progression;
  final String? currentChapterTitle;
  final int? currentPage;
  final int? totalPages;
  final DateTime updatedAt;
  const ReadingProgressEntry({
    required this.bookId,
    this.locatorJson,
    required this.progression,
    this.currentChapterTitle,
    this.currentPage,
    this.totalPages,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<String>(bookId);
    if (!nullToAbsent || locatorJson != null) {
      map['locator_json'] = Variable<String>(locatorJson);
    }
    map['progression'] = Variable<double>(progression);
    if (!nullToAbsent || currentChapterTitle != null) {
      map['current_chapter_title'] = Variable<String>(currentChapterTitle);
    }
    if (!nullToAbsent || currentPage != null) {
      map['current_page'] = Variable<int>(currentPage);
    }
    if (!nullToAbsent || totalPages != null) {
      map['total_pages'] = Variable<int>(totalPages);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ReadingProgressEntriesCompanion toCompanion(bool nullToAbsent) {
    return ReadingProgressEntriesCompanion(
      bookId: Value(bookId),
      locatorJson: locatorJson == null && nullToAbsent
          ? const Value.absent()
          : Value(locatorJson),
      progression: Value(progression),
      currentChapterTitle: currentChapterTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(currentChapterTitle),
      currentPage: currentPage == null && nullToAbsent
          ? const Value.absent()
          : Value(currentPage),
      totalPages: totalPages == null && nullToAbsent
          ? const Value.absent()
          : Value(totalPages),
      updatedAt: Value(updatedAt),
    );
  }

  factory ReadingProgressEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReadingProgressEntry(
      bookId: serializer.fromJson<String>(json['bookId']),
      locatorJson: serializer.fromJson<String?>(json['locatorJson']),
      progression: serializer.fromJson<double>(json['progression']),
      currentChapterTitle: serializer.fromJson<String?>(
        json['currentChapterTitle'],
      ),
      currentPage: serializer.fromJson<int?>(json['currentPage']),
      totalPages: serializer.fromJson<int?>(json['totalPages']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<String>(bookId),
      'locatorJson': serializer.toJson<String?>(locatorJson),
      'progression': serializer.toJson<double>(progression),
      'currentChapterTitle': serializer.toJson<String?>(currentChapterTitle),
      'currentPage': serializer.toJson<int?>(currentPage),
      'totalPages': serializer.toJson<int?>(totalPages),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ReadingProgressEntry copyWith({
    String? bookId,
    Value<String?> locatorJson = const Value.absent(),
    double? progression,
    Value<String?> currentChapterTitle = const Value.absent(),
    Value<int?> currentPage = const Value.absent(),
    Value<int?> totalPages = const Value.absent(),
    DateTime? updatedAt,
  }) => ReadingProgressEntry(
    bookId: bookId ?? this.bookId,
    locatorJson: locatorJson.present ? locatorJson.value : this.locatorJson,
    progression: progression ?? this.progression,
    currentChapterTitle: currentChapterTitle.present
        ? currentChapterTitle.value
        : this.currentChapterTitle,
    currentPage: currentPage.present ? currentPage.value : this.currentPage,
    totalPages: totalPages.present ? totalPages.value : this.totalPages,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ReadingProgressEntry copyWithCompanion(ReadingProgressEntriesCompanion data) {
    return ReadingProgressEntry(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      locatorJson: data.locatorJson.present
          ? data.locatorJson.value
          : this.locatorJson,
      progression: data.progression.present
          ? data.progression.value
          : this.progression,
      currentChapterTitle: data.currentChapterTitle.present
          ? data.currentChapterTitle.value
          : this.currentChapterTitle,
      currentPage: data.currentPage.present
          ? data.currentPage.value
          : this.currentPage,
      totalPages: data.totalPages.present
          ? data.totalPages.value
          : this.totalPages,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReadingProgressEntry(')
          ..write('bookId: $bookId, ')
          ..write('locatorJson: $locatorJson, ')
          ..write('progression: $progression, ')
          ..write('currentChapterTitle: $currentChapterTitle, ')
          ..write('currentPage: $currentPage, ')
          ..write('totalPages: $totalPages, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    bookId,
    locatorJson,
    progression,
    currentChapterTitle,
    currentPage,
    totalPages,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReadingProgressEntry &&
          other.bookId == this.bookId &&
          other.locatorJson == this.locatorJson &&
          other.progression == this.progression &&
          other.currentChapterTitle == this.currentChapterTitle &&
          other.currentPage == this.currentPage &&
          other.totalPages == this.totalPages &&
          other.updatedAt == this.updatedAt);
}

class ReadingProgressEntriesCompanion
    extends UpdateCompanion<ReadingProgressEntry> {
  final Value<String> bookId;
  final Value<String?> locatorJson;
  final Value<double> progression;
  final Value<String?> currentChapterTitle;
  final Value<int?> currentPage;
  final Value<int?> totalPages;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ReadingProgressEntriesCompanion({
    this.bookId = const Value.absent(),
    this.locatorJson = const Value.absent(),
    this.progression = const Value.absent(),
    this.currentChapterTitle = const Value.absent(),
    this.currentPage = const Value.absent(),
    this.totalPages = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReadingProgressEntriesCompanion.insert({
    required String bookId,
    this.locatorJson = const Value.absent(),
    this.progression = const Value.absent(),
    this.currentChapterTitle = const Value.absent(),
    this.currentPage = const Value.absent(),
    this.totalPages = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : bookId = Value(bookId),
       updatedAt = Value(updatedAt);
  static Insertable<ReadingProgressEntry> custom({
    Expression<String>? bookId,
    Expression<String>? locatorJson,
    Expression<double>? progression,
    Expression<String>? currentChapterTitle,
    Expression<int>? currentPage,
    Expression<int>? totalPages,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (locatorJson != null) 'locator_json': locatorJson,
      if (progression != null) 'progression': progression,
      if (currentChapterTitle != null)
        'current_chapter_title': currentChapterTitle,
      if (currentPage != null) 'current_page': currentPage,
      if (totalPages != null) 'total_pages': totalPages,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReadingProgressEntriesCompanion copyWith({
    Value<String>? bookId,
    Value<String?>? locatorJson,
    Value<double>? progression,
    Value<String?>? currentChapterTitle,
    Value<int?>? currentPage,
    Value<int?>? totalPages,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ReadingProgressEntriesCompanion(
      bookId: bookId ?? this.bookId,
      locatorJson: locatorJson ?? this.locatorJson,
      progression: progression ?? this.progression,
      currentChapterTitle: currentChapterTitle ?? this.currentChapterTitle,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (locatorJson.present) {
      map['locator_json'] = Variable<String>(locatorJson.value);
    }
    if (progression.present) {
      map['progression'] = Variable<double>(progression.value);
    }
    if (currentChapterTitle.present) {
      map['current_chapter_title'] = Variable<String>(
        currentChapterTitle.value,
      );
    }
    if (currentPage.present) {
      map['current_page'] = Variable<int>(currentPage.value);
    }
    if (totalPages.present) {
      map['total_pages'] = Variable<int>(totalPages.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReadingProgressEntriesCompanion(')
          ..write('bookId: $bookId, ')
          ..write('locatorJson: $locatorJson, ')
          ..write('progression: $progression, ')
          ..write('currentChapterTitle: $currentChapterTitle, ')
          ..write('currentPage: $currentPage, ')
          ..write('totalPages: $totalPages, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EpubReaderSettingsEntriesTable extends EpubReaderSettingsEntries
    with TableInfo<$EpubReaderSettingsEntriesTable, EpubReaderSettingsEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EpubReaderSettingsEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _themeMeta = const VerificationMeta('theme');
  @override
  late final GeneratedColumn<String> theme = GeneratedColumn<String>(
    'theme',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fontSizeMeta = const VerificationMeta(
    'fontSize',
  );
  @override
  late final GeneratedColumn<double> fontSize = GeneratedColumn<double>(
    'font_size',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lineHeightMeta = const VerificationMeta(
    'lineHeight',
  );
  @override
  late final GeneratedColumn<double> lineHeight = GeneratedColumn<double>(
    'line_height',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pageMarginsMeta = const VerificationMeta(
    'pageMargins',
  );
  @override
  late final GeneratedColumn<double> pageMargins = GeneratedColumn<double>(
    'page_margins',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _publisherStylesMeta = const VerificationMeta(
    'publisherStyles',
  );
  @override
  late final GeneratedColumn<bool> publisherStyles = GeneratedColumn<bool>(
    'publisher_styles',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("publisher_styles" IN (0, 1))',
    ),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    theme,
    fontSize,
    lineHeight,
    pageMargins,
    publisherStyles,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'epub_reader_settings_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<EpubReaderSettingsEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('theme')) {
      context.handle(
        _themeMeta,
        theme.isAcceptableOrUnknown(data['theme']!, _themeMeta),
      );
    } else if (isInserting) {
      context.missing(_themeMeta);
    }
    if (data.containsKey('font_size')) {
      context.handle(
        _fontSizeMeta,
        fontSize.isAcceptableOrUnknown(data['font_size']!, _fontSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_fontSizeMeta);
    }
    if (data.containsKey('line_height')) {
      context.handle(
        _lineHeightMeta,
        lineHeight.isAcceptableOrUnknown(data['line_height']!, _lineHeightMeta),
      );
    } else if (isInserting) {
      context.missing(_lineHeightMeta);
    }
    if (data.containsKey('page_margins')) {
      context.handle(
        _pageMarginsMeta,
        pageMargins.isAcceptableOrUnknown(
          data['page_margins']!,
          _pageMarginsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_pageMarginsMeta);
    }
    if (data.containsKey('publisher_styles')) {
      context.handle(
        _publisherStylesMeta,
        publisherStyles.isAcceptableOrUnknown(
          data['publisher_styles']!,
          _publisherStylesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_publisherStylesMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EpubReaderSettingsEntry map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EpubReaderSettingsEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      theme: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}theme'],
      )!,
      fontSize: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}font_size'],
      )!,
      lineHeight: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}line_height'],
      )!,
      pageMargins: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}page_margins'],
      )!,
      publisherStyles: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}publisher_styles'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $EpubReaderSettingsEntriesTable createAlias(String alias) {
    return $EpubReaderSettingsEntriesTable(attachedDatabase, alias);
  }
}

class EpubReaderSettingsEntry extends DataClass
    implements Insertable<EpubReaderSettingsEntry> {
  final int id;
  final String theme;
  final double fontSize;
  final double lineHeight;
  final double pageMargins;
  final bool publisherStyles;
  final DateTime updatedAt;
  const EpubReaderSettingsEntry({
    required this.id,
    required this.theme,
    required this.fontSize,
    required this.lineHeight,
    required this.pageMargins,
    required this.publisherStyles,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['theme'] = Variable<String>(theme);
    map['font_size'] = Variable<double>(fontSize);
    map['line_height'] = Variable<double>(lineHeight);
    map['page_margins'] = Variable<double>(pageMargins);
    map['publisher_styles'] = Variable<bool>(publisherStyles);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  EpubReaderSettingsEntriesCompanion toCompanion(bool nullToAbsent) {
    return EpubReaderSettingsEntriesCompanion(
      id: Value(id),
      theme: Value(theme),
      fontSize: Value(fontSize),
      lineHeight: Value(lineHeight),
      pageMargins: Value(pageMargins),
      publisherStyles: Value(publisherStyles),
      updatedAt: Value(updatedAt),
    );
  }

  factory EpubReaderSettingsEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EpubReaderSettingsEntry(
      id: serializer.fromJson<int>(json['id']),
      theme: serializer.fromJson<String>(json['theme']),
      fontSize: serializer.fromJson<double>(json['fontSize']),
      lineHeight: serializer.fromJson<double>(json['lineHeight']),
      pageMargins: serializer.fromJson<double>(json['pageMargins']),
      publisherStyles: serializer.fromJson<bool>(json['publisherStyles']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'theme': serializer.toJson<String>(theme),
      'fontSize': serializer.toJson<double>(fontSize),
      'lineHeight': serializer.toJson<double>(lineHeight),
      'pageMargins': serializer.toJson<double>(pageMargins),
      'publisherStyles': serializer.toJson<bool>(publisherStyles),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  EpubReaderSettingsEntry copyWith({
    int? id,
    String? theme,
    double? fontSize,
    double? lineHeight,
    double? pageMargins,
    bool? publisherStyles,
    DateTime? updatedAt,
  }) => EpubReaderSettingsEntry(
    id: id ?? this.id,
    theme: theme ?? this.theme,
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    pageMargins: pageMargins ?? this.pageMargins,
    publisherStyles: publisherStyles ?? this.publisherStyles,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  EpubReaderSettingsEntry copyWithCompanion(
    EpubReaderSettingsEntriesCompanion data,
  ) {
    return EpubReaderSettingsEntry(
      id: data.id.present ? data.id.value : this.id,
      theme: data.theme.present ? data.theme.value : this.theme,
      fontSize: data.fontSize.present ? data.fontSize.value : this.fontSize,
      lineHeight: data.lineHeight.present
          ? data.lineHeight.value
          : this.lineHeight,
      pageMargins: data.pageMargins.present
          ? data.pageMargins.value
          : this.pageMargins,
      publisherStyles: data.publisherStyles.present
          ? data.publisherStyles.value
          : this.publisherStyles,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EpubReaderSettingsEntry(')
          ..write('id: $id, ')
          ..write('theme: $theme, ')
          ..write('fontSize: $fontSize, ')
          ..write('lineHeight: $lineHeight, ')
          ..write('pageMargins: $pageMargins, ')
          ..write('publisherStyles: $publisherStyles, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    theme,
    fontSize,
    lineHeight,
    pageMargins,
    publisherStyles,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EpubReaderSettingsEntry &&
          other.id == this.id &&
          other.theme == this.theme &&
          other.fontSize == this.fontSize &&
          other.lineHeight == this.lineHeight &&
          other.pageMargins == this.pageMargins &&
          other.publisherStyles == this.publisherStyles &&
          other.updatedAt == this.updatedAt);
}

class EpubReaderSettingsEntriesCompanion
    extends UpdateCompanion<EpubReaderSettingsEntry> {
  final Value<int> id;
  final Value<String> theme;
  final Value<double> fontSize;
  final Value<double> lineHeight;
  final Value<double> pageMargins;
  final Value<bool> publisherStyles;
  final Value<DateTime> updatedAt;
  const EpubReaderSettingsEntriesCompanion({
    this.id = const Value.absent(),
    this.theme = const Value.absent(),
    this.fontSize = const Value.absent(),
    this.lineHeight = const Value.absent(),
    this.pageMargins = const Value.absent(),
    this.publisherStyles = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  EpubReaderSettingsEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String theme,
    required double fontSize,
    required double lineHeight,
    required double pageMargins,
    required bool publisherStyles,
    required DateTime updatedAt,
  }) : theme = Value(theme),
       fontSize = Value(fontSize),
       lineHeight = Value(lineHeight),
       pageMargins = Value(pageMargins),
       publisherStyles = Value(publisherStyles),
       updatedAt = Value(updatedAt);
  static Insertable<EpubReaderSettingsEntry> custom({
    Expression<int>? id,
    Expression<String>? theme,
    Expression<double>? fontSize,
    Expression<double>? lineHeight,
    Expression<double>? pageMargins,
    Expression<bool>? publisherStyles,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (theme != null) 'theme': theme,
      if (fontSize != null) 'font_size': fontSize,
      if (lineHeight != null) 'line_height': lineHeight,
      if (pageMargins != null) 'page_margins': pageMargins,
      if (publisherStyles != null) 'publisher_styles': publisherStyles,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  EpubReaderSettingsEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? theme,
    Value<double>? fontSize,
    Value<double>? lineHeight,
    Value<double>? pageMargins,
    Value<bool>? publisherStyles,
    Value<DateTime>? updatedAt,
  }) {
    return EpubReaderSettingsEntriesCompanion(
      id: id ?? this.id,
      theme: theme ?? this.theme,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      pageMargins: pageMargins ?? this.pageMargins,
      publisherStyles: publisherStyles ?? this.publisherStyles,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (theme.present) {
      map['theme'] = Variable<String>(theme.value);
    }
    if (fontSize.present) {
      map['font_size'] = Variable<double>(fontSize.value);
    }
    if (lineHeight.present) {
      map['line_height'] = Variable<double>(lineHeight.value);
    }
    if (pageMargins.present) {
      map['page_margins'] = Variable<double>(pageMargins.value);
    }
    if (publisherStyles.present) {
      map['publisher_styles'] = Variable<bool>(publisherStyles.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EpubReaderSettingsEntriesCompanion(')
          ..write('id: $id, ')
          ..write('theme: $theme, ')
          ..write('fontSize: $fontSize, ')
          ..write('lineHeight: $lineHeight, ')
          ..write('pageMargins: $pageMargins, ')
          ..write('publisherStyles: $publisherStyles, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $CollectionsTable extends Collections
    with TableInfo<$CollectionsTable, Collection> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CollectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _normalizedNameMeta = const VerificationMeta(
    'normalizedName',
  );
  @override
  late final GeneratedColumn<String> normalizedName = GeneratedColumn<String>(
    'normalized_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _customCoverPathMeta = const VerificationMeta(
    'customCoverPath',
  );
  @override
  late final GeneratedColumn<String> customCoverPath = GeneratedColumn<String>(
    'custom_cover_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    normalizedName,
    description,
    customCoverPath,
    createdAt,
    updatedAt,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'collections';
  @override
  VerificationContext validateIntegrity(
    Insertable<Collection> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('normalized_name')) {
      context.handle(
        _normalizedNameMeta,
        normalizedName.isAcceptableOrUnknown(
          data['normalized_name']!,
          _normalizedNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalizedNameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('custom_cover_path')) {
      context.handle(
        _customCoverPathMeta,
        customCoverPath.isAcceptableOrUnknown(
          data['custom_cover_path']!,
          _customCoverPathMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {normalizedName},
  ];
  @override
  Collection map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Collection(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      normalizedName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalized_name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      customCoverPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}custom_cover_path'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      ),
    );
  }

  @override
  $CollectionsTable createAlias(String alias) {
    return $CollectionsTable(attachedDatabase, alias);
  }
}

class Collection extends DataClass implements Insertable<Collection> {
  final String id;
  final String name;
  final String normalizedName;
  final String? description;
  final String? customCoverPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? sortOrder;
  const Collection({
    required this.id,
    required this.name,
    required this.normalizedName,
    this.description,
    this.customCoverPath,
    required this.createdAt,
    required this.updatedAt,
    this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['normalized_name'] = Variable<String>(normalizedName);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || customCoverPath != null) {
      map['custom_cover_path'] = Variable<String>(customCoverPath);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || sortOrder != null) {
      map['sort_order'] = Variable<int>(sortOrder);
    }
    return map;
  }

  CollectionsCompanion toCompanion(bool nullToAbsent) {
    return CollectionsCompanion(
      id: Value(id),
      name: Value(name),
      normalizedName: Value(normalizedName),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      customCoverPath: customCoverPath == null && nullToAbsent
          ? const Value.absent()
          : Value(customCoverPath),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      sortOrder: sortOrder == null && nullToAbsent
          ? const Value.absent()
          : Value(sortOrder),
    );
  }

  factory Collection.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Collection(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      normalizedName: serializer.fromJson<String>(json['normalizedName']),
      description: serializer.fromJson<String?>(json['description']),
      customCoverPath: serializer.fromJson<String?>(json['customCoverPath']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      sortOrder: serializer.fromJson<int?>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'normalizedName': serializer.toJson<String>(normalizedName),
      'description': serializer.toJson<String?>(description),
      'customCoverPath': serializer.toJson<String?>(customCoverPath),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'sortOrder': serializer.toJson<int?>(sortOrder),
    };
  }

  Collection copyWith({
    String? id,
    String? name,
    String? normalizedName,
    Value<String?> description = const Value.absent(),
    Value<String?> customCoverPath = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<int?> sortOrder = const Value.absent(),
  }) => Collection(
    id: id ?? this.id,
    name: name ?? this.name,
    normalizedName: normalizedName ?? this.normalizedName,
    description: description.present ? description.value : this.description,
    customCoverPath: customCoverPath.present
        ? customCoverPath.value
        : this.customCoverPath,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    sortOrder: sortOrder.present ? sortOrder.value : this.sortOrder,
  );
  Collection copyWithCompanion(CollectionsCompanion data) {
    return Collection(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      normalizedName: data.normalizedName.present
          ? data.normalizedName.value
          : this.normalizedName,
      description: data.description.present
          ? data.description.value
          : this.description,
      customCoverPath: data.customCoverPath.present
          ? data.customCoverPath.value
          : this.customCoverPath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Collection(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('normalizedName: $normalizedName, ')
          ..write('description: $description, ')
          ..write('customCoverPath: $customCoverPath, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    normalizedName,
    description,
    customCoverPath,
    createdAt,
    updatedAt,
    sortOrder,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Collection &&
          other.id == this.id &&
          other.name == this.name &&
          other.normalizedName == this.normalizedName &&
          other.description == this.description &&
          other.customCoverPath == this.customCoverPath &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.sortOrder == this.sortOrder);
}

class CollectionsCompanion extends UpdateCompanion<Collection> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> normalizedName;
  final Value<String?> description;
  final Value<String?> customCoverPath;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int?> sortOrder;
  final Value<int> rowid;
  const CollectionsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.normalizedName = const Value.absent(),
    this.description = const Value.absent(),
    this.customCoverPath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CollectionsCompanion.insert({
    required String id,
    required String name,
    required String normalizedName,
    this.description = const Value.absent(),
    this.customCoverPath = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       normalizedName = Value(normalizedName),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Collection> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? normalizedName,
    Expression<String>? description,
    Expression<String>? customCoverPath,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (normalizedName != null) 'normalized_name': normalizedName,
      if (description != null) 'description': description,
      if (customCoverPath != null) 'custom_cover_path': customCoverPath,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CollectionsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? normalizedName,
    Value<String?>? description,
    Value<String?>? customCoverPath,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int?>? sortOrder,
    Value<int>? rowid,
  }) {
    return CollectionsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      normalizedName: normalizedName ?? this.normalizedName,
      description: description ?? this.description,
      customCoverPath: customCoverPath ?? this.customCoverPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (normalizedName.present) {
      map['normalized_name'] = Variable<String>(normalizedName.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (customCoverPath.present) {
      map['custom_cover_path'] = Variable<String>(customCoverPath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CollectionsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('normalizedName: $normalizedName, ')
          ..write('description: $description, ')
          ..write('customCoverPath: $customCoverPath, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BookCollectionEntriesTable extends BookCollectionEntries
    with TableInfo<$BookCollectionEntriesTable, BookCollectionEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookCollectionEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _collectionIdMeta = const VerificationMeta(
    'collectionId',
  );
  @override
  late final GeneratedColumn<String> collectionId = GeneratedColumn<String>(
    'collection_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES collections (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [bookId, collectionId, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'book_collection_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookCollectionEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('collection_id')) {
      context.handle(
        _collectionIdMeta,
        collectionId.isAcceptableOrUnknown(
          data['collection_id']!,
          _collectionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_collectionIdMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookId, collectionId};
  @override
  BookCollectionEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookCollectionEntry(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      collectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collection_id'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $BookCollectionEntriesTable createAlias(String alias) {
    return $BookCollectionEntriesTable(attachedDatabase, alias);
  }
}

class BookCollectionEntry extends DataClass
    implements Insertable<BookCollectionEntry> {
  final String bookId;
  final String collectionId;
  final DateTime addedAt;
  const BookCollectionEntry({
    required this.bookId,
    required this.collectionId,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<String>(bookId);
    map['collection_id'] = Variable<String>(collectionId);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  BookCollectionEntriesCompanion toCompanion(bool nullToAbsent) {
    return BookCollectionEntriesCompanion(
      bookId: Value(bookId),
      collectionId: Value(collectionId),
      addedAt: Value(addedAt),
    );
  }

  factory BookCollectionEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookCollectionEntry(
      bookId: serializer.fromJson<String>(json['bookId']),
      collectionId: serializer.fromJson<String>(json['collectionId']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<String>(bookId),
      'collectionId': serializer.toJson<String>(collectionId),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  BookCollectionEntry copyWith({
    String? bookId,
    String? collectionId,
    DateTime? addedAt,
  }) => BookCollectionEntry(
    bookId: bookId ?? this.bookId,
    collectionId: collectionId ?? this.collectionId,
    addedAt: addedAt ?? this.addedAt,
  );
  BookCollectionEntry copyWithCompanion(BookCollectionEntriesCompanion data) {
    return BookCollectionEntry(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      collectionId: data.collectionId.present
          ? data.collectionId.value
          : this.collectionId,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookCollectionEntry(')
          ..write('bookId: $bookId, ')
          ..write('collectionId: $collectionId, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(bookId, collectionId, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookCollectionEntry &&
          other.bookId == this.bookId &&
          other.collectionId == this.collectionId &&
          other.addedAt == this.addedAt);
}

class BookCollectionEntriesCompanion
    extends UpdateCompanion<BookCollectionEntry> {
  final Value<String> bookId;
  final Value<String> collectionId;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const BookCollectionEntriesCompanion({
    this.bookId = const Value.absent(),
    this.collectionId = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BookCollectionEntriesCompanion.insert({
    required String bookId,
    required String collectionId,
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  }) : bookId = Value(bookId),
       collectionId = Value(collectionId),
       addedAt = Value(addedAt);
  static Insertable<BookCollectionEntry> custom({
    Expression<String>? bookId,
    Expression<String>? collectionId,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (collectionId != null) 'collection_id': collectionId,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BookCollectionEntriesCompanion copyWith({
    Value<String>? bookId,
    Value<String>? collectionId,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return BookCollectionEntriesCompanion(
      bookId: bookId ?? this.bookId,
      collectionId: collectionId ?? this.collectionId,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (collectionId.present) {
      map['collection_id'] = Variable<String>(collectionId.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookCollectionEntriesCompanion(')
          ..write('bookId: $bookId, ')
          ..write('collectionId: $collectionId, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BookmarksTable extends Bookmarks
    with TableInfo<$BookmarksTable, Bookmark> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookmarksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _locatorJsonMeta = const VerificationMeta(
    'locatorJson',
  );
  @override
  late final GeneratedColumn<String> locatorJson = GeneratedColumn<String>(
    'locator_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hrefMeta = const VerificationMeta('href');
  @override
  late final GeneratedColumn<String> href = GeneratedColumn<String>(
    'href',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _progressionMeta = const VerificationMeta(
    'progression',
  );
  @override
  late final GeneratedColumn<double> progression = GeneratedColumn<double>(
    'progression',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _chapterTitleMeta = const VerificationMeta(
    'chapterTitle',
  );
  @override
  late final GeneratedColumn<String> chapterTitle = GeneratedColumn<String>(
    'chapter_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    locatorJson,
    href,
    progression,
    position,
    chapterTitle,
    title,
    note,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bookmarks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Bookmark> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('locator_json')) {
      context.handle(
        _locatorJsonMeta,
        locatorJson.isAcceptableOrUnknown(
          data['locator_json']!,
          _locatorJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_locatorJsonMeta);
    }
    if (data.containsKey('href')) {
      context.handle(
        _hrefMeta,
        href.isAcceptableOrUnknown(data['href']!, _hrefMeta),
      );
    }
    if (data.containsKey('progression')) {
      context.handle(
        _progressionMeta,
        progression.isAcceptableOrUnknown(
          data['progression']!,
          _progressionMeta,
        ),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('chapter_title')) {
      context.handle(
        _chapterTitleMeta,
        chapterTitle.isAcceptableOrUnknown(
          data['chapter_title']!,
          _chapterTitleMeta,
        ),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Bookmark map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Bookmark(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      locatorJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}locator_json'],
      )!,
      href: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}href'],
      ),
      progression: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}progression'],
      ),
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      ),
      chapterTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_title'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $BookmarksTable createAlias(String alias) {
    return $BookmarksTable(attachedDatabase, alias);
  }
}

class Bookmark extends DataClass implements Insertable<Bookmark> {
  final String id;
  final String bookId;
  final String locatorJson;
  final String? href;
  final double? progression;
  final int? position;
  final String? chapterTitle;
  final String? title;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Bookmark({
    required this.id,
    required this.bookId,
    required this.locatorJson,
    this.href,
    this.progression,
    this.position,
    this.chapterTitle,
    this.title,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['book_id'] = Variable<String>(bookId);
    map['locator_json'] = Variable<String>(locatorJson);
    if (!nullToAbsent || href != null) {
      map['href'] = Variable<String>(href);
    }
    if (!nullToAbsent || progression != null) {
      map['progression'] = Variable<double>(progression);
    }
    if (!nullToAbsent || position != null) {
      map['position'] = Variable<int>(position);
    }
    if (!nullToAbsent || chapterTitle != null) {
      map['chapter_title'] = Variable<String>(chapterTitle);
    }
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  BookmarksCompanion toCompanion(bool nullToAbsent) {
    return BookmarksCompanion(
      id: Value(id),
      bookId: Value(bookId),
      locatorJson: Value(locatorJson),
      href: href == null && nullToAbsent ? const Value.absent() : Value(href),
      progression: progression == null && nullToAbsent
          ? const Value.absent()
          : Value(progression),
      position: position == null && nullToAbsent
          ? const Value.absent()
          : Value(position),
      chapterTitle: chapterTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(chapterTitle),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Bookmark.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Bookmark(
      id: serializer.fromJson<String>(json['id']),
      bookId: serializer.fromJson<String>(json['bookId']),
      locatorJson: serializer.fromJson<String>(json['locatorJson']),
      href: serializer.fromJson<String?>(json['href']),
      progression: serializer.fromJson<double?>(json['progression']),
      position: serializer.fromJson<int?>(json['position']),
      chapterTitle: serializer.fromJson<String?>(json['chapterTitle']),
      title: serializer.fromJson<String?>(json['title']),
      note: serializer.fromJson<String?>(json['note']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'bookId': serializer.toJson<String>(bookId),
      'locatorJson': serializer.toJson<String>(locatorJson),
      'href': serializer.toJson<String?>(href),
      'progression': serializer.toJson<double?>(progression),
      'position': serializer.toJson<int?>(position),
      'chapterTitle': serializer.toJson<String?>(chapterTitle),
      'title': serializer.toJson<String?>(title),
      'note': serializer.toJson<String?>(note),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Bookmark copyWith({
    String? id,
    String? bookId,
    String? locatorJson,
    Value<String?> href = const Value.absent(),
    Value<double?> progression = const Value.absent(),
    Value<int?> position = const Value.absent(),
    Value<String?> chapterTitle = const Value.absent(),
    Value<String?> title = const Value.absent(),
    Value<String?> note = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Bookmark(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    locatorJson: locatorJson ?? this.locatorJson,
    href: href.present ? href.value : this.href,
    progression: progression.present ? progression.value : this.progression,
    position: position.present ? position.value : this.position,
    chapterTitle: chapterTitle.present ? chapterTitle.value : this.chapterTitle,
    title: title.present ? title.value : this.title,
    note: note.present ? note.value : this.note,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Bookmark copyWithCompanion(BookmarksCompanion data) {
    return Bookmark(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      locatorJson: data.locatorJson.present
          ? data.locatorJson.value
          : this.locatorJson,
      href: data.href.present ? data.href.value : this.href,
      progression: data.progression.present
          ? data.progression.value
          : this.progression,
      position: data.position.present ? data.position.value : this.position,
      chapterTitle: data.chapterTitle.present
          ? data.chapterTitle.value
          : this.chapterTitle,
      title: data.title.present ? data.title.value : this.title,
      note: data.note.present ? data.note.value : this.note,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Bookmark(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('locatorJson: $locatorJson, ')
          ..write('href: $href, ')
          ..write('progression: $progression, ')
          ..write('position: $position, ')
          ..write('chapterTitle: $chapterTitle, ')
          ..write('title: $title, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    locatorJson,
    href,
    progression,
    position,
    chapterTitle,
    title,
    note,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Bookmark &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.locatorJson == this.locatorJson &&
          other.href == this.href &&
          other.progression == this.progression &&
          other.position == this.position &&
          other.chapterTitle == this.chapterTitle &&
          other.title == this.title &&
          other.note == this.note &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class BookmarksCompanion extends UpdateCompanion<Bookmark> {
  final Value<String> id;
  final Value<String> bookId;
  final Value<String> locatorJson;
  final Value<String?> href;
  final Value<double?> progression;
  final Value<int?> position;
  final Value<String?> chapterTitle;
  final Value<String?> title;
  final Value<String?> note;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const BookmarksCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.locatorJson = const Value.absent(),
    this.href = const Value.absent(),
    this.progression = const Value.absent(),
    this.position = const Value.absent(),
    this.chapterTitle = const Value.absent(),
    this.title = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BookmarksCompanion.insert({
    required String id,
    required String bookId,
    required String locatorJson,
    this.href = const Value.absent(),
    this.progression = const Value.absent(),
    this.position = const Value.absent(),
    this.chapterTitle = const Value.absent(),
    this.title = const Value.absent(),
    this.note = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       bookId = Value(bookId),
       locatorJson = Value(locatorJson),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Bookmark> custom({
    Expression<String>? id,
    Expression<String>? bookId,
    Expression<String>? locatorJson,
    Expression<String>? href,
    Expression<double>? progression,
    Expression<int>? position,
    Expression<String>? chapterTitle,
    Expression<String>? title,
    Expression<String>? note,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (locatorJson != null) 'locator_json': locatorJson,
      if (href != null) 'href': href,
      if (progression != null) 'progression': progression,
      if (position != null) 'position': position,
      if (chapterTitle != null) 'chapter_title': chapterTitle,
      if (title != null) 'title': title,
      if (note != null) 'note': note,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BookmarksCompanion copyWith({
    Value<String>? id,
    Value<String>? bookId,
    Value<String>? locatorJson,
    Value<String?>? href,
    Value<double?>? progression,
    Value<int?>? position,
    Value<String?>? chapterTitle,
    Value<String?>? title,
    Value<String?>? note,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return BookmarksCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      locatorJson: locatorJson ?? this.locatorJson,
      href: href ?? this.href,
      progression: progression ?? this.progression,
      position: position ?? this.position,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      title: title ?? this.title,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (locatorJson.present) {
      map['locator_json'] = Variable<String>(locatorJson.value);
    }
    if (href.present) {
      map['href'] = Variable<String>(href.value);
    }
    if (progression.present) {
      map['progression'] = Variable<double>(progression.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (chapterTitle.present) {
      map['chapter_title'] = Variable<String>(chapterTitle.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookmarksCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('locatorJson: $locatorJson, ')
          ..write('href: $href, ')
          ..write('progression: $progression, ')
          ..write('position: $position, ')
          ..write('chapterTitle: $chapterTitle, ')
          ..write('title: $title, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReaderAnnotationsTable extends ReaderAnnotations
    with TableInfo<$ReaderAnnotationsTable, ReaderAnnotation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReaderAnnotationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _locatorJsonMeta = const VerificationMeta(
    'locatorJson',
  );
  @override
  late final GeneratedColumn<String> locatorJson = GeneratedColumn<String>(
    'locator_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _locationKeyMeta = const VerificationMeta(
    'locationKey',
  );
  @override
  late final GeneratedColumn<String> locationKey = GeneratedColumn<String>(
    'location_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _selectedTextMeta = const VerificationMeta(
    'selectedText',
  );
  @override
  late final GeneratedColumn<String> selectedText = GeneratedColumn<String>(
    'selected_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _textBeforeMeta = const VerificationMeta(
    'textBefore',
  );
  @override
  late final GeneratedColumn<String> textBefore = GeneratedColumn<String>(
    'text_before',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _textAfterMeta = const VerificationMeta(
    'textAfter',
  );
  @override
  late final GeneratedColumn<String> textAfter = GeneratedColumn<String>(
    'text_after',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _styleMeta = const VerificationMeta('style');
  @override
  late final GeneratedColumn<String> style = GeneratedColumn<String>(
    'style',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('highlight'),
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('yellow'),
  );
  static const VerificationMeta _hrefMeta = const VerificationMeta('href');
  @override
  late final GeneratedColumn<String> href = GeneratedColumn<String>(
    'href',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _progressionMeta = const VerificationMeta(
    'progression',
  );
  @override
  late final GeneratedColumn<double> progression = GeneratedColumn<double>(
    'progression',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalProgressionMeta = const VerificationMeta(
    'totalProgression',
  );
  @override
  late final GeneratedColumn<double> totalProgression = GeneratedColumn<double>(
    'total_progression',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    locatorJson,
    locationKey,
    selectedText,
    textBefore,
    textAfter,
    note,
    style,
    color,
    href,
    progression,
    totalProgression,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reader_annotations';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReaderAnnotation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('locator_json')) {
      context.handle(
        _locatorJsonMeta,
        locatorJson.isAcceptableOrUnknown(
          data['locator_json']!,
          _locatorJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_locatorJsonMeta);
    }
    if (data.containsKey('location_key')) {
      context.handle(
        _locationKeyMeta,
        locationKey.isAcceptableOrUnknown(
          data['location_key']!,
          _locationKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_locationKeyMeta);
    }
    if (data.containsKey('selected_text')) {
      context.handle(
        _selectedTextMeta,
        selectedText.isAcceptableOrUnknown(
          data['selected_text']!,
          _selectedTextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_selectedTextMeta);
    }
    if (data.containsKey('text_before')) {
      context.handle(
        _textBeforeMeta,
        textBefore.isAcceptableOrUnknown(data['text_before']!, _textBeforeMeta),
      );
    }
    if (data.containsKey('text_after')) {
      context.handle(
        _textAfterMeta,
        textAfter.isAcceptableOrUnknown(data['text_after']!, _textAfterMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('style')) {
      context.handle(
        _styleMeta,
        style.isAcceptableOrUnknown(data['style']!, _styleMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('href')) {
      context.handle(
        _hrefMeta,
        href.isAcceptableOrUnknown(data['href']!, _hrefMeta),
      );
    } else if (isInserting) {
      context.missing(_hrefMeta);
    }
    if (data.containsKey('progression')) {
      context.handle(
        _progressionMeta,
        progression.isAcceptableOrUnknown(
          data['progression']!,
          _progressionMeta,
        ),
      );
    }
    if (data.containsKey('total_progression')) {
      context.handle(
        _totalProgressionMeta,
        totalProgression.isAcceptableOrUnknown(
          data['total_progression']!,
          _totalProgressionMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {bookId, locationKey},
  ];
  @override
  ReaderAnnotation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReaderAnnotation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      locatorJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}locator_json'],
      )!,
      locationKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location_key'],
      )!,
      selectedText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}selected_text'],
      )!,
      textBefore: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text_before'],
      ),
      textAfter: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text_after'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      style: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}style'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      )!,
      href: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}href'],
      )!,
      progression: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}progression'],
      ),
      totalProgression: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}total_progression'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ReaderAnnotationsTable createAlias(String alias) {
    return $ReaderAnnotationsTable(attachedDatabase, alias);
  }
}

class ReaderAnnotation extends DataClass
    implements Insertable<ReaderAnnotation> {
  final String id;
  final String bookId;
  final String locatorJson;
  final String locationKey;
  final String selectedText;
  final String? textBefore;
  final String? textAfter;
  final String? note;
  final String style;
  final String color;
  final String href;
  final double? progression;
  final double? totalProgression;
  final DateTime createdAt;
  final DateTime updatedAt;
  const ReaderAnnotation({
    required this.id,
    required this.bookId,
    required this.locatorJson,
    required this.locationKey,
    required this.selectedText,
    this.textBefore,
    this.textAfter,
    this.note,
    required this.style,
    required this.color,
    required this.href,
    this.progression,
    this.totalProgression,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['book_id'] = Variable<String>(bookId);
    map['locator_json'] = Variable<String>(locatorJson);
    map['location_key'] = Variable<String>(locationKey);
    map['selected_text'] = Variable<String>(selectedText);
    if (!nullToAbsent || textBefore != null) {
      map['text_before'] = Variable<String>(textBefore);
    }
    if (!nullToAbsent || textAfter != null) {
      map['text_after'] = Variable<String>(textAfter);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['style'] = Variable<String>(style);
    map['color'] = Variable<String>(color);
    map['href'] = Variable<String>(href);
    if (!nullToAbsent || progression != null) {
      map['progression'] = Variable<double>(progression);
    }
    if (!nullToAbsent || totalProgression != null) {
      map['total_progression'] = Variable<double>(totalProgression);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ReaderAnnotationsCompanion toCompanion(bool nullToAbsent) {
    return ReaderAnnotationsCompanion(
      id: Value(id),
      bookId: Value(bookId),
      locatorJson: Value(locatorJson),
      locationKey: Value(locationKey),
      selectedText: Value(selectedText),
      textBefore: textBefore == null && nullToAbsent
          ? const Value.absent()
          : Value(textBefore),
      textAfter: textAfter == null && nullToAbsent
          ? const Value.absent()
          : Value(textAfter),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      style: Value(style),
      color: Value(color),
      href: Value(href),
      progression: progression == null && nullToAbsent
          ? const Value.absent()
          : Value(progression),
      totalProgression: totalProgression == null && nullToAbsent
          ? const Value.absent()
          : Value(totalProgression),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ReaderAnnotation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReaderAnnotation(
      id: serializer.fromJson<String>(json['id']),
      bookId: serializer.fromJson<String>(json['bookId']),
      locatorJson: serializer.fromJson<String>(json['locatorJson']),
      locationKey: serializer.fromJson<String>(json['locationKey']),
      selectedText: serializer.fromJson<String>(json['selectedText']),
      textBefore: serializer.fromJson<String?>(json['textBefore']),
      textAfter: serializer.fromJson<String?>(json['textAfter']),
      note: serializer.fromJson<String?>(json['note']),
      style: serializer.fromJson<String>(json['style']),
      color: serializer.fromJson<String>(json['color']),
      href: serializer.fromJson<String>(json['href']),
      progression: serializer.fromJson<double?>(json['progression']),
      totalProgression: serializer.fromJson<double?>(json['totalProgression']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'bookId': serializer.toJson<String>(bookId),
      'locatorJson': serializer.toJson<String>(locatorJson),
      'locationKey': serializer.toJson<String>(locationKey),
      'selectedText': serializer.toJson<String>(selectedText),
      'textBefore': serializer.toJson<String?>(textBefore),
      'textAfter': serializer.toJson<String?>(textAfter),
      'note': serializer.toJson<String?>(note),
      'style': serializer.toJson<String>(style),
      'color': serializer.toJson<String>(color),
      'href': serializer.toJson<String>(href),
      'progression': serializer.toJson<double?>(progression),
      'totalProgression': serializer.toJson<double?>(totalProgression),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ReaderAnnotation copyWith({
    String? id,
    String? bookId,
    String? locatorJson,
    String? locationKey,
    String? selectedText,
    Value<String?> textBefore = const Value.absent(),
    Value<String?> textAfter = const Value.absent(),
    Value<String?> note = const Value.absent(),
    String? style,
    String? color,
    String? href,
    Value<double?> progression = const Value.absent(),
    Value<double?> totalProgression = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ReaderAnnotation(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    locatorJson: locatorJson ?? this.locatorJson,
    locationKey: locationKey ?? this.locationKey,
    selectedText: selectedText ?? this.selectedText,
    textBefore: textBefore.present ? textBefore.value : this.textBefore,
    textAfter: textAfter.present ? textAfter.value : this.textAfter,
    note: note.present ? note.value : this.note,
    style: style ?? this.style,
    color: color ?? this.color,
    href: href ?? this.href,
    progression: progression.present ? progression.value : this.progression,
    totalProgression: totalProgression.present
        ? totalProgression.value
        : this.totalProgression,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ReaderAnnotation copyWithCompanion(ReaderAnnotationsCompanion data) {
    return ReaderAnnotation(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      locatorJson: data.locatorJson.present
          ? data.locatorJson.value
          : this.locatorJson,
      locationKey: data.locationKey.present
          ? data.locationKey.value
          : this.locationKey,
      selectedText: data.selectedText.present
          ? data.selectedText.value
          : this.selectedText,
      textBefore: data.textBefore.present
          ? data.textBefore.value
          : this.textBefore,
      textAfter: data.textAfter.present ? data.textAfter.value : this.textAfter,
      note: data.note.present ? data.note.value : this.note,
      style: data.style.present ? data.style.value : this.style,
      color: data.color.present ? data.color.value : this.color,
      href: data.href.present ? data.href.value : this.href,
      progression: data.progression.present
          ? data.progression.value
          : this.progression,
      totalProgression: data.totalProgression.present
          ? data.totalProgression.value
          : this.totalProgression,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReaderAnnotation(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('locatorJson: $locatorJson, ')
          ..write('locationKey: $locationKey, ')
          ..write('selectedText: $selectedText, ')
          ..write('textBefore: $textBefore, ')
          ..write('textAfter: $textAfter, ')
          ..write('note: $note, ')
          ..write('style: $style, ')
          ..write('color: $color, ')
          ..write('href: $href, ')
          ..write('progression: $progression, ')
          ..write('totalProgression: $totalProgression, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    locatorJson,
    locationKey,
    selectedText,
    textBefore,
    textAfter,
    note,
    style,
    color,
    href,
    progression,
    totalProgression,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReaderAnnotation &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.locatorJson == this.locatorJson &&
          other.locationKey == this.locationKey &&
          other.selectedText == this.selectedText &&
          other.textBefore == this.textBefore &&
          other.textAfter == this.textAfter &&
          other.note == this.note &&
          other.style == this.style &&
          other.color == this.color &&
          other.href == this.href &&
          other.progression == this.progression &&
          other.totalProgression == this.totalProgression &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ReaderAnnotationsCompanion extends UpdateCompanion<ReaderAnnotation> {
  final Value<String> id;
  final Value<String> bookId;
  final Value<String> locatorJson;
  final Value<String> locationKey;
  final Value<String> selectedText;
  final Value<String?> textBefore;
  final Value<String?> textAfter;
  final Value<String?> note;
  final Value<String> style;
  final Value<String> color;
  final Value<String> href;
  final Value<double?> progression;
  final Value<double?> totalProgression;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ReaderAnnotationsCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.locatorJson = const Value.absent(),
    this.locationKey = const Value.absent(),
    this.selectedText = const Value.absent(),
    this.textBefore = const Value.absent(),
    this.textAfter = const Value.absent(),
    this.note = const Value.absent(),
    this.style = const Value.absent(),
    this.color = const Value.absent(),
    this.href = const Value.absent(),
    this.progression = const Value.absent(),
    this.totalProgression = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReaderAnnotationsCompanion.insert({
    required String id,
    required String bookId,
    required String locatorJson,
    required String locationKey,
    required String selectedText,
    this.textBefore = const Value.absent(),
    this.textAfter = const Value.absent(),
    this.note = const Value.absent(),
    this.style = const Value.absent(),
    this.color = const Value.absent(),
    required String href,
    this.progression = const Value.absent(),
    this.totalProgression = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       bookId = Value(bookId),
       locatorJson = Value(locatorJson),
       locationKey = Value(locationKey),
       selectedText = Value(selectedText),
       href = Value(href),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ReaderAnnotation> custom({
    Expression<String>? id,
    Expression<String>? bookId,
    Expression<String>? locatorJson,
    Expression<String>? locationKey,
    Expression<String>? selectedText,
    Expression<String>? textBefore,
    Expression<String>? textAfter,
    Expression<String>? note,
    Expression<String>? style,
    Expression<String>? color,
    Expression<String>? href,
    Expression<double>? progression,
    Expression<double>? totalProgression,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (locatorJson != null) 'locator_json': locatorJson,
      if (locationKey != null) 'location_key': locationKey,
      if (selectedText != null) 'selected_text': selectedText,
      if (textBefore != null) 'text_before': textBefore,
      if (textAfter != null) 'text_after': textAfter,
      if (note != null) 'note': note,
      if (style != null) 'style': style,
      if (color != null) 'color': color,
      if (href != null) 'href': href,
      if (progression != null) 'progression': progression,
      if (totalProgression != null) 'total_progression': totalProgression,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReaderAnnotationsCompanion copyWith({
    Value<String>? id,
    Value<String>? bookId,
    Value<String>? locatorJson,
    Value<String>? locationKey,
    Value<String>? selectedText,
    Value<String?>? textBefore,
    Value<String?>? textAfter,
    Value<String?>? note,
    Value<String>? style,
    Value<String>? color,
    Value<String>? href,
    Value<double?>? progression,
    Value<double?>? totalProgression,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ReaderAnnotationsCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      locatorJson: locatorJson ?? this.locatorJson,
      locationKey: locationKey ?? this.locationKey,
      selectedText: selectedText ?? this.selectedText,
      textBefore: textBefore ?? this.textBefore,
      textAfter: textAfter ?? this.textAfter,
      note: note ?? this.note,
      style: style ?? this.style,
      color: color ?? this.color,
      href: href ?? this.href,
      progression: progression ?? this.progression,
      totalProgression: totalProgression ?? this.totalProgression,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (locatorJson.present) {
      map['locator_json'] = Variable<String>(locatorJson.value);
    }
    if (locationKey.present) {
      map['location_key'] = Variable<String>(locationKey.value);
    }
    if (selectedText.present) {
      map['selected_text'] = Variable<String>(selectedText.value);
    }
    if (textBefore.present) {
      map['text_before'] = Variable<String>(textBefore.value);
    }
    if (textAfter.present) {
      map['text_after'] = Variable<String>(textAfter.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (style.present) {
      map['style'] = Variable<String>(style.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (href.present) {
      map['href'] = Variable<String>(href.value);
    }
    if (progression.present) {
      map['progression'] = Variable<double>(progression.value);
    }
    if (totalProgression.present) {
      map['total_progression'] = Variable<double>(totalProgression.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReaderAnnotationsCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('locatorJson: $locatorJson, ')
          ..write('locationKey: $locationKey, ')
          ..write('selectedText: $selectedText, ')
          ..write('textBefore: $textBefore, ')
          ..write('textAfter: $textAfter, ')
          ..write('note: $note, ')
          ..write('style: $style, ')
          ..write('color: $color, ')
          ..write('href: $href, ')
          ..write('progression: $progression, ')
          ..write('totalProgression: $totalProgression, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppConnectivitySettingsEntriesTable
    extends AppConnectivitySettingsEntries
    with
        TableInfo<
          $AppConnectivitySettingsEntriesTable,
          AppConnectivitySettingsEntry
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppConnectivitySettingsEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hasAcknowledgedOnlineMeta =
      const VerificationMeta('hasAcknowledgedOnline');
  @override
  late final GeneratedColumn<bool> hasAcknowledgedOnline =
      GeneratedColumn<bool>(
        'has_acknowledged_online',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("has_acknowledged_online" IN (0, 1))',
        ),
      );
  @override
  List<GeneratedColumn> get $columns => [id, mode, hasAcknowledgedOnline];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_connectivity_settings_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppConnectivitySettingsEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('has_acknowledged_online')) {
      context.handle(
        _hasAcknowledgedOnlineMeta,
        hasAcknowledgedOnline.isAcceptableOrUnknown(
          data['has_acknowledged_online']!,
          _hasAcknowledgedOnlineMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_hasAcknowledgedOnlineMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppConnectivitySettingsEntry map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppConnectivitySettingsEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      hasAcknowledgedOnline: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_acknowledged_online'],
      )!,
    );
  }

  @override
  $AppConnectivitySettingsEntriesTable createAlias(String alias) {
    return $AppConnectivitySettingsEntriesTable(attachedDatabase, alias);
  }
}

class AppConnectivitySettingsEntry extends DataClass
    implements Insertable<AppConnectivitySettingsEntry> {
  final int id;
  final String mode;
  final bool hasAcknowledgedOnline;
  const AppConnectivitySettingsEntry({
    required this.id,
    required this.mode,
    required this.hasAcknowledgedOnline,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['mode'] = Variable<String>(mode);
    map['has_acknowledged_online'] = Variable<bool>(hasAcknowledgedOnline);
    return map;
  }

  AppConnectivitySettingsEntriesCompanion toCompanion(bool nullToAbsent) {
    return AppConnectivitySettingsEntriesCompanion(
      id: Value(id),
      mode: Value(mode),
      hasAcknowledgedOnline: Value(hasAcknowledgedOnline),
    );
  }

  factory AppConnectivitySettingsEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppConnectivitySettingsEntry(
      id: serializer.fromJson<int>(json['id']),
      mode: serializer.fromJson<String>(json['mode']),
      hasAcknowledgedOnline: serializer.fromJson<bool>(
        json['hasAcknowledgedOnline'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'mode': serializer.toJson<String>(mode),
      'hasAcknowledgedOnline': serializer.toJson<bool>(hasAcknowledgedOnline),
    };
  }

  AppConnectivitySettingsEntry copyWith({
    int? id,
    String? mode,
    bool? hasAcknowledgedOnline,
  }) => AppConnectivitySettingsEntry(
    id: id ?? this.id,
    mode: mode ?? this.mode,
    hasAcknowledgedOnline: hasAcknowledgedOnline ?? this.hasAcknowledgedOnline,
  );
  AppConnectivitySettingsEntry copyWithCompanion(
    AppConnectivitySettingsEntriesCompanion data,
  ) {
    return AppConnectivitySettingsEntry(
      id: data.id.present ? data.id.value : this.id,
      mode: data.mode.present ? data.mode.value : this.mode,
      hasAcknowledgedOnline: data.hasAcknowledgedOnline.present
          ? data.hasAcknowledgedOnline.value
          : this.hasAcknowledgedOnline,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppConnectivitySettingsEntry(')
          ..write('id: $id, ')
          ..write('mode: $mode, ')
          ..write('hasAcknowledgedOnline: $hasAcknowledgedOnline')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, mode, hasAcknowledgedOnline);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppConnectivitySettingsEntry &&
          other.id == this.id &&
          other.mode == this.mode &&
          other.hasAcknowledgedOnline == this.hasAcknowledgedOnline);
}

class AppConnectivitySettingsEntriesCompanion
    extends UpdateCompanion<AppConnectivitySettingsEntry> {
  final Value<int> id;
  final Value<String> mode;
  final Value<bool> hasAcknowledgedOnline;
  const AppConnectivitySettingsEntriesCompanion({
    this.id = const Value.absent(),
    this.mode = const Value.absent(),
    this.hasAcknowledgedOnline = const Value.absent(),
  });
  AppConnectivitySettingsEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String mode,
    required bool hasAcknowledgedOnline,
  }) : mode = Value(mode),
       hasAcknowledgedOnline = Value(hasAcknowledgedOnline);
  static Insertable<AppConnectivitySettingsEntry> custom({
    Expression<int>? id,
    Expression<String>? mode,
    Expression<bool>? hasAcknowledgedOnline,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mode != null) 'mode': mode,
      if (hasAcknowledgedOnline != null)
        'has_acknowledged_online': hasAcknowledgedOnline,
    });
  }

  AppConnectivitySettingsEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? mode,
    Value<bool>? hasAcknowledgedOnline,
  }) {
    return AppConnectivitySettingsEntriesCompanion(
      id: id ?? this.id,
      mode: mode ?? this.mode,
      hasAcknowledgedOnline:
          hasAcknowledgedOnline ?? this.hasAcknowledgedOnline,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (hasAcknowledgedOnline.present) {
      map['has_acknowledged_online'] = Variable<bool>(
        hasAcknowledgedOnline.value,
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppConnectivitySettingsEntriesCompanion(')
          ..write('id: $id, ')
          ..write('mode: $mode, ')
          ..write('hasAcknowledgedOnline: $hasAcknowledgedOnline')
          ..write(')'))
        .toString();
  }
}

class $CatalogSourcesEntriesTable extends CatalogSourcesEntries
    with TableInfo<$CatalogSourcesEntriesTable, CatalogSourcesEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CatalogSourcesEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseUrlMeta = const VerificationMeta(
    'baseUrl',
  );
  @override
  late final GeneratedColumn<String> baseUrl = GeneratedColumn<String>(
    'base_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isBuiltInMeta = const VerificationMeta(
    'isBuiltIn',
  );
  @override
  late final GeneratedColumn<bool> isBuiltIn = GeneratedColumn<bool>(
    'is_built_in',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_built_in" IN (0, 1))',
    ),
  );
  static const VerificationMeta _isEnabledMeta = const VerificationMeta(
    'isEnabled',
  );
  @override
  late final GeneratedColumn<bool> isEnabled = GeneratedColumn<bool>(
    'is_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_enabled" IN (0, 1))',
    ),
  );
  static const VerificationMeta _supportsSearchMeta = const VerificationMeta(
    'supportsSearch',
  );
  @override
  late final GeneratedColumn<bool> supportsSearch = GeneratedColumn<bool>(
    'supports_search',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("supports_search" IN (0, 1))',
    ),
  );
  static const VerificationMeta _supportsNavigationMeta =
      const VerificationMeta('supportsNavigation');
  @override
  late final GeneratedColumn<bool> supportsNavigation = GeneratedColumn<bool>(
    'supports_navigation',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("supports_navigation" IN (0, 1))',
    ),
  );
  static const VerificationMeta _supportsAcquisitionMeta =
      const VerificationMeta('supportsAcquisition');
  @override
  late final GeneratedColumn<bool> supportsAcquisition = GeneratedColumn<bool>(
    'supports_acquisition',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("supports_acquisition" IN (0, 1))',
    ),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSuccessfulAccessAtMeta =
      const VerificationMeta('lastSuccessfulAccessAt');
  @override
  late final GeneratedColumn<DateTime> lastSuccessfulAccessAt =
      GeneratedColumn<DateTime>(
        'last_successful_access_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastCheckedAtMeta = const VerificationMeta(
    'lastCheckedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastCheckedAt =
      GeneratedColumn<DateTime>(
        'last_checked_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _healthMeta = const VerificationMeta('health');
  @override
  late final GeneratedColumn<String> health = GeneratedColumn<String>(
    'health',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorCodeMeta = const VerificationMeta(
    'lastErrorCode',
  );
  @override
  late final GeneratedColumn<String> lastErrorCode = GeneratedColumn<String>(
    'last_error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    baseUrl,
    type,
    isBuiltIn,
    isEnabled,
    supportsSearch,
    supportsNavigation,
    supportsAcquisition,
    createdAt,
    updatedAt,
    lastSuccessfulAccessAt,
    lastCheckedAt,
    health,
    lastErrorCode,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'catalog_sources_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<CatalogSourcesEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('base_url')) {
      context.handle(
        _baseUrlMeta,
        baseUrl.isAcceptableOrUnknown(data['base_url']!, _baseUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_baseUrlMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('is_built_in')) {
      context.handle(
        _isBuiltInMeta,
        isBuiltIn.isAcceptableOrUnknown(data['is_built_in']!, _isBuiltInMeta),
      );
    } else if (isInserting) {
      context.missing(_isBuiltInMeta);
    }
    if (data.containsKey('is_enabled')) {
      context.handle(
        _isEnabledMeta,
        isEnabled.isAcceptableOrUnknown(data['is_enabled']!, _isEnabledMeta),
      );
    } else if (isInserting) {
      context.missing(_isEnabledMeta);
    }
    if (data.containsKey('supports_search')) {
      context.handle(
        _supportsSearchMeta,
        supportsSearch.isAcceptableOrUnknown(
          data['supports_search']!,
          _supportsSearchMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_supportsSearchMeta);
    }
    if (data.containsKey('supports_navigation')) {
      context.handle(
        _supportsNavigationMeta,
        supportsNavigation.isAcceptableOrUnknown(
          data['supports_navigation']!,
          _supportsNavigationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_supportsNavigationMeta);
    }
    if (data.containsKey('supports_acquisition')) {
      context.handle(
        _supportsAcquisitionMeta,
        supportsAcquisition.isAcceptableOrUnknown(
          data['supports_acquisition']!,
          _supportsAcquisitionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_supportsAcquisitionMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('last_successful_access_at')) {
      context.handle(
        _lastSuccessfulAccessAtMeta,
        lastSuccessfulAccessAt.isAcceptableOrUnknown(
          data['last_successful_access_at']!,
          _lastSuccessfulAccessAtMeta,
        ),
      );
    }
    if (data.containsKey('last_checked_at')) {
      context.handle(
        _lastCheckedAtMeta,
        lastCheckedAt.isAcceptableOrUnknown(
          data['last_checked_at']!,
          _lastCheckedAtMeta,
        ),
      );
    }
    if (data.containsKey('health')) {
      context.handle(
        _healthMeta,
        health.isAcceptableOrUnknown(data['health']!, _healthMeta),
      );
    }
    if (data.containsKey('last_error_code')) {
      context.handle(
        _lastErrorCodeMeta,
        lastErrorCode.isAcceptableOrUnknown(
          data['last_error_code']!,
          _lastErrorCodeMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CatalogSourcesEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CatalogSourcesEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      baseUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_url'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      isBuiltIn: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_built_in'],
      )!,
      isEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_enabled'],
      )!,
      supportsSearch: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}supports_search'],
      )!,
      supportsNavigation: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}supports_navigation'],
      )!,
      supportsAcquisition: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}supports_acquisition'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      lastSuccessfulAccessAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_successful_access_at'],
      ),
      lastCheckedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_checked_at'],
      ),
      health: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}health'],
      ),
      lastErrorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_code'],
      ),
    );
  }

  @override
  $CatalogSourcesEntriesTable createAlias(String alias) {
    return $CatalogSourcesEntriesTable(attachedDatabase, alias);
  }
}

class CatalogSourcesEntry extends DataClass
    implements Insertable<CatalogSourcesEntry> {
  final String id;
  final String name;
  final String baseUrl;
  final String type;
  final bool isBuiltIn;
  final bool isEnabled;
  final bool supportsSearch;
  final bool supportsNavigation;
  final bool supportsAcquisition;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastSuccessfulAccessAt;
  final DateTime? lastCheckedAt;
  final String? health;
  final String? lastErrorCode;
  const CatalogSourcesEntry({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.type,
    required this.isBuiltIn,
    required this.isEnabled,
    required this.supportsSearch,
    required this.supportsNavigation,
    required this.supportsAcquisition,
    required this.createdAt,
    required this.updatedAt,
    this.lastSuccessfulAccessAt,
    this.lastCheckedAt,
    this.health,
    this.lastErrorCode,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['base_url'] = Variable<String>(baseUrl);
    map['type'] = Variable<String>(type);
    map['is_built_in'] = Variable<bool>(isBuiltIn);
    map['is_enabled'] = Variable<bool>(isEnabled);
    map['supports_search'] = Variable<bool>(supportsSearch);
    map['supports_navigation'] = Variable<bool>(supportsNavigation);
    map['supports_acquisition'] = Variable<bool>(supportsAcquisition);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || lastSuccessfulAccessAt != null) {
      map['last_successful_access_at'] = Variable<DateTime>(
        lastSuccessfulAccessAt,
      );
    }
    if (!nullToAbsent || lastCheckedAt != null) {
      map['last_checked_at'] = Variable<DateTime>(lastCheckedAt);
    }
    if (!nullToAbsent || health != null) {
      map['health'] = Variable<String>(health);
    }
    if (!nullToAbsent || lastErrorCode != null) {
      map['last_error_code'] = Variable<String>(lastErrorCode);
    }
    return map;
  }

  CatalogSourcesEntriesCompanion toCompanion(bool nullToAbsent) {
    return CatalogSourcesEntriesCompanion(
      id: Value(id),
      name: Value(name),
      baseUrl: Value(baseUrl),
      type: Value(type),
      isBuiltIn: Value(isBuiltIn),
      isEnabled: Value(isEnabled),
      supportsSearch: Value(supportsSearch),
      supportsNavigation: Value(supportsNavigation),
      supportsAcquisition: Value(supportsAcquisition),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      lastSuccessfulAccessAt: lastSuccessfulAccessAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSuccessfulAccessAt),
      lastCheckedAt: lastCheckedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCheckedAt),
      health: health == null && nullToAbsent
          ? const Value.absent()
          : Value(health),
      lastErrorCode: lastErrorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorCode),
    );
  }

  factory CatalogSourcesEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CatalogSourcesEntry(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      baseUrl: serializer.fromJson<String>(json['baseUrl']),
      type: serializer.fromJson<String>(json['type']),
      isBuiltIn: serializer.fromJson<bool>(json['isBuiltIn']),
      isEnabled: serializer.fromJson<bool>(json['isEnabled']),
      supportsSearch: serializer.fromJson<bool>(json['supportsSearch']),
      supportsNavigation: serializer.fromJson<bool>(json['supportsNavigation']),
      supportsAcquisition: serializer.fromJson<bool>(
        json['supportsAcquisition'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      lastSuccessfulAccessAt: serializer.fromJson<DateTime?>(
        json['lastSuccessfulAccessAt'],
      ),
      lastCheckedAt: serializer.fromJson<DateTime?>(json['lastCheckedAt']),
      health: serializer.fromJson<String?>(json['health']),
      lastErrorCode: serializer.fromJson<String?>(json['lastErrorCode']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'baseUrl': serializer.toJson<String>(baseUrl),
      'type': serializer.toJson<String>(type),
      'isBuiltIn': serializer.toJson<bool>(isBuiltIn),
      'isEnabled': serializer.toJson<bool>(isEnabled),
      'supportsSearch': serializer.toJson<bool>(supportsSearch),
      'supportsNavigation': serializer.toJson<bool>(supportsNavigation),
      'supportsAcquisition': serializer.toJson<bool>(supportsAcquisition),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'lastSuccessfulAccessAt': serializer.toJson<DateTime?>(
        lastSuccessfulAccessAt,
      ),
      'lastCheckedAt': serializer.toJson<DateTime?>(lastCheckedAt),
      'health': serializer.toJson<String?>(health),
      'lastErrorCode': serializer.toJson<String?>(lastErrorCode),
    };
  }

  CatalogSourcesEntry copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? type,
    bool? isBuiltIn,
    bool? isEnabled,
    bool? supportsSearch,
    bool? supportsNavigation,
    bool? supportsAcquisition,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> lastSuccessfulAccessAt = const Value.absent(),
    Value<DateTime?> lastCheckedAt = const Value.absent(),
    Value<String?> health = const Value.absent(),
    Value<String?> lastErrorCode = const Value.absent(),
  }) => CatalogSourcesEntry(
    id: id ?? this.id,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    type: type ?? this.type,
    isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    isEnabled: isEnabled ?? this.isEnabled,
    supportsSearch: supportsSearch ?? this.supportsSearch,
    supportsNavigation: supportsNavigation ?? this.supportsNavigation,
    supportsAcquisition: supportsAcquisition ?? this.supportsAcquisition,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastSuccessfulAccessAt: lastSuccessfulAccessAt.present
        ? lastSuccessfulAccessAt.value
        : this.lastSuccessfulAccessAt,
    lastCheckedAt: lastCheckedAt.present
        ? lastCheckedAt.value
        : this.lastCheckedAt,
    health: health.present ? health.value : this.health,
    lastErrorCode: lastErrorCode.present
        ? lastErrorCode.value
        : this.lastErrorCode,
  );
  CatalogSourcesEntry copyWithCompanion(CatalogSourcesEntriesCompanion data) {
    return CatalogSourcesEntry(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      baseUrl: data.baseUrl.present ? data.baseUrl.value : this.baseUrl,
      type: data.type.present ? data.type.value : this.type,
      isBuiltIn: data.isBuiltIn.present ? data.isBuiltIn.value : this.isBuiltIn,
      isEnabled: data.isEnabled.present ? data.isEnabled.value : this.isEnabled,
      supportsSearch: data.supportsSearch.present
          ? data.supportsSearch.value
          : this.supportsSearch,
      supportsNavigation: data.supportsNavigation.present
          ? data.supportsNavigation.value
          : this.supportsNavigation,
      supportsAcquisition: data.supportsAcquisition.present
          ? data.supportsAcquisition.value
          : this.supportsAcquisition,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      lastSuccessfulAccessAt: data.lastSuccessfulAccessAt.present
          ? data.lastSuccessfulAccessAt.value
          : this.lastSuccessfulAccessAt,
      lastCheckedAt: data.lastCheckedAt.present
          ? data.lastCheckedAt.value
          : this.lastCheckedAt,
      health: data.health.present ? data.health.value : this.health,
      lastErrorCode: data.lastErrorCode.present
          ? data.lastErrorCode.value
          : this.lastErrorCode,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CatalogSourcesEntry(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('type: $type, ')
          ..write('isBuiltIn: $isBuiltIn, ')
          ..write('isEnabled: $isEnabled, ')
          ..write('supportsSearch: $supportsSearch, ')
          ..write('supportsNavigation: $supportsNavigation, ')
          ..write('supportsAcquisition: $supportsAcquisition, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastSuccessfulAccessAt: $lastSuccessfulAccessAt, ')
          ..write('lastCheckedAt: $lastCheckedAt, ')
          ..write('health: $health, ')
          ..write('lastErrorCode: $lastErrorCode')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    baseUrl,
    type,
    isBuiltIn,
    isEnabled,
    supportsSearch,
    supportsNavigation,
    supportsAcquisition,
    createdAt,
    updatedAt,
    lastSuccessfulAccessAt,
    lastCheckedAt,
    health,
    lastErrorCode,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CatalogSourcesEntry &&
          other.id == this.id &&
          other.name == this.name &&
          other.baseUrl == this.baseUrl &&
          other.type == this.type &&
          other.isBuiltIn == this.isBuiltIn &&
          other.isEnabled == this.isEnabled &&
          other.supportsSearch == this.supportsSearch &&
          other.supportsNavigation == this.supportsNavigation &&
          other.supportsAcquisition == this.supportsAcquisition &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.lastSuccessfulAccessAt == this.lastSuccessfulAccessAt &&
          other.lastCheckedAt == this.lastCheckedAt &&
          other.health == this.health &&
          other.lastErrorCode == this.lastErrorCode);
}

class CatalogSourcesEntriesCompanion
    extends UpdateCompanion<CatalogSourcesEntry> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> baseUrl;
  final Value<String> type;
  final Value<bool> isBuiltIn;
  final Value<bool> isEnabled;
  final Value<bool> supportsSearch;
  final Value<bool> supportsNavigation;
  final Value<bool> supportsAcquisition;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> lastSuccessfulAccessAt;
  final Value<DateTime?> lastCheckedAt;
  final Value<String?> health;
  final Value<String?> lastErrorCode;
  final Value<int> rowid;
  const CatalogSourcesEntriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.baseUrl = const Value.absent(),
    this.type = const Value.absent(),
    this.isBuiltIn = const Value.absent(),
    this.isEnabled = const Value.absent(),
    this.supportsSearch = const Value.absent(),
    this.supportsNavigation = const Value.absent(),
    this.supportsAcquisition = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.lastSuccessfulAccessAt = const Value.absent(),
    this.lastCheckedAt = const Value.absent(),
    this.health = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CatalogSourcesEntriesCompanion.insert({
    required String id,
    required String name,
    required String baseUrl,
    required String type,
    required bool isBuiltIn,
    required bool isEnabled,
    required bool supportsSearch,
    required bool supportsNavigation,
    required bool supportsAcquisition,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.lastSuccessfulAccessAt = const Value.absent(),
    this.lastCheckedAt = const Value.absent(),
    this.health = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       baseUrl = Value(baseUrl),
       type = Value(type),
       isBuiltIn = Value(isBuiltIn),
       isEnabled = Value(isEnabled),
       supportsSearch = Value(supportsSearch),
       supportsNavigation = Value(supportsNavigation),
       supportsAcquisition = Value(supportsAcquisition),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<CatalogSourcesEntry> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? baseUrl,
    Expression<String>? type,
    Expression<bool>? isBuiltIn,
    Expression<bool>? isEnabled,
    Expression<bool>? supportsSearch,
    Expression<bool>? supportsNavigation,
    Expression<bool>? supportsAcquisition,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? lastSuccessfulAccessAt,
    Expression<DateTime>? lastCheckedAt,
    Expression<String>? health,
    Expression<String>? lastErrorCode,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (baseUrl != null) 'base_url': baseUrl,
      if (type != null) 'type': type,
      if (isBuiltIn != null) 'is_built_in': isBuiltIn,
      if (isEnabled != null) 'is_enabled': isEnabled,
      if (supportsSearch != null) 'supports_search': supportsSearch,
      if (supportsNavigation != null) 'supports_navigation': supportsNavigation,
      if (supportsAcquisition != null)
        'supports_acquisition': supportsAcquisition,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (lastSuccessfulAccessAt != null)
        'last_successful_access_at': lastSuccessfulAccessAt,
      if (lastCheckedAt != null) 'last_checked_at': lastCheckedAt,
      if (health != null) 'health': health,
      if (lastErrorCode != null) 'last_error_code': lastErrorCode,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CatalogSourcesEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? baseUrl,
    Value<String>? type,
    Value<bool>? isBuiltIn,
    Value<bool>? isEnabled,
    Value<bool>? supportsSearch,
    Value<bool>? supportsNavigation,
    Value<bool>? supportsAcquisition,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? lastSuccessfulAccessAt,
    Value<DateTime?>? lastCheckedAt,
    Value<String?>? health,
    Value<String?>? lastErrorCode,
    Value<int>? rowid,
  }) {
    return CatalogSourcesEntriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      type: type ?? this.type,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      isEnabled: isEnabled ?? this.isEnabled,
      supportsSearch: supportsSearch ?? this.supportsSearch,
      supportsNavigation: supportsNavigation ?? this.supportsNavigation,
      supportsAcquisition: supportsAcquisition ?? this.supportsAcquisition,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastSuccessfulAccessAt:
          lastSuccessfulAccessAt ?? this.lastSuccessfulAccessAt,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      health: health ?? this.health,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (baseUrl.present) {
      map['base_url'] = Variable<String>(baseUrl.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (isBuiltIn.present) {
      map['is_built_in'] = Variable<bool>(isBuiltIn.value);
    }
    if (isEnabled.present) {
      map['is_enabled'] = Variable<bool>(isEnabled.value);
    }
    if (supportsSearch.present) {
      map['supports_search'] = Variable<bool>(supportsSearch.value);
    }
    if (supportsNavigation.present) {
      map['supports_navigation'] = Variable<bool>(supportsNavigation.value);
    }
    if (supportsAcquisition.present) {
      map['supports_acquisition'] = Variable<bool>(supportsAcquisition.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (lastSuccessfulAccessAt.present) {
      map['last_successful_access_at'] = Variable<DateTime>(
        lastSuccessfulAccessAt.value,
      );
    }
    if (lastCheckedAt.present) {
      map['last_checked_at'] = Variable<DateTime>(lastCheckedAt.value);
    }
    if (health.present) {
      map['health'] = Variable<String>(health.value);
    }
    if (lastErrorCode.present) {
      map['last_error_code'] = Variable<String>(lastErrorCode.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CatalogSourcesEntriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('type: $type, ')
          ..write('isBuiltIn: $isBuiltIn, ')
          ..write('isEnabled: $isEnabled, ')
          ..write('supportsSearch: $supportsSearch, ')
          ..write('supportsNavigation: $supportsNavigation, ')
          ..write('supportsAcquisition: $supportsAcquisition, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastSuccessfulAccessAt: $lastSuccessfulAccessAt, ')
          ..write('lastCheckedAt: $lastCheckedAt, ')
          ..write('health: $health, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RemoteDownloadTasksTable extends RemoteDownloadTasks
    with TableInfo<$RemoteDownloadTasksTable, RemoteDownloadTask> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RemoteDownloadTasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _publicationRemoteIdMeta =
      const VerificationMeta('publicationRemoteId');
  @override
  late final GeneratedColumn<String> publicationRemoteId =
      GeneratedColumn<String>(
        'publication_remote_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorsJsonMeta = const VerificationMeta(
    'authorsJson',
  );
  @override
  late final GeneratedColumn<String> authorsJson = GeneratedColumn<String>(
    'authors_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _acquisitionUriMeta = const VerificationMeta(
    'acquisitionUri',
  );
  @override
  late final GeneratedColumn<String> acquisitionUri = GeneratedColumn<String>(
    'acquisition_uri',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _declaredMediaTypeMeta = const VerificationMeta(
    'declaredMediaType',
  );
  @override
  late final GeneratedColumn<String> declaredMediaType =
      GeneratedColumn<String>(
        'declared_media_type',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _expectedFinalMediaTypeMeta =
      const VerificationMeta('expectedFinalMediaType');
  @override
  late final GeneratedColumn<String> expectedFinalMediaType =
      GeneratedColumn<String>(
        'expected_final_media_type',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _suggestedFilenameMeta = const VerificationMeta(
    'suggestedFilename',
  );
  @override
  late final GeneratedColumn<String> suggestedFilename =
      GeneratedColumn<String>(
        'suggested_filename',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _expectedSizeBytesMeta = const VerificationMeta(
    'expectedSizeBytes',
  );
  @override
  late final GeneratedColumn<int> expectedSizeBytes = GeneratedColumn<int>(
    'expected_size_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _downloadedBytesMeta = const VerificationMeta(
    'downloadedBytes',
  );
  @override
  late final GeneratedColumn<int> downloadedBytes = GeneratedColumn<int>(
    'downloaded_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalBytesMeta = const VerificationMeta(
    'totalBytes',
  );
  @override
  late final GeneratedColumn<int> totalBytes = GeneratedColumn<int>(
    'total_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _temporaryFilePathMeta = const VerificationMeta(
    'temporaryFilePath',
  );
  @override
  late final GeneratedColumn<String> temporaryFilePath =
      GeneratedColumn<String>(
        'temporary_file_path',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _failureCategoryMeta = const VerificationMeta(
    'failureCategory',
  );
  @override
  late final GeneratedColumn<String> failureCategory = GeneratedColumn<String>(
    'failure_category',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _importedBookIdMeta = const VerificationMeta(
    'importedBookId',
  );
  @override
  late final GeneratedColumn<String> importedBookId = GeneratedColumn<String>(
    'imported_book_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _attemptIdMeta = const VerificationMeta(
    'attemptId',
  );
  @override
  late final GeneratedColumn<int> attemptId = GeneratedColumn<int>(
    'attempt_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _remoteMetadataJsonMeta =
      const VerificationMeta('remoteMetadataJson');
  @override
  late final GeneratedColumn<String> remoteMetadataJson =
      GeneratedColumn<String>(
        'remote_metadata_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sourceId,
    publicationRemoteId,
    title,
    authorsJson,
    acquisitionUri,
    declaredMediaType,
    expectedFinalMediaType,
    suggestedFilename,
    expectedSizeBytes,
    downloadedBytes,
    totalBytes,
    state,
    temporaryFilePath,
    sha256,
    failureCategory,
    createdAt,
    updatedAt,
    startedAt,
    completedAt,
    importedBookId,
    retryCount,
    attemptId,
    remoteMetadataJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'remote_download_tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<RemoteDownloadTask> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('publication_remote_id')) {
      context.handle(
        _publicationRemoteIdMeta,
        publicationRemoteId.isAcceptableOrUnknown(
          data['publication_remote_id']!,
          _publicationRemoteIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_publicationRemoteIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('authors_json')) {
      context.handle(
        _authorsJsonMeta,
        authorsJson.isAcceptableOrUnknown(
          data['authors_json']!,
          _authorsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_authorsJsonMeta);
    }
    if (data.containsKey('acquisition_uri')) {
      context.handle(
        _acquisitionUriMeta,
        acquisitionUri.isAcceptableOrUnknown(
          data['acquisition_uri']!,
          _acquisitionUriMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_acquisitionUriMeta);
    }
    if (data.containsKey('declared_media_type')) {
      context.handle(
        _declaredMediaTypeMeta,
        declaredMediaType.isAcceptableOrUnknown(
          data['declared_media_type']!,
          _declaredMediaTypeMeta,
        ),
      );
    }
    if (data.containsKey('expected_final_media_type')) {
      context.handle(
        _expectedFinalMediaTypeMeta,
        expectedFinalMediaType.isAcceptableOrUnknown(
          data['expected_final_media_type']!,
          _expectedFinalMediaTypeMeta,
        ),
      );
    }
    if (data.containsKey('suggested_filename')) {
      context.handle(
        _suggestedFilenameMeta,
        suggestedFilename.isAcceptableOrUnknown(
          data['suggested_filename']!,
          _suggestedFilenameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_suggestedFilenameMeta);
    }
    if (data.containsKey('expected_size_bytes')) {
      context.handle(
        _expectedSizeBytesMeta,
        expectedSizeBytes.isAcceptableOrUnknown(
          data['expected_size_bytes']!,
          _expectedSizeBytesMeta,
        ),
      );
    }
    if (data.containsKey('downloaded_bytes')) {
      context.handle(
        _downloadedBytesMeta,
        downloadedBytes.isAcceptableOrUnknown(
          data['downloaded_bytes']!,
          _downloadedBytesMeta,
        ),
      );
    }
    if (data.containsKey('total_bytes')) {
      context.handle(
        _totalBytesMeta,
        totalBytes.isAcceptableOrUnknown(data['total_bytes']!, _totalBytesMeta),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('temporary_file_path')) {
      context.handle(
        _temporaryFilePathMeta,
        temporaryFilePath.isAcceptableOrUnknown(
          data['temporary_file_path']!,
          _temporaryFilePathMeta,
        ),
      );
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    }
    if (data.containsKey('failure_category')) {
      context.handle(
        _failureCategoryMeta,
        failureCategory.isAcceptableOrUnknown(
          data['failure_category']!,
          _failureCategoryMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('imported_book_id')) {
      context.handle(
        _importedBookIdMeta,
        importedBookId.isAcceptableOrUnknown(
          data['imported_book_id']!,
          _importedBookIdMeta,
        ),
      );
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    }
    if (data.containsKey('attempt_id')) {
      context.handle(
        _attemptIdMeta,
        attemptId.isAcceptableOrUnknown(data['attempt_id']!, _attemptIdMeta),
      );
    }
    if (data.containsKey('remote_metadata_json')) {
      context.handle(
        _remoteMetadataJsonMeta,
        remoteMetadataJson.isAcceptableOrUnknown(
          data['remote_metadata_json']!,
          _remoteMetadataJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RemoteDownloadTask map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RemoteDownloadTask(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      publicationRemoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}publication_remote_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      authorsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}authors_json'],
      )!,
      acquisitionUri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}acquisition_uri'],
      )!,
      declaredMediaType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}declared_media_type'],
      ),
      expectedFinalMediaType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}expected_final_media_type'],
      ),
      suggestedFilename: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}suggested_filename'],
      )!,
      expectedSizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expected_size_bytes'],
      ),
      downloadedBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}downloaded_bytes'],
      )!,
      totalBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_bytes'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      temporaryFilePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}temporary_file_path'],
      ),
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      ),
      failureCategory: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_category'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      ),
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
      importedBookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}imported_book_id'],
      ),
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      attemptId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_id'],
      )!,
      remoteMetadataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_metadata_json'],
      ),
    );
  }

  @override
  $RemoteDownloadTasksTable createAlias(String alias) {
    return $RemoteDownloadTasksTable(attachedDatabase, alias);
  }
}

class RemoteDownloadTask extends DataClass
    implements Insertable<RemoteDownloadTask> {
  final String id;
  final String sourceId;
  final String publicationRemoteId;
  final String title;
  final String authorsJson;
  final String acquisitionUri;
  final String? declaredMediaType;
  final String? expectedFinalMediaType;
  final String suggestedFilename;
  final int? expectedSizeBytes;
  final int downloadedBytes;
  final int? totalBytes;
  final String state;
  final String? temporaryFilePath;
  final String? sha256;
  final String? failureCategory;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? importedBookId;
  final int retryCount;
  final int attemptId;
  final String? remoteMetadataJson;
  const RemoteDownloadTask({
    required this.id,
    required this.sourceId,
    required this.publicationRemoteId,
    required this.title,
    required this.authorsJson,
    required this.acquisitionUri,
    this.declaredMediaType,
    this.expectedFinalMediaType,
    required this.suggestedFilename,
    this.expectedSizeBytes,
    required this.downloadedBytes,
    this.totalBytes,
    required this.state,
    this.temporaryFilePath,
    this.sha256,
    this.failureCategory,
    required this.createdAt,
    required this.updatedAt,
    this.startedAt,
    this.completedAt,
    this.importedBookId,
    required this.retryCount,
    required this.attemptId,
    this.remoteMetadataJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['source_id'] = Variable<String>(sourceId);
    map['publication_remote_id'] = Variable<String>(publicationRemoteId);
    map['title'] = Variable<String>(title);
    map['authors_json'] = Variable<String>(authorsJson);
    map['acquisition_uri'] = Variable<String>(acquisitionUri);
    if (!nullToAbsent || declaredMediaType != null) {
      map['declared_media_type'] = Variable<String>(declaredMediaType);
    }
    if (!nullToAbsent || expectedFinalMediaType != null) {
      map['expected_final_media_type'] = Variable<String>(
        expectedFinalMediaType,
      );
    }
    map['suggested_filename'] = Variable<String>(suggestedFilename);
    if (!nullToAbsent || expectedSizeBytes != null) {
      map['expected_size_bytes'] = Variable<int>(expectedSizeBytes);
    }
    map['downloaded_bytes'] = Variable<int>(downloadedBytes);
    if (!nullToAbsent || totalBytes != null) {
      map['total_bytes'] = Variable<int>(totalBytes);
    }
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || temporaryFilePath != null) {
      map['temporary_file_path'] = Variable<String>(temporaryFilePath);
    }
    if (!nullToAbsent || sha256 != null) {
      map['sha256'] = Variable<String>(sha256);
    }
    if (!nullToAbsent || failureCategory != null) {
      map['failure_category'] = Variable<String>(failureCategory);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || startedAt != null) {
      map['started_at'] = Variable<DateTime>(startedAt);
    }
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    if (!nullToAbsent || importedBookId != null) {
      map['imported_book_id'] = Variable<String>(importedBookId);
    }
    map['retry_count'] = Variable<int>(retryCount);
    map['attempt_id'] = Variable<int>(attemptId);
    if (!nullToAbsent || remoteMetadataJson != null) {
      map['remote_metadata_json'] = Variable<String>(remoteMetadataJson);
    }
    return map;
  }

  RemoteDownloadTasksCompanion toCompanion(bool nullToAbsent) {
    return RemoteDownloadTasksCompanion(
      id: Value(id),
      sourceId: Value(sourceId),
      publicationRemoteId: Value(publicationRemoteId),
      title: Value(title),
      authorsJson: Value(authorsJson),
      acquisitionUri: Value(acquisitionUri),
      declaredMediaType: declaredMediaType == null && nullToAbsent
          ? const Value.absent()
          : Value(declaredMediaType),
      expectedFinalMediaType: expectedFinalMediaType == null && nullToAbsent
          ? const Value.absent()
          : Value(expectedFinalMediaType),
      suggestedFilename: Value(suggestedFilename),
      expectedSizeBytes: expectedSizeBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(expectedSizeBytes),
      downloadedBytes: Value(downloadedBytes),
      totalBytes: totalBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(totalBytes),
      state: Value(state),
      temporaryFilePath: temporaryFilePath == null && nullToAbsent
          ? const Value.absent()
          : Value(temporaryFilePath),
      sha256: sha256 == null && nullToAbsent
          ? const Value.absent()
          : Value(sha256),
      failureCategory: failureCategory == null && nullToAbsent
          ? const Value.absent()
          : Value(failureCategory),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      startedAt: startedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(startedAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      importedBookId: importedBookId == null && nullToAbsent
          ? const Value.absent()
          : Value(importedBookId),
      retryCount: Value(retryCount),
      attemptId: Value(attemptId),
      remoteMetadataJson: remoteMetadataJson == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteMetadataJson),
    );
  }

  factory RemoteDownloadTask.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RemoteDownloadTask(
      id: serializer.fromJson<String>(json['id']),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      publicationRemoteId: serializer.fromJson<String>(
        json['publicationRemoteId'],
      ),
      title: serializer.fromJson<String>(json['title']),
      authorsJson: serializer.fromJson<String>(json['authorsJson']),
      acquisitionUri: serializer.fromJson<String>(json['acquisitionUri']),
      declaredMediaType: serializer.fromJson<String?>(
        json['declaredMediaType'],
      ),
      expectedFinalMediaType: serializer.fromJson<String?>(
        json['expectedFinalMediaType'],
      ),
      suggestedFilename: serializer.fromJson<String>(json['suggestedFilename']),
      expectedSizeBytes: serializer.fromJson<int?>(json['expectedSizeBytes']),
      downloadedBytes: serializer.fromJson<int>(json['downloadedBytes']),
      totalBytes: serializer.fromJson<int?>(json['totalBytes']),
      state: serializer.fromJson<String>(json['state']),
      temporaryFilePath: serializer.fromJson<String?>(
        json['temporaryFilePath'],
      ),
      sha256: serializer.fromJson<String?>(json['sha256']),
      failureCategory: serializer.fromJson<String?>(json['failureCategory']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      startedAt: serializer.fromJson<DateTime?>(json['startedAt']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      importedBookId: serializer.fromJson<String?>(json['importedBookId']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      attemptId: serializer.fromJson<int>(json['attemptId']),
      remoteMetadataJson: serializer.fromJson<String?>(
        json['remoteMetadataJson'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sourceId': serializer.toJson<String>(sourceId),
      'publicationRemoteId': serializer.toJson<String>(publicationRemoteId),
      'title': serializer.toJson<String>(title),
      'authorsJson': serializer.toJson<String>(authorsJson),
      'acquisitionUri': serializer.toJson<String>(acquisitionUri),
      'declaredMediaType': serializer.toJson<String?>(declaredMediaType),
      'expectedFinalMediaType': serializer.toJson<String?>(
        expectedFinalMediaType,
      ),
      'suggestedFilename': serializer.toJson<String>(suggestedFilename),
      'expectedSizeBytes': serializer.toJson<int?>(expectedSizeBytes),
      'downloadedBytes': serializer.toJson<int>(downloadedBytes),
      'totalBytes': serializer.toJson<int?>(totalBytes),
      'state': serializer.toJson<String>(state),
      'temporaryFilePath': serializer.toJson<String?>(temporaryFilePath),
      'sha256': serializer.toJson<String?>(sha256),
      'failureCategory': serializer.toJson<String?>(failureCategory),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'startedAt': serializer.toJson<DateTime?>(startedAt),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'importedBookId': serializer.toJson<String?>(importedBookId),
      'retryCount': serializer.toJson<int>(retryCount),
      'attemptId': serializer.toJson<int>(attemptId),
      'remoteMetadataJson': serializer.toJson<String?>(remoteMetadataJson),
    };
  }

  RemoteDownloadTask copyWith({
    String? id,
    String? sourceId,
    String? publicationRemoteId,
    String? title,
    String? authorsJson,
    String? acquisitionUri,
    Value<String?> declaredMediaType = const Value.absent(),
    Value<String?> expectedFinalMediaType = const Value.absent(),
    String? suggestedFilename,
    Value<int?> expectedSizeBytes = const Value.absent(),
    int? downloadedBytes,
    Value<int?> totalBytes = const Value.absent(),
    String? state,
    Value<String?> temporaryFilePath = const Value.absent(),
    Value<String?> sha256 = const Value.absent(),
    Value<String?> failureCategory = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> startedAt = const Value.absent(),
    Value<DateTime?> completedAt = const Value.absent(),
    Value<String?> importedBookId = const Value.absent(),
    int? retryCount,
    int? attemptId,
    Value<String?> remoteMetadataJson = const Value.absent(),
  }) => RemoteDownloadTask(
    id: id ?? this.id,
    sourceId: sourceId ?? this.sourceId,
    publicationRemoteId: publicationRemoteId ?? this.publicationRemoteId,
    title: title ?? this.title,
    authorsJson: authorsJson ?? this.authorsJson,
    acquisitionUri: acquisitionUri ?? this.acquisitionUri,
    declaredMediaType: declaredMediaType.present
        ? declaredMediaType.value
        : this.declaredMediaType,
    expectedFinalMediaType: expectedFinalMediaType.present
        ? expectedFinalMediaType.value
        : this.expectedFinalMediaType,
    suggestedFilename: suggestedFilename ?? this.suggestedFilename,
    expectedSizeBytes: expectedSizeBytes.present
        ? expectedSizeBytes.value
        : this.expectedSizeBytes,
    downloadedBytes: downloadedBytes ?? this.downloadedBytes,
    totalBytes: totalBytes.present ? totalBytes.value : this.totalBytes,
    state: state ?? this.state,
    temporaryFilePath: temporaryFilePath.present
        ? temporaryFilePath.value
        : this.temporaryFilePath,
    sha256: sha256.present ? sha256.value : this.sha256,
    failureCategory: failureCategory.present
        ? failureCategory.value
        : this.failureCategory,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    startedAt: startedAt.present ? startedAt.value : this.startedAt,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
    importedBookId: importedBookId.present
        ? importedBookId.value
        : this.importedBookId,
    retryCount: retryCount ?? this.retryCount,
    attemptId: attemptId ?? this.attemptId,
    remoteMetadataJson: remoteMetadataJson.present
        ? remoteMetadataJson.value
        : this.remoteMetadataJson,
  );
  RemoteDownloadTask copyWithCompanion(RemoteDownloadTasksCompanion data) {
    return RemoteDownloadTask(
      id: data.id.present ? data.id.value : this.id,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      publicationRemoteId: data.publicationRemoteId.present
          ? data.publicationRemoteId.value
          : this.publicationRemoteId,
      title: data.title.present ? data.title.value : this.title,
      authorsJson: data.authorsJson.present
          ? data.authorsJson.value
          : this.authorsJson,
      acquisitionUri: data.acquisitionUri.present
          ? data.acquisitionUri.value
          : this.acquisitionUri,
      declaredMediaType: data.declaredMediaType.present
          ? data.declaredMediaType.value
          : this.declaredMediaType,
      expectedFinalMediaType: data.expectedFinalMediaType.present
          ? data.expectedFinalMediaType.value
          : this.expectedFinalMediaType,
      suggestedFilename: data.suggestedFilename.present
          ? data.suggestedFilename.value
          : this.suggestedFilename,
      expectedSizeBytes: data.expectedSizeBytes.present
          ? data.expectedSizeBytes.value
          : this.expectedSizeBytes,
      downloadedBytes: data.downloadedBytes.present
          ? data.downloadedBytes.value
          : this.downloadedBytes,
      totalBytes: data.totalBytes.present
          ? data.totalBytes.value
          : this.totalBytes,
      state: data.state.present ? data.state.value : this.state,
      temporaryFilePath: data.temporaryFilePath.present
          ? data.temporaryFilePath.value
          : this.temporaryFilePath,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      failureCategory: data.failureCategory.present
          ? data.failureCategory.value
          : this.failureCategory,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      importedBookId: data.importedBookId.present
          ? data.importedBookId.value
          : this.importedBookId,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      attemptId: data.attemptId.present ? data.attemptId.value : this.attemptId,
      remoteMetadataJson: data.remoteMetadataJson.present
          ? data.remoteMetadataJson.value
          : this.remoteMetadataJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RemoteDownloadTask(')
          ..write('id: $id, ')
          ..write('sourceId: $sourceId, ')
          ..write('publicationRemoteId: $publicationRemoteId, ')
          ..write('title: $title, ')
          ..write('authorsJson: $authorsJson, ')
          ..write('acquisitionUri: $acquisitionUri, ')
          ..write('declaredMediaType: $declaredMediaType, ')
          ..write('expectedFinalMediaType: $expectedFinalMediaType, ')
          ..write('suggestedFilename: $suggestedFilename, ')
          ..write('expectedSizeBytes: $expectedSizeBytes, ')
          ..write('downloadedBytes: $downloadedBytes, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('state: $state, ')
          ..write('temporaryFilePath: $temporaryFilePath, ')
          ..write('sha256: $sha256, ')
          ..write('failureCategory: $failureCategory, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('startedAt: $startedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('importedBookId: $importedBookId, ')
          ..write('retryCount: $retryCount, ')
          ..write('attemptId: $attemptId, ')
          ..write('remoteMetadataJson: $remoteMetadataJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    sourceId,
    publicationRemoteId,
    title,
    authorsJson,
    acquisitionUri,
    declaredMediaType,
    expectedFinalMediaType,
    suggestedFilename,
    expectedSizeBytes,
    downloadedBytes,
    totalBytes,
    state,
    temporaryFilePath,
    sha256,
    failureCategory,
    createdAt,
    updatedAt,
    startedAt,
    completedAt,
    importedBookId,
    retryCount,
    attemptId,
    remoteMetadataJson,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RemoteDownloadTask &&
          other.id == this.id &&
          other.sourceId == this.sourceId &&
          other.publicationRemoteId == this.publicationRemoteId &&
          other.title == this.title &&
          other.authorsJson == this.authorsJson &&
          other.acquisitionUri == this.acquisitionUri &&
          other.declaredMediaType == this.declaredMediaType &&
          other.expectedFinalMediaType == this.expectedFinalMediaType &&
          other.suggestedFilename == this.suggestedFilename &&
          other.expectedSizeBytes == this.expectedSizeBytes &&
          other.downloadedBytes == this.downloadedBytes &&
          other.totalBytes == this.totalBytes &&
          other.state == this.state &&
          other.temporaryFilePath == this.temporaryFilePath &&
          other.sha256 == this.sha256 &&
          other.failureCategory == this.failureCategory &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.startedAt == this.startedAt &&
          other.completedAt == this.completedAt &&
          other.importedBookId == this.importedBookId &&
          other.retryCount == this.retryCount &&
          other.attemptId == this.attemptId &&
          other.remoteMetadataJson == this.remoteMetadataJson);
}

class RemoteDownloadTasksCompanion extends UpdateCompanion<RemoteDownloadTask> {
  final Value<String> id;
  final Value<String> sourceId;
  final Value<String> publicationRemoteId;
  final Value<String> title;
  final Value<String> authorsJson;
  final Value<String> acquisitionUri;
  final Value<String?> declaredMediaType;
  final Value<String?> expectedFinalMediaType;
  final Value<String> suggestedFilename;
  final Value<int?> expectedSizeBytes;
  final Value<int> downloadedBytes;
  final Value<int?> totalBytes;
  final Value<String> state;
  final Value<String?> temporaryFilePath;
  final Value<String?> sha256;
  final Value<String?> failureCategory;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> startedAt;
  final Value<DateTime?> completedAt;
  final Value<String?> importedBookId;
  final Value<int> retryCount;
  final Value<int> attemptId;
  final Value<String?> remoteMetadataJson;
  final Value<int> rowid;
  const RemoteDownloadTasksCompanion({
    this.id = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.publicationRemoteId = const Value.absent(),
    this.title = const Value.absent(),
    this.authorsJson = const Value.absent(),
    this.acquisitionUri = const Value.absent(),
    this.declaredMediaType = const Value.absent(),
    this.expectedFinalMediaType = const Value.absent(),
    this.suggestedFilename = const Value.absent(),
    this.expectedSizeBytes = const Value.absent(),
    this.downloadedBytes = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.state = const Value.absent(),
    this.temporaryFilePath = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.failureCategory = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.importedBookId = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.attemptId = const Value.absent(),
    this.remoteMetadataJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RemoteDownloadTasksCompanion.insert({
    required String id,
    required String sourceId,
    required String publicationRemoteId,
    required String title,
    required String authorsJson,
    required String acquisitionUri,
    this.declaredMediaType = const Value.absent(),
    this.expectedFinalMediaType = const Value.absent(),
    required String suggestedFilename,
    this.expectedSizeBytes = const Value.absent(),
    this.downloadedBytes = const Value.absent(),
    this.totalBytes = const Value.absent(),
    required String state,
    this.temporaryFilePath = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.failureCategory = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.startedAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.importedBookId = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.attemptId = const Value.absent(),
    this.remoteMetadataJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sourceId = Value(sourceId),
       publicationRemoteId = Value(publicationRemoteId),
       title = Value(title),
       authorsJson = Value(authorsJson),
       acquisitionUri = Value(acquisitionUri),
       suggestedFilename = Value(suggestedFilename),
       state = Value(state),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<RemoteDownloadTask> custom({
    Expression<String>? id,
    Expression<String>? sourceId,
    Expression<String>? publicationRemoteId,
    Expression<String>? title,
    Expression<String>? authorsJson,
    Expression<String>? acquisitionUri,
    Expression<String>? declaredMediaType,
    Expression<String>? expectedFinalMediaType,
    Expression<String>? suggestedFilename,
    Expression<int>? expectedSizeBytes,
    Expression<int>? downloadedBytes,
    Expression<int>? totalBytes,
    Expression<String>? state,
    Expression<String>? temporaryFilePath,
    Expression<String>? sha256,
    Expression<String>? failureCategory,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? completedAt,
    Expression<String>? importedBookId,
    Expression<int>? retryCount,
    Expression<int>? attemptId,
    Expression<String>? remoteMetadataJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceId != null) 'source_id': sourceId,
      if (publicationRemoteId != null)
        'publication_remote_id': publicationRemoteId,
      if (title != null) 'title': title,
      if (authorsJson != null) 'authors_json': authorsJson,
      if (acquisitionUri != null) 'acquisition_uri': acquisitionUri,
      if (declaredMediaType != null) 'declared_media_type': declaredMediaType,
      if (expectedFinalMediaType != null)
        'expected_final_media_type': expectedFinalMediaType,
      if (suggestedFilename != null) 'suggested_filename': suggestedFilename,
      if (expectedSizeBytes != null) 'expected_size_bytes': expectedSizeBytes,
      if (downloadedBytes != null) 'downloaded_bytes': downloadedBytes,
      if (totalBytes != null) 'total_bytes': totalBytes,
      if (state != null) 'state': state,
      if (temporaryFilePath != null) 'temporary_file_path': temporaryFilePath,
      if (sha256 != null) 'sha256': sha256,
      if (failureCategory != null) 'failure_category': failureCategory,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (startedAt != null) 'started_at': startedAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (importedBookId != null) 'imported_book_id': importedBookId,
      if (retryCount != null) 'retry_count': retryCount,
      if (attemptId != null) 'attempt_id': attemptId,
      if (remoteMetadataJson != null)
        'remote_metadata_json': remoteMetadataJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RemoteDownloadTasksCompanion copyWith({
    Value<String>? id,
    Value<String>? sourceId,
    Value<String>? publicationRemoteId,
    Value<String>? title,
    Value<String>? authorsJson,
    Value<String>? acquisitionUri,
    Value<String?>? declaredMediaType,
    Value<String?>? expectedFinalMediaType,
    Value<String>? suggestedFilename,
    Value<int?>? expectedSizeBytes,
    Value<int>? downloadedBytes,
    Value<int?>? totalBytes,
    Value<String>? state,
    Value<String?>? temporaryFilePath,
    Value<String?>? sha256,
    Value<String?>? failureCategory,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? startedAt,
    Value<DateTime?>? completedAt,
    Value<String?>? importedBookId,
    Value<int>? retryCount,
    Value<int>? attemptId,
    Value<String?>? remoteMetadataJson,
    Value<int>? rowid,
  }) {
    return RemoteDownloadTasksCompanion(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      publicationRemoteId: publicationRemoteId ?? this.publicationRemoteId,
      title: title ?? this.title,
      authorsJson: authorsJson ?? this.authorsJson,
      acquisitionUri: acquisitionUri ?? this.acquisitionUri,
      declaredMediaType: declaredMediaType ?? this.declaredMediaType,
      expectedFinalMediaType:
          expectedFinalMediaType ?? this.expectedFinalMediaType,
      suggestedFilename: suggestedFilename ?? this.suggestedFilename,
      expectedSizeBytes: expectedSizeBytes ?? this.expectedSizeBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      state: state ?? this.state,
      temporaryFilePath: temporaryFilePath ?? this.temporaryFilePath,
      sha256: sha256 ?? this.sha256,
      failureCategory: failureCategory ?? this.failureCategory,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      importedBookId: importedBookId ?? this.importedBookId,
      retryCount: retryCount ?? this.retryCount,
      attemptId: attemptId ?? this.attemptId,
      remoteMetadataJson: remoteMetadataJson ?? this.remoteMetadataJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (publicationRemoteId.present) {
      map['publication_remote_id'] = Variable<String>(
        publicationRemoteId.value,
      );
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (authorsJson.present) {
      map['authors_json'] = Variable<String>(authorsJson.value);
    }
    if (acquisitionUri.present) {
      map['acquisition_uri'] = Variable<String>(acquisitionUri.value);
    }
    if (declaredMediaType.present) {
      map['declared_media_type'] = Variable<String>(declaredMediaType.value);
    }
    if (expectedFinalMediaType.present) {
      map['expected_final_media_type'] = Variable<String>(
        expectedFinalMediaType.value,
      );
    }
    if (suggestedFilename.present) {
      map['suggested_filename'] = Variable<String>(suggestedFilename.value);
    }
    if (expectedSizeBytes.present) {
      map['expected_size_bytes'] = Variable<int>(expectedSizeBytes.value);
    }
    if (downloadedBytes.present) {
      map['downloaded_bytes'] = Variable<int>(downloadedBytes.value);
    }
    if (totalBytes.present) {
      map['total_bytes'] = Variable<int>(totalBytes.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (temporaryFilePath.present) {
      map['temporary_file_path'] = Variable<String>(temporaryFilePath.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (failureCategory.present) {
      map['failure_category'] = Variable<String>(failureCategory.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (importedBookId.present) {
      map['imported_book_id'] = Variable<String>(importedBookId.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (attemptId.present) {
      map['attempt_id'] = Variable<int>(attemptId.value);
    }
    if (remoteMetadataJson.present) {
      map['remote_metadata_json'] = Variable<String>(remoteMetadataJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RemoteDownloadTasksCompanion(')
          ..write('id: $id, ')
          ..write('sourceId: $sourceId, ')
          ..write('publicationRemoteId: $publicationRemoteId, ')
          ..write('title: $title, ')
          ..write('authorsJson: $authorsJson, ')
          ..write('acquisitionUri: $acquisitionUri, ')
          ..write('declaredMediaType: $declaredMediaType, ')
          ..write('expectedFinalMediaType: $expectedFinalMediaType, ')
          ..write('suggestedFilename: $suggestedFilename, ')
          ..write('expectedSizeBytes: $expectedSizeBytes, ')
          ..write('downloadedBytes: $downloadedBytes, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('state: $state, ')
          ..write('temporaryFilePath: $temporaryFilePath, ')
          ..write('sha256: $sha256, ')
          ..write('failureCategory: $failureCategory, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('startedAt: $startedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('importedBookId: $importedBookId, ')
          ..write('retryCount: $retryCount, ')
          ..write('attemptId: $attemptId, ')
          ..write('remoteMetadataJson: $remoteMetadataJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RemoteCacheSettingsEntriesTable extends RemoteCacheSettingsEntries
    with TableInfo<$RemoteCacheSettingsEntriesTable, RemoteCacheSettingsEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RemoteCacheSettingsEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maximumBytesMeta = const VerificationMeta(
    'maximumBytes',
  );
  @override
  late final GeneratedColumn<int> maximumBytes = GeneratedColumn<int>(
    'maximum_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, maximumBytes];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'remote_cache_settings_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<RemoteCacheSettingsEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('maximum_bytes')) {
      context.handle(
        _maximumBytesMeta,
        maximumBytes.isAcceptableOrUnknown(
          data['maximum_bytes']!,
          _maximumBytesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_maximumBytesMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RemoteCacheSettingsEntry map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RemoteCacheSettingsEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      maximumBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}maximum_bytes'],
      )!,
    );
  }

  @override
  $RemoteCacheSettingsEntriesTable createAlias(String alias) {
    return $RemoteCacheSettingsEntriesTable(attachedDatabase, alias);
  }
}

class RemoteCacheSettingsEntry extends DataClass
    implements Insertable<RemoteCacheSettingsEntry> {
  final int id;
  final int maximumBytes;
  const RemoteCacheSettingsEntry({
    required this.id,
    required this.maximumBytes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['maximum_bytes'] = Variable<int>(maximumBytes);
    return map;
  }

  RemoteCacheSettingsEntriesCompanion toCompanion(bool nullToAbsent) {
    return RemoteCacheSettingsEntriesCompanion(
      id: Value(id),
      maximumBytes: Value(maximumBytes),
    );
  }

  factory RemoteCacheSettingsEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RemoteCacheSettingsEntry(
      id: serializer.fromJson<int>(json['id']),
      maximumBytes: serializer.fromJson<int>(json['maximumBytes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'maximumBytes': serializer.toJson<int>(maximumBytes),
    };
  }

  RemoteCacheSettingsEntry copyWith({int? id, int? maximumBytes}) =>
      RemoteCacheSettingsEntry(
        id: id ?? this.id,
        maximumBytes: maximumBytes ?? this.maximumBytes,
      );
  RemoteCacheSettingsEntry copyWithCompanion(
    RemoteCacheSettingsEntriesCompanion data,
  ) {
    return RemoteCacheSettingsEntry(
      id: data.id.present ? data.id.value : this.id,
      maximumBytes: data.maximumBytes.present
          ? data.maximumBytes.value
          : this.maximumBytes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RemoteCacheSettingsEntry(')
          ..write('id: $id, ')
          ..write('maximumBytes: $maximumBytes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, maximumBytes);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RemoteCacheSettingsEntry &&
          other.id == this.id &&
          other.maximumBytes == this.maximumBytes);
}

class RemoteCacheSettingsEntriesCompanion
    extends UpdateCompanion<RemoteCacheSettingsEntry> {
  final Value<int> id;
  final Value<int> maximumBytes;
  const RemoteCacheSettingsEntriesCompanion({
    this.id = const Value.absent(),
    this.maximumBytes = const Value.absent(),
  });
  RemoteCacheSettingsEntriesCompanion.insert({
    this.id = const Value.absent(),
    required int maximumBytes,
  }) : maximumBytes = Value(maximumBytes);
  static Insertable<RemoteCacheSettingsEntry> custom({
    Expression<int>? id,
    Expression<int>? maximumBytes,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (maximumBytes != null) 'maximum_bytes': maximumBytes,
    });
  }

  RemoteCacheSettingsEntriesCompanion copyWith({
    Value<int>? id,
    Value<int>? maximumBytes,
  }) {
    return RemoteCacheSettingsEntriesCompanion(
      id: id ?? this.id,
      maximumBytes: maximumBytes ?? this.maximumBytes,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (maximumBytes.present) {
      map['maximum_bytes'] = Variable<int>(maximumBytes.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RemoteCacheSettingsEntriesCompanion(')
          ..write('id: $id, ')
          ..write('maximumBytes: $maximumBytes')
          ..write(')'))
        .toString();
  }
}

class $HomeOnlineTabSettingsEntriesTable extends HomeOnlineTabSettingsEntries
    with
        TableInfo<
          $HomeOnlineTabSettingsEntriesTable,
          HomeOnlineTabSettingsEntry
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HomeOnlineTabSettingsEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _visibleOnHomeMeta = const VerificationMeta(
    'visibleOnHome',
  );
  @override
  late final GeneratedColumn<bool> visibleOnHome = GeneratedColumn<bool>(
    'visible_on_home',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("visible_on_home" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [sourceId, visibleOnHome];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'home_online_tab_settings_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<HomeOnlineTabSettingsEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('visible_on_home')) {
      context.handle(
        _visibleOnHomeMeta,
        visibleOnHome.isAcceptableOrUnknown(
          data['visible_on_home']!,
          _visibleOnHomeMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId};
  @override
  HomeOnlineTabSettingsEntry map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HomeOnlineTabSettingsEntry(
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      visibleOnHome: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}visible_on_home'],
      )!,
    );
  }

  @override
  $HomeOnlineTabSettingsEntriesTable createAlias(String alias) {
    return $HomeOnlineTabSettingsEntriesTable(attachedDatabase, alias);
  }
}

class HomeOnlineTabSettingsEntry extends DataClass
    implements Insertable<HomeOnlineTabSettingsEntry> {
  final String sourceId;
  final bool visibleOnHome;
  const HomeOnlineTabSettingsEntry({
    required this.sourceId,
    required this.visibleOnHome,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<String>(sourceId);
    map['visible_on_home'] = Variable<bool>(visibleOnHome);
    return map;
  }

  HomeOnlineTabSettingsEntriesCompanion toCompanion(bool nullToAbsent) {
    return HomeOnlineTabSettingsEntriesCompanion(
      sourceId: Value(sourceId),
      visibleOnHome: Value(visibleOnHome),
    );
  }

  factory HomeOnlineTabSettingsEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HomeOnlineTabSettingsEntry(
      sourceId: serializer.fromJson<String>(json['sourceId']),
      visibleOnHome: serializer.fromJson<bool>(json['visibleOnHome']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceId': serializer.toJson<String>(sourceId),
      'visibleOnHome': serializer.toJson<bool>(visibleOnHome),
    };
  }

  HomeOnlineTabSettingsEntry copyWith({
    String? sourceId,
    bool? visibleOnHome,
  }) => HomeOnlineTabSettingsEntry(
    sourceId: sourceId ?? this.sourceId,
    visibleOnHome: visibleOnHome ?? this.visibleOnHome,
  );
  HomeOnlineTabSettingsEntry copyWithCompanion(
    HomeOnlineTabSettingsEntriesCompanion data,
  ) {
    return HomeOnlineTabSettingsEntry(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      visibleOnHome: data.visibleOnHome.present
          ? data.visibleOnHome.value
          : this.visibleOnHome,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HomeOnlineTabSettingsEntry(')
          ..write('sourceId: $sourceId, ')
          ..write('visibleOnHome: $visibleOnHome')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sourceId, visibleOnHome);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HomeOnlineTabSettingsEntry &&
          other.sourceId == this.sourceId &&
          other.visibleOnHome == this.visibleOnHome);
}

class HomeOnlineTabSettingsEntriesCompanion
    extends UpdateCompanion<HomeOnlineTabSettingsEntry> {
  final Value<String> sourceId;
  final Value<bool> visibleOnHome;
  final Value<int> rowid;
  const HomeOnlineTabSettingsEntriesCompanion({
    this.sourceId = const Value.absent(),
    this.visibleOnHome = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HomeOnlineTabSettingsEntriesCompanion.insert({
    required String sourceId,
    this.visibleOnHome = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sourceId = Value(sourceId);
  static Insertable<HomeOnlineTabSettingsEntry> custom({
    Expression<String>? sourceId,
    Expression<bool>? visibleOnHome,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (visibleOnHome != null) 'visible_on_home': visibleOnHome,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HomeOnlineTabSettingsEntriesCompanion copyWith({
    Value<String>? sourceId,
    Value<bool>? visibleOnHome,
    Value<int>? rowid,
  }) {
    return HomeOnlineTabSettingsEntriesCompanion(
      sourceId: sourceId ?? this.sourceId,
      visibleOnHome: visibleOnHome ?? this.visibleOnHome,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (visibleOnHome.present) {
      map['visible_on_home'] = Variable<bool>(visibleOnHome.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HomeOnlineTabSettingsEntriesCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('visibleOnHome: $visibleOnHome, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LibrarySectionSettingsEntriesTable extends LibrarySectionSettingsEntries
    with
        TableInfo<
          $LibrarySectionSettingsEntriesTable,
          LibrarySectionSettingsEntry
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LibrarySectionSettingsEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _defaultSectionMeta = const VerificationMeta(
    'defaultSection',
  );
  @override
  late final GeneratedColumn<String> defaultSection = GeneratedColumn<String>(
    'default_section',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, defaultSection];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'library_section_settings_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<LibrarySectionSettingsEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('default_section')) {
      context.handle(
        _defaultSectionMeta,
        defaultSection.isAcceptableOrUnknown(
          data['default_section']!,
          _defaultSectionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_defaultSectionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LibrarySectionSettingsEntry map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LibrarySectionSettingsEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      defaultSection: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}default_section'],
      )!,
    );
  }

  @override
  $LibrarySectionSettingsEntriesTable createAlias(String alias) {
    return $LibrarySectionSettingsEntriesTable(attachedDatabase, alias);
  }
}

class LibrarySectionSettingsEntry extends DataClass
    implements Insertable<LibrarySectionSettingsEntry> {
  final int id;
  final String defaultSection;
  const LibrarySectionSettingsEntry({
    required this.id,
    required this.defaultSection,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['default_section'] = Variable<String>(defaultSection);
    return map;
  }

  LibrarySectionSettingsEntriesCompanion toCompanion(bool nullToAbsent) {
    return LibrarySectionSettingsEntriesCompanion(
      id: Value(id),
      defaultSection: Value(defaultSection),
    );
  }

  factory LibrarySectionSettingsEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LibrarySectionSettingsEntry(
      id: serializer.fromJson<int>(json['id']),
      defaultSection: serializer.fromJson<String>(json['defaultSection']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'defaultSection': serializer.toJson<String>(defaultSection),
    };
  }

  LibrarySectionSettingsEntry copyWith({int? id, String? defaultSection}) =>
      LibrarySectionSettingsEntry(
        id: id ?? this.id,
        defaultSection: defaultSection ?? this.defaultSection,
      );
  LibrarySectionSettingsEntry copyWithCompanion(
    LibrarySectionSettingsEntriesCompanion data,
  ) {
    return LibrarySectionSettingsEntry(
      id: data.id.present ? data.id.value : this.id,
      defaultSection: data.defaultSection.present
          ? data.defaultSection.value
          : this.defaultSection,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LibrarySectionSettingsEntry(')
          ..write('id: $id, ')
          ..write('defaultSection: $defaultSection')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, defaultSection);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LibrarySectionSettingsEntry &&
          other.id == this.id &&
          other.defaultSection == this.defaultSection);
}

class LibrarySectionSettingsEntriesCompanion
    extends UpdateCompanion<LibrarySectionSettingsEntry> {
  final Value<int> id;
  final Value<String> defaultSection;
  const LibrarySectionSettingsEntriesCompanion({
    this.id = const Value.absent(),
    this.defaultSection = const Value.absent(),
  });
  LibrarySectionSettingsEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String defaultSection,
  }) : defaultSection = Value(defaultSection);
  static Insertable<LibrarySectionSettingsEntry> custom({
    Expression<int>? id,
    Expression<String>? defaultSection,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (defaultSection != null) 'default_section': defaultSection,
    });
  }

  LibrarySectionSettingsEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? defaultSection,
  }) {
    return LibrarySectionSettingsEntriesCompanion(
      id: id ?? this.id,
      defaultSection: defaultSection ?? this.defaultSection,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (defaultSection.present) {
      map['default_section'] = Variable<String>(defaultSection.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LibrarySectionSettingsEntriesCompanion(')
          ..write('id: $id, ')
          ..write('defaultSection: $defaultSection')
          ..write(')'))
        .toString();
  }
}

class $HomeDefaultCarouselSettingsEntriesTable
    extends HomeDefaultCarouselSettingsEntries
    with
        TableInfo<
          $HomeDefaultCarouselSettingsEntriesTable,
          HomeDefaultCarouselSettingsEntry
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HomeDefaultCarouselSettingsEntriesTable(
    this.attachedDatabase, [
    this._alias,
  ]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _defaultCarouselMeta = const VerificationMeta(
    'defaultCarousel',
  );
  @override
  late final GeneratedColumn<String> defaultCarousel = GeneratedColumn<String>(
    'default_carousel',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, defaultCarousel];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'home_default_carousel_settings_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<HomeDefaultCarouselSettingsEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('default_carousel')) {
      context.handle(
        _defaultCarouselMeta,
        defaultCarousel.isAcceptableOrUnknown(
          data['default_carousel']!,
          _defaultCarouselMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_defaultCarouselMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HomeDefaultCarouselSettingsEntry map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HomeDefaultCarouselSettingsEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      defaultCarousel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}default_carousel'],
      )!,
    );
  }

  @override
  $HomeDefaultCarouselSettingsEntriesTable createAlias(String alias) {
    return $HomeDefaultCarouselSettingsEntriesTable(attachedDatabase, alias);
  }
}

class HomeDefaultCarouselSettingsEntry extends DataClass
    implements Insertable<HomeDefaultCarouselSettingsEntry> {
  final int id;
  final String defaultCarousel;
  const HomeDefaultCarouselSettingsEntry({
    required this.id,
    required this.defaultCarousel,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['default_carousel'] = Variable<String>(defaultCarousel);
    return map;
  }

  HomeDefaultCarouselSettingsEntriesCompanion toCompanion(bool nullToAbsent) {
    return HomeDefaultCarouselSettingsEntriesCompanion(
      id: Value(id),
      defaultCarousel: Value(defaultCarousel),
    );
  }

  factory HomeDefaultCarouselSettingsEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HomeDefaultCarouselSettingsEntry(
      id: serializer.fromJson<int>(json['id']),
      defaultCarousel: serializer.fromJson<String>(json['defaultCarousel']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'defaultCarousel': serializer.toJson<String>(defaultCarousel),
    };
  }

  HomeDefaultCarouselSettingsEntry copyWith({
    int? id,
    String? defaultCarousel,
  }) => HomeDefaultCarouselSettingsEntry(
    id: id ?? this.id,
    defaultCarousel: defaultCarousel ?? this.defaultCarousel,
  );
  HomeDefaultCarouselSettingsEntry copyWithCompanion(
    HomeDefaultCarouselSettingsEntriesCompanion data,
  ) {
    return HomeDefaultCarouselSettingsEntry(
      id: data.id.present ? data.id.value : this.id,
      defaultCarousel: data.defaultCarousel.present
          ? data.defaultCarousel.value
          : this.defaultCarousel,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HomeDefaultCarouselSettingsEntry(')
          ..write('id: $id, ')
          ..write('defaultCarousel: $defaultCarousel')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, defaultCarousel);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HomeDefaultCarouselSettingsEntry &&
          other.id == this.id &&
          other.defaultCarousel == this.defaultCarousel);
}

class HomeDefaultCarouselSettingsEntriesCompanion
    extends UpdateCompanion<HomeDefaultCarouselSettingsEntry> {
  final Value<int> id;
  final Value<String> defaultCarousel;
  const HomeDefaultCarouselSettingsEntriesCompanion({
    this.id = const Value.absent(),
    this.defaultCarousel = const Value.absent(),
  });
  HomeDefaultCarouselSettingsEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String defaultCarousel,
  }) : defaultCarousel = Value(defaultCarousel);
  static Insertable<HomeDefaultCarouselSettingsEntry> custom({
    Expression<int>? id,
    Expression<String>? defaultCarousel,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (defaultCarousel != null) 'default_carousel': defaultCarousel,
    });
  }

  HomeDefaultCarouselSettingsEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? defaultCarousel,
  }) {
    return HomeDefaultCarouselSettingsEntriesCompanion(
      id: id ?? this.id,
      defaultCarousel: defaultCarousel ?? this.defaultCarousel,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (defaultCarousel.present) {
      map['default_carousel'] = Variable<String>(defaultCarousel.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HomeDefaultCarouselSettingsEntriesCompanion(')
          ..write('id: $id, ')
          ..write('defaultCarousel: $defaultCarousel')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $BookDisplaySettingsEntriesTable bookDisplaySettingsEntries =
      $BookDisplaySettingsEntriesTable(this);
  late final $BooksTable books = $BooksTable(this);
  late final $ReadingProgressEntriesTable readingProgressEntries =
      $ReadingProgressEntriesTable(this);
  late final $EpubReaderSettingsEntriesTable epubReaderSettingsEntries =
      $EpubReaderSettingsEntriesTable(this);
  late final $CollectionsTable collections = $CollectionsTable(this);
  late final $BookCollectionEntriesTable bookCollectionEntries =
      $BookCollectionEntriesTable(this);
  late final $BookmarksTable bookmarks = $BookmarksTable(this);
  late final $ReaderAnnotationsTable readerAnnotations =
      $ReaderAnnotationsTable(this);
  late final $AppConnectivitySettingsEntriesTable
  appConnectivitySettingsEntries = $AppConnectivitySettingsEntriesTable(this);
  late final $CatalogSourcesEntriesTable catalogSourcesEntries =
      $CatalogSourcesEntriesTable(this);
  late final $RemoteDownloadTasksTable remoteDownloadTasks =
      $RemoteDownloadTasksTable(this);
  late final $RemoteCacheSettingsEntriesTable remoteCacheSettingsEntries =
      $RemoteCacheSettingsEntriesTable(this);
  late final $HomeOnlineTabSettingsEntriesTable homeOnlineTabSettingsEntries =
      $HomeOnlineTabSettingsEntriesTable(this);
  late final $LibrarySectionSettingsEntriesTable librarySectionSettingsEntries =
      $LibrarySectionSettingsEntriesTable(this);
  late final $HomeDefaultCarouselSettingsEntriesTable
  homeDefaultCarouselSettingsEntries = $HomeDefaultCarouselSettingsEntriesTable(
    this,
  );
  late final Index bookCollectionEntriesCollectionId = Index(
    'book_collection_entries_collection_id',
    'CREATE INDEX book_collection_entries_collection_id ON book_collection_entries (collection_id)',
  );
  late final Index bookmarksBookId = Index(
    'bookmarks_book_id',
    'CREATE INDEX bookmarks_book_id ON bookmarks (book_id)',
  );
  late final Index bookmarksBookProgression = Index(
    'bookmarks_book_progression',
    'CREATE INDEX bookmarks_book_progression ON bookmarks (book_id, progression)',
  );
  late final Index readerAnnotationsBookId = Index(
    'reader_annotations_book_id',
    'CREATE INDEX reader_annotations_book_id ON reader_annotations (book_id)',
  );
  late final Index readerAnnotationsBookOrder = Index(
    'reader_annotations_book_order',
    'CREATE INDEX reader_annotations_book_order ON reader_annotations (book_id, total_progression, href, progression)',
  );
  late final BooksDao booksDao = BooksDao(this as AppDatabase);
  late final ReadingProgressDao readingProgressDao = ReadingProgressDao(
    this as AppDatabase,
  );
  late final EpubReaderSettingsDao epubReaderSettingsDao =
      EpubReaderSettingsDao(this as AppDatabase);
  late final CollectionsDao collectionsDao = CollectionsDao(
    this as AppDatabase,
  );
  late final BookmarksDao bookmarksDao = BookmarksDao(this as AppDatabase);
  late final AppConnectivitySettingsDao appConnectivitySettingsDao =
      AppConnectivitySettingsDao(this as AppDatabase);
  late final LibrarySectionSettingsDao librarySectionSettingsDao =
      LibrarySectionSettingsDao(this as AppDatabase);
  late final HomeDefaultCarouselSettingsDao homeDefaultCarouselSettingsDao =
      HomeDefaultCarouselSettingsDao(this as AppDatabase);
  late final RemoteCacheSettingsDao remoteCacheSettingsDao =
      RemoteCacheSettingsDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    bookDisplaySettingsEntries,
    books,
    readingProgressEntries,
    epubReaderSettingsEntries,
    collections,
    bookCollectionEntries,
    bookmarks,
    readerAnnotations,
    appConnectivitySettingsEntries,
    catalogSourcesEntries,
    remoteDownloadTasks,
    remoteCacheSettingsEntries,
    homeOnlineTabSettingsEntries,
    librarySectionSettingsEntries,
    homeDefaultCarouselSettingsEntries,
    bookCollectionEntriesCollectionId,
    bookmarksBookId,
    bookmarksBookProgression,
    readerAnnotationsBookId,
    readerAnnotationsBookOrder,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'books',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate('reading_progress_entries', kind: UpdateKind.delete),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'books',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('book_collection_entries', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'collections',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('book_collection_entries', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'books',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('bookmarks', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'books',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('reader_annotations', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$BookDisplaySettingsEntriesTableCreateCompanionBuilder =
    BookDisplaySettingsEntriesCompanion Function({
      Value<int> id,
      Value<String> layout,
    });
typedef $$BookDisplaySettingsEntriesTableUpdateCompanionBuilder =
    BookDisplaySettingsEntriesCompanion Function({
      Value<int> id,
      Value<String> layout,
    });

class $$BookDisplaySettingsEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $BookDisplaySettingsEntriesTable> {
  $$BookDisplaySettingsEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get layout => $composableBuilder(
    column: $table.layout,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BookDisplaySettingsEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $BookDisplaySettingsEntriesTable> {
  $$BookDisplaySettingsEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get layout => $composableBuilder(
    column: $table.layout,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BookDisplaySettingsEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $BookDisplaySettingsEntriesTable> {
  $$BookDisplaySettingsEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get layout =>
      $composableBuilder(column: $table.layout, builder: (column) => column);
}

class $$BookDisplaySettingsEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BookDisplaySettingsEntriesTable,
          BookDisplaySettingsEntry,
          $$BookDisplaySettingsEntriesTableFilterComposer,
          $$BookDisplaySettingsEntriesTableOrderingComposer,
          $$BookDisplaySettingsEntriesTableAnnotationComposer,
          $$BookDisplaySettingsEntriesTableCreateCompanionBuilder,
          $$BookDisplaySettingsEntriesTableUpdateCompanionBuilder,
          (
            BookDisplaySettingsEntry,
            BaseReferences<
              _$AppDatabase,
              $BookDisplaySettingsEntriesTable,
              BookDisplaySettingsEntry
            >,
          ),
          BookDisplaySettingsEntry,
          PrefetchHooks Function()
        > {
  $$BookDisplaySettingsEntriesTableTableManager(
    _$AppDatabase db,
    $BookDisplaySettingsEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookDisplaySettingsEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$BookDisplaySettingsEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$BookDisplaySettingsEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> layout = const Value.absent(),
              }) => BookDisplaySettingsEntriesCompanion(id: id, layout: layout),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> layout = const Value.absent(),
              }) => BookDisplaySettingsEntriesCompanion.insert(
                id: id,
                layout: layout,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BookDisplaySettingsEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BookDisplaySettingsEntriesTable,
      BookDisplaySettingsEntry,
      $$BookDisplaySettingsEntriesTableFilterComposer,
      $$BookDisplaySettingsEntriesTableOrderingComposer,
      $$BookDisplaySettingsEntriesTableAnnotationComposer,
      $$BookDisplaySettingsEntriesTableCreateCompanionBuilder,
      $$BookDisplaySettingsEntriesTableUpdateCompanionBuilder,
      (
        BookDisplaySettingsEntry,
        BaseReferences<
          _$AppDatabase,
          $BookDisplaySettingsEntriesTable,
          BookDisplaySettingsEntry
        >,
      ),
      BookDisplaySettingsEntry,
      PrefetchHooks Function()
    >;
typedef $$BooksTableCreateCompanionBuilder =
    BooksCompanion Function({
      required String id,
      required String title,
      Value<String?> sortTitle,
      Value<String?> author,
      Value<String?> description,
      required String filePath,
      Value<String?> originalFilePath,
      required String fileName,
      required String fileExtension,
      Value<String?> mediaType,
      Value<String?> coverPath,
      Value<String> coverProvenance,
      Value<String?> language,
      Value<String?> publisher,
      Value<String?> publishedDate,
      Value<String?> isbn,
      Value<int?> pageCount,
      required int fileSizeBytes,
      required DateTime dateAdded,
      Value<DateTime?> lastOpenedAt,
      Value<bool> isFavorite,
      Value<String?> authorsJson,
      Value<String?> contributorsJson,
      Value<String?> identifiersJson,
      Value<String?> subjectsJson,
      Value<String?> rights,
      Value<String?> seriesName,
      Value<double?> seriesIndex,
      Value<String?> edition,
      Value<String?> source,
      Value<String?> coverage,
      Value<String?> type,
      Value<String?> modifiedDate,
      Value<String?> catalogSourceId,
      Value<String?> remotePublicationId,
      Value<String?> remotePublicationLocation,
      Value<String?> remoteAcquisitionLocation,
      Value<String?> metadataOriginsJson,
      Value<String?> tocJson,
      Value<int> rowid,
    });
typedef $$BooksTableUpdateCompanionBuilder =
    BooksCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String?> sortTitle,
      Value<String?> author,
      Value<String?> description,
      Value<String> filePath,
      Value<String?> originalFilePath,
      Value<String> fileName,
      Value<String> fileExtension,
      Value<String?> mediaType,
      Value<String?> coverPath,
      Value<String> coverProvenance,
      Value<String?> language,
      Value<String?> publisher,
      Value<String?> publishedDate,
      Value<String?> isbn,
      Value<int?> pageCount,
      Value<int> fileSizeBytes,
      Value<DateTime> dateAdded,
      Value<DateTime?> lastOpenedAt,
      Value<bool> isFavorite,
      Value<String?> authorsJson,
      Value<String?> contributorsJson,
      Value<String?> identifiersJson,
      Value<String?> subjectsJson,
      Value<String?> rights,
      Value<String?> seriesName,
      Value<double?> seriesIndex,
      Value<String?> edition,
      Value<String?> source,
      Value<String?> coverage,
      Value<String?> type,
      Value<String?> modifiedDate,
      Value<String?> catalogSourceId,
      Value<String?> remotePublicationId,
      Value<String?> remotePublicationLocation,
      Value<String?> remoteAcquisitionLocation,
      Value<String?> metadataOriginsJson,
      Value<String?> tocJson,
      Value<int> rowid,
    });

final class $$BooksTableReferences
    extends BaseReferences<_$AppDatabase, $BooksTable, Book> {
  $$BooksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<
    $ReadingProgressEntriesTable,
    List<ReadingProgressEntry>
  >
  _readingProgressEntriesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.readingProgressEntries,
        aliasName: 'books__id__reading_progress_entries__book_id',
      );

  $$ReadingProgressEntriesTableProcessedTableManager
  get readingProgressEntriesRefs {
    final manager = $$ReadingProgressEntriesTableTableManager(
      $_db,
      $_db.readingProgressEntries,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _readingProgressEntriesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $BookCollectionEntriesTable,
    List<BookCollectionEntry>
  >
  _bookCollectionEntriesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.bookCollectionEntries,
        aliasName: 'books__id__book_collection_entries__book_id',
      );

  $$BookCollectionEntriesTableProcessedTableManager
  get bookCollectionEntriesRefs {
    final manager = $$BookCollectionEntriesTableTableManager(
      $_db,
      $_db.bookCollectionEntries,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _bookCollectionEntriesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$BookmarksTable, List<Bookmark>>
  _bookmarksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.bookmarks,
    aliasName: 'books__id__bookmarks__book_id',
  );

  $$BookmarksTableProcessedTableManager get bookmarksRefs {
    final manager = $$BookmarksTableTableManager(
      $_db,
      $_db.bookmarks,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_bookmarksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ReaderAnnotationsTable, List<ReaderAnnotation>>
  _readerAnnotationsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.readerAnnotations,
        aliasName: 'books__id__reader_annotations__book_id',
      );

  $$ReaderAnnotationsTableProcessedTableManager get readerAnnotationsRefs {
    final manager = $$ReaderAnnotationsTableTableManager(
      $_db,
      $_db.readerAnnotations,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _readerAnnotationsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$BooksTableFilterComposer extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sortTitle => $composableBuilder(
    column: $table.sortTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalFilePath => $composableBuilder(
    column: $table.originalFilePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileExtension => $composableBuilder(
    column: $table.fileExtension,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverProvenance => $composableBuilder(
    column: $table.coverProvenance,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publisher => $composableBuilder(
    column: $table.publisher,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publishedDate => $composableBuilder(
    column: $table.publishedDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get isbn => $composableBuilder(
    column: $table.isbn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSizeBytes => $composableBuilder(
    column: $table.fileSizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dateAdded => $composableBuilder(
    column: $table.dateAdded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastOpenedAt => $composableBuilder(
    column: $table.lastOpenedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorsJson => $composableBuilder(
    column: $table.authorsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contributorsJson => $composableBuilder(
    column: $table.contributorsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get identifiersJson => $composableBuilder(
    column: $table.identifiersJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subjectsJson => $composableBuilder(
    column: $table.subjectsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rights => $composableBuilder(
    column: $table.rights,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get seriesName => $composableBuilder(
    column: $table.seriesName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get seriesIndex => $composableBuilder(
    column: $table.seriesIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get edition => $composableBuilder(
    column: $table.edition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverage => $composableBuilder(
    column: $table.coverage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modifiedDate => $composableBuilder(
    column: $table.modifiedDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get catalogSourceId => $composableBuilder(
    column: $table.catalogSourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remotePublicationId => $composableBuilder(
    column: $table.remotePublicationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remotePublicationLocation => $composableBuilder(
    column: $table.remotePublicationLocation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteAcquisitionLocation => $composableBuilder(
    column: $table.remoteAcquisitionLocation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadataOriginsJson => $composableBuilder(
    column: $table.metadataOriginsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tocJson => $composableBuilder(
    column: $table.tocJson,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> readingProgressEntriesRefs(
    Expression<bool> Function($$ReadingProgressEntriesTableFilterComposer f) f,
  ) {
    final $$ReadingProgressEntriesTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.readingProgressEntries,
          getReferencedColumn: (t) => t.bookId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ReadingProgressEntriesTableFilterComposer(
                $db: $db,
                $table: $db.readingProgressEntries,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> bookCollectionEntriesRefs(
    Expression<bool> Function($$BookCollectionEntriesTableFilterComposer f) f,
  ) {
    final $$BookCollectionEntriesTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.bookCollectionEntries,
          getReferencedColumn: (t) => t.bookId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BookCollectionEntriesTableFilterComposer(
                $db: $db,
                $table: $db.bookCollectionEntries,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> bookmarksRefs(
    Expression<bool> Function($$BookmarksTableFilterComposer f) f,
  ) {
    final $$BookmarksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookmarks,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookmarksTableFilterComposer(
            $db: $db,
            $table: $db.bookmarks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> readerAnnotationsRefs(
    Expression<bool> Function($$ReaderAnnotationsTableFilterComposer f) f,
  ) {
    final $$ReaderAnnotationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.readerAnnotations,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReaderAnnotationsTableFilterComposer(
            $db: $db,
            $table: $db.readerAnnotations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BooksTableOrderingComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sortTitle => $composableBuilder(
    column: $table.sortTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalFilePath => $composableBuilder(
    column: $table.originalFilePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileExtension => $composableBuilder(
    column: $table.fileExtension,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverProvenance => $composableBuilder(
    column: $table.coverProvenance,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publisher => $composableBuilder(
    column: $table.publisher,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publishedDate => $composableBuilder(
    column: $table.publishedDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get isbn => $composableBuilder(
    column: $table.isbn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSizeBytes => $composableBuilder(
    column: $table.fileSizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dateAdded => $composableBuilder(
    column: $table.dateAdded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastOpenedAt => $composableBuilder(
    column: $table.lastOpenedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorsJson => $composableBuilder(
    column: $table.authorsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contributorsJson => $composableBuilder(
    column: $table.contributorsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get identifiersJson => $composableBuilder(
    column: $table.identifiersJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subjectsJson => $composableBuilder(
    column: $table.subjectsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rights => $composableBuilder(
    column: $table.rights,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get seriesName => $composableBuilder(
    column: $table.seriesName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get seriesIndex => $composableBuilder(
    column: $table.seriesIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get edition => $composableBuilder(
    column: $table.edition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverage => $composableBuilder(
    column: $table.coverage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modifiedDate => $composableBuilder(
    column: $table.modifiedDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get catalogSourceId => $composableBuilder(
    column: $table.catalogSourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remotePublicationId => $composableBuilder(
    column: $table.remotePublicationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remotePublicationLocation => $composableBuilder(
    column: $table.remotePublicationLocation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteAcquisitionLocation => $composableBuilder(
    column: $table.remoteAcquisitionLocation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadataOriginsJson => $composableBuilder(
    column: $table.metadataOriginsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tocJson => $composableBuilder(
    column: $table.tocJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BooksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get sortTitle =>
      $composableBuilder(column: $table.sortTitle, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<String> get originalFilePath => $composableBuilder(
    column: $table.originalFilePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get fileExtension => $composableBuilder(
    column: $table.fileExtension,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mediaType =>
      $composableBuilder(column: $table.mediaType, builder: (column) => column);

  GeneratedColumn<String> get coverPath =>
      $composableBuilder(column: $table.coverPath, builder: (column) => column);

  GeneratedColumn<String> get coverProvenance => $composableBuilder(
    column: $table.coverProvenance,
    builder: (column) => column,
  );

  GeneratedColumn<String> get language =>
      $composableBuilder(column: $table.language, builder: (column) => column);

  GeneratedColumn<String> get publisher =>
      $composableBuilder(column: $table.publisher, builder: (column) => column);

  GeneratedColumn<String> get publishedDate => $composableBuilder(
    column: $table.publishedDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get isbn =>
      $composableBuilder(column: $table.isbn, builder: (column) => column);

  GeneratedColumn<int> get pageCount =>
      $composableBuilder(column: $table.pageCount, builder: (column) => column);

  GeneratedColumn<int> get fileSizeBytes => $composableBuilder(
    column: $table.fileSizeBytes,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get dateAdded =>
      $composableBuilder(column: $table.dateAdded, builder: (column) => column);

  GeneratedColumn<DateTime> get lastOpenedAt => $composableBuilder(
    column: $table.lastOpenedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => column,
  );

  GeneratedColumn<String> get authorsJson => $composableBuilder(
    column: $table.authorsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contributorsJson => $composableBuilder(
    column: $table.contributorsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get identifiersJson => $composableBuilder(
    column: $table.identifiersJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get subjectsJson => $composableBuilder(
    column: $table.subjectsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rights =>
      $composableBuilder(column: $table.rights, builder: (column) => column);

  GeneratedColumn<String> get seriesName => $composableBuilder(
    column: $table.seriesName,
    builder: (column) => column,
  );

  GeneratedColumn<double> get seriesIndex => $composableBuilder(
    column: $table.seriesIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get edition =>
      $composableBuilder(column: $table.edition, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get coverage =>
      $composableBuilder(column: $table.coverage, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get modifiedDate => $composableBuilder(
    column: $table.modifiedDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get catalogSourceId => $composableBuilder(
    column: $table.catalogSourceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get remotePublicationId => $composableBuilder(
    column: $table.remotePublicationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get remotePublicationLocation => $composableBuilder(
    column: $table.remotePublicationLocation,
    builder: (column) => column,
  );

  GeneratedColumn<String> get remoteAcquisitionLocation => $composableBuilder(
    column: $table.remoteAcquisitionLocation,
    builder: (column) => column,
  );

  GeneratedColumn<String> get metadataOriginsJson => $composableBuilder(
    column: $table.metadataOriginsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tocJson =>
      $composableBuilder(column: $table.tocJson, builder: (column) => column);

  Expression<T> readingProgressEntriesRefs<T extends Object>(
    Expression<T> Function($$ReadingProgressEntriesTableAnnotationComposer a) f,
  ) {
    final $$ReadingProgressEntriesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.readingProgressEntries,
          getReferencedColumn: (t) => t.bookId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ReadingProgressEntriesTableAnnotationComposer(
                $db: $db,
                $table: $db.readingProgressEntries,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> bookCollectionEntriesRefs<T extends Object>(
    Expression<T> Function($$BookCollectionEntriesTableAnnotationComposer a) f,
  ) {
    final $$BookCollectionEntriesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.bookCollectionEntries,
          getReferencedColumn: (t) => t.bookId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BookCollectionEntriesTableAnnotationComposer(
                $db: $db,
                $table: $db.bookCollectionEntries,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> bookmarksRefs<T extends Object>(
    Expression<T> Function($$BookmarksTableAnnotationComposer a) f,
  ) {
    final $$BookmarksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookmarks,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookmarksTableAnnotationComposer(
            $db: $db,
            $table: $db.bookmarks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> readerAnnotationsRefs<T extends Object>(
    Expression<T> Function($$ReaderAnnotationsTableAnnotationComposer a) f,
  ) {
    final $$ReaderAnnotationsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.readerAnnotations,
          getReferencedColumn: (t) => t.bookId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ReaderAnnotationsTableAnnotationComposer(
                $db: $db,
                $table: $db.readerAnnotations,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$BooksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BooksTable,
          Book,
          $$BooksTableFilterComposer,
          $$BooksTableOrderingComposer,
          $$BooksTableAnnotationComposer,
          $$BooksTableCreateCompanionBuilder,
          $$BooksTableUpdateCompanionBuilder,
          (Book, $$BooksTableReferences),
          Book,
          PrefetchHooks Function({
            bool readingProgressEntriesRefs,
            bool bookCollectionEntriesRefs,
            bool bookmarksRefs,
            bool readerAnnotationsRefs,
          })
        > {
  $$BooksTableTableManager(_$AppDatabase db, $BooksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BooksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BooksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BooksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> sortTitle = const Value.absent(),
                Value<String?> author = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<String?> originalFilePath = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<String> fileExtension = const Value.absent(),
                Value<String?> mediaType = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<String> coverProvenance = const Value.absent(),
                Value<String?> language = const Value.absent(),
                Value<String?> publisher = const Value.absent(),
                Value<String?> publishedDate = const Value.absent(),
                Value<String?> isbn = const Value.absent(),
                Value<int?> pageCount = const Value.absent(),
                Value<int> fileSizeBytes = const Value.absent(),
                Value<DateTime> dateAdded = const Value.absent(),
                Value<DateTime?> lastOpenedAt = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<String?> authorsJson = const Value.absent(),
                Value<String?> contributorsJson = const Value.absent(),
                Value<String?> identifiersJson = const Value.absent(),
                Value<String?> subjectsJson = const Value.absent(),
                Value<String?> rights = const Value.absent(),
                Value<String?> seriesName = const Value.absent(),
                Value<double?> seriesIndex = const Value.absent(),
                Value<String?> edition = const Value.absent(),
                Value<String?> source = const Value.absent(),
                Value<String?> coverage = const Value.absent(),
                Value<String?> type = const Value.absent(),
                Value<String?> modifiedDate = const Value.absent(),
                Value<String?> catalogSourceId = const Value.absent(),
                Value<String?> remotePublicationId = const Value.absent(),
                Value<String?> remotePublicationLocation = const Value.absent(),
                Value<String?> remoteAcquisitionLocation = const Value.absent(),
                Value<String?> metadataOriginsJson = const Value.absent(),
                Value<String?> tocJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BooksCompanion(
                id: id,
                title: title,
                sortTitle: sortTitle,
                author: author,
                description: description,
                filePath: filePath,
                originalFilePath: originalFilePath,
                fileName: fileName,
                fileExtension: fileExtension,
                mediaType: mediaType,
                coverPath: coverPath,
                coverProvenance: coverProvenance,
                language: language,
                publisher: publisher,
                publishedDate: publishedDate,
                isbn: isbn,
                pageCount: pageCount,
                fileSizeBytes: fileSizeBytes,
                dateAdded: dateAdded,
                lastOpenedAt: lastOpenedAt,
                isFavorite: isFavorite,
                authorsJson: authorsJson,
                contributorsJson: contributorsJson,
                identifiersJson: identifiersJson,
                subjectsJson: subjectsJson,
                rights: rights,
                seriesName: seriesName,
                seriesIndex: seriesIndex,
                edition: edition,
                source: source,
                coverage: coverage,
                type: type,
                modifiedDate: modifiedDate,
                catalogSourceId: catalogSourceId,
                remotePublicationId: remotePublicationId,
                remotePublicationLocation: remotePublicationLocation,
                remoteAcquisitionLocation: remoteAcquisitionLocation,
                metadataOriginsJson: metadataOriginsJson,
                tocJson: tocJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<String?> sortTitle = const Value.absent(),
                Value<String?> author = const Value.absent(),
                Value<String?> description = const Value.absent(),
                required String filePath,
                Value<String?> originalFilePath = const Value.absent(),
                required String fileName,
                required String fileExtension,
                Value<String?> mediaType = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<String> coverProvenance = const Value.absent(),
                Value<String?> language = const Value.absent(),
                Value<String?> publisher = const Value.absent(),
                Value<String?> publishedDate = const Value.absent(),
                Value<String?> isbn = const Value.absent(),
                Value<int?> pageCount = const Value.absent(),
                required int fileSizeBytes,
                required DateTime dateAdded,
                Value<DateTime?> lastOpenedAt = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<String?> authorsJson = const Value.absent(),
                Value<String?> contributorsJson = const Value.absent(),
                Value<String?> identifiersJson = const Value.absent(),
                Value<String?> subjectsJson = const Value.absent(),
                Value<String?> rights = const Value.absent(),
                Value<String?> seriesName = const Value.absent(),
                Value<double?> seriesIndex = const Value.absent(),
                Value<String?> edition = const Value.absent(),
                Value<String?> source = const Value.absent(),
                Value<String?> coverage = const Value.absent(),
                Value<String?> type = const Value.absent(),
                Value<String?> modifiedDate = const Value.absent(),
                Value<String?> catalogSourceId = const Value.absent(),
                Value<String?> remotePublicationId = const Value.absent(),
                Value<String?> remotePublicationLocation = const Value.absent(),
                Value<String?> remoteAcquisitionLocation = const Value.absent(),
                Value<String?> metadataOriginsJson = const Value.absent(),
                Value<String?> tocJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BooksCompanion.insert(
                id: id,
                title: title,
                sortTitle: sortTitle,
                author: author,
                description: description,
                filePath: filePath,
                originalFilePath: originalFilePath,
                fileName: fileName,
                fileExtension: fileExtension,
                mediaType: mediaType,
                coverPath: coverPath,
                coverProvenance: coverProvenance,
                language: language,
                publisher: publisher,
                publishedDate: publishedDate,
                isbn: isbn,
                pageCount: pageCount,
                fileSizeBytes: fileSizeBytes,
                dateAdded: dateAdded,
                lastOpenedAt: lastOpenedAt,
                isFavorite: isFavorite,
                authorsJson: authorsJson,
                contributorsJson: contributorsJson,
                identifiersJson: identifiersJson,
                subjectsJson: subjectsJson,
                rights: rights,
                seriesName: seriesName,
                seriesIndex: seriesIndex,
                edition: edition,
                source: source,
                coverage: coverage,
                type: type,
                modifiedDate: modifiedDate,
                catalogSourceId: catalogSourceId,
                remotePublicationId: remotePublicationId,
                remotePublicationLocation: remotePublicationLocation,
                remoteAcquisitionLocation: remoteAcquisitionLocation,
                metadataOriginsJson: metadataOriginsJson,
                tocJson: tocJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$BooksTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                readingProgressEntriesRefs = false,
                bookCollectionEntriesRefs = false,
                bookmarksRefs = false,
                readerAnnotationsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (readingProgressEntriesRefs) db.readingProgressEntries,
                    if (bookCollectionEntriesRefs) db.bookCollectionEntries,
                    if (bookmarksRefs) db.bookmarks,
                    if (readerAnnotationsRefs) db.readerAnnotations,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (readingProgressEntriesRefs)
                        await $_getPrefetchedData<
                          Book,
                          $BooksTable,
                          ReadingProgressEntry
                        >(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._readingProgressEntriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).readingProgressEntriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (bookCollectionEntriesRefs)
                        await $_getPrefetchedData<
                          Book,
                          $BooksTable,
                          BookCollectionEntry
                        >(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._bookCollectionEntriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).bookCollectionEntriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (bookmarksRefs)
                        await $_getPrefetchedData<Book, $BooksTable, Bookmark>(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._bookmarksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).bookmarksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (readerAnnotationsRefs)
                        await $_getPrefetchedData<
                          Book,
                          $BooksTable,
                          ReaderAnnotation
                        >(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._readerAnnotationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).readerAnnotationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$BooksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BooksTable,
      Book,
      $$BooksTableFilterComposer,
      $$BooksTableOrderingComposer,
      $$BooksTableAnnotationComposer,
      $$BooksTableCreateCompanionBuilder,
      $$BooksTableUpdateCompanionBuilder,
      (Book, $$BooksTableReferences),
      Book,
      PrefetchHooks Function({
        bool readingProgressEntriesRefs,
        bool bookCollectionEntriesRefs,
        bool bookmarksRefs,
        bool readerAnnotationsRefs,
      })
    >;
typedef $$ReadingProgressEntriesTableCreateCompanionBuilder =
    ReadingProgressEntriesCompanion Function({
      required String bookId,
      Value<String?> locatorJson,
      Value<double> progression,
      Value<String?> currentChapterTitle,
      Value<int?> currentPage,
      Value<int?> totalPages,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ReadingProgressEntriesTableUpdateCompanionBuilder =
    ReadingProgressEntriesCompanion Function({
      Value<String> bookId,
      Value<String?> locatorJson,
      Value<double> progression,
      Value<String?> currentChapterTitle,
      Value<int?> currentPage,
      Value<int?> totalPages,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ReadingProgressEntriesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ReadingProgressEntriesTable,
          ReadingProgressEntry
        > {
  $$ReadingProgressEntriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BooksTable _bookIdTable(_$AppDatabase db) =>
      db.books.createAlias('reading_progress_entries__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReadingProgressEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $ReadingProgressEntriesTable> {
  $$ReadingProgressEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get locatorJson => $composableBuilder(
    column: $table.locatorJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progression => $composableBuilder(
    column: $table.progression,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentChapterTitle => $composableBuilder(
    column: $table.currentChapterTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get currentPage => $composableBuilder(
    column: $table.currentPage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalPages => $composableBuilder(
    column: $table.totalPages,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingProgressEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $ReadingProgressEntriesTable> {
  $$ReadingProgressEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get locatorJson => $composableBuilder(
    column: $table.locatorJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progression => $composableBuilder(
    column: $table.progression,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentChapterTitle => $composableBuilder(
    column: $table.currentChapterTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get currentPage => $composableBuilder(
    column: $table.currentPage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalPages => $composableBuilder(
    column: $table.totalPages,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingProgressEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReadingProgressEntriesTable> {
  $$ReadingProgressEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get locatorJson => $composableBuilder(
    column: $table.locatorJson,
    builder: (column) => column,
  );

  GeneratedColumn<double> get progression => $composableBuilder(
    column: $table.progression,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currentChapterTitle => $composableBuilder(
    column: $table.currentChapterTitle,
    builder: (column) => column,
  );

  GeneratedColumn<int> get currentPage => $composableBuilder(
    column: $table.currentPage,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalPages => $composableBuilder(
    column: $table.totalPages,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingProgressEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReadingProgressEntriesTable,
          ReadingProgressEntry,
          $$ReadingProgressEntriesTableFilterComposer,
          $$ReadingProgressEntriesTableOrderingComposer,
          $$ReadingProgressEntriesTableAnnotationComposer,
          $$ReadingProgressEntriesTableCreateCompanionBuilder,
          $$ReadingProgressEntriesTableUpdateCompanionBuilder,
          (ReadingProgressEntry, $$ReadingProgressEntriesTableReferences),
          ReadingProgressEntry,
          PrefetchHooks Function({bool bookId})
        > {
  $$ReadingProgressEntriesTableTableManager(
    _$AppDatabase db,
    $ReadingProgressEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReadingProgressEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ReadingProgressEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ReadingProgressEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> bookId = const Value.absent(),
                Value<String?> locatorJson = const Value.absent(),
                Value<double> progression = const Value.absent(),
                Value<String?> currentChapterTitle = const Value.absent(),
                Value<int?> currentPage = const Value.absent(),
                Value<int?> totalPages = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReadingProgressEntriesCompanion(
                bookId: bookId,
                locatorJson: locatorJson,
                progression: progression,
                currentChapterTitle: currentChapterTitle,
                currentPage: currentPage,
                totalPages: totalPages,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookId,
                Value<String?> locatorJson = const Value.absent(),
                Value<double> progression = const Value.absent(),
                Value<String?> currentChapterTitle = const Value.absent(),
                Value<int?> currentPage = const Value.absent(),
                Value<int?> totalPages = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ReadingProgressEntriesCompanion.insert(
                bookId: bookId,
                locatorJson: locatorJson,
                progression: progression,
                currentChapterTitle: currentChapterTitle,
                currentPage: currentPage,
                totalPages: totalPages,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ReadingProgressEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bookId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.bookId,
                                referencedTable:
                                    $$ReadingProgressEntriesTableReferences
                                        ._bookIdTable(db),
                                referencedColumn:
                                    $$ReadingProgressEntriesTableReferences
                                        ._bookIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ReadingProgressEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReadingProgressEntriesTable,
      ReadingProgressEntry,
      $$ReadingProgressEntriesTableFilterComposer,
      $$ReadingProgressEntriesTableOrderingComposer,
      $$ReadingProgressEntriesTableAnnotationComposer,
      $$ReadingProgressEntriesTableCreateCompanionBuilder,
      $$ReadingProgressEntriesTableUpdateCompanionBuilder,
      (ReadingProgressEntry, $$ReadingProgressEntriesTableReferences),
      ReadingProgressEntry,
      PrefetchHooks Function({bool bookId})
    >;
typedef $$EpubReaderSettingsEntriesTableCreateCompanionBuilder =
    EpubReaderSettingsEntriesCompanion Function({
      Value<int> id,
      required String theme,
      required double fontSize,
      required double lineHeight,
      required double pageMargins,
      required bool publisherStyles,
      required DateTime updatedAt,
    });
typedef $$EpubReaderSettingsEntriesTableUpdateCompanionBuilder =
    EpubReaderSettingsEntriesCompanion Function({
      Value<int> id,
      Value<String> theme,
      Value<double> fontSize,
      Value<double> lineHeight,
      Value<double> pageMargins,
      Value<bool> publisherStyles,
      Value<DateTime> updatedAt,
    });

class $$EpubReaderSettingsEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $EpubReaderSettingsEntriesTable> {
  $$EpubReaderSettingsEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get theme => $composableBuilder(
    column: $table.theme,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get fontSize => $composableBuilder(
    column: $table.fontSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lineHeight => $composableBuilder(
    column: $table.lineHeight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pageMargins => $composableBuilder(
    column: $table.pageMargins,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get publisherStyles => $composableBuilder(
    column: $table.publisherStyles,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EpubReaderSettingsEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $EpubReaderSettingsEntriesTable> {
  $$EpubReaderSettingsEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get theme => $composableBuilder(
    column: $table.theme,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get fontSize => $composableBuilder(
    column: $table.fontSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lineHeight => $composableBuilder(
    column: $table.lineHeight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pageMargins => $composableBuilder(
    column: $table.pageMargins,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get publisherStyles => $composableBuilder(
    column: $table.publisherStyles,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EpubReaderSettingsEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $EpubReaderSettingsEntriesTable> {
  $$EpubReaderSettingsEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get theme =>
      $composableBuilder(column: $table.theme, builder: (column) => column);

  GeneratedColumn<double> get fontSize =>
      $composableBuilder(column: $table.fontSize, builder: (column) => column);

  GeneratedColumn<double> get lineHeight => $composableBuilder(
    column: $table.lineHeight,
    builder: (column) => column,
  );

  GeneratedColumn<double> get pageMargins => $composableBuilder(
    column: $table.pageMargins,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get publisherStyles => $composableBuilder(
    column: $table.publisherStyles,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$EpubReaderSettingsEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EpubReaderSettingsEntriesTable,
          EpubReaderSettingsEntry,
          $$EpubReaderSettingsEntriesTableFilterComposer,
          $$EpubReaderSettingsEntriesTableOrderingComposer,
          $$EpubReaderSettingsEntriesTableAnnotationComposer,
          $$EpubReaderSettingsEntriesTableCreateCompanionBuilder,
          $$EpubReaderSettingsEntriesTableUpdateCompanionBuilder,
          (
            EpubReaderSettingsEntry,
            BaseReferences<
              _$AppDatabase,
              $EpubReaderSettingsEntriesTable,
              EpubReaderSettingsEntry
            >,
          ),
          EpubReaderSettingsEntry,
          PrefetchHooks Function()
        > {
  $$EpubReaderSettingsEntriesTableTableManager(
    _$AppDatabase db,
    $EpubReaderSettingsEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EpubReaderSettingsEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$EpubReaderSettingsEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$EpubReaderSettingsEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> theme = const Value.absent(),
                Value<double> fontSize = const Value.absent(),
                Value<double> lineHeight = const Value.absent(),
                Value<double> pageMargins = const Value.absent(),
                Value<bool> publisherStyles = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => EpubReaderSettingsEntriesCompanion(
                id: id,
                theme: theme,
                fontSize: fontSize,
                lineHeight: lineHeight,
                pageMargins: pageMargins,
                publisherStyles: publisherStyles,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String theme,
                required double fontSize,
                required double lineHeight,
                required double pageMargins,
                required bool publisherStyles,
                required DateTime updatedAt,
              }) => EpubReaderSettingsEntriesCompanion.insert(
                id: id,
                theme: theme,
                fontSize: fontSize,
                lineHeight: lineHeight,
                pageMargins: pageMargins,
                publisherStyles: publisherStyles,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EpubReaderSettingsEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EpubReaderSettingsEntriesTable,
      EpubReaderSettingsEntry,
      $$EpubReaderSettingsEntriesTableFilterComposer,
      $$EpubReaderSettingsEntriesTableOrderingComposer,
      $$EpubReaderSettingsEntriesTableAnnotationComposer,
      $$EpubReaderSettingsEntriesTableCreateCompanionBuilder,
      $$EpubReaderSettingsEntriesTableUpdateCompanionBuilder,
      (
        EpubReaderSettingsEntry,
        BaseReferences<
          _$AppDatabase,
          $EpubReaderSettingsEntriesTable,
          EpubReaderSettingsEntry
        >,
      ),
      EpubReaderSettingsEntry,
      PrefetchHooks Function()
    >;
typedef $$CollectionsTableCreateCompanionBuilder =
    CollectionsCompanion Function({
      required String id,
      required String name,
      required String normalizedName,
      Value<String?> description,
      Value<String?> customCoverPath,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int?> sortOrder,
      Value<int> rowid,
    });
typedef $$CollectionsTableUpdateCompanionBuilder =
    CollectionsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> normalizedName,
      Value<String?> description,
      Value<String?> customCoverPath,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int?> sortOrder,
      Value<int> rowid,
    });

final class $$CollectionsTableReferences
    extends BaseReferences<_$AppDatabase, $CollectionsTable, Collection> {
  $$CollectionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<
    $BookCollectionEntriesTable,
    List<BookCollectionEntry>
  >
  _bookCollectionEntriesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.bookCollectionEntries,
        aliasName: 'collections__id__book_collection_entries__collection_id',
      );

  $$BookCollectionEntriesTableProcessedTableManager
  get bookCollectionEntriesRefs {
    final manager = $$BookCollectionEntriesTableTableManager(
      $_db,
      $_db.bookCollectionEntries,
    ).filter((f) => f.collectionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _bookCollectionEntriesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CollectionsTableFilterComposer
    extends Composer<_$AppDatabase, $CollectionsTable> {
  $$CollectionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customCoverPath => $composableBuilder(
    column: $table.customCoverPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> bookCollectionEntriesRefs(
    Expression<bool> Function($$BookCollectionEntriesTableFilterComposer f) f,
  ) {
    final $$BookCollectionEntriesTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.bookCollectionEntries,
          getReferencedColumn: (t) => t.collectionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BookCollectionEntriesTableFilterComposer(
                $db: $db,
                $table: $db.bookCollectionEntries,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$CollectionsTableOrderingComposer
    extends Composer<_$AppDatabase, $CollectionsTable> {
  $$CollectionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customCoverPath => $composableBuilder(
    column: $table.customCoverPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CollectionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CollectionsTable> {
  $$CollectionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get normalizedName => $composableBuilder(
    column: $table.normalizedName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get customCoverPath => $composableBuilder(
    column: $table.customCoverPath,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  Expression<T> bookCollectionEntriesRefs<T extends Object>(
    Expression<T> Function($$BookCollectionEntriesTableAnnotationComposer a) f,
  ) {
    final $$BookCollectionEntriesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.bookCollectionEntries,
          getReferencedColumn: (t) => t.collectionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$BookCollectionEntriesTableAnnotationComposer(
                $db: $db,
                $table: $db.bookCollectionEntries,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$CollectionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CollectionsTable,
          Collection,
          $$CollectionsTableFilterComposer,
          $$CollectionsTableOrderingComposer,
          $$CollectionsTableAnnotationComposer,
          $$CollectionsTableCreateCompanionBuilder,
          $$CollectionsTableUpdateCompanionBuilder,
          (Collection, $$CollectionsTableReferences),
          Collection,
          PrefetchHooks Function({bool bookCollectionEntriesRefs})
        > {
  $$CollectionsTableTableManager(_$AppDatabase db, $CollectionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CollectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CollectionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CollectionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> normalizedName = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> customCoverPath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int?> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CollectionsCompanion(
                id: id,
                name: name,
                normalizedName: normalizedName,
                description: description,
                customCoverPath: customCoverPath,
                createdAt: createdAt,
                updatedAt: updatedAt,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String normalizedName,
                Value<String?> description = const Value.absent(),
                Value<String?> customCoverPath = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int?> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CollectionsCompanion.insert(
                id: id,
                name: name,
                normalizedName: normalizedName,
                description: description,
                customCoverPath: customCoverPath,
                createdAt: createdAt,
                updatedAt: updatedAt,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CollectionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookCollectionEntriesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (bookCollectionEntriesRefs) db.bookCollectionEntries,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (bookCollectionEntriesRefs)
                    await $_getPrefetchedData<
                      Collection,
                      $CollectionsTable,
                      BookCollectionEntry
                    >(
                      currentTable: table,
                      referencedTable: $$CollectionsTableReferences
                          ._bookCollectionEntriesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$CollectionsTableReferences(
                            db,
                            table,
                            p0,
                          ).bookCollectionEntriesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.collectionId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$CollectionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CollectionsTable,
      Collection,
      $$CollectionsTableFilterComposer,
      $$CollectionsTableOrderingComposer,
      $$CollectionsTableAnnotationComposer,
      $$CollectionsTableCreateCompanionBuilder,
      $$CollectionsTableUpdateCompanionBuilder,
      (Collection, $$CollectionsTableReferences),
      Collection,
      PrefetchHooks Function({bool bookCollectionEntriesRefs})
    >;
typedef $$BookCollectionEntriesTableCreateCompanionBuilder =
    BookCollectionEntriesCompanion Function({
      required String bookId,
      required String collectionId,
      required DateTime addedAt,
      Value<int> rowid,
    });
typedef $$BookCollectionEntriesTableUpdateCompanionBuilder =
    BookCollectionEntriesCompanion Function({
      Value<String> bookId,
      Value<String> collectionId,
      Value<DateTime> addedAt,
      Value<int> rowid,
    });

final class $$BookCollectionEntriesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $BookCollectionEntriesTable,
          BookCollectionEntry
        > {
  $$BookCollectionEntriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BooksTable _bookIdTable(_$AppDatabase db) =>
      db.books.createAlias('book_collection_entries__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $CollectionsTable _collectionIdTable(_$AppDatabase db) => db
      .collections
      .createAlias('book_collection_entries__collection_id__collections__id');

  $$CollectionsTableProcessedTableManager get collectionId {
    final $_column = $_itemColumn<String>('collection_id')!;

    final manager = $$CollectionsTableTableManager(
      $_db,
      $_db.collections,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_collectionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$BookCollectionEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $BookCollectionEntriesTable> {
  $$BookCollectionEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CollectionsTableFilterComposer get collectionId {
    final $$CollectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableFilterComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookCollectionEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $BookCollectionEntriesTable> {
  $$BookCollectionEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CollectionsTableOrderingComposer get collectionId {
    final $$CollectionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableOrderingComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookCollectionEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $BookCollectionEntriesTable> {
  $$BookCollectionEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CollectionsTableAnnotationComposer get collectionId {
    final $$CollectionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.collectionId,
      referencedTable: $db.collections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CollectionsTableAnnotationComposer(
            $db: $db,
            $table: $db.collections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookCollectionEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BookCollectionEntriesTable,
          BookCollectionEntry,
          $$BookCollectionEntriesTableFilterComposer,
          $$BookCollectionEntriesTableOrderingComposer,
          $$BookCollectionEntriesTableAnnotationComposer,
          $$BookCollectionEntriesTableCreateCompanionBuilder,
          $$BookCollectionEntriesTableUpdateCompanionBuilder,
          (BookCollectionEntry, $$BookCollectionEntriesTableReferences),
          BookCollectionEntry,
          PrefetchHooks Function({bool bookId, bool collectionId})
        > {
  $$BookCollectionEntriesTableTableManager(
    _$AppDatabase db,
    $BookCollectionEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookCollectionEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$BookCollectionEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$BookCollectionEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> bookId = const Value.absent(),
                Value<String> collectionId = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookCollectionEntriesCompanion(
                bookId: bookId,
                collectionId: collectionId,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookId,
                required String collectionId,
                required DateTime addedAt,
                Value<int> rowid = const Value.absent(),
              }) => BookCollectionEntriesCompanion.insert(
                bookId: bookId,
                collectionId: collectionId,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$BookCollectionEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false, collectionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bookId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.bookId,
                                referencedTable:
                                    $$BookCollectionEntriesTableReferences
                                        ._bookIdTable(db),
                                referencedColumn:
                                    $$BookCollectionEntriesTableReferences
                                        ._bookIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (collectionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.collectionId,
                                referencedTable:
                                    $$BookCollectionEntriesTableReferences
                                        ._collectionIdTable(db),
                                referencedColumn:
                                    $$BookCollectionEntriesTableReferences
                                        ._collectionIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$BookCollectionEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BookCollectionEntriesTable,
      BookCollectionEntry,
      $$BookCollectionEntriesTableFilterComposer,
      $$BookCollectionEntriesTableOrderingComposer,
      $$BookCollectionEntriesTableAnnotationComposer,
      $$BookCollectionEntriesTableCreateCompanionBuilder,
      $$BookCollectionEntriesTableUpdateCompanionBuilder,
      (BookCollectionEntry, $$BookCollectionEntriesTableReferences),
      BookCollectionEntry,
      PrefetchHooks Function({bool bookId, bool collectionId})
    >;
typedef $$BookmarksTableCreateCompanionBuilder =
    BookmarksCompanion Function({
      required String id,
      required String bookId,
      required String locatorJson,
      Value<String?> href,
      Value<double?> progression,
      Value<int?> position,
      Value<String?> chapterTitle,
      Value<String?> title,
      Value<String?> note,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$BookmarksTableUpdateCompanionBuilder =
    BookmarksCompanion Function({
      Value<String> id,
      Value<String> bookId,
      Value<String> locatorJson,
      Value<String?> href,
      Value<double?> progression,
      Value<int?> position,
      Value<String?> chapterTitle,
      Value<String?> title,
      Value<String?> note,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$BookmarksTableReferences
    extends BaseReferences<_$AppDatabase, $BookmarksTable, Bookmark> {
  $$BookmarksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BooksTable _bookIdTable(_$AppDatabase db) =>
      db.books.createAlias('bookmarks__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$BookmarksTableFilterComposer
    extends Composer<_$AppDatabase, $BookmarksTable> {
  $$BookmarksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locatorJson => $composableBuilder(
    column: $table.locatorJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get href => $composableBuilder(
    column: $table.href,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progression => $composableBuilder(
    column: $table.progression,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookmarksTableOrderingComposer
    extends Composer<_$AppDatabase, $BookmarksTable> {
  $$BookmarksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locatorJson => $composableBuilder(
    column: $table.locatorJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get href => $composableBuilder(
    column: $table.href,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progression => $composableBuilder(
    column: $table.progression,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookmarksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BookmarksTable> {
  $$BookmarksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get locatorJson => $composableBuilder(
    column: $table.locatorJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get href =>
      $composableBuilder(column: $table.href, builder: (column) => column);

  GeneratedColumn<double> get progression => $composableBuilder(
    column: $table.progression,
    builder: (column) => column,
  );

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookmarksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BookmarksTable,
          Bookmark,
          $$BookmarksTableFilterComposer,
          $$BookmarksTableOrderingComposer,
          $$BookmarksTableAnnotationComposer,
          $$BookmarksTableCreateCompanionBuilder,
          $$BookmarksTableUpdateCompanionBuilder,
          (Bookmark, $$BookmarksTableReferences),
          Bookmark,
          PrefetchHooks Function({bool bookId})
        > {
  $$BookmarksTableTableManager(_$AppDatabase db, $BookmarksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookmarksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookmarksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookmarksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<String> locatorJson = const Value.absent(),
                Value<String?> href = const Value.absent(),
                Value<double?> progression = const Value.absent(),
                Value<int?> position = const Value.absent(),
                Value<String?> chapterTitle = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookmarksCompanion(
                id: id,
                bookId: bookId,
                locatorJson: locatorJson,
                href: href,
                progression: progression,
                position: position,
                chapterTitle: chapterTitle,
                title: title,
                note: note,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String bookId,
                required String locatorJson,
                Value<String?> href = const Value.absent(),
                Value<double?> progression = const Value.absent(),
                Value<int?> position = const Value.absent(),
                Value<String?> chapterTitle = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> note = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => BookmarksCompanion.insert(
                id: id,
                bookId: bookId,
                locatorJson: locatorJson,
                href: href,
                progression: progression,
                position: position,
                chapterTitle: chapterTitle,
                title: title,
                note: note,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$BookmarksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bookId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.bookId,
                                referencedTable: $$BookmarksTableReferences
                                    ._bookIdTable(db),
                                referencedColumn: $$BookmarksTableReferences
                                    ._bookIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$BookmarksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BookmarksTable,
      Bookmark,
      $$BookmarksTableFilterComposer,
      $$BookmarksTableOrderingComposer,
      $$BookmarksTableAnnotationComposer,
      $$BookmarksTableCreateCompanionBuilder,
      $$BookmarksTableUpdateCompanionBuilder,
      (Bookmark, $$BookmarksTableReferences),
      Bookmark,
      PrefetchHooks Function({bool bookId})
    >;
typedef $$ReaderAnnotationsTableCreateCompanionBuilder =
    ReaderAnnotationsCompanion Function({
      required String id,
      required String bookId,
      required String locatorJson,
      required String locationKey,
      required String selectedText,
      Value<String?> textBefore,
      Value<String?> textAfter,
      Value<String?> note,
      Value<String> style,
      Value<String> color,
      required String href,
      Value<double?> progression,
      Value<double?> totalProgression,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ReaderAnnotationsTableUpdateCompanionBuilder =
    ReaderAnnotationsCompanion Function({
      Value<String> id,
      Value<String> bookId,
      Value<String> locatorJson,
      Value<String> locationKey,
      Value<String> selectedText,
      Value<String?> textBefore,
      Value<String?> textAfter,
      Value<String?> note,
      Value<String> style,
      Value<String> color,
      Value<String> href,
      Value<double?> progression,
      Value<double?> totalProgression,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ReaderAnnotationsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ReaderAnnotationsTable,
          ReaderAnnotation
        > {
  $$ReaderAnnotationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BooksTable _bookIdTable(_$AppDatabase db) =>
      db.books.createAlias('reader_annotations__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReaderAnnotationsTableFilterComposer
    extends Composer<_$AppDatabase, $ReaderAnnotationsTable> {
  $$ReaderAnnotationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locatorJson => $composableBuilder(
    column: $table.locatorJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locationKey => $composableBuilder(
    column: $table.locationKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get selectedText => $composableBuilder(
    column: $table.selectedText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get textBefore => $composableBuilder(
    column: $table.textBefore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get textAfter => $composableBuilder(
    column: $table.textAfter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get style => $composableBuilder(
    column: $table.style,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get href => $composableBuilder(
    column: $table.href,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progression => $composableBuilder(
    column: $table.progression,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get totalProgression => $composableBuilder(
    column: $table.totalProgression,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReaderAnnotationsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReaderAnnotationsTable> {
  $$ReaderAnnotationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locatorJson => $composableBuilder(
    column: $table.locatorJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locationKey => $composableBuilder(
    column: $table.locationKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get selectedText => $composableBuilder(
    column: $table.selectedText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get textBefore => $composableBuilder(
    column: $table.textBefore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get textAfter => $composableBuilder(
    column: $table.textAfter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get style => $composableBuilder(
    column: $table.style,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get href => $composableBuilder(
    column: $table.href,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progression => $composableBuilder(
    column: $table.progression,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get totalProgression => $composableBuilder(
    column: $table.totalProgression,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReaderAnnotationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReaderAnnotationsTable> {
  $$ReaderAnnotationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get locatorJson => $composableBuilder(
    column: $table.locatorJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get locationKey => $composableBuilder(
    column: $table.locationKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get selectedText => $composableBuilder(
    column: $table.selectedText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get textBefore => $composableBuilder(
    column: $table.textBefore,
    builder: (column) => column,
  );

  GeneratedColumn<String> get textAfter =>
      $composableBuilder(column: $table.textAfter, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get style =>
      $composableBuilder(column: $table.style, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<String> get href =>
      $composableBuilder(column: $table.href, builder: (column) => column);

  GeneratedColumn<double> get progression => $composableBuilder(
    column: $table.progression,
    builder: (column) => column,
  );

  GeneratedColumn<double> get totalProgression => $composableBuilder(
    column: $table.totalProgression,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReaderAnnotationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReaderAnnotationsTable,
          ReaderAnnotation,
          $$ReaderAnnotationsTableFilterComposer,
          $$ReaderAnnotationsTableOrderingComposer,
          $$ReaderAnnotationsTableAnnotationComposer,
          $$ReaderAnnotationsTableCreateCompanionBuilder,
          $$ReaderAnnotationsTableUpdateCompanionBuilder,
          (ReaderAnnotation, $$ReaderAnnotationsTableReferences),
          ReaderAnnotation,
          PrefetchHooks Function({bool bookId})
        > {
  $$ReaderAnnotationsTableTableManager(
    _$AppDatabase db,
    $ReaderAnnotationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReaderAnnotationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReaderAnnotationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReaderAnnotationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<String> locatorJson = const Value.absent(),
                Value<String> locationKey = const Value.absent(),
                Value<String> selectedText = const Value.absent(),
                Value<String?> textBefore = const Value.absent(),
                Value<String?> textAfter = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String> style = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<String> href = const Value.absent(),
                Value<double?> progression = const Value.absent(),
                Value<double?> totalProgression = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReaderAnnotationsCompanion(
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
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String bookId,
                required String locatorJson,
                required String locationKey,
                required String selectedText,
                Value<String?> textBefore = const Value.absent(),
                Value<String?> textAfter = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String> style = const Value.absent(),
                Value<String> color = const Value.absent(),
                required String href,
                Value<double?> progression = const Value.absent(),
                Value<double?> totalProgression = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ReaderAnnotationsCompanion.insert(
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
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ReaderAnnotationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bookId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.bookId,
                                referencedTable:
                                    $$ReaderAnnotationsTableReferences
                                        ._bookIdTable(db),
                                referencedColumn:
                                    $$ReaderAnnotationsTableReferences
                                        ._bookIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ReaderAnnotationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReaderAnnotationsTable,
      ReaderAnnotation,
      $$ReaderAnnotationsTableFilterComposer,
      $$ReaderAnnotationsTableOrderingComposer,
      $$ReaderAnnotationsTableAnnotationComposer,
      $$ReaderAnnotationsTableCreateCompanionBuilder,
      $$ReaderAnnotationsTableUpdateCompanionBuilder,
      (ReaderAnnotation, $$ReaderAnnotationsTableReferences),
      ReaderAnnotation,
      PrefetchHooks Function({bool bookId})
    >;
typedef $$AppConnectivitySettingsEntriesTableCreateCompanionBuilder =
    AppConnectivitySettingsEntriesCompanion Function({
      Value<int> id,
      required String mode,
      required bool hasAcknowledgedOnline,
    });
typedef $$AppConnectivitySettingsEntriesTableUpdateCompanionBuilder =
    AppConnectivitySettingsEntriesCompanion Function({
      Value<int> id,
      Value<String> mode,
      Value<bool> hasAcknowledgedOnline,
    });

class $$AppConnectivitySettingsEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $AppConnectivitySettingsEntriesTable> {
  $$AppConnectivitySettingsEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasAcknowledgedOnline => $composableBuilder(
    column: $table.hasAcknowledgedOnline,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppConnectivitySettingsEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $AppConnectivitySettingsEntriesTable> {
  $$AppConnectivitySettingsEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasAcknowledgedOnline => $composableBuilder(
    column: $table.hasAcknowledgedOnline,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppConnectivitySettingsEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppConnectivitySettingsEntriesTable> {
  $$AppConnectivitySettingsEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<bool> get hasAcknowledgedOnline => $composableBuilder(
    column: $table.hasAcknowledgedOnline,
    builder: (column) => column,
  );
}

class $$AppConnectivitySettingsEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppConnectivitySettingsEntriesTable,
          AppConnectivitySettingsEntry,
          $$AppConnectivitySettingsEntriesTableFilterComposer,
          $$AppConnectivitySettingsEntriesTableOrderingComposer,
          $$AppConnectivitySettingsEntriesTableAnnotationComposer,
          $$AppConnectivitySettingsEntriesTableCreateCompanionBuilder,
          $$AppConnectivitySettingsEntriesTableUpdateCompanionBuilder,
          (
            AppConnectivitySettingsEntry,
            BaseReferences<
              _$AppDatabase,
              $AppConnectivitySettingsEntriesTable,
              AppConnectivitySettingsEntry
            >,
          ),
          AppConnectivitySettingsEntry,
          PrefetchHooks Function()
        > {
  $$AppConnectivitySettingsEntriesTableTableManager(
    _$AppDatabase db,
    $AppConnectivitySettingsEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppConnectivitySettingsEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$AppConnectivitySettingsEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$AppConnectivitySettingsEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<bool> hasAcknowledgedOnline = const Value.absent(),
              }) => AppConnectivitySettingsEntriesCompanion(
                id: id,
                mode: mode,
                hasAcknowledgedOnline: hasAcknowledgedOnline,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String mode,
                required bool hasAcknowledgedOnline,
              }) => AppConnectivitySettingsEntriesCompanion.insert(
                id: id,
                mode: mode,
                hasAcknowledgedOnline: hasAcknowledgedOnline,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppConnectivitySettingsEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppConnectivitySettingsEntriesTable,
      AppConnectivitySettingsEntry,
      $$AppConnectivitySettingsEntriesTableFilterComposer,
      $$AppConnectivitySettingsEntriesTableOrderingComposer,
      $$AppConnectivitySettingsEntriesTableAnnotationComposer,
      $$AppConnectivitySettingsEntriesTableCreateCompanionBuilder,
      $$AppConnectivitySettingsEntriesTableUpdateCompanionBuilder,
      (
        AppConnectivitySettingsEntry,
        BaseReferences<
          _$AppDatabase,
          $AppConnectivitySettingsEntriesTable,
          AppConnectivitySettingsEntry
        >,
      ),
      AppConnectivitySettingsEntry,
      PrefetchHooks Function()
    >;
typedef $$CatalogSourcesEntriesTableCreateCompanionBuilder =
    CatalogSourcesEntriesCompanion Function({
      required String id,
      required String name,
      required String baseUrl,
      required String type,
      required bool isBuiltIn,
      required bool isEnabled,
      required bool supportsSearch,
      required bool supportsNavigation,
      required bool supportsAcquisition,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> lastSuccessfulAccessAt,
      Value<DateTime?> lastCheckedAt,
      Value<String?> health,
      Value<String?> lastErrorCode,
      Value<int> rowid,
    });
typedef $$CatalogSourcesEntriesTableUpdateCompanionBuilder =
    CatalogSourcesEntriesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> baseUrl,
      Value<String> type,
      Value<bool> isBuiltIn,
      Value<bool> isEnabled,
      Value<bool> supportsSearch,
      Value<bool> supportsNavigation,
      Value<bool> supportsAcquisition,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> lastSuccessfulAccessAt,
      Value<DateTime?> lastCheckedAt,
      Value<String?> health,
      Value<String?> lastErrorCode,
      Value<int> rowid,
    });

class $$CatalogSourcesEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $CatalogSourcesEntriesTable> {
  $$CatalogSourcesEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isBuiltIn => $composableBuilder(
    column: $table.isBuiltIn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isEnabled => $composableBuilder(
    column: $table.isEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get supportsSearch => $composableBuilder(
    column: $table.supportsSearch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get supportsNavigation => $composableBuilder(
    column: $table.supportsNavigation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get supportsAcquisition => $composableBuilder(
    column: $table.supportsAcquisition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSuccessfulAccessAt => $composableBuilder(
    column: $table.lastSuccessfulAccessAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastCheckedAt => $composableBuilder(
    column: $table.lastCheckedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get health => $composableBuilder(
    column: $table.health,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CatalogSourcesEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CatalogSourcesEntriesTable> {
  $$CatalogSourcesEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isBuiltIn => $composableBuilder(
    column: $table.isBuiltIn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isEnabled => $composableBuilder(
    column: $table.isEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get supportsSearch => $composableBuilder(
    column: $table.supportsSearch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get supportsNavigation => $composableBuilder(
    column: $table.supportsNavigation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get supportsAcquisition => $composableBuilder(
    column: $table.supportsAcquisition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSuccessfulAccessAt => $composableBuilder(
    column: $table.lastSuccessfulAccessAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastCheckedAt => $composableBuilder(
    column: $table.lastCheckedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get health => $composableBuilder(
    column: $table.health,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CatalogSourcesEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CatalogSourcesEntriesTable> {
  $$CatalogSourcesEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get baseUrl =>
      $composableBuilder(column: $table.baseUrl, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<bool> get isBuiltIn =>
      $composableBuilder(column: $table.isBuiltIn, builder: (column) => column);

  GeneratedColumn<bool> get isEnabled =>
      $composableBuilder(column: $table.isEnabled, builder: (column) => column);

  GeneratedColumn<bool> get supportsSearch => $composableBuilder(
    column: $table.supportsSearch,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get supportsNavigation => $composableBuilder(
    column: $table.supportsNavigation,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get supportsAcquisition => $composableBuilder(
    column: $table.supportsAcquisition,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSuccessfulAccessAt => $composableBuilder(
    column: $table.lastSuccessfulAccessAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastCheckedAt => $composableBuilder(
    column: $table.lastCheckedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get health =>
      $composableBuilder(column: $table.health, builder: (column) => column);

  GeneratedColumn<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => column,
  );
}

class $$CatalogSourcesEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CatalogSourcesEntriesTable,
          CatalogSourcesEntry,
          $$CatalogSourcesEntriesTableFilterComposer,
          $$CatalogSourcesEntriesTableOrderingComposer,
          $$CatalogSourcesEntriesTableAnnotationComposer,
          $$CatalogSourcesEntriesTableCreateCompanionBuilder,
          $$CatalogSourcesEntriesTableUpdateCompanionBuilder,
          (
            CatalogSourcesEntry,
            BaseReferences<
              _$AppDatabase,
              $CatalogSourcesEntriesTable,
              CatalogSourcesEntry
            >,
          ),
          CatalogSourcesEntry,
          PrefetchHooks Function()
        > {
  $$CatalogSourcesEntriesTableTableManager(
    _$AppDatabase db,
    $CatalogSourcesEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CatalogSourcesEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CatalogSourcesEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CatalogSourcesEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> baseUrl = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<bool> isBuiltIn = const Value.absent(),
                Value<bool> isEnabled = const Value.absent(),
                Value<bool> supportsSearch = const Value.absent(),
                Value<bool> supportsNavigation = const Value.absent(),
                Value<bool> supportsAcquisition = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> lastSuccessfulAccessAt = const Value.absent(),
                Value<DateTime?> lastCheckedAt = const Value.absent(),
                Value<String?> health = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CatalogSourcesEntriesCompanion(
                id: id,
                name: name,
                baseUrl: baseUrl,
                type: type,
                isBuiltIn: isBuiltIn,
                isEnabled: isEnabled,
                supportsSearch: supportsSearch,
                supportsNavigation: supportsNavigation,
                supportsAcquisition: supportsAcquisition,
                createdAt: createdAt,
                updatedAt: updatedAt,
                lastSuccessfulAccessAt: lastSuccessfulAccessAt,
                lastCheckedAt: lastCheckedAt,
                health: health,
                lastErrorCode: lastErrorCode,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String baseUrl,
                required String type,
                required bool isBuiltIn,
                required bool isEnabled,
                required bool supportsSearch,
                required bool supportsNavigation,
                required bool supportsAcquisition,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> lastSuccessfulAccessAt = const Value.absent(),
                Value<DateTime?> lastCheckedAt = const Value.absent(),
                Value<String?> health = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CatalogSourcesEntriesCompanion.insert(
                id: id,
                name: name,
                baseUrl: baseUrl,
                type: type,
                isBuiltIn: isBuiltIn,
                isEnabled: isEnabled,
                supportsSearch: supportsSearch,
                supportsNavigation: supportsNavigation,
                supportsAcquisition: supportsAcquisition,
                createdAt: createdAt,
                updatedAt: updatedAt,
                lastSuccessfulAccessAt: lastSuccessfulAccessAt,
                lastCheckedAt: lastCheckedAt,
                health: health,
                lastErrorCode: lastErrorCode,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CatalogSourcesEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CatalogSourcesEntriesTable,
      CatalogSourcesEntry,
      $$CatalogSourcesEntriesTableFilterComposer,
      $$CatalogSourcesEntriesTableOrderingComposer,
      $$CatalogSourcesEntriesTableAnnotationComposer,
      $$CatalogSourcesEntriesTableCreateCompanionBuilder,
      $$CatalogSourcesEntriesTableUpdateCompanionBuilder,
      (
        CatalogSourcesEntry,
        BaseReferences<
          _$AppDatabase,
          $CatalogSourcesEntriesTable,
          CatalogSourcesEntry
        >,
      ),
      CatalogSourcesEntry,
      PrefetchHooks Function()
    >;
typedef $$RemoteDownloadTasksTableCreateCompanionBuilder =
    RemoteDownloadTasksCompanion Function({
      required String id,
      required String sourceId,
      required String publicationRemoteId,
      required String title,
      required String authorsJson,
      required String acquisitionUri,
      Value<String?> declaredMediaType,
      Value<String?> expectedFinalMediaType,
      required String suggestedFilename,
      Value<int?> expectedSizeBytes,
      Value<int> downloadedBytes,
      Value<int?> totalBytes,
      required String state,
      Value<String?> temporaryFilePath,
      Value<String?> sha256,
      Value<String?> failureCategory,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> startedAt,
      Value<DateTime?> completedAt,
      Value<String?> importedBookId,
      Value<int> retryCount,
      Value<int> attemptId,
      Value<String?> remoteMetadataJson,
      Value<int> rowid,
    });
typedef $$RemoteDownloadTasksTableUpdateCompanionBuilder =
    RemoteDownloadTasksCompanion Function({
      Value<String> id,
      Value<String> sourceId,
      Value<String> publicationRemoteId,
      Value<String> title,
      Value<String> authorsJson,
      Value<String> acquisitionUri,
      Value<String?> declaredMediaType,
      Value<String?> expectedFinalMediaType,
      Value<String> suggestedFilename,
      Value<int?> expectedSizeBytes,
      Value<int> downloadedBytes,
      Value<int?> totalBytes,
      Value<String> state,
      Value<String?> temporaryFilePath,
      Value<String?> sha256,
      Value<String?> failureCategory,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> startedAt,
      Value<DateTime?> completedAt,
      Value<String?> importedBookId,
      Value<int> retryCount,
      Value<int> attemptId,
      Value<String?> remoteMetadataJson,
      Value<int> rowid,
    });

class $$RemoteDownloadTasksTableFilterComposer
    extends Composer<_$AppDatabase, $RemoteDownloadTasksTable> {
  $$RemoteDownloadTasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publicationRemoteId => $composableBuilder(
    column: $table.publicationRemoteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorsJson => $composableBuilder(
    column: $table.authorsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get acquisitionUri => $composableBuilder(
    column: $table.acquisitionUri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get declaredMediaType => $composableBuilder(
    column: $table.declaredMediaType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get expectedFinalMediaType => $composableBuilder(
    column: $table.expectedFinalMediaType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get suggestedFilename => $composableBuilder(
    column: $table.suggestedFilename,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expectedSizeBytes => $composableBuilder(
    column: $table.expectedSizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get downloadedBytes => $composableBuilder(
    column: $table.downloadedBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get temporaryFilePath => $composableBuilder(
    column: $table.temporaryFilePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureCategory => $composableBuilder(
    column: $table.failureCategory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get importedBookId => $composableBuilder(
    column: $table.importedBookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptId => $composableBuilder(
    column: $table.attemptId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteMetadataJson => $composableBuilder(
    column: $table.remoteMetadataJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RemoteDownloadTasksTableOrderingComposer
    extends Composer<_$AppDatabase, $RemoteDownloadTasksTable> {
  $$RemoteDownloadTasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publicationRemoteId => $composableBuilder(
    column: $table.publicationRemoteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorsJson => $composableBuilder(
    column: $table.authorsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get acquisitionUri => $composableBuilder(
    column: $table.acquisitionUri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get declaredMediaType => $composableBuilder(
    column: $table.declaredMediaType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get expectedFinalMediaType => $composableBuilder(
    column: $table.expectedFinalMediaType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get suggestedFilename => $composableBuilder(
    column: $table.suggestedFilename,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expectedSizeBytes => $composableBuilder(
    column: $table.expectedSizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get downloadedBytes => $composableBuilder(
    column: $table.downloadedBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get temporaryFilePath => $composableBuilder(
    column: $table.temporaryFilePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureCategory => $composableBuilder(
    column: $table.failureCategory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get importedBookId => $composableBuilder(
    column: $table.importedBookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptId => $composableBuilder(
    column: $table.attemptId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteMetadataJson => $composableBuilder(
    column: $table.remoteMetadataJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RemoteDownloadTasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $RemoteDownloadTasksTable> {
  $$RemoteDownloadTasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get publicationRemoteId => $composableBuilder(
    column: $table.publicationRemoteId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get authorsJson => $composableBuilder(
    column: $table.authorsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get acquisitionUri => $composableBuilder(
    column: $table.acquisitionUri,
    builder: (column) => column,
  );

  GeneratedColumn<String> get declaredMediaType => $composableBuilder(
    column: $table.declaredMediaType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get expectedFinalMediaType => $composableBuilder(
    column: $table.expectedFinalMediaType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get suggestedFilename => $composableBuilder(
    column: $table.suggestedFilename,
    builder: (column) => column,
  );

  GeneratedColumn<int> get expectedSizeBytes => $composableBuilder(
    column: $table.expectedSizeBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get downloadedBytes => $composableBuilder(
    column: $table.downloadedBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get temporaryFilePath => $composableBuilder(
    column: $table.temporaryFilePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<String> get failureCategory => $composableBuilder(
    column: $table.failureCategory,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get importedBookId => $composableBuilder(
    column: $table.importedBookId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attemptId =>
      $composableBuilder(column: $table.attemptId, builder: (column) => column);

  GeneratedColumn<String> get remoteMetadataJson => $composableBuilder(
    column: $table.remoteMetadataJson,
    builder: (column) => column,
  );
}

class $$RemoteDownloadTasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RemoteDownloadTasksTable,
          RemoteDownloadTask,
          $$RemoteDownloadTasksTableFilterComposer,
          $$RemoteDownloadTasksTableOrderingComposer,
          $$RemoteDownloadTasksTableAnnotationComposer,
          $$RemoteDownloadTasksTableCreateCompanionBuilder,
          $$RemoteDownloadTasksTableUpdateCompanionBuilder,
          (
            RemoteDownloadTask,
            BaseReferences<
              _$AppDatabase,
              $RemoteDownloadTasksTable,
              RemoteDownloadTask
            >,
          ),
          RemoteDownloadTask,
          PrefetchHooks Function()
        > {
  $$RemoteDownloadTasksTableTableManager(
    _$AppDatabase db,
    $RemoteDownloadTasksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RemoteDownloadTasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RemoteDownloadTasksTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$RemoteDownloadTasksTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String> publicationRemoteId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> authorsJson = const Value.absent(),
                Value<String> acquisitionUri = const Value.absent(),
                Value<String?> declaredMediaType = const Value.absent(),
                Value<String?> expectedFinalMediaType = const Value.absent(),
                Value<String> suggestedFilename = const Value.absent(),
                Value<int?> expectedSizeBytes = const Value.absent(),
                Value<int> downloadedBytes = const Value.absent(),
                Value<int?> totalBytes = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> temporaryFilePath = const Value.absent(),
                Value<String?> sha256 = const Value.absent(),
                Value<String?> failureCategory = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> startedAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<String?> importedBookId = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<int> attemptId = const Value.absent(),
                Value<String?> remoteMetadataJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RemoteDownloadTasksCompanion(
                id: id,
                sourceId: sourceId,
                publicationRemoteId: publicationRemoteId,
                title: title,
                authorsJson: authorsJson,
                acquisitionUri: acquisitionUri,
                declaredMediaType: declaredMediaType,
                expectedFinalMediaType: expectedFinalMediaType,
                suggestedFilename: suggestedFilename,
                expectedSizeBytes: expectedSizeBytes,
                downloadedBytes: downloadedBytes,
                totalBytes: totalBytes,
                state: state,
                temporaryFilePath: temporaryFilePath,
                sha256: sha256,
                failureCategory: failureCategory,
                createdAt: createdAt,
                updatedAt: updatedAt,
                startedAt: startedAt,
                completedAt: completedAt,
                importedBookId: importedBookId,
                retryCount: retryCount,
                attemptId: attemptId,
                remoteMetadataJson: remoteMetadataJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sourceId,
                required String publicationRemoteId,
                required String title,
                required String authorsJson,
                required String acquisitionUri,
                Value<String?> declaredMediaType = const Value.absent(),
                Value<String?> expectedFinalMediaType = const Value.absent(),
                required String suggestedFilename,
                Value<int?> expectedSizeBytes = const Value.absent(),
                Value<int> downloadedBytes = const Value.absent(),
                Value<int?> totalBytes = const Value.absent(),
                required String state,
                Value<String?> temporaryFilePath = const Value.absent(),
                Value<String?> sha256 = const Value.absent(),
                Value<String?> failureCategory = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> startedAt = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
                Value<String?> importedBookId = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<int> attemptId = const Value.absent(),
                Value<String?> remoteMetadataJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RemoteDownloadTasksCompanion.insert(
                id: id,
                sourceId: sourceId,
                publicationRemoteId: publicationRemoteId,
                title: title,
                authorsJson: authorsJson,
                acquisitionUri: acquisitionUri,
                declaredMediaType: declaredMediaType,
                expectedFinalMediaType: expectedFinalMediaType,
                suggestedFilename: suggestedFilename,
                expectedSizeBytes: expectedSizeBytes,
                downloadedBytes: downloadedBytes,
                totalBytes: totalBytes,
                state: state,
                temporaryFilePath: temporaryFilePath,
                sha256: sha256,
                failureCategory: failureCategory,
                createdAt: createdAt,
                updatedAt: updatedAt,
                startedAt: startedAt,
                completedAt: completedAt,
                importedBookId: importedBookId,
                retryCount: retryCount,
                attemptId: attemptId,
                remoteMetadataJson: remoteMetadataJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RemoteDownloadTasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RemoteDownloadTasksTable,
      RemoteDownloadTask,
      $$RemoteDownloadTasksTableFilterComposer,
      $$RemoteDownloadTasksTableOrderingComposer,
      $$RemoteDownloadTasksTableAnnotationComposer,
      $$RemoteDownloadTasksTableCreateCompanionBuilder,
      $$RemoteDownloadTasksTableUpdateCompanionBuilder,
      (
        RemoteDownloadTask,
        BaseReferences<
          _$AppDatabase,
          $RemoteDownloadTasksTable,
          RemoteDownloadTask
        >,
      ),
      RemoteDownloadTask,
      PrefetchHooks Function()
    >;
typedef $$RemoteCacheSettingsEntriesTableCreateCompanionBuilder =
    RemoteCacheSettingsEntriesCompanion Function({
      Value<int> id,
      required int maximumBytes,
    });
typedef $$RemoteCacheSettingsEntriesTableUpdateCompanionBuilder =
    RemoteCacheSettingsEntriesCompanion Function({
      Value<int> id,
      Value<int> maximumBytes,
    });

class $$RemoteCacheSettingsEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $RemoteCacheSettingsEntriesTable> {
  $$RemoteCacheSettingsEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maximumBytes => $composableBuilder(
    column: $table.maximumBytes,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RemoteCacheSettingsEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $RemoteCacheSettingsEntriesTable> {
  $$RemoteCacheSettingsEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maximumBytes => $composableBuilder(
    column: $table.maximumBytes,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RemoteCacheSettingsEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RemoteCacheSettingsEntriesTable> {
  $$RemoteCacheSettingsEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get maximumBytes => $composableBuilder(
    column: $table.maximumBytes,
    builder: (column) => column,
  );
}

class $$RemoteCacheSettingsEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RemoteCacheSettingsEntriesTable,
          RemoteCacheSettingsEntry,
          $$RemoteCacheSettingsEntriesTableFilterComposer,
          $$RemoteCacheSettingsEntriesTableOrderingComposer,
          $$RemoteCacheSettingsEntriesTableAnnotationComposer,
          $$RemoteCacheSettingsEntriesTableCreateCompanionBuilder,
          $$RemoteCacheSettingsEntriesTableUpdateCompanionBuilder,
          (
            RemoteCacheSettingsEntry,
            BaseReferences<
              _$AppDatabase,
              $RemoteCacheSettingsEntriesTable,
              RemoteCacheSettingsEntry
            >,
          ),
          RemoteCacheSettingsEntry,
          PrefetchHooks Function()
        > {
  $$RemoteCacheSettingsEntriesTableTableManager(
    _$AppDatabase db,
    $RemoteCacheSettingsEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RemoteCacheSettingsEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$RemoteCacheSettingsEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$RemoteCacheSettingsEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> maximumBytes = const Value.absent(),
              }) => RemoteCacheSettingsEntriesCompanion(
                id: id,
                maximumBytes: maximumBytes,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int maximumBytes,
              }) => RemoteCacheSettingsEntriesCompanion.insert(
                id: id,
                maximumBytes: maximumBytes,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RemoteCacheSettingsEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RemoteCacheSettingsEntriesTable,
      RemoteCacheSettingsEntry,
      $$RemoteCacheSettingsEntriesTableFilterComposer,
      $$RemoteCacheSettingsEntriesTableOrderingComposer,
      $$RemoteCacheSettingsEntriesTableAnnotationComposer,
      $$RemoteCacheSettingsEntriesTableCreateCompanionBuilder,
      $$RemoteCacheSettingsEntriesTableUpdateCompanionBuilder,
      (
        RemoteCacheSettingsEntry,
        BaseReferences<
          _$AppDatabase,
          $RemoteCacheSettingsEntriesTable,
          RemoteCacheSettingsEntry
        >,
      ),
      RemoteCacheSettingsEntry,
      PrefetchHooks Function()
    >;
typedef $$HomeOnlineTabSettingsEntriesTableCreateCompanionBuilder =
    HomeOnlineTabSettingsEntriesCompanion Function({
      required String sourceId,
      Value<bool> visibleOnHome,
      Value<int> rowid,
    });
typedef $$HomeOnlineTabSettingsEntriesTableUpdateCompanionBuilder =
    HomeOnlineTabSettingsEntriesCompanion Function({
      Value<String> sourceId,
      Value<bool> visibleOnHome,
      Value<int> rowid,
    });

class $$HomeOnlineTabSettingsEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $HomeOnlineTabSettingsEntriesTable> {
  $$HomeOnlineTabSettingsEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get visibleOnHome => $composableBuilder(
    column: $table.visibleOnHome,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HomeOnlineTabSettingsEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $HomeOnlineTabSettingsEntriesTable> {
  $$HomeOnlineTabSettingsEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get visibleOnHome => $composableBuilder(
    column: $table.visibleOnHome,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HomeOnlineTabSettingsEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $HomeOnlineTabSettingsEntriesTable> {
  $$HomeOnlineTabSettingsEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<bool> get visibleOnHome => $composableBuilder(
    column: $table.visibleOnHome,
    builder: (column) => column,
  );
}

class $$HomeOnlineTabSettingsEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HomeOnlineTabSettingsEntriesTable,
          HomeOnlineTabSettingsEntry,
          $$HomeOnlineTabSettingsEntriesTableFilterComposer,
          $$HomeOnlineTabSettingsEntriesTableOrderingComposer,
          $$HomeOnlineTabSettingsEntriesTableAnnotationComposer,
          $$HomeOnlineTabSettingsEntriesTableCreateCompanionBuilder,
          $$HomeOnlineTabSettingsEntriesTableUpdateCompanionBuilder,
          (
            HomeOnlineTabSettingsEntry,
            BaseReferences<
              _$AppDatabase,
              $HomeOnlineTabSettingsEntriesTable,
              HomeOnlineTabSettingsEntry
            >,
          ),
          HomeOnlineTabSettingsEntry,
          PrefetchHooks Function()
        > {
  $$HomeOnlineTabSettingsEntriesTableTableManager(
    _$AppDatabase db,
    $HomeOnlineTabSettingsEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HomeOnlineTabSettingsEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$HomeOnlineTabSettingsEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$HomeOnlineTabSettingsEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> sourceId = const Value.absent(),
                Value<bool> visibleOnHome = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HomeOnlineTabSettingsEntriesCompanion(
                sourceId: sourceId,
                visibleOnHome: visibleOnHome,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sourceId,
                Value<bool> visibleOnHome = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HomeOnlineTabSettingsEntriesCompanion.insert(
                sourceId: sourceId,
                visibleOnHome: visibleOnHome,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HomeOnlineTabSettingsEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HomeOnlineTabSettingsEntriesTable,
      HomeOnlineTabSettingsEntry,
      $$HomeOnlineTabSettingsEntriesTableFilterComposer,
      $$HomeOnlineTabSettingsEntriesTableOrderingComposer,
      $$HomeOnlineTabSettingsEntriesTableAnnotationComposer,
      $$HomeOnlineTabSettingsEntriesTableCreateCompanionBuilder,
      $$HomeOnlineTabSettingsEntriesTableUpdateCompanionBuilder,
      (
        HomeOnlineTabSettingsEntry,
        BaseReferences<
          _$AppDatabase,
          $HomeOnlineTabSettingsEntriesTable,
          HomeOnlineTabSettingsEntry
        >,
      ),
      HomeOnlineTabSettingsEntry,
      PrefetchHooks Function()
    >;
typedef $$LibrarySectionSettingsEntriesTableCreateCompanionBuilder =
    LibrarySectionSettingsEntriesCompanion Function({
      Value<int> id,
      required String defaultSection,
    });
typedef $$LibrarySectionSettingsEntriesTableUpdateCompanionBuilder =
    LibrarySectionSettingsEntriesCompanion Function({
      Value<int> id,
      Value<String> defaultSection,
    });

class $$LibrarySectionSettingsEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $LibrarySectionSettingsEntriesTable> {
  $$LibrarySectionSettingsEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get defaultSection => $composableBuilder(
    column: $table.defaultSection,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LibrarySectionSettingsEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $LibrarySectionSettingsEntriesTable> {
  $$LibrarySectionSettingsEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get defaultSection => $composableBuilder(
    column: $table.defaultSection,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LibrarySectionSettingsEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LibrarySectionSettingsEntriesTable> {
  $$LibrarySectionSettingsEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get defaultSection => $composableBuilder(
    column: $table.defaultSection,
    builder: (column) => column,
  );
}

class $$LibrarySectionSettingsEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LibrarySectionSettingsEntriesTable,
          LibrarySectionSettingsEntry,
          $$LibrarySectionSettingsEntriesTableFilterComposer,
          $$LibrarySectionSettingsEntriesTableOrderingComposer,
          $$LibrarySectionSettingsEntriesTableAnnotationComposer,
          $$LibrarySectionSettingsEntriesTableCreateCompanionBuilder,
          $$LibrarySectionSettingsEntriesTableUpdateCompanionBuilder,
          (
            LibrarySectionSettingsEntry,
            BaseReferences<
              _$AppDatabase,
              $LibrarySectionSettingsEntriesTable,
              LibrarySectionSettingsEntry
            >,
          ),
          LibrarySectionSettingsEntry,
          PrefetchHooks Function()
        > {
  $$LibrarySectionSettingsEntriesTableTableManager(
    _$AppDatabase db,
    $LibrarySectionSettingsEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LibrarySectionSettingsEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$LibrarySectionSettingsEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LibrarySectionSettingsEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> defaultSection = const Value.absent(),
              }) => LibrarySectionSettingsEntriesCompanion(
                id: id,
                defaultSection: defaultSection,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String defaultSection,
              }) => LibrarySectionSettingsEntriesCompanion.insert(
                id: id,
                defaultSection: defaultSection,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LibrarySectionSettingsEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LibrarySectionSettingsEntriesTable,
      LibrarySectionSettingsEntry,
      $$LibrarySectionSettingsEntriesTableFilterComposer,
      $$LibrarySectionSettingsEntriesTableOrderingComposer,
      $$LibrarySectionSettingsEntriesTableAnnotationComposer,
      $$LibrarySectionSettingsEntriesTableCreateCompanionBuilder,
      $$LibrarySectionSettingsEntriesTableUpdateCompanionBuilder,
      (
        LibrarySectionSettingsEntry,
        BaseReferences<
          _$AppDatabase,
          $LibrarySectionSettingsEntriesTable,
          LibrarySectionSettingsEntry
        >,
      ),
      LibrarySectionSettingsEntry,
      PrefetchHooks Function()
    >;
typedef $$HomeDefaultCarouselSettingsEntriesTableCreateCompanionBuilder =
    HomeDefaultCarouselSettingsEntriesCompanion Function({
      Value<int> id,
      required String defaultCarousel,
    });
typedef $$HomeDefaultCarouselSettingsEntriesTableUpdateCompanionBuilder =
    HomeDefaultCarouselSettingsEntriesCompanion Function({
      Value<int> id,
      Value<String> defaultCarousel,
    });

class $$HomeDefaultCarouselSettingsEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $HomeDefaultCarouselSettingsEntriesTable> {
  $$HomeDefaultCarouselSettingsEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get defaultCarousel => $composableBuilder(
    column: $table.defaultCarousel,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HomeDefaultCarouselSettingsEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $HomeDefaultCarouselSettingsEntriesTable> {
  $$HomeDefaultCarouselSettingsEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get defaultCarousel => $composableBuilder(
    column: $table.defaultCarousel,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HomeDefaultCarouselSettingsEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $HomeDefaultCarouselSettingsEntriesTable> {
  $$HomeDefaultCarouselSettingsEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get defaultCarousel => $composableBuilder(
    column: $table.defaultCarousel,
    builder: (column) => column,
  );
}

class $$HomeDefaultCarouselSettingsEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HomeDefaultCarouselSettingsEntriesTable,
          HomeDefaultCarouselSettingsEntry,
          $$HomeDefaultCarouselSettingsEntriesTableFilterComposer,
          $$HomeDefaultCarouselSettingsEntriesTableOrderingComposer,
          $$HomeDefaultCarouselSettingsEntriesTableAnnotationComposer,
          $$HomeDefaultCarouselSettingsEntriesTableCreateCompanionBuilder,
          $$HomeDefaultCarouselSettingsEntriesTableUpdateCompanionBuilder,
          (
            HomeDefaultCarouselSettingsEntry,
            BaseReferences<
              _$AppDatabase,
              $HomeDefaultCarouselSettingsEntriesTable,
              HomeDefaultCarouselSettingsEntry
            >,
          ),
          HomeDefaultCarouselSettingsEntry,
          PrefetchHooks Function()
        > {
  $$HomeDefaultCarouselSettingsEntriesTableTableManager(
    _$AppDatabase db,
    $HomeDefaultCarouselSettingsEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HomeDefaultCarouselSettingsEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$HomeDefaultCarouselSettingsEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$HomeDefaultCarouselSettingsEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> defaultCarousel = const Value.absent(),
              }) => HomeDefaultCarouselSettingsEntriesCompanion(
                id: id,
                defaultCarousel: defaultCarousel,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String defaultCarousel,
              }) => HomeDefaultCarouselSettingsEntriesCompanion.insert(
                id: id,
                defaultCarousel: defaultCarousel,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HomeDefaultCarouselSettingsEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HomeDefaultCarouselSettingsEntriesTable,
      HomeDefaultCarouselSettingsEntry,
      $$HomeDefaultCarouselSettingsEntriesTableFilterComposer,
      $$HomeDefaultCarouselSettingsEntriesTableOrderingComposer,
      $$HomeDefaultCarouselSettingsEntriesTableAnnotationComposer,
      $$HomeDefaultCarouselSettingsEntriesTableCreateCompanionBuilder,
      $$HomeDefaultCarouselSettingsEntriesTableUpdateCompanionBuilder,
      (
        HomeDefaultCarouselSettingsEntry,
        BaseReferences<
          _$AppDatabase,
          $HomeDefaultCarouselSettingsEntriesTable,
          HomeDefaultCarouselSettingsEntry
        >,
      ),
      HomeDefaultCarouselSettingsEntry,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$BookDisplaySettingsEntriesTableTableManager
  get bookDisplaySettingsEntries =>
      $$BookDisplaySettingsEntriesTableTableManager(
        _db,
        _db.bookDisplaySettingsEntries,
      );
  $$BooksTableTableManager get books =>
      $$BooksTableTableManager(_db, _db.books);
  $$ReadingProgressEntriesTableTableManager get readingProgressEntries =>
      $$ReadingProgressEntriesTableTableManager(
        _db,
        _db.readingProgressEntries,
      );
  $$EpubReaderSettingsEntriesTableTableManager get epubReaderSettingsEntries =>
      $$EpubReaderSettingsEntriesTableTableManager(
        _db,
        _db.epubReaderSettingsEntries,
      );
  $$CollectionsTableTableManager get collections =>
      $$CollectionsTableTableManager(_db, _db.collections);
  $$BookCollectionEntriesTableTableManager get bookCollectionEntries =>
      $$BookCollectionEntriesTableTableManager(_db, _db.bookCollectionEntries);
  $$BookmarksTableTableManager get bookmarks =>
      $$BookmarksTableTableManager(_db, _db.bookmarks);
  $$ReaderAnnotationsTableTableManager get readerAnnotations =>
      $$ReaderAnnotationsTableTableManager(_db, _db.readerAnnotations);
  $$AppConnectivitySettingsEntriesTableTableManager
  get appConnectivitySettingsEntries =>
      $$AppConnectivitySettingsEntriesTableTableManager(
        _db,
        _db.appConnectivitySettingsEntries,
      );
  $$CatalogSourcesEntriesTableTableManager get catalogSourcesEntries =>
      $$CatalogSourcesEntriesTableTableManager(_db, _db.catalogSourcesEntries);
  $$RemoteDownloadTasksTableTableManager get remoteDownloadTasks =>
      $$RemoteDownloadTasksTableTableManager(_db, _db.remoteDownloadTasks);
  $$RemoteCacheSettingsEntriesTableTableManager
  get remoteCacheSettingsEntries =>
      $$RemoteCacheSettingsEntriesTableTableManager(
        _db,
        _db.remoteCacheSettingsEntries,
      );
  $$HomeOnlineTabSettingsEntriesTableTableManager
  get homeOnlineTabSettingsEntries =>
      $$HomeOnlineTabSettingsEntriesTableTableManager(
        _db,
        _db.homeOnlineTabSettingsEntries,
      );
  $$LibrarySectionSettingsEntriesTableTableManager
  get librarySectionSettingsEntries =>
      $$LibrarySectionSettingsEntriesTableTableManager(
        _db,
        _db.librarySectionSettingsEntries,
      );
  $$HomeDefaultCarouselSettingsEntriesTableTableManager
  get homeDefaultCarouselSettingsEntries =>
      $$HomeDefaultCarouselSettingsEntriesTableTableManager(
        _db,
        _db.homeDefaultCarouselSettingsEntries,
      );
}

mixin _$BooksDaoMixin on DatabaseAccessor<AppDatabase> {
  $BooksTable get books => attachedDatabase.books;
  $CollectionsTable get collections => attachedDatabase.collections;
  $BookCollectionEntriesTable get bookCollectionEntries =>
      attachedDatabase.bookCollectionEntries;
  BooksDaoManager get managers => BooksDaoManager(this);
}

class BooksDaoManager {
  final _$BooksDaoMixin _db;
  BooksDaoManager(this._db);
  $$BooksTableTableManager get books =>
      $$BooksTableTableManager(_db.attachedDatabase, _db.books);
  $$CollectionsTableTableManager get collections =>
      $$CollectionsTableTableManager(_db.attachedDatabase, _db.collections);
  $$BookCollectionEntriesTableTableManager get bookCollectionEntries =>
      $$BookCollectionEntriesTableTableManager(
        _db.attachedDatabase,
        _db.bookCollectionEntries,
      );
}

mixin _$ReadingProgressDaoMixin on DatabaseAccessor<AppDatabase> {
  $BooksTable get books => attachedDatabase.books;
  $ReadingProgressEntriesTable get readingProgressEntries =>
      attachedDatabase.readingProgressEntries;
  ReadingProgressDaoManager get managers => ReadingProgressDaoManager(this);
}

class ReadingProgressDaoManager {
  final _$ReadingProgressDaoMixin _db;
  ReadingProgressDaoManager(this._db);
  $$BooksTableTableManager get books =>
      $$BooksTableTableManager(_db.attachedDatabase, _db.books);
  $$ReadingProgressEntriesTableTableManager get readingProgressEntries =>
      $$ReadingProgressEntriesTableTableManager(
        _db.attachedDatabase,
        _db.readingProgressEntries,
      );
}

mixin _$EpubReaderSettingsDaoMixin on DatabaseAccessor<AppDatabase> {
  $EpubReaderSettingsEntriesTable get epubReaderSettingsEntries =>
      attachedDatabase.epubReaderSettingsEntries;
  EpubReaderSettingsDaoManager get managers =>
      EpubReaderSettingsDaoManager(this);
}

class EpubReaderSettingsDaoManager {
  final _$EpubReaderSettingsDaoMixin _db;
  EpubReaderSettingsDaoManager(this._db);
  $$EpubReaderSettingsEntriesTableTableManager get epubReaderSettingsEntries =>
      $$EpubReaderSettingsEntriesTableTableManager(
        _db.attachedDatabase,
        _db.epubReaderSettingsEntries,
      );
}

mixin _$CollectionsDaoMixin on DatabaseAccessor<AppDatabase> {
  $CollectionsTable get collections => attachedDatabase.collections;
  $BooksTable get books => attachedDatabase.books;
  $BookCollectionEntriesTable get bookCollectionEntries =>
      attachedDatabase.bookCollectionEntries;
  CollectionsDaoManager get managers => CollectionsDaoManager(this);
}

class CollectionsDaoManager {
  final _$CollectionsDaoMixin _db;
  CollectionsDaoManager(this._db);
  $$CollectionsTableTableManager get collections =>
      $$CollectionsTableTableManager(_db.attachedDatabase, _db.collections);
  $$BooksTableTableManager get books =>
      $$BooksTableTableManager(_db.attachedDatabase, _db.books);
  $$BookCollectionEntriesTableTableManager get bookCollectionEntries =>
      $$BookCollectionEntriesTableTableManager(
        _db.attachedDatabase,
        _db.bookCollectionEntries,
      );
}

mixin _$BookmarksDaoMixin on DatabaseAccessor<AppDatabase> {
  $BooksTable get books => attachedDatabase.books;
  $BookmarksTable get bookmarks => attachedDatabase.bookmarks;
  BookmarksDaoManager get managers => BookmarksDaoManager(this);
}

class BookmarksDaoManager {
  final _$BookmarksDaoMixin _db;
  BookmarksDaoManager(this._db);
  $$BooksTableTableManager get books =>
      $$BooksTableTableManager(_db.attachedDatabase, _db.books);
  $$BookmarksTableTableManager get bookmarks =>
      $$BookmarksTableTableManager(_db.attachedDatabase, _db.bookmarks);
}

mixin _$AppConnectivitySettingsDaoMixin on DatabaseAccessor<AppDatabase> {
  $AppConnectivitySettingsEntriesTable get appConnectivitySettingsEntries =>
      attachedDatabase.appConnectivitySettingsEntries;
  AppConnectivitySettingsDaoManager get managers =>
      AppConnectivitySettingsDaoManager(this);
}

class AppConnectivitySettingsDaoManager {
  final _$AppConnectivitySettingsDaoMixin _db;
  AppConnectivitySettingsDaoManager(this._db);
  $$AppConnectivitySettingsEntriesTableTableManager
  get appConnectivitySettingsEntries =>
      $$AppConnectivitySettingsEntriesTableTableManager(
        _db.attachedDatabase,
        _db.appConnectivitySettingsEntries,
      );
}

mixin _$LibrarySectionSettingsDaoMixin on DatabaseAccessor<AppDatabase> {
  $LibrarySectionSettingsEntriesTable get librarySectionSettingsEntries =>
      attachedDatabase.librarySectionSettingsEntries;
  LibrarySectionSettingsDaoManager get managers =>
      LibrarySectionSettingsDaoManager(this);
}

class LibrarySectionSettingsDaoManager {
  final _$LibrarySectionSettingsDaoMixin _db;
  LibrarySectionSettingsDaoManager(this._db);
  $$LibrarySectionSettingsEntriesTableTableManager
  get librarySectionSettingsEntries =>
      $$LibrarySectionSettingsEntriesTableTableManager(
        _db.attachedDatabase,
        _db.librarySectionSettingsEntries,
      );
}

mixin _$HomeDefaultCarouselSettingsDaoMixin on DatabaseAccessor<AppDatabase> {
  $HomeDefaultCarouselSettingsEntriesTable
  get homeDefaultCarouselSettingsEntries =>
      attachedDatabase.homeDefaultCarouselSettingsEntries;
  HomeDefaultCarouselSettingsDaoManager get managers =>
      HomeDefaultCarouselSettingsDaoManager(this);
}

class HomeDefaultCarouselSettingsDaoManager {
  final _$HomeDefaultCarouselSettingsDaoMixin _db;
  HomeDefaultCarouselSettingsDaoManager(this._db);
  $$HomeDefaultCarouselSettingsEntriesTableTableManager
  get homeDefaultCarouselSettingsEntries =>
      $$HomeDefaultCarouselSettingsEntriesTableTableManager(
        _db.attachedDatabase,
        _db.homeDefaultCarouselSettingsEntries,
      );
}

mixin _$RemoteCacheSettingsDaoMixin on DatabaseAccessor<AppDatabase> {
  $RemoteCacheSettingsEntriesTable get remoteCacheSettingsEntries =>
      attachedDatabase.remoteCacheSettingsEntries;
  RemoteCacheSettingsDaoManager get managers =>
      RemoteCacheSettingsDaoManager(this);
}

class RemoteCacheSettingsDaoManager {
  final _$RemoteCacheSettingsDaoMixin _db;
  RemoteCacheSettingsDaoManager(this._db);
  $$RemoteCacheSettingsEntriesTableTableManager
  get remoteCacheSettingsEntries =>
      $$RemoteCacheSettingsEntriesTableTableManager(
        _db.attachedDatabase,
        _db.remoteCacheSettingsEntries,
      );
}

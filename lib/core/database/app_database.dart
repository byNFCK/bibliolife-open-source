import 'package:bibliolife/core/database/tables/books_table.dart';
import 'package:bibliolife/features/collections/domain/models/system_collection.dart';
import 'package:bibliolife/core/database/tables/bookmarks_table.dart';
import 'package:bibliolife/core/database/tables/book_collection_entries_table.dart';
import 'package:bibliolife/core/database/tables/collections_table.dart';
import 'package:bibliolife/core/database/tables/epub_reader_settings_table.dart';
import 'package:bibliolife/core/database/tables/home_online_tab_settings_table.dart';
import 'package:bibliolife/core/database/tables/home_default_carousel_settings_table.dart';
import 'package:bibliolife/core/database/tables/library_section_settings_table.dart';
import 'package:bibliolife/core/database/tables/app_connectivity_settings_table.dart';
import 'package:bibliolife/core/database/tables/catalog_sources_table.dart';
import 'package:bibliolife/core/database/tables/reading_progress_table.dart';
import 'package:bibliolife/core/database/tables/reader_annotations_table.dart';
import 'package:bibliolife/core/database/tables/remote_download_tasks_table.dart';
import 'package:bibliolife/core/database/tables/remote_cache_settings_table.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_cache_budget.dart';
import 'package:bibliolife/shared/models/book_cover_provenance.dart';
import 'package:bibliolife/core/database/tables/book_display_settings_table.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';
part 'daos/books_dao.dart';
part 'daos/bookmarks_dao.dart';
part 'daos/collections_dao.dart';
part 'daos/epub_reader_settings_dao.dart';
part 'daos/app_connectivity_settings_dao.dart';
part 'daos/library_section_settings_dao.dart';
part 'daos/home_default_carousel_settings_dao.dart';
part 'daos/reading_progress_dao.dart';
part 'daos/remote_cache_settings_dao.dart';

@DriftDatabase(
  tables: [
    BookDisplaySettingsEntries,
    Books,
    ReadingProgressEntries,
    EpubReaderSettingsEntries,
    Collections,
    BookCollectionEntries,
    Bookmarks,
    ReaderAnnotations,
    AppConnectivitySettingsEntries,
    CatalogSourcesEntries,
    RemoteDownloadTasks,
    RemoteCacheSettingsEntries,
    HomeOnlineTabSettingsEntries,
    LibrarySectionSettingsEntries,
    HomeDefaultCarouselSettingsEntries,
  ],
  daos: [
    BooksDao,
    ReadingProgressDao,
    EpubReaderSettingsDao,
    CollectionsDao,
    BookmarksDao,
    AppConnectivitySettingsDao,
    LibrarySectionSettingsDao,
    HomeDefaultCarouselSettingsDao,
    RemoteCacheSettingsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'bibliolife'));

  @override
  int get schemaVersion => 23;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await customStatement(
        'CREATE INDEX IF NOT EXISTS remote_download_tasks_state_updated_at '
        'ON remote_download_tasks(state, updated_at)',
      );
      await into(remoteCacheSettingsEntries).insert(
        RemoteCacheSettingsEntriesCompanion.insert(
          id: const Value(1),
          maximumBytes: remoteCacheDefaultMaximumBytes,
        ),
      );
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(books, books.originalFilePath);
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS books_original_file_path_unique '
          'ON books(original_file_path)',
        );
      }
      if (from < 3) {
        await migrator.createTable(epubReaderSettingsEntries);
      }
      if (from < 4) {
        await migrator.createTable(collections);
        await migrator.createTable(bookCollectionEntries);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS book_collection_entries_collection_id '
          'ON book_collection_entries(collection_id)',
        );
      }
      if (from < 5) {
        await migrator.createTable(bookmarks);
      } else if (from < 6) {
        await migrator.addColumn(bookmarks, bookmarks.position);
      }
      if (from < 7) {
        await migrator.createTable(readerAnnotations);
      }
      if (from < 8) {
        await migrator.createTable(appConnectivitySettingsEntries);
      }
      if (from < 9) {
        await migrator.createTable(catalogSourcesEntries);
      }
      if (from < 10) {
        await _addBookColumnIfMissing(migrator, books.authorsJson);
        await _addBookColumnIfMissing(migrator, books.contributorsJson);
        await _addBookColumnIfMissing(migrator, books.identifiersJson);
        await _addBookColumnIfMissing(migrator, books.subjectsJson);
        await _addBookColumnIfMissing(migrator, books.rights);
        await _addBookColumnIfMissing(migrator, books.seriesName);
        await _addBookColumnIfMissing(migrator, books.seriesIndex);
        await _addBookColumnIfMissing(migrator, books.edition);
        await _addBookColumnIfMissing(migrator, books.source);
        await _addBookColumnIfMissing(migrator, books.coverage);
        await _addBookColumnIfMissing(migrator, books.type);
        await _addBookColumnIfMissing(migrator, books.modifiedDate);
      }
      if (from < 11) {
        await _addBookColumnIfMissing(migrator, books.catalogSourceId);
        await _addBookColumnIfMissing(migrator, books.remotePublicationId);
        await _addBookColumnIfMissing(
          migrator,
          books.remotePublicationLocation,
        );
        await _addBookColumnIfMissing(
          migrator,
          books.remoteAcquisitionLocation,
        );
        await _addBookColumnIfMissing(migrator, books.metadataOriginsJson);
      }
      if (from < 12) {
        await migrator.createTable(remoteDownloadTasks);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS remote_download_tasks_state_updated_at '
          'ON remote_download_tasks(state, updated_at)',
        );
      } else if (from < 13) {
        await migrator.addColumn(
          remoteDownloadTasks,
          remoteDownloadTasks.remoteMetadataJson,
        );
      }
      if (from < 14) {
        await _addBookColumnIfMissing(migrator, books.tocJson);
      }
      if (from < 15) {
        await migrator.createTable(remoteCacheSettingsEntries);
        await customStatement(
          'INSERT OR IGNORE INTO remote_cache_settings_entries '
          '(id, maximum_bytes) VALUES (1, $remoteCacheDefaultMaximumBytes)',
        );
      }
      if (from < 16) {
        await migrator.createTable(homeOnlineTabSettingsEntries);
      }
      if (from < 17) {
        await _addBookColumnIfMissing(migrator, books.coverProvenance);
        // Earlier rows cannot prove an online origin. Their existing local
        // file came from the import pipeline, so keep it as embedded rather
        // than allowing metadata refresh to downgrade it to a placeholder.
        final tables = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'books'",
        ).get();
        if (tables.isNotEmpty) {
          await customStatement(
            "UPDATE books SET cover_provenance = 'embedded' "
            "WHERE cover_path IS NOT NULL AND trim(cover_path) <> ''",
          );
        }
      }
      if (from < 18) {
        await migrator.createTable(librarySectionSettingsEntries);
      }
      if (from < 19) {
        await migrator.createTable(homeDefaultCarouselSettingsEntries);
      }
      if (from < 20) {
        // Some historical fixtures predate Collections altogether. In that
        // case the v4 branch above creates the current table, so adding these
        // columns again would fail. Existing v19 databases still receive both
        // columns through the same guarded operation.
        await _addCollectionColumnIfMissing(migrator, collections.description);
        await _addCollectionColumnIfMissing(
          migrator,
          collections.customCoverPath,
        );
      }
      if (from < 21) {
        final existing = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name = 'book_display_settings_entries'",
        ).get();
        if (existing.isEmpty) {
          await migrator.createTable(bookDisplaySettingsEntries);
        }
      }
      if (from < 23) {
        // Phase 1 statuses are rejected data, not collection memberships.
        await customStatement('DROP TABLE IF EXISTS reading_status_entries');
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await _ensureSystemCollections();
    },
  );

  Future<void> _ensureSystemCollections() async {
    // Existing user names may match display names or even the internal key.
    // Never rename them: choose an unused private normalized key instead.
    for (final entry in systemCollectionNames.entries) {
      final existing = await (select(
        collections,
      )..where((c) => c.id.equals(entry.key))).getSingleOrNull();
      if (existing != null) continue;
      var key = '\u0000${entry.key}';
      var suffix = 0;
      while (await (select(
            collections,
          )..where((c) => c.normalizedName.equals(key))).getSingleOrNull() !=
          null) {
        key = '\u0000${entry.key}:${++suffix}';
      }
      final now = DateTime.now();
      await into(collections).insert(
        CollectionsCompanion.insert(
          id: entry.key,
          name: entry.value,
          normalizedName: key,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
  }

  Future<void> _addBookColumnIfMissing(
    Migrator migrator,
    GeneratedColumn<Object> column,
  ) async {
    final tables = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'books'",
    ).get();
    if (tables.isEmpty) return;
    final columns = await customSelect('PRAGMA table_info(books)').get();
    if (columns.any((row) => row.read<String>('name') == column.$name)) return;
    await migrator.addColumn(books, column);
  }

  Future<void> _addCollectionColumnIfMissing(
    Migrator migrator,
    GeneratedColumn<Object> column,
  ) async {
    final tables = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'collections'",
    ).get();
    if (tables.isEmpty) return;
    final columns = await customSelect('PRAGMA table_info(collections)').get();
    if (columns.any((row) => row.read<String>('name') == column.$name)) return;
    await migrator.addColumn(collections, column);
  }
}

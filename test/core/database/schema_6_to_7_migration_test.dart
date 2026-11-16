import 'dart:io';

import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/catalog_sources/data/built_in_catalog_sources.dart';
import 'package:bibliolife/features/catalog_sources/data/drift_catalog_source_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'migrates a real schema 10 books row to nullable schema 11 provenance',
    () async {
      final directory = await Directory.systemTemp.createTemp('bibliolife_v9');
      final file = File(
        '${directory.path}${Platform.pathSeparator}bibliolife.sqlite',
      );
      final executor = NativeDatabase(
        file,
        setup: (database) {
          database.execute('''
          CREATE TABLE books (
            id TEXT NOT NULL PRIMARY KEY,
            title TEXT NOT NULL,
            sort_title TEXT NULL,
            author TEXT NULL,
            description TEXT NULL,
            file_path TEXT NOT NULL UNIQUE,
            original_file_path TEXT NULL UNIQUE,
            file_name TEXT NOT NULL,
            file_extension TEXT NOT NULL,
            media_type TEXT NULL,
            cover_path TEXT NULL,
            language TEXT NULL,
            publisher TEXT NULL,
            published_date TEXT NULL,
            isbn TEXT NULL,
            page_count INTEGER NULL,
            file_size_bytes INTEGER NOT NULL,
            date_added INTEGER NOT NULL,
            last_opened_at INTEGER NULL,
            is_favorite INTEGER NOT NULL DEFAULT 0,
            authors_json TEXT NULL,
            contributors_json TEXT NULL,
            identifiers_json TEXT NULL,
            subjects_json TEXT NULL,
            rights TEXT NULL,
            series_name TEXT NULL,
            series_index REAL NULL,
            edition TEXT NULL,
            source TEXT NULL,
            coverage TEXT NULL,
            type TEXT NULL,
            modified_date TEXT NULL
          )
        ''');
          database.execute(
            "INSERT INTO books "
            "(id,title,author,file_path,file_name,file_extension,file_size_bytes,date_added,is_favorite) "
            "VALUES ('v9-book','Preserved','Author','/books/v9.epub','v9.epub','epub',42,0,1)",
          );
          // A real schema 10 database already has the schema 4 collections table.
          database.execute(
            'CREATE TABLE collections (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, normalized_name TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, sort_order INTEGER)',
          );
          database.execute('PRAGMA user_version = 10');
        },
      );
      final database = AppDatabase(executor);
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });

      final row = await database.booksDao.getBookById('v9-book');

      expect(row?.title, 'Preserved');
      expect(row?.author, 'Author');
      expect(row?.filePath, '/books/v9.epub');
      expect(row?.isFavorite, isTrue);
      expect(row?.authorsJson, null);
      expect(row?.subjectsJson, null);
      expect(row?.rights, null);
      expect(row?.seriesName, null);
      expect(row?.catalogSourceId, null);
      expect(row?.metadataOriginsJson, null);
      expect(
        (await database.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        23,
      );
      expect(
        await database.select(database.remoteDownloadTasks).get(),
        isEmpty,
      );
      expect(
        (await database
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type='index' "
                  "AND name='remote_download_tasks_state_updated_at'",
                )
                .getSingle())
            .read<String>('name'),
        'remote_download_tasks_state_updated_at',
      );
    },
  );

  test(
    'migrates a schema 8 fixture to 11 and seeds built-in sources idempotently',
    () async {
      final directory = await Directory.systemTemp.createTemp('bibliolife_v8');
      final file = File(
        '${directory.path}${Platform.pathSeparator}bibliolife.sqlite',
      );
      final fixture = AppDatabase(NativeDatabase(file));
      await fixture.booksDao.insertBook(
        BooksCompanion.insert(
          id: 'v8-book',
          title: 'Preserved title',
          author: const Value('Author'),
          filePath: '/books/v8.epub',
          fileName: 'v8.epub',
          fileExtension: 'epub',
          fileSizeBytes: 1,
          dateAdded: DateTime(2026),
          isFavorite: const Value(true),
        ),
      );
      await fixture.readingProgressDao.upsertProgress(
        ReadingProgressEntriesCompanion.insert(
          bookId: 'v8-book',
          locatorJson: const Value('{"href":"chapter.xhtml"}'),
          updatedAt: DateTime(2026),
        ),
      );
      await fixture.bookmarksDao.insertBookmark(
        BookmarksCompanion.insert(
          id: 'v8-bookmark',
          bookId: 'v8-book',
          locatorJson: '{"href":"chapter.xhtml"}',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
      await fixture
          .into(fixture.readerAnnotations)
          .insert(
            ReaderAnnotationsCompanion.insert(
              id: 'v8-annotation',
              bookId: 'v8-book',
              locatorJson: '{"href":"chapter.xhtml"}',
              locationKey: 'chapter.xhtml|0',
              selectedText: 'Preserved annotation',
              href: 'chapter.xhtml',
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          );
      await fixture.appConnectivitySettingsDao.upsert(
        AppConnectivitySettingsEntriesCompanion.insert(
          id: const Value(1),
          mode: 'online',
          hasAcknowledgedOnline: true,
        ),
      );
      await fixture.customStatement('DROP TABLE catalog_sources_entries');
      await fixture.customStatement('PRAGMA user_version = 8');
      await fixture.close();
      final database = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });
      expect(
        (await database.booksDao.getBookById('v8-book'))?.filePath,
        '/books/v8.epub',
      );
      expect(
        (await database.readingProgressDao.getProgressForBook(
          'v8-book',
        ))?.locatorJson,
        '{"href":"chapter.xhtml"}',
      );
      expect(await database.bookmarksDao.countForBook('v8-book'), 1);
      expect(
        (await database.select(database.readerAnnotations).get())
            .single
            .selectedText,
        'Preserved annotation',
      );
      expect(
        (await database.appConnectivitySettingsDao.load())?.mode,
        'online',
      );
      final repository = DriftCatalogSourceRepository(database);
      await repository.ensureBuiltInSources();
      await repository.ensureBuiltInSources();
      final sources = await repository.getAll();
      expect(
        sources.map((source) => source.id).toSet(),
        builtInCatalogSources.map((source) => source.id).toSet(),
      );
      expect(sources, hasLength(builtInCatalogSources.length));
    },
  );

  test(
    'migrates schema 6 to 11 while preserving book, bookmark and progress',
    () async {
      final directory = await Directory.systemTemp.createTemp('bibliolife_v6');
      final file = File(
        '${directory.path}${Platform.pathSeparator}bibliolife.sqlite',
      );
      final fixture = AppDatabase(NativeDatabase(file));
      await fixture.booksDao.insertBook(
        BooksCompanion.insert(
          id: 'book-1',
          title: 'Book',
          filePath: '/books/book.epub',
          fileName: 'book.epub',
          fileExtension: 'epub',
          fileSizeBytes: 1,
          dateAdded: DateTime(2026),
        ),
      );
      await fixture.bookmarksDao.insertBookmark(
        BookmarksCompanion.insert(
          id: 'bookmark-1',
          bookId: 'book-1',
          locatorJson: '{"href":"chapter.xhtml"}',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
      await fixture.readingProgressDao.upsertProgress(
        ReadingProgressEntriesCompanion.insert(
          bookId: 'book-1',
          locatorJson: const Value('{"href":"chapter.xhtml"}'),
          updatedAt: DateTime(2026),
        ),
      );
      await fixture.customStatement('DROP TABLE reader_annotations');
      await fixture.customStatement('PRAGMA user_version = 6');
      await fixture.close();

      final database = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });
      expect(
        (await database.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        23,
      );
      expect(
        await database.select(database.remoteDownloadTasks).get(),
        isEmpty,
      );
      expect((await database.booksDao.getBookById('book-1'))?.title, 'Book');
      expect(await database.bookmarksDao.countForBook('book-1'), 1);
      expect(
        (await database.readingProgressDao.getProgressForBook(
          'book-1',
        ))?.locatorJson,
        '{"href":"chapter.xhtml"}',
      );
      expect(
        (await database
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type='table' AND name='reader_annotations'",
                )
                .get())
            .single
            .read<String>('name'),
        'reader_annotations',
      );
      expect(
        (await database
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type='table' AND name='app_connectivity_settings_entries'",
                )
                .get())
            .single
            .read<String>('name'),
        'app_connectivity_settings_entries',
      );
      expect(
        (await database
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type='table' AND name='catalog_sources_entries'",
                )
                .get())
            .single
            .read<String>('name'),
        'catalog_sources_entries',
      );
    },
  );

  test(
    'migrates schema 12 queue rows to nullable metadata snapshots',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bibliolife-schema-12-',
      );
      final file = File('${directory.path}/bibliolife.sqlite');
      final fixture = AppDatabase(NativeDatabase(file));
      await fixture.customSelect('SELECT 1').get();
      await fixture.customStatement(
        'ALTER TABLE remote_download_tasks DROP COLUMN remote_metadata_json',
      );
      await fixture.customStatement(
        "INSERT INTO remote_download_tasks ("
        "id, source_id, publication_remote_id, title, authors_json, "
        "acquisition_uri, suggested_filename, downloaded_bytes, state, "
        "created_at, updated_at, retry_count, attempt_id"
        ") VALUES ("
        "'legacy', 'source', 'publication', 'Legacy', '[\"Author\"]', "
        "'https://example.test/book.epub', 'Legacy.epub', 0, 'queued', "
        "0, 0, 0, 0"
        ")",
      );
      await fixture.customStatement('PRAGMA user_version = 12');
      await fixture.close();

      final database = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });
      final row = await (database.select(
        database.remoteDownloadTasks,
      )..where((table) => table.id.equals('legacy'))).getSingle();

      expect(row.title, 'Legacy');
      expect(row.remoteMetadataJson, null);
      expect(
        (await database.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        23,
      );
    },
  );
}

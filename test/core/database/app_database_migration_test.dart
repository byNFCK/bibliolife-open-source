import 'dart:io';

import 'package:bibliolife/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'migrates a genuine v3 database to the current schema without losing existing data',
    () async {
      final directory = await Directory.systemTemp.createTemp('bibliolife_v3');
      final file = File(
        '${directory.path}${Platform.pathSeparator}bibliolife.sqlite',
      );
      final database = AppDatabase(
        NativeDatabase(
          file,
          setup: (database) => _createV3Schema(database.execute),
        ),
      );
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });

      expect((await database.booksDao.getBookById('book-1'))?.title, 'Book');
      expect(
        (await database.readingProgressDao.getProgressForBook(
          'book-1',
        ))?.progression,
        0.5,
      );
      expect((await database.epubReaderSettingsDao.load())?.theme, 'system');
      expect(await database.bookmarksDao.countForBook('book-1'), 0);
      expect(
        (await database
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'book_collection_entries_collection_id'",
                )
                .get())
            .single
            .read<String>('name'),
        'book_collection_entries_collection_id',
      );
      expect(
        (await database.customSelect('PRAGMA foreign_keys').get()).single
            .read<int>('foreign_keys'),
        1,
      );

      await database.collectionsDao.insertCollection(
        CollectionsCompanion.insert(
          id: 'collection-1',
          name: 'Unread',
          normalizedName: 'unread',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
      await database.collectionsDao.addMembership(
        BookCollectionEntriesCompanion.insert(
          bookId: 'book-1',
          collectionId: 'collection-1',
          addedAt: DateTime(2026),
        ),
      );
      await database.booksDao.deleteBookById('book-1');
      expect(
        await database.collectionsDao.containsMembership(
          'collection-1',
          'book-1',
        ),
        isFalse,
      );
    },
  );
}

void _createV3Schema(void Function(String) execute) {
  execute('''
    CREATE TABLE books (
      id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, sort_title TEXT,
      author TEXT, description TEXT, file_path TEXT NOT NULL UNIQUE,
      original_file_path TEXT UNIQUE, file_name TEXT NOT NULL,
      file_extension TEXT NOT NULL, media_type TEXT, cover_path TEXT,
      language TEXT, publisher TEXT, published_date TEXT, isbn TEXT,
      page_count INTEGER, file_size_bytes INTEGER NOT NULL,
      date_added INTEGER NOT NULL, last_opened_at INTEGER,
      is_favorite INTEGER NOT NULL DEFAULT 0
    )
  ''');
  execute('''
    CREATE TABLE reading_progress_entries (
      book_id TEXT NOT NULL PRIMARY KEY, locator_json TEXT, progression REAL NOT NULL DEFAULT 0.0,
      current_chapter_title TEXT, current_page INTEGER, total_pages INTEGER,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
    )
  ''');
  execute('''
    CREATE TABLE epub_reader_settings_entries (
      id INTEGER NOT NULL PRIMARY KEY, theme TEXT NOT NULL, font_size REAL NOT NULL,
      line_height REAL NOT NULL, page_margins REAL NOT NULL,
      publisher_styles INTEGER NOT NULL, updated_at INTEGER NOT NULL
    )
  ''');
  execute(
    "INSERT INTO books VALUES ('book-1', 'Book', NULL, NULL, NULL, '/books/book.epub', NULL, 'book.epub', 'epub', NULL, NULL, NULL, NULL, NULL, NULL, NULL, 1, 0, NULL, 0)",
  );
  execute(
    "INSERT INTO reading_progress_entries VALUES ('book-1', NULL, 0.5, NULL, NULL, NULL, 1)",
  );
  execute(
    "INSERT INTO epub_reader_settings_entries VALUES (1, 'system', 1.0, 1.5, 1.0, 1, 1)",
  );
  execute('PRAGMA user_version = 3');
}

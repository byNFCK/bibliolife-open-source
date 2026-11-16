import 'dart:io';

import 'package:bibliolife/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'v16 migration preserves a book and classifies its local cover conservatively',
    () async {
      final directory = await Directory.systemTemp.createTemp('bibliolife_v16');
      final file = File(
        '${directory.path}${Platform.pathSeparator}bibliolife.db',
      );
      final old = AppDatabase(NativeDatabase(file));
      await old.customStatement(
        "INSERT INTO books (id, title, file_path, file_name, file_extension, "
        "file_size_bytes, date_added, cover_path) VALUES "
        "('book-1', 'Preserved', '/books/one.epub', 'one.epub', 'epub', 1, "
        "'2026-01-01 00:00:00.000', '/covers/one.png')",
      );
      await old.customStatement(
        'ALTER TABLE books DROP COLUMN cover_provenance',
      );
      await old.customStatement('PRAGMA user_version = 16');
      await old.close();

      final migrated = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await migrated.close();
        await directory.delete(recursive: true);
      });

      final row = await migrated
          .customSelect('SELECT cover_path, cover_provenance FROM books')
          .getSingle();
      expect(row.read<String>('cover_path'), '/covers/one.png');
      expect(row.read<String>('cover_provenance'), 'embedded');
    },
  );
}

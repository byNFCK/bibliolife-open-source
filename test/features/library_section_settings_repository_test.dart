import 'dart:io';

import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/library/data/repositories/drift_library_section_settings_repository.dart';
import 'package:bibliolife/features/library/domain/library_section.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftLibrarySectionSettingsRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftLibrarySectionSettingsRepository(
      database.librarySectionSettingsDao,
    );
  });

  tearDown(() => database.close());

  test('missing preference defaults to All books', () async {
    expect(await repository.load(), LibrarySection.allBooks);
  });

  for (final entry in {
    'collection': LibrarySection.collection,
    'follow': LibrarySection.follow,
    'all_books': LibrarySection.allBooks,
    'unsorted': LibrarySection.allBooks,
  }.entries) {
    test('loads stable stored value ${entry.key}', () async {
      await database.librarySectionSettingsDao.upsert(
        LibrarySectionSettingsEntriesCompanion.insert(
          id: const Value(1),
          defaultSection: entry.key,
        ),
      );

      expect(await repository.load(), entry.value);
    });
  }

  test('unknown stored value falls back to and repairs All books', () async {
    await database.librarySectionSettingsDao.upsert(
      LibrarySectionSettingsEntriesCompanion.insert(
        id: const Value(1),
        defaultSection: 'something_old',
      ),
    );

    expect(await repository.load(), LibrarySection.allBooks);
    expect(
      (await database.librarySectionSettingsDao.load())?.defaultSection,
      'all_books',
    );
  });

  test('persists the default across database recreation', () async {
    await database.close();
    final directory = await Directory.systemTemp.createTemp(
      'library-section-settings-',
    );
    final file = File('${directory.path}${Platform.pathSeparator}settings.db');
    final first = AppDatabase(NativeDatabase(file));
    await DriftLibrarySectionSettingsRepository(
      first.librarySectionSettingsDao,
    ).save(LibrarySection.follow);
    await first.close();

    final reopened = AppDatabase(NativeDatabase(file));
    addTearDown(() async {
      await reopened.close();
      await directory.delete(recursive: true);
    });

    expect(
      await DriftLibrarySectionSettingsRepository(
        reopened.librarySectionSettingsDao,
      ).load(),
      LibrarySection.follow,
    );
  });

  test('saves All books using the canonical persisted value', () async {
    await repository.save(LibrarySection.allBooks);

    expect(
      (await database.librarySectionSettingsDao.load())?.defaultSection,
      'all_books',
    );
  });
}

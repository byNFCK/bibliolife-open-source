import 'package:bibliolife/shared/presentation/widgets/biblio_tabs.dart';
import 'dart:async';
import 'dart:io';

import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:bibliolife/features/library/data/repositories/drift_book_display_settings_repository.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_view_toggle.dart';
import 'package:bibliolife/features/settings/presentation/widgets/settings_body.dart';
import 'package:bibliolife/app/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer containerFor(AppDatabase database) => ProviderContainer(
  overrides: [appDatabaseProvider.overrideWithValue(database)],
);

void main() {
  test(
    'default and unknown stored values safely use Grid without rewriting',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = DriftBookDisplaySettingsRepository(database);
      for (final stored in [null, 'unknown', 'grid', 'list']) {
        if (stored != null) await repository.save(stored);
        final container = containerFor(database);
        container.read(libraryViewModeProvider);
        await container.read(libraryViewModeProvider.notifier).ready;
        expect(
          container.read(libraryViewModeProvider),
          stored == 'list' ? LibraryViewMode.list : LibraryViewMode.grid,
        );
        expect(await repository.load(), stored);
        container.dispose();
      }
    },
  );

  test('layout survives database and application restart', () async {
    final directory = await Directory.systemTemp.createTemp('book_layout');
    final file = File('${directory.path}/settings.db');
    var database = AppDatabase(NativeDatabase(file));
    var container = containerFor(database);
    container.read(libraryViewModeProvider);
    await container.read(libraryViewModeProvider.notifier).ready;
    await container
        .read(libraryViewModeProvider.notifier)
        .setMode(LibraryViewMode.list);
    container.dispose();
    await database.close();
    database = AppDatabase(NativeDatabase(file));
    container = containerFor(database);
    container.read(libraryViewModeProvider);
    await container.read(libraryViewModeProvider.notifier).ready;
    expect(container.read(libraryViewModeProvider), LibraryViewMode.list);
    container.dispose();
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'v20 upgrade preserves existing Library preference and adds Grid default',
    () async {
      final directory = await Directory.systemTemp.createTemp('layout_v20');
      final file = File('${directory.path}/settings.db');
      final old = AppDatabase(NativeDatabase(file));
      await old.customStatement(
        "INSERT INTO library_section_settings_entries (id, default_section) VALUES (1, 'follow')",
      );
      await old.customStatement('DROP TABLE book_display_settings_entries');
      await old.customStatement('PRAGMA user_version = 20');
      await old.close();
      final migrated = AppDatabase(NativeDatabase(file));
      final container = containerFor(migrated);
      container.read(libraryViewModeProvider);
      await container.read(libraryViewModeProvider.notifier).ready;
      expect(container.read(libraryViewModeProvider), LibraryViewMode.grid);
      expect(
        (await migrated.librarySectionSettingsDao.load())?.defaultSection,
        'follow',
      );
      await container
          .read(libraryViewModeProvider.notifier)
          .setMode(LibraryViewMode.list);
      expect(
        (await migrated.librarySectionSettingsDao.load())?.defaultSection,
        'follow',
      );
      container.dispose();
      await migrated.close();
      await directory.delete(recursive: true);
    },
  );

  test(
    'late load cannot overwrite user action and rapid saves stay ordered',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = _DelayedRepository(database);
      final container = ProviderContainer(
        overrides: [
          bookDisplaySettingsRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      container.read(libraryViewModeProvider);
      final notifier = container.read(libraryViewModeProvider.notifier);
      final first = notifier.setMode(LibraryViewMode.list);
      final last = notifier.setMode(LibraryViewMode.grid);
      repository.loaded.complete('list');
      await Future.wait([first, last]);
      expect(container.read(libraryViewModeProvider), LibraryViewMode.grid);
      expect(await DriftBookDisplaySettingsRepository(database).load(), 'grid');
    },
  );

  test('failed save rolls back to durable selection', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final container = ProviderContainer(
      overrides: [
        bookDisplaySettingsRepositoryProvider.overrideWithValue(
          _FailingRepository(database),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(libraryViewModeProvider);
    final notifier = container.read(libraryViewModeProvider.notifier);
    await notifier.ready;
    await expectLater(notifier.setMode(LibraryViewMode.grid), throwsStateError);
    expect(container.read(libraryViewModeProvider), LibraryViewMode.list);
  });

  for (final theme in [lightTheme, darkTheme]) {
    testWidgets(
      'narrow large text selector synchronizes toolbar in ${theme.brightness}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final container = containerFor(database);
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(2)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      const BookDisplayLayoutSettingTile(),
                      Consumer(
                        builder: (context, ref, _) => LibraryViewToggle(
                          viewMode: ref.watch(libraryViewModeProvider),
                          onPressed: () => ref
                              .read(libraryViewModeProvider.notifier)
                              .toggle(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('book-display-option-list')));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Show grid view'), findsOneWidget);
        expect(
          tester
              .widget<BiblioTabs<LibraryViewMode>>(
                find.byType(BiblioTabs<LibraryViewMode>),
              )
              .selectedId,
          LibraryViewMode.list,
        );
        await tester.ensureVisible(find.byTooltip('Show grid view'));
        await tester.tap(find.byTooltip('Show grid view'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<BiblioTabs<LibraryViewMode>>(
                find.byType(BiblioTabs<LibraryViewMode>),
              )
              .selectedId,
          LibraryViewMode.grid,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _DelayedRepository extends DriftBookDisplaySettingsRepository {
  _DelayedRepository(super.database);
  final loaded = Completer<String?>();
  @override
  Future<String?> load() => loaded.future;
}

class _FailingRepository extends DriftBookDisplaySettingsRepository {
  _FailingRepository(super.database);
  @override
  Future<String?> load() async => 'list';
  @override
  Future<void> save(String layout) async => throw StateError('disk full');
}

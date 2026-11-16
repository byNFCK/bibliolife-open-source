import 'package:bibliolife/features/collections/domain/models/system_collection.dart';
import 'package:bibliolife/features/collections/presentation/system_collection_colors.dart';
import '../support/unified_book_list_assertions.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_providers.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:bibliolife/shared/presentation/widgets/app_book_card.dart';
import 'package:bibliolife/shared/presentation/widgets/app_book_list_tile.dart';
import 'package:bibliolife/features/collections/application/providers/collection_editor_providers.dart';
import 'package:bibliolife/features/collections/application/providers/collection_providers.dart';
import 'package:bibliolife/features/collections/application/providers/collection_repository_provider.dart';
import 'package:bibliolife/features/collections/data/services/collection_cover_picker.dart';
import 'package:bibliolife/features/collections/domain/models/library_collection.dart';
import 'package:bibliolife/features/collections/domain/repositories/collection_repository.dart';
import 'package:bibliolife/features/collections/presentation/screens/collection_editor_screen.dart';
import 'package:bibliolife/features/collections/presentation/widgets/collection_cover.dart';
import 'package:bibliolife/features/library/application/providers/library_providers.dart';
import 'package:bibliolife/features/metadata/application/providers/cover_storage_service_provider.dart';
import 'package:bibliolife/features/metadata/data/services/cover_storage_service.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'system editor keeps name fixed and saves description, cover and books',
    (tester) async {
      final directory = Directory(
        'build/system-editor-${DateTime.now().microsecondsSinceEpoch}',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = _FakeCollectionRepository();
      final books = [_book('a', 'Book A'), _book('b', 'Book B')];
      final collection = LibraryCollection(
        id: systemReadingId,
        name: 'Reading',
        normalizedName: 'reserved',
        description: 'Before',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        sortOrder: null,
      );
      await tester.pumpWidget(
        _subject(
          repository: repository,
          books: books,
          collection: collection,
          memberBooks: [books[0]],
          collectionId: collection.id,
          picker: const _FakeCoverPicker(),
          storage: CoverStorageService(
            documentsDirectory: () async => directory,
            imageValidator: const _AlwaysValidImageValidator(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('collection-editor-name')))
            .readOnly,
        isTrue,
      );
      expect(
        Theme.of(
          tester.element(find.byKey(const Key('collection-editor-name'))),
        ).colorScheme.primary,
        systemCollectionColorScheme(systemReadingId, Brightness.light)!.primary,
      );
      await tester.enterText(
        find.byKey(const Key('collection-editor-description')),
        'After',
      );
      await tester.runAsync(() async {
        tester
            .widget<InkWell>(
              find.byKey(const Key('collection-editor-cover-uploader')),
            )
            .onTap!();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const Key('collection-editor-add-book')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collection-editor-add-book')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collection-book-option-a')));
      await tester.tap(find.byKey(const Key('collection-book-option-b')));
      await tester.tap(find.byKey(const Key('collection-book-selector-done')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collection-editor-save')));
      await tester.pumpAndSettle();
      expect(repository.lastSave!.name, 'Reading');
      expect(repository.lastSave!.description, 'After');
      expect(repository.lastSave!.customCoverPath, isNotNull);
      expect(repository.lastSave!.selectedBookIds, {'b'});
    },
  );

  testWidgets(
    'discarding a system cover draft requests temporary cover cleanup',
    (tester) async {
      final storage = _TrackingCoverStorage();
      final repository = _FakeCollectionRepository();
      final collection = LibraryCollection(
        id: systemFinishedId,
        name: 'Finished',
        normalizedName: 'reserved',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        sortOrder: null,
      );
      await tester.pumpWidget(
        _subject(
          repository: repository,
          books: const [],
          collection: collection,
          memberBooks: const [],
          collectionId: collection.id,
          picker: const _FakeCoverPicker(),
          storage: storage,
        ),
      );
      await tester.pumpAndSettle();
      tester
          .widget<InkWell>(
            find.byKey(const Key('collection-editor-cover-uploader')),
          )
          .onTap!();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collection-editor-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(storage.deleted, ['/missing/test-draft.png']);
      expect(repository.lastSave, isNull);
    },
  );

  for (final mode in LibraryViewMode.values) {
    testWidgets('selector preserves checked state and Done in $mode', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _FakeCollectionRepository();
      await tester.pumpWidget(
        _subject(
          repository: repository,
          books: [_book('a', 'Book A'), _book('b', 'Book B')],
          mode: mode,
          initialBookIds: {'a'},
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('collection-editor-add-book')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collection-editor-add-book')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(const ValueKey('collection-book-option-a')),
            )
            .value,
        isTrue,
      );
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(const ValueKey('collection-book-option-b')),
            )
            .value,
        isFalse,
      );
      if (mode == LibraryViewMode.list) {
        expect(find.byType(AppBookListTile), findsWidgets);
        expectUnifiedBookList(tester);
        final tile = tester.widget<AppBookListTile>(
          find.byKey(const ValueKey('collection-book-selector-row-b')),
        );
        expect(tile.title, 'Book B');
        expect(tile.actions.single, isA<Checkbox>());
        await tester.tap(find.text('Book B').last);
      } else {
        expect(
          find.byKey(const ValueKey('collection-book-selector-card-b')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('collection-book-option-b')),
        );
      }
      await tester.pump();
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(const ValueKey('collection-book-option-b')),
            )
            .value,
        isTrue,
      );
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
      await tester.tap(find.byKey(const Key('collection-book-selector-done')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('collection-editor-name')),
        'Selected',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collection-editor-save')));
      await tester.pumpAndSettle();
      expect(repository.lastSave?.selectedBookIds, {'a', 'b'});
    });
  }

  for (final mode in LibraryViewMode.values) {
    for (final dark in [false, true]) {
      testWidgets(
        'collection selection is lazy and fits 320px scale2 $mode dark=$dark',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(320, 1000));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            _subject(
              repository: _FakeCollectionRepository(),
              books: List.generate(
                200,
                (i) => _book('$i', 'Long book title number $i'),
              ),
              mode: mode,
              dark: dark,
              scale: 2,
              initialBookIds: {'0'},
            ),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(const Key('collection-editor-add-book')),
            300,
            scrollable: find
                .descendant(
                  of: find.byKey(const Key('collection-editor-scroll')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('collection-editor-add-book')));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<Checkbox>(
                  find.byKey(const ValueKey('collection-book-option-0')),
                )
                .value,
            isTrue,
          );
          expect(find.byType(Checkbox).evaluate().length, lessThan(30));
          expect(tester.takeException(), isNull);
          final container = ProviderScope.containerOf(
            tester.element(find.byType(CollectionEditorScreen)),
          );
          final other = mode == LibraryViewMode.grid
              ? LibraryViewMode.list
              : LibraryViewMode.grid;
          await container.read(libraryViewModeProvider.notifier).setMode(other);
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<Checkbox>(
                  find.byKey(const ValueKey('collection-book-option-0')),
                )
                .value,
            isTrue,
          );
          expect(tester.takeException(), isNull);
          await tester.tap(
            find.byKey(const Key('collection-book-selector-done')),
          );
          await tester.pumpAndSettle();
          expect(find.byType(CollectionEditorScreen), findsOneWidget);
        },
      );
    }
  }

  testWidgets('selector keeps independent layout offsets and checked values', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _subject(
        repository: _FakeCollectionRepository(),
        books: List.generate(200, (i) => _book('$i', 'Book $i')),
        initialBookIds: {'0'},
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('collection-editor-add-book')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('collection-editor-add-book')));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CollectionEditorScreen)),
    );
    Finder scroll() => find
        .descendant(
          of: find.byKey(const Key('collection-book-selector')),
          matching: find.byType(Scrollable),
        )
        .first;
    tester.state<ScrollableState>(scroll()).position.jumpTo(1200);
    await tester.pumpAndSettle();
    await container
        .read(libraryViewModeProvider.notifier)
        .setMode(LibraryViewMode.list);
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(scroll()).position.pixels, 0);
    tester.state<ScrollableState>(scroll()).position.jumpTo(600);
    await tester.pumpAndSettle();
    await container
        .read(libraryViewModeProvider.notifier)
        .setMode(LibraryViewMode.grid);
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(scroll()).position.pixels,
      closeTo(1200, 1),
    );
    await container
        .read(libraryViewModeProvider.notifier)
        .setMode(LibraryViewMode.list);
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(scroll()).position.pixels,
      closeTo(600, 1),
    );
    tester.state<ScrollableState>(scroll()).position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const ValueKey('collection-book-option-0')),
          )
          .value,
      isTrue,
    );
  });

  testWidgets(
    'editor retains layout offsets without replacing its scroll controller',
    (tester) async {
      await tester.pumpWidget(
        _subject(
          repository: _FakeCollectionRepository(),
          books: List.generate(200, (i) => _book('$i', 'Book $i')),
          initialBookIds: {for (var i = 0; i < 200; i++) '$i'},
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CollectionEditorScreen)),
      );
      final root = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const Key('collection-editor-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      root.position.jumpTo(1800);
      await tester.pumpAndSettle();
      await container
          .read(libraryViewModeProvider.notifier)
          .setMode(LibraryViewMode.list);
      await tester.pumpAndSettle();
      expect(root.position.pixels, 0);
      root.position.jumpTo(1300);
      await tester.pumpAndSettle();
      await container
          .read(libraryViewModeProvider.notifier)
          .setMode(LibraryViewMode.grid);
      await tester.pumpAndSettle();
      expect(root.position.pixels, closeTo(1800, 1));
      await container
          .read(libraryViewModeProvider.notifier)
          .setMode(LibraryViewMode.list);
      await tester.pumpAndSettle();
      expect(root.position.pixels, closeTo(1300, 1));
      expect(find.byType(AppBookListTile).evaluate().length, lessThan(30));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'List draft remove can be cancelled and discarded without saving membership',
    (tester) async {
      final repository = _FakeCollectionRepository();
      await tester.pumpWidget(
        _subject(
          repository: repository,
          books: [_book('a', 'Book A')],
          initialBookIds: {'a'},
          mode: LibraryViewMode.list,
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('collection-editor-remove-a')),
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('collection-editor-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('collection-editor-remove-a')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('collection-editor-back')));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(CollectionEditorScreen), findsOneWidget);
      expect(repository.lastSave, isNull);
      await tester.tap(find.byKey(const Key('collection-editor-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(CollectionEditorScreen), findsNothing);
      expect(repository.lastSave, isNull);
    },
  );

  testWidgets(
    'layout change retains editor fields, draft and remove is draft-only',
    (tester) async {
      final repository = _FakeCollectionRepository();
      await tester.pumpWidget(
        _subject(
          repository: repository,
          books: [_book('a', 'Book A'), _book('b', 'Book B')],
          initialBookIds: {'a', 'b'},
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('collection-editor-name')),
        'Draft',
      );
      await tester.enterText(
        find.byKey(const Key('collection-editor-description')),
        'Description',
      );
      final field = tester
          .widget<TextField>(find.byKey(const Key('collection-editor-name')))
          .controller;
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CollectionEditorScreen)),
      );
      await container
          .read(libraryViewModeProvider.notifier)
          .setMode(LibraryViewMode.list);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('collection-editor-name')))
            .controller,
        same(field),
      );
      expect(field!.text, 'Draft');
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('collection-editor-description')),
            )
            .controller!
            .text,
        'Description',
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('collection-editor-remove-a')),
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('collection-editor-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('collection-editor-remove-a')),
      );
      await tester.pumpAndSettle();
      expect(repository.lastSave, isNull);
      expect(
        find.byKey(const ValueKey('collection-editor-book-row-a')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('collection-editor-book-row-b')),
        findsOneWidget,
      );
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      final row = tester.widget<AppBookListTile>(
        find.byKey(const ValueKey('collection-editor-book-row-b')),
      );
      expect(row.onOpen, isNull);
      expectUnifiedBookList(tester);
      await container
          .read(libraryViewModeProvider.notifier)
          .setMode(LibraryViewMode.grid);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('collection-editor-book-card-b')),
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('collection-editor-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final card = tester.widget<AppBookCard>(
        find.byKey(const ValueKey('collection-editor-book-card-b')),
      );
      expect(card.onOpen, isNull);
      expect(card.favoriteAvailable, isFalse);
      await tester.tap(find.byKey(const Key('collection-editor-save')));
      await tester.pumpAndSettle();
      expect(repository.lastSave?.selectedBookIds, {'b'});
      expect(repository.lastSave?.description, 'Description');
    },
  );

  testWidgets('create editor starts as a draft and saves metadata', (
    tester,
  ) async {
    final repository = _FakeCollectionRepository();
    final books = [_book('book-a', 'Book A')];
    await tester.pumpWidget(_subject(repository: repository, books: books));
    await tester.pumpAndSettle();

    expect(find.text('Create collection'), findsOneWidget);
    expect(
      find.byKey(const Key('collection-editor-added-books-heading')),
      findsOneWidget,
    );
    expect(find.byType(CollectionEditorScreen), findsOneWidget);
    final coverSize = tester.getSize(
      find.byKey(const Key('collection-editor-cover-viewport')),
    );
    expect(coverSize.width / coverSize.height, 16 / 9);
    expect(
      find.byKey(const Key('collection-editor-cover-viewport')),
      findsOneWidget,
    );
    expect(
      tester.widget(find.byKey(const Key('collection-editor-cover-viewport'))),
      isA<CollectionCover>(),
    );
    expect(find.byKey(const Key('collection-editor-save')), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('collection-editor-save')))
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const Key('collection-editor-name')),
      '  Reading  ',
    );
    await tester.enterText(
      find.byKey(const Key('collection-editor-description')),
      'Description\nwith line breaks',
    );
    await tester.tap(find.byKey(const Key('collection-editor-save')));
    await tester.pumpAndSettle();

    expect(repository.lastSave?.collectionId, isNull);
    expect(repository.lastSave?.name, '  Reading  ');
    expect(repository.lastSave?.description, 'Description\nwith line breaks');
    expect(repository.lastSave?.selectedBookIds, isEmpty);
  });

  testWidgets('editor cover keeps 16:9 at common phone widths', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final width in [390.0, 412.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(
        _subject(repository: _FakeCollectionRepository(), books: const []),
      );
      final size = tester.getSize(
        find.byKey(const Key('collection-editor-cover-viewport')),
      );
      expect(size.width / size.height, 16 / 9);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('book selector supports multiple draft selections', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakeCollectionRepository();
    final books = [
      _book('book-a', 'Book A'),
      _book('book-b', 'Book B'),
      _book('book-c', 'Book C'),
    ];
    await tester.pumpWidget(_subject(repository: repository, books: books));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('collection-editor-name')),
      'Reading',
    );
    await tester.tap(find.byKey(const Key('collection-editor-add-book')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('collection-book-selector')), findsOneWidget);

    tester
        .widget<Checkbox>(
          find.byKey(const ValueKey('collection-book-option-book-a')),
        )
        .onChanged!(true);
    await tester.pump();
    tester
        .widget<Checkbox>(
          find.byKey(const ValueKey('collection-book-option-book-c')),
        )
        .onChanged!(true);
    await tester.pump();
    await tester.tap(find.byKey(const Key('collection-book-selector-done')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('collection-editor-scroll')),
      const Offset(0, -1000),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('collection-editor-book-grid')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('collection-editor-remove-book-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('collection-editor-remove-book-c')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('collection-editor-save')));
    await tester.pumpAndSettle();
    expect(repository.lastSave?.selectedBookIds, {'book-a', 'book-c'});
  });

  testWidgets('edit editor loads metadata and saves membership diff', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakeCollectionRepository();
    final books = [
      _book('book-a', 'Book A'),
      _book('book-b', 'Book B'),
      _book('book-c', 'Book C'),
    ];
    final collection = LibraryCollection(
      id: 'collection-1',
      name: 'Reading',
      normalizedName: 'reading',
      description: 'Existing description',
      customCoverPath: null,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      sortOrder: null,
    );
    await tester.pumpWidget(
      _subject(
        repository: repository,
        books: books,
        collection: collection,
        memberBooks: [books[0], books[1]],
        collectionId: collection.id,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Edit collection'), findsOneWidget);
    expect(find.text('Existing description'), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('collection-editor-scroll')),
      const Offset(0, -1000),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('collection-editor-remove-book-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('collection-editor-remove-book-b')),
      findsOneWidget,
    );

    final removeBookA = find.byKey(
      const ValueKey('collection-editor-remove-book-a'),
    );
    tester.widget<IconButton>(removeBookA).onPressed!();
    await tester.pump();
    await tester.drag(
      find.byKey(const Key('collection-editor-scroll')),
      const Offset(0, 1000),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('collection-editor-add-book')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('collection-book-option-book-c')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('collection-book-option-book-c')),
    );
    await tester.tap(find.byKey(const Key('collection-book-selector-done')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('collection-editor-save')));
    await tester.pumpAndSettle();

    expect(repository.lastSave?.collectionId, collection.id);
    expect(repository.lastSave?.selectedBookIds, {'book-b', 'book-c'});
    expect(repository.lastSave?.description, 'Existing description');
  });

  testWidgets('back confirms and can discard unsaved changes', (tester) async {
    final repository = _FakeCollectionRepository();
    await tester.pumpWidget(_subject(repository: repository, books: const []));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('collection-editor-name')),
      'Unsaved',
    );
    await tester.tap(find.byKey(const Key('collection-editor-back')));
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(CollectionEditorScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('collection-editor-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(CollectionEditorScreen), findsNothing);
    expect(repository.lastSave, isNull);
  });

  testWidgets('cover picker stores and removes a draft cover', (tester) async {
    final directory = Directory(
      'build/collection-editor-test-${DateTime.now().microsecondsSinceEpoch}',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = _FakeCollectionRepository();
    await tester.pumpWidget(
      _subject(
        repository: repository,
        books: const [],
        picker: const _FakeCoverPicker(),
        storage: CoverStorageService(
          documentsDirectory: () async => directory,
          imageValidator: const _AlwaysValidImageValidator(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final pickCover = tester
        .widget<InkWell>(
          find.byKey(const Key('collection-editor-cover-uploader')),
        )
        .onTap! as Future<void> Function();
    await tester.runAsync(pickCover);
    await tester.pump();

    expect(
      find.byKey(const Key('collection-editor-change-cover')),
      findsOneWidget,
    );
    final image = tester.widget<Image>(
      find
          .descendant(
            of: find.byKey(const Key('collection-editor-cover-uploader')),
            matching: find.byType(Image),
          )
          .first,
    );
    expect(image.fit, BoxFit.cover);
    final removeCover = tester
        .widget<IconButton>(
          find.descendant(
            of: find.byKey(const Key('collection-editor-remove-cover')),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed! as Future<void> Function();
    await tester.runAsync(removeCover);
    await tester.pump();
    expect(
      find.byKey(const Key('collection-editor-change-cover')),
      findsNothing,
    );
  });
}

Widget _subject({
  required _FakeCollectionRepository repository,
  required List<LibraryBook> books,
  CollectionRepository? collectionRepository,
  LibraryCollection? collection,
  List<LibraryBook>? memberBooks,
  String? collectionId,
  CollectionCoverPicker? picker,
  CoverStorageService? storage,
  LibraryViewMode mode = LibraryViewMode.grid,
  Set<String> initialBookIds = const {},
  bool dark = false,
  double scale = 1,
}) {
  final overrides = [
    readingProgressProvider.overrideWith((ref, _) => Stream.value(null)),
    libraryViewModeProvider.overrideWith(() => _LayoutMode(mode)),
    collectionRepositoryProvider.overrideWithValue(
      collectionRepository ?? repository,
    ),
    allBooksProvider.overrideWithValue(AsyncData<List<LibraryBook>>(books)),
    if (collectionId != null && collection != null)
      collectionByIdProvider(
        collectionId,
      ).overrideWith((ref) => Future.value(collection)),
    if (collectionId != null && memberBooks != null)
      booksInCollectionProvider(
        collectionId,
      ).overrideWithValue(AsyncData<List<LibraryBook>>(memberBooks)),
    if (picker != null) collectionCoverPickerProvider.overrideWithValue(picker),
    if (storage != null) coverStorageServiceProvider.overrideWithValue(storage),
  ];
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: dark
          ? ThemeData.dark(useMaterial3: true)
          : ThemeData(useMaterial3: true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: CollectionEditorScreen(
        collectionId: collectionId,
        initialBookIds: initialBookIds,
      ),
    ),
  );
}

LibraryBook _book(String id, String title) => LibraryBook(
  id: id,
  title: title,
  sortTitle: title,
  author: 'Author',
  description: null,
  filePath: '/books/$id.epub',
  fileName: '$id.epub',
  fileExtension: 'epub',
  format: BookFormat.epub,
  mediaType: null,
  coverPath: null,
  language: null,
  publisher: null,
  publishedDate: null,
  isbn: null,
  pageCount: null,
  fileSizeBytes: 1,
  dateAdded: DateTime(2026),
  lastOpenedAt: null,
  isFavorite: false,
);

class _FakeCollectionRepository implements CollectionRepository {
  _EditorSave? lastSave;

  @override
  Future<LibraryCollection> saveEditor({
    String? collectionId,
    required String name,
    required String? description,
    required String? customCoverPath,
    required Set<String> selectedBookIds,
  }) async {
    lastSave = _EditorSave(
      collectionId: collectionId,
      name: name,
      description: description,
      customCoverPath: customCoverPath,
      selectedBookIds: Set.of(selectedBookIds),
    );
    return LibraryCollection(
      id: collectionId ?? 'created',
      name: name.trim(),
      normalizedName: name.trim().toLowerCase(),
      description: description,
      customCoverPath: customCoverPath,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      sortOrder: null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EditorSave {
  const _EditorSave({
    required this.collectionId,
    required this.name,
    required this.description,
    required this.customCoverPath,
    required this.selectedBookIds,
  });

  final String? collectionId;
  final String name;
  final String? description;
  final String? customCoverPath;
  final Set<String> selectedBookIds;
}

class _TrackingCoverStorage implements CoverStorageService {
  final deleted = <String?>[];
  @override
  Future<String?> storeValidatedCollectionCover({
    required String collectionKey,
    required Uint8List bytes,
    String? extension,
  }) async => '/missing/test-draft.png';
  @override
  Future<void> deleteStoredCover(String? path) async {
    deleted.add(path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCoverPicker implements CollectionCoverPicker {
  const _FakeCoverPicker();

  @override
  Future<PickedCollectionCover?> pickCover() async => PickedCollectionCover(
    bytes: Uint8List.fromList([1, 2, 3]),
    extension: 'png',
  );
}

class _AlwaysValidImageValidator implements CoverImageValidator {
  const _AlwaysValidImageValidator();

  @override
  Future<bool> isDecodable(Uint8List bytes) async => bytes.isNotEmpty;
}

class _LayoutMode extends LibraryViewModeNotifier {
  _LayoutMode(this.initial);
  final LibraryViewMode initial;
  @override
  LibraryViewMode build() {
    ready = Future.value();
    return initial;
  }

  @override
  Future<void> setMode(LibraryViewMode mode) async {
    state = mode;
  }
}

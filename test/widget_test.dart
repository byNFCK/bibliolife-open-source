import 'package:bibliolife/app/app.dart';
import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/core/database/database_provider.dart';
import 'package:drift/native.dart';
import 'package:bibliolife/app/router/app_shell.dart';
import 'package:bibliolife/app/theme/app_theme.dart';
import 'package:bibliolife/features/connectivity/application/app_connectivity_mode_provider.dart';
import 'package:bibliolife/features/library/application/providers/library_repository_provider.dart';
import 'package:bibliolife/features/library/application/providers/library_section_provider.dart';
import 'package:bibliolife/features/library/domain/library_section_settings_repository.dart';
import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_providers.dart';
import 'package:bibliolife/features/reader/domain/models/reading_progress.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('app starts on Home and shows bottom navigation', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryRepositoryProvider.overrideWithValue(
            _EmptyLibraryRepository(),
          ),
          librarySectionSettingsRepositoryProvider.overrideWithValue(
            _AllBooksLibrarySectionSettingsRepository(),
          ),
          allReadingProgressProvider.overrideWith(
            (ref) => Stream.value(<ReadingProgress>[]),
          ),
          onlineAccessAllowedProvider.overrideWithValue(false),
        ],
        child: App(
          injectedLightColorScheme: fallbackLightColorScheme,
          injectedDarkColorScheme: fallbackDarkColorScheme,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Search books'), findsOneWidget);
    expect(find.text('Explore online'), findsNothing);
    expect(find.text('Recently opened'), findsNothing);
    expect(find.byType(FloatingNavigationIsland), findsOneWidget);
    expect(
      tester
          .widget<Scaffold>(find.byKey(const Key('production-app-shell')))
          .extendBody,
      isTrue,
    );
  });

  testWidgets('bottom navigation opens Library and Profile', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.viewPadding = const FakeViewPadding(top: 24);
    tester.view.padding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryRepositoryProvider.overrideWithValue(
            _EmptyLibraryRepository(),
          ),
          librarySectionSettingsRepositoryProvider.overrideWithValue(
            _AllBooksLibrarySectionSettingsRepository(),
          ),
          allReadingProgressProvider.overrideWith(
            (ref) => Stream.value(<ReadingProgress>[]),
          ),
          onlineAccessAllowedProvider.overrideWithValue(false),
        ],
        child: App(
          injectedLightColorScheme: fallbackLightColorScheme,
          injectedDarkColorScheme: fallbackDarkColorScheme,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final shell = tester.widget<Scaffold>(
      find.byKey(const Key('production-app-shell')),
    );
    expect(shell.extendBody, isTrue);
    expect(shell.bottomNavigationBar, isNull);
    expect(find.byType(FloatingNavigationIsland), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('BiblioLife'), findsNothing);
    expect(
      tester.getRect(find.text('Search books')).top,
      greaterThanOrEqualTo(24),
    );
    final homeNavbarBounds = tester.getRect(
      find.byKey(const Key('navigation-island-surface')),
    );
    final homePillBounds = tester.getRect(
      find.byKey(const Key('navigation-selected-circle')),
    );

    await tester.tap(find.byKey(const Key('navigation-destination-1')));
    await tester.pumpAndSettle();
    // The persisted default Library section is user-configurable; navigation
    // and the section-specific Add action are the durable shell contract.
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('BiblioLife'), findsNothing);
    expect(tester.getRect(find.byTooltip('Add')).top, greaterThanOrEqualTo(24));
    expect(find.byType(FloatingNavigationIsland), findsOneWidget);
    final libraryNavbarBounds = tester.getRect(
      find.byKey(const Key('navigation-island-surface')),
    );
    final libraryPillBounds = tester.getRect(
      find.byKey(const Key('navigation-selected-circle')),
    );

    await tester.tap(find.byKey(const Key('navigation-destination-2')));
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('BiblioLife'), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    expect(tester.getRect(find.text('Profile')).top, greaterThanOrEqualTo(24));
    expect(find.byType(FloatingNavigationIsland), findsOneWidget);
    final profileNavbarBounds = tester.getRect(
      find.byKey(const Key('navigation-island-surface')),
    );
    final profilePillBounds = tester.getRect(
      find.byKey(const Key('navigation-selected-circle')),
    );

    expect(libraryNavbarBounds, homeNavbarBounds);
    expect(profileNavbarBounds, homeNavbarBounds);
    expect(libraryPillBounds.size, homePillBounds.size);
    expect(profilePillBounds.size, homePillBounds.size);
    expect(libraryPillBounds.left, greaterThan(homePillBounds.left));
    expect(profilePillBounds.left, greaterThan(libraryPillBounds.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('foreground settings sheet covers the floating navbar', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(database.close));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          libraryRepositoryProvider.overrideWithValue(
            _EmptyLibraryRepository(),
          ),
          librarySectionSettingsRepositoryProvider.overrideWithValue(
            _AllBooksLibrarySectionSettingsRepository(),
          ),
          allReadingProgressProvider.overrideWith(
            (ref) => Stream.value(<ReadingProgress>[]),
          ),
          onlineAccessAllowedProvider.overrideWithValue(false),
        ],
        child: App(
          injectedLightColorScheme: fallbackLightColorScheme,
          injectedDarkColorScheme: fallbackDarkColorScheme,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('navigation-destination-2')));
    await tester.pumpAndSettle();
    final sheetEntry = find.byKey(
      const Key('home-online-libraries-settings-row'),
    );
    await tester.ensureVisible(sheetEntry);
    await tester.pumpAndSettle();
    await tester.tap(sheetEntry);
    await tester.pumpAndSettle();

    expect(find.byType(ModalBarrier), findsAtLeastNWidgets(1));
    expect(find.byType(FloatingNavigationIsland), findsOneWidget);
    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('navigation-destination-0'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Profile', skipOffstage: false), findsOneWidget);
    expect(find.text('Search books'), findsNothing);
    expect(find.byType(ModalBarrier), findsAtLeastNWidgets(1));

    await tester.tapAt(const Offset(12, 12));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('navigation-destination-0')));
    await tester.pumpAndSettle();
    expect(find.text('Search books'), findsOneWidget);
    // Dispose provider streams while the fake event loop can still drain.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}

class _EmptyLibraryRepository implements LibraryRepository {
  @override
  Stream<List<LibraryBook>> watchAllBooks() => Stream.value([]);

  @override
  Stream<List<LibraryBook>> watchFavoriteBooks() => watchAllBooks();

  @override
  Stream<List<LibraryBook>> watchUnsortedBooks() => watchAllBooks();

  @override
  Future<List<LibraryBook>> getAllBooks() async => [];

  @override
  Future<LibraryBook?> getBookById(String id) async => null;

  @override
  Future<LibraryBook?> findBookByFilePath(String filePath) async => null;

  @override
  Future<LibraryBook?> findBookByOriginalFilePath(
    String originalFilePath,
  ) async => null;

  @override
  Future<void> addBook(LibraryBook book) async {}

  @override
  Future<void> updateBook(LibraryBook book) async {}

  @override
  Future<void> deleteBook(String id) async {}

  @override
  Future<void> setFavorite(String id, bool isFavorite) async {}

  @override
  Future<void> markBookOpened(String id, DateTime openedAt) async {}
}

class _AllBooksLibrarySectionSettingsRepository
    implements LibrarySectionSettingsRepository {
  @override
  Future<LibrarySection> load() async => LibrarySection.allBooks;

  @override
  Future<void> save(LibrarySection section) async {}
}

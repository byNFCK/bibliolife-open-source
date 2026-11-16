import 'package:bibliolife/app/app.dart';
import 'package:bibliolife/app/theme/app_theme.dart';
import 'package:bibliolife/features/connectivity/application/app_connectivity_mode_provider.dart';
import 'package:bibliolife/features/library/application/providers/library_repository_provider.dart';
import 'package:bibliolife/features/library/domain/repositories/library_repository.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_providers.dart';
import 'package:bibliolife/features/reader/domain/models/reading_progress.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Material You theme', () {
    test('provides distinct fallback light and dark ColorSchemes', () {
      expect(fallbackLightColorScheme.brightness, Brightness.light);
      expect(fallbackDarkColorScheme.brightness, Brightness.dark);
      expect(
        fallbackLightColorScheme.surface,
        isNot(fallbackDarkColorScheme.surface),
      );
      expect(fallbackLightColorScheme.primary, isNot(Colors.purple));
    });

    test('maps component themes to semantic tonal roles', () {
      final scheme = fallbackLightColorScheme;
      final theme = buildAppTheme(scheme);
      final selected = <WidgetState>{WidgetState.selected};

      expect(theme.scaffoldBackgroundColor, scheme.surface);
      expect(theme.cardTheme.color, scheme.surfaceContainerLow);
      expect(
        theme.navigationBarTheme.backgroundColor,
        scheme.surfaceContainerHigh,
      );
      expect(
        theme.navigationBarTheme.indicatorColor,
        scheme.secondaryContainer,
      );
      expect(
        theme.navigationBarTheme.iconTheme!.resolve(selected)!.color,
        scheme.onSecondaryContainer,
      );
      expect(
        theme.navigationBarTheme.iconTheme!.resolve({})!.color,
        scheme.onSurfaceVariant,
      );
      expect(
        theme.inputDecorationTheme.fillColor,
        scheme.surfaceContainerHighest,
      );
    });

    for (final scheme in [fallbackLightColorScheme, fallbackDarkColorScheme]) {
      test(
        '${scheme.brightness.name} semantic pairs retain readable contrast',
        () {
          expect(_contrast(scheme.onSurface, scheme.surface), greaterThan(4.5));
          expect(
            _contrast(scheme.onPrimaryContainer, scheme.primaryContainer),
            greaterThan(4.5),
          );
          expect(
            _contrast(scheme.onSecondaryContainer, scheme.secondaryContainer),
            greaterThan(4.5),
          );
        },
      );
    }

    testWidgets('applies an injected dynamic test scheme', (tester) async {
      final injected = ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: Brightness.light,
      );

      await tester.pumpWidget(_testApp(lightScheme: injected));
      await tester.pumpAndSettle();

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.theme!.colorScheme, injected);
    });

    testWidgets('Search entry uses semantic surface roles', (tester) async {
      await tester.pumpWidget(_testApp());
      await tester.pumpAndSettle();

      final material = tester.widget<Material>(
        find
            .ancestor(
              of: find.byKey(const Key('home-search-action')),
              matching: find.byType(Material),
            )
            .first,
      );
      final scheme = fallbackLightColorScheme;
      expect(material.color, scheme.surfaceContainerHigh);
      final shape = material.shape! as StadiumBorder;
      expect(shape.side.color, scheme.outlineVariant);
    });
  });
}

Widget _testApp({ColorScheme? lightScheme}) {
  return ProviderScope(
    overrides: [
      libraryRepositoryProvider.overrideWithValue(_EmptyLibraryRepository()),
      allReadingProgressProvider.overrideWith(
        (ref) => Stream.value(<ReadingProgress>[]),
      ),
      onlineAccessAllowedProvider.overrideWithValue(false),
    ],
    child: App(
      injectedLightColorScheme: lightScheme ?? fallbackLightColorScheme,
      injectedDarkColorScheme: fallbackDarkColorScheme,
    ),
  );
}

double _contrast(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground
      : background;
  final darker = identical(lighter, foreground) ? background : foreground;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
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

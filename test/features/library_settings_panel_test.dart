import 'package:bibliolife/features/library/application/providers/library_section_provider.dart';
import 'package:bibliolife/features/library/domain/library_section_settings_repository.dart';
import 'package:bibliolife/features/settings/presentation/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Library default setting shows and saves exactly three choices', (
    tester,
  ) async {
    final repository = _MemoryLibrarySectionSettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          librarySectionSettingsRepositoryProvider.overrideWithValue(
            repository,
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: LibrarySettingsPanel())),
      ),
    );
    await tester.pumpAndSettle();

    final settingCard = find.byKey(const Key('library-settings-section'));
    expect(find.text('Default tab in Library'), findsOneWidget);
    expect(
      find.descendant(of: settingCard, matching: find.text('All books')),
      findsOneWidget,
    );

    expect(find.byType(RadioListTile<LibrarySection>), findsNothing);
    expect(
      find.byKey(const Key('default-library-section-option-collection')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('default-library-section-option-follow')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('default-library-section-option-all-books')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('default-library-section-option-collection')),
    );
    await tester.pumpAndSettle();
    expect(repository.section, LibrarySection.collection);
    expect(
      find.descendant(of: settingCard, matching: find.text('Collection')),
      findsOneWidget,
    );

    await tester.tap(settingCard);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('default-library-section-option-follow')),
    );
    await tester.pumpAndSettle();
    expect(repository.section, LibrarySection.follow);

    await tester.tap(settingCard);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('default-library-section-option-all-books')),
    );
    await tester.pumpAndSettle();
    expect(repository.section, LibrarySection.allBooks);
  });
}

class _MemoryLibrarySectionSettingsRepository
    implements LibrarySectionSettingsRepository {
  LibrarySection section = LibrarySection.allBooks;

  @override
  Future<LibrarySection> load() async => section;

  @override
  Future<void> save(LibrarySection next) async => section = next;
}

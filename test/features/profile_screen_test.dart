import 'package:bibliolife/features/profile/presentation/screens/profile_screen.dart';
import 'package:bibliolife/features/settings/presentation/widgets/settings_body.dart';
import 'package:bibliolife/features/home/application/providers/home_default_carousel_provider.dart';
import 'package:bibliolife/features/home/domain/home_default_carousel_settings_repository.dart';
import 'package:bibliolife/features/connectivity/application/app_connectivity_mode_provider.dart';
import 'package:bibliolife/features/connectivity/data/app_connectivity_mode_repository.dart';
import 'package:bibliolife/features/connectivity/domain/app_connectivity_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('Profile uses compact canonical settings hierarchy', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ProfileScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.byKey(const Key('settings-heading-Online')), findsOneWidget);
    expect(find.text('Storage', skipOffstage: false), findsOneWidget);
    expect(find.byType(SettingsBody), findsOneWidget);

    expect(find.byType(RadioListTile<ThemeMode>), findsNothing);
    expect(find.byType(SegmentedButton), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.byKey(const Key('online-cache-limit-selector')), findsNothing);

    final appearance = tester.getTopLeft(find.text('Appearance')).dy;
    final library = tester.getTopLeft(find.text('Library')).dy;
    final online = tester
        .getTopLeft(find.byKey(const Key('settings-heading-Online')))
        .dy;
    final storage = tester
        .getTopLeft(find.text('Storage', skipOffstage: false))
        .dy;
    expect(appearance, lessThan(library));
    expect(library, lessThan(online));
    expect(online, lessThan(storage));
  });

  testWidgets('Profile setting rows open their focused selectors', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ProfileScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RadioListTile<ThemeMode>), findsNothing);
    expect(find.byKey(const Key('theme-option-system')), findsOneWidget);
    expect(find.byKey(const Key('theme-option-light')), findsOneWidget);
    expect(find.byKey(const Key('theme-option-dark')), findsOneWidget);
    await tester.tap(find.byKey(const Key('theme-option-dark')));
    await tester.pumpAndSettle();
    expect(find.text('Dark'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('home-online-libraries-settings-row')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('home-online-libraries-settings-row')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNWidgets(5));
  });

  testWidgets('Profile exposes and persists the default Home carousel', (
    tester,
  ) async {
    final repository = _MemoryHomeDefaultCarouselSettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeDefaultCarouselSettingsRepositoryProvider.overrideWithValue(
            repository,
          ),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final librarySection = find.byKey(const Key('settings-section-library'));
    expect(
      find.descendant(
        of: librarySection,
        matching: find.byKey(const Key('default-home-carousel-settings-row')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: librarySection,
        matching: find.text('Recently opened'),
      ),
      findsOneWidget,
    );

    expect(find.byType(RadioListTile<HomeDefaultCarousel>), findsNothing);
    expect(
      find.byKey(const Key('default-home-carousel-option-recently-opened')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('default-home-carousel-option-favorites')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const Key('default-home-carousel-option-favorites')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('default-home-carousel-option-favorites')),
    );
    await tester.pumpAndSettle();

    expect(repository.value, HomeDefaultCarousel.favorites);
    expect(
      find.descendant(of: librarySection, matching: find.text('Favorites')),
      findsOneWidget,
    );
  });

  testWidgets('Application mode keeps the online acknowledgement flow', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConnectivityModeRepositoryProvider.overrideWithValue(
            _OfflineRepository(),
          ),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RadioListTile<AppConnectivityMode>), findsNothing);
    await tester.ensureVisible(
      find.byKey(const Key('application-mode-option-online')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('application-mode-option-online')));
    await tester.pumpAndSettle();
    expect(find.text('Enable Online mode?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('application-mode-settings-row')),
      findsOneWidget,
    );
  });
}

class _OfflineRepository implements AppConnectivityModeRepository {
  @override
  Future<AppConnectivityState> load() async =>
      const AppConnectivityState.offline();

  @override
  Future<void> save(AppConnectivityState state) async {}
}

class _MemoryHomeDefaultCarouselSettingsRepository
    implements HomeDefaultCarouselSettingsRepository {
  HomeDefaultCarousel value = HomeDefaultCarousel.recentlyOpened;

  @override
  Future<HomeDefaultCarousel> load() async => value;

  @override
  Future<void> save(HomeDefaultCarousel carousel) async => value = carousel;
}

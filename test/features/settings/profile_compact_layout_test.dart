// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'package:bibliolife/app/theme/dynamic_color_scheme.dart';
// ignore: depend_on_referenced_packages
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:dynamic_color/samples.dart';
import 'package:bibliolife/features/connectivity/application/app_connectivity_mode_provider.dart';
import 'package:bibliolife/features/connectivity/domain/app_connectivity_mode.dart';
import 'package:bibliolife/features/library/application/providers/library_section_provider.dart';
import 'package:bibliolife/features/home/application/providers/home_default_carousel_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_cache_settings_provider.dart';
import 'package:bibliolife/features/settings/presentation/widgets/settings_control_content.dart';
import 'package:bibliolife/features/settings/presentation/widgets/settings_segmented_control.dart';
import 'package:bibliolife/features/settings/presentation/widgets/settings_tile.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/app/router/app_shell.dart';
import 'package:bibliolife/app/theme/app_theme.dart';
import 'package:bibliolife/app/theme/theme_mode_provider.dart';
import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway_provider.dart';
import 'package:bibliolife/features/catalog_sources/data/remote_cache_service.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_gateway.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_cache_budget.dart';
import 'package:bibliolife/features/home/application/providers/home_online_tab_settings_provider.dart';
import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:bibliolife/features/profile/presentation/screens/profile_screen.dart';
import 'package:bibliolife/shared/presentation/widgets/biblio_tabs.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  for (final entry in [
    (name: 'dynamic A', palette: CorePalette.of(0xff428a47)),
    (name: 'dynamic B', palette: CorePalette.of(0xff9650aa)),
    (name: 'fallback', palette: null),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'Profile track and disabled colors ${entry.name} $brightness',
        (tester) async {
          final scheme = entry.palette == null
              ? (brightness == Brightness.light
                    ? fallbackLightColorScheme
                    : fallbackDarkColorScheme)
              : dynamicSchemeFromCorePalette(entry.palette!, brightness);
          final theme = ThemeData(
            colorScheme: scheme,
            scaffoldBackgroundColor: scheme.surface,
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: SettingsSegmentedControl<int>(
                  title: 'Test',
                  icon: Icons.settings,
                  selected: 0,
                  onSelected: null,
                  items: const [
                    BiblioTabItem(id: 0, label: 'Selected', icon: Icons.check),
                    BiblioTabItem(
                      id: 1,
                      label: 'Disabled',
                      icon: Icons.close,
                      enabled: false,
                    ),
                  ],
                ),
              ),
            ),
          );
          final tabs = find.byType(BiblioTabs<int>);
          final expectedTrackRole = brightness == Brightness.light
              ? scheme.surfaceContainerHighest
              : scheme.surfaceContainerHigh;
          final expectedTrack = expectedTrackRole == scheme.surface
              ? Color.alphaBlend(
                  scheme.onSurface.withValues(alpha: .10),
                  scheme.surface,
                )
              : expectedTrackRole;
          final track = tester
              .widgetList<Material>(
                find.descendant(of: tabs, matching: find.byType(Material)),
              )
              .firstWhere((material) => material.color != null);
          expect(track.color, expectedTrack);
          final capsule = tester.widget<DecoratedBox>(
            find.descendant(
              of: find.descendant(
                of: tabs,
                matching: find.byType(AnimatedPositionedDirectional),
              ),
              matching: find.byType(DecoratedBox),
            ),
          );
          expect(
            (capsule.decoration as ShapeDecoration).color,
            scheme.secondaryContainer,
          );
          for (final (label, icon, foreground) in [
            ('Selected', Icons.check, scheme.onSecondaryContainer),
            ('Disabled', Icons.close, scheme.onSurfaceVariant),
          ]) {
            final color = foreground.withValues(alpha: .38);
            expect(tester.widget<Text>(find.text(label)).style!.color, color);
            expect(tester.widget<Icon>(find.byIcon(icon)).color, color);
          }
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: SettingsSegmentedControl<int>(
                  title: 'Test',
                  icon: Icons.settings,
                  selected: 0,
                  onSelected: (_) {},
                  items: const [
                    BiblioTabItem(id: 0, label: 'Selected', icon: Icons.check),
                    BiblioTabItem(
                      id: 1,
                      label: 'Disabled',
                      icon: Icons.close,
                      enabled: false,
                    ),
                  ],
                ),
              ),
            ),
          );
          final disabledColor = scheme.onSurfaceVariant.withValues(alpha: .38);
          expect(
            tester.widget<Text>(find.text('Disabled')).style!.color,
            disabledColor,
          );
          expect(
            tester.widget<Icon>(find.byIcon(Icons.close)).color,
            disabledColor,
          );
          expect(
            tester.widget<Text>(find.text('Selected')).style!.color,
            scheme.onSecondaryContainer,
          );
          expect(
            tester.widget<Icon>(find.byIcon(Icons.check)).color,
            scheme.onSecondaryContainer,
          );
        },
      );
    }
  }

  for (final palette in [
    (
      name: 'dynamic A',
      light: SampleColorSchemes.green(Brightness.light),
      dark: SampleColorSchemes.green(Brightness.dark),
    ),
    (
      name: 'dynamic B',
      light: SampleColorSchemes.orange(Brightness.light),
      dark: SampleColorSchemes.orange(Brightness.dark),
    ),
    (
      name: 'fallback',
      light: fallbackLightColorScheme,
      dark: fallbackDarkColorScheme,
    ),
  ]) {
    for (final dark in [false, true]) {
      testWidgets(
        'all six Profile selectors inherit ${palette.name} dark=$dark',
        (tester) async {
          final h = await _pump(
            tester,
            dark: dark,
            lightScheme: palette.light,
            darkScheme: palette.dark,
          );
          final semantics = tester.ensureSemantics();
          final scheme = dark ? palette.dark : palette.light;
          for (final key in [
            'theme-settings-row',
            'book-display-layout-settings-row',
            'library-settings-row',
            'default-home-carousel-settings-row',
            'application-mode-settings-row',
            'online-cache-settings-row',
          ]) {
            final row = find.byKey(Key(key));
            final control = tester.widget<SettingsSegmentedControl<Object>>(
              find.ancestor(
                of: row,
                matching: find.byWidgetPredicate(
                  (w) => w is SettingsSegmentedControl<Object>,
                ),
              ),
            );
            final selected = control.items.singleWhere(
              (item) => item.id == control.selected,
            );
            final option = find.byKey(selected.key!);
            await tester.ensureVisible(option);
            await tester.pumpAndSettle();
            final tabs = find.descendant(
              of: row,
              matching: find.byWidgetPredicate((w) => w is BiblioTabs<Object>),
            );
            expect(
              tester.widget<BiblioTabs<Object>>(tabs).selectedId,
              control.selected,
            );
            final capsule = find.descendant(
              of: find.descendant(
                of: tabs,
                matching: find.byType(AnimatedPositionedDirectional),
              ),
              matching: find.byType(DecoratedBox),
            );
            final decoration =
                tester.renderObject<RenderDecoratedBox>(capsule).decoration
                    as ShapeDecoration;
            expect(decoration.color, scheme.secondaryContainer, reason: key);
            expect(decoration.color, isNot(const Color(0xFF743349)));
            final label = tester.widget<Text>(
              find.descendant(of: option, matching: find.text(selected.label)),
            );
            expect(
              label.style!.color,
              scheme.onSecondaryContainer,
              reason: key,
            );
            for (final icon in tester.widgetList<Icon>(
              find.descendant(of: option, matching: find.byType(Icon)),
            )) {
              expect(icon.color, scheme.onSecondaryContainer, reason: key);
            }
            expect(
              tester
                  .getSemantics(option)
                  .getSemanticsData()
                  .flagsCollection
                  .isSelected,
              ui.Tristate.isTrue,
            );
          }
          expect(h.gatewayCalls, 0);
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  }

  for (final dark in [false, true]) {
    for (final size in [
      const Size(320, 800),
      const Size(390, 844),
      const Size(844, 390),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'compact Profile geometry dark=$dark size=$size scale=$scale',
          (tester) async {
            final h = await _pump(tester, size: size, scale: scale, dark: dark);
            final semantics = tester.ensureSemantics();
            for (final section in [
              'appearance',
              'library',
              'online',
              'storage',
              'diagnostics',
            ]) {
              final card = find.byKey(Key('settings-section-$section'));
              await tester.scrollUntilVisible(card, 180, scrollable: _scroll());
              await tester.pumpAndSettle();
              expect(card, findsOneWidget);
              final bounds = tester.getRect(card);
              expect(bounds.left, 20);
              expect(bounds.right, size.width - 20);
              expect(find.byType(SettingsControlContent), findsNWidgets(6));
              expect(
                find.byWidgetPredicate((w) => w is SettingsSegmentedControl),
                findsNWidgets(6),
              );
              expect(find.byType(Card), findsNWidgets(5));
              expect(
                find.byType(SettingsSegmentedControl<ThemeMode>),
                findsOneWidget,
              );
              expect(
                find.byType(SettingsSegmentedControl<LibraryViewMode>),
                findsOneWidget,
              );
              expect(find.byType(SettingsTile), findsNWidgets(4));
              for (final redundant in [
                'Manage sources',
                'Manage libraries',
                'Open logs',
                'Clear cache',
              ]) {
                expect(find.text(redundant), findsNothing);
              }
              final sectionCard = tester.widget<Card>(card);
              expect(sectionCard.elevation, 0);
            }
            tester.state<ScrollableState>(_scroll()).position.jumpTo(0);
            await tester.pumpAndSettle();
            for (final prefix in ['theme-option-', 'book-display-option-']) {
              await tester.scrollUntilVisible(
                find.byKey(
                  Key(
                    '$prefix${prefix.startsWith('theme') ? 'system' : 'grid'}',
                  ),
                ),
                120,
                scrollable: _scroll(),
              );
              await tester.pumpAndSettle();
              final options = prefix.startsWith('theme')
                  ? ['system', 'light', 'dark']
                  : ['grid', 'list'];
              expect(
                options
                    .where(
                      (option) =>
                          tester
                              .getSemantics(find.byKey(Key('$prefix$option')))
                              .getSemanticsData()
                              .flagsCollection
                              .isSelected ==
                          ui.Tristate.isTrue,
                    )
                    .length,
                1,
              );
            }
            for (final scroll
                in find
                    .descendant(
                      of: find.byType(BiblioTabs<ThemeMode>),
                      matching: find.byType(Scrollable),
                    )
                    .evaluate()) {
              final state = tester.state<ScrollableState>(
                find.byElementPredicate((e) => identical(e, scroll)),
              );
              expect(state.position.maxScrollExtent, 0);
            }
            final list = tester.state<ScrollableState>(
              find
                  .descendant(
                    of: find.byKey(
                      const PageStorageKey('profile-settings-scroll'),
                    ),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await tester.scrollUntilVisible(
              find.byKey(const Key('logs-settings-row')),
              180,
              scrollable: _scroll(),
            );
            list.position.jumpTo(list.position.maxScrollExtent);
            await tester.pumpAndSettle();
            final log = tester.getRect(
              find.byKey(const Key('logs-settings-row')),
            );
            final navigation = tester.getRect(
              find.byKey(const Key('navigation-island-surface')),
            );
            expect(log.bottom, lessThanOrEqualTo(navigation.top));
            expect(navigation.height, AppNavigationPresentation.surfaceHeight);
            expect(h.databaseBuilds, 1);
            expect(h.gatewayCalls, 0);
            expect(h.cache.clears, 0);
            expect(h.cache.snapshots, 1);
            expect(tester.takeException(), isNull);
            semantics.dispose();
          },
        );
      }
    }
  }

  testWidgets(
    'inline Theme uses the existing provider and immediate system behavior',
    (tester) async {
      final h = await _pump(tester);
      final notifier = h.container.read(themeModeProvider.notifier);
      for (final entry in {
        'dark': ThemeMode.dark,
        'light': ThemeMode.light,
        'system': ThemeMode.system,
      }.entries) {
        await tester.tap(find.byKey(Key('theme-option-${entry.key}')));
        await tester.pumpAndSettle();
        expect(h.container.read(themeModeProvider), entry.value);
        expect(h.container.read(themeModeProvider.notifier), same(notifier));
        expect(find.byType(BottomSheet), findsNothing);
        if (entry.value != ThemeMode.system) {
          expect(
            Theme.of(tester.element(find.byType(ProfileScreen))).brightness,
            entry.value == ThemeMode.dark ? Brightness.dark : Brightness.light,
          );
        }
      }
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(ProfileScreen))).brightness,
        Brightness.dark,
      );
      expect(h.databaseBuilds, 1);
      expect(h.gatewayCalls, 0);
      expect(
        await h.database.select(h.database.bookDisplaySettingsEntries).get(),
        isEmpty,
      );
    },
  );

  testWidgets(
    'inline Grid List persists and reflects external changes without provider recreation',
    (tester) async {
      final h = await _pump(tester);
      final notifier = h.container.read(libraryViewModeProvider.notifier);
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const PageStorageKey('profile-settings-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const Key('book-display-option-list')));
      await tester.pumpAndSettle();
      expect(h.container.read(libraryViewModeProvider), LibraryViewMode.list);
      expect(
        await h.container.read(bookDisplaySettingsRepositoryProvider).load(),
        'list',
      );
      await notifier.setMode(LibraryViewMode.grid);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BiblioTabs<LibraryViewMode>>(
              find.byType(BiblioTabs<LibraryViewMode>),
            )
            .selectedId,
        LibraryViewMode.grid,
      );
      expect(
        h.container.read(libraryViewModeProvider.notifier),
        same(notifier),
      );
      expect(
        tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const PageStorageKey('profile-settings-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        ),
        same(scroll),
      );
      expect(
        await h.container.read(bookDisplaySettingsRepositoryProvider).load(),
        'grid',
      );
    },
  );

  testWidgets(
    'online source count and existing navigation preserve overview scroll',
    (tester) async {
      final h = await _pump(tester);
      await h.container
          .read(homeOnlineTabSettingsRepositoryProvider)
          .setVisible(sourceId: 'builtin-project-gutenberg', visible: false);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('home-online-libraries-settings-row')),
        180,
        scrollable: _scroll(),
      );
      await tester.pumpAndSettle();
      expect(find.text('4 of 5 enabled'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('home-online-libraries-settings-row')),
      );
      await tester.pumpAndSettle();
      final toggle = find.byKey(
        const Key('home-online-library-toggle-builtin-project-gutenberg'),
      );
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      h.router.pop();
      await tester.pumpAndSettle();
      expect(find.text('5 of 5 enabled'), findsOneWidget);

      final online = find.byKey(const Key('online-libraries-settings-row'));
      await tester.ensureVisible(online);
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(
                    const PageStorageKey('profile-settings-scroll'),
                  ),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      final before = position.pixels;
      await tester.tap(online);
      await tester.pumpAndSettle();
      expect(find.text('Online libraries destination'), findsOneWidget);
      h.router.pop();
      await tester.pumpAndSettle();
      expect(position.pixels, closeTo(before, .1));
      final log = find.byKey(const Key('logs-settings-row'));
      await tester.ensureVisible(log);
      await tester.pumpAndSettle();
      await tester.tap(log);
      await tester.pumpAndSettle();
      expect(find.text('LOG destination'), findsOneWidget);
      h.router.pop();
      await tester.pumpAndSettle();
      expect(h.gatewayCalls, 0);
    },
  );

  testWidgets(
    'Profile cache action preserves cancel and explicit confirmation',
    (tester) async {
      final h = await _pump(tester);
      final action = find.byKey(const Key('online-cache-clear'));
      await tester.scrollUntilVisible(action, 180, scrollable: _scroll());
      await tester.pumpAndSettle();
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('online-cache-clear-confirmation')),
        findsOneWidget,
      );
      expect(h.cache.clears, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.cache.clears, 0);
      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(h.cache.clears, 1);
      expect(find.text('0.0 MB used'), findsOneWidget);
      expect(h.gatewayCalls, 0);
    },
  );

  testWidgets(
    'all direct defaults and cache choices persist without opening a sheet',
    (tester) async {
      final h = await _pump(tester);
      Future<void> select(String key) async {
        final finder = find.byKey(Key(key));
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        final offset = tester.state<ScrollableState>(_scroll()).position.pixels;
        await tester.tap(finder);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(
          tester.state<ScrollableState>(_scroll()).position.pixels,
          closeTo(offset, .1),
        );
      }

      await select('default-library-section-option-follow');
      expect(
        h.container.read(defaultLibrarySectionProvider).requireValue,
        LibrarySection.follow,
      );
      expect(
        await h.container.read(librarySectionSettingsRepositoryProvider).load(),
        LibrarySection.follow,
      );
      await select('default-home-carousel-option-favorites');
      expect(
        h.container.read(defaultHomeCarouselProvider).requireValue,
        HomeDefaultCarousel.favorites,
      );
      expect(
        await h.container
            .read(homeDefaultCarouselSettingsRepositoryProvider)
            .load(),
        HomeDefaultCarousel.favorites,
      );
      await select('online-cache-limit-512');
      expect(
        (await h.container.read(remoteCacheSettingsRepositoryProvider).load())
            .maximumBytes,
        remoteCacheMinimumMaximumBytes,
      );
      expect(h.cache.updates, 1);
      expect(h.cache.clears, 0);
      expect(h.gatewayCalls, 0);
    },
  );

  testWidgets(
    'direct Online retains acknowledgement and cancellation selection',
    (tester) async {
      final h = await _pump(tester);
      final online = find.byKey(const Key('application-mode-option-online'));
      await tester.ensureVisible(online);
      await tester.pumpAndSettle();
      await tester.tap(online);
      await tester.pumpAndSettle();
      expect(find.text('Enable Online mode?'), findsOneWidget);
      expect(
        h.container.read(appConnectivityModeProvider).mode,
        AppConnectivityMode.offline,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BiblioTabs<AppConnectivityMode>>(
              find.byType(BiblioTabs<AppConnectivityMode>),
            )
            .selectedId,
        AppConnectivityMode.offline,
      );
      await tester.tap(online);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enable Online'));
      await tester.pumpAndSettle();
      expect(
        h.container.read(appConnectivityModeProvider).mode,
        AppConnectivityMode.online,
      );
      expect(
        (await h.container.read(appConnectivityModeRepositoryProvider).load())
            .hasAcknowledgedOnline,
        isTrue,
      );
      await tester.tap(
        find.byKey(const Key('application-mode-option-offline')),
      );
      await tester.pumpAndSettle();
      await tester.tap(online);
      await tester.pumpAndSettle();
      expect(find.text('Enable Online mode?'), findsNothing);
      expect(
        h.container.read(appConnectivityModeProvider).mode,
        AppConnectivityMode.online,
      );
      expect(h.gatewayCalls, 0);
    },
  );

  testWidgets(
    'section surface pixels stay distinct in fallback and Android dynamic themes',
    (tester) async {
      const fontDir = String.fromEnvironment('PROFILE31_FONT_DIR');
      if (fontDir.isNotEmpty) {
        await tester.runAsync(() async {
          final loader = FontLoader('ProfileSurfaceRoboto');
          for (final name in [
            'roboto-regular.ttf',
            'roboto-medium.ttf',
            'roboto-bold.ttf',
          ]) {
            loader.addFont(
              File('$fontDir/$name').readAsBytes().then(ByteData.sublistView),
            );
          }
          await loader.load();
          await (FontLoader('MaterialIcons')..addFont(
                File(
                  '$fontDir/MaterialIcons-Regular.otf',
                ).readAsBytes().then(ByteData.sublistView),
              ))
              .load();
        });
      }
      final measurements = <Map<String, Object>>[];
      final palettes = [
        (
          name: 'dynamic-a',
          palette: CorePalette.fromList(CorePalette.of(0xff428a47).asList()),
        ),
        (
          name: 'dynamic-b',
          palette: CorePalette.fromList(CorePalette.of(0xff9650aa).asList()),
        ),
        (name: 'fallback', palette: null),
      ];
      for (final entry in palettes) {
        for (final dark in [false, true]) {
          await tester.pumpWidget(const SizedBox());
          final h = await _pump(
            tester,
            dark: dark,
            lightScheme: entry.palette == null
                ? fallbackLightColorScheme
                : dynamicSchemeFromCorePalette(
                    entry.palette!,
                    Brightness.light,
                  ),
            darkScheme: entry.palette == null
                ? fallbackDarkColorScheme
                : dynamicSchemeFromCorePalette(entry.palette!, Brightness.dark),
            font: fontDir.isEmpty ? null : 'ProfileSurfaceRoboto',
          );
          final theme = Theme.of(tester.element(find.byType(ProfileScreen)));
          final page = theme.scaffoldBackgroundColor;
          final expectedRole = entry.palette == null
              ? (dark ? fallbackDarkColorScheme : fallbackLightColorScheme)
                    .surfaceContainer
              : Color(entry.palette!.neutral.get(dark ? 12 : 94));
          expect(theme.colorScheme.surfaceContainer, expectedRole);
          String hex(Color color) =>
              '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
          double contrast(Color a, Color b) {
            final x = a.computeLuminance();
            final y = b.computeLuminance();
            return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
          }

          final sections = <String, Object>{};
          for (final name in [
            'appearance',
            'library',
            'online',
            'storage',
            'diagnostics',
          ]) {
            final card = find.byKey(Key('settings-section-$name'));
            await tester.ensureVisible(card);
            await tester.pumpAndSettle();
            final bounds = tester.getRect(card);
            final root = tester.getTopLeft(
              find.byKey(const Key('profile-render')),
            );
            final local = bounds.shift(-root);
            final expected = tester.widget<Card>(card).color!;
            expect(expected, expectedRole);
            expect(tester.widget<Card>(card).clipBehavior, Clip.antiAlias);
            expect(
              (tester.widget<Card>(card).shape! as RoundedRectangleBorder)
                  .borderRadius,
              BorderRadius.circular(18),
            );
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const Key('profile-render')),
              );
              final rendered = await boundary.toImage(pixelRatio: 2);
              final data = await rendered.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              Color pixel(Offset at) {
                final x = (at.dx * 2).round().clamp(0, rendered.width - 1);
                final y = (at.dy * 2).round().clamp(0, rendered.height - 1);
                final i = (y * rendered.width + x) * 4;
                return Color.fromARGB(
                  data!.getUint8(i + 3),
                  data.getUint8(i),
                  data.getUint8(i + 1),
                  data.getUint8(i + 2),
                );
              }

              final outside = pixel(Offset(2, local.center.dy));
              final inside = pixel(Offset(local.left + 4, local.center.dy));
              expect(outside, page);
              expect(
                inside.toARGB32(),
                expected.toARGB32(),
                reason: 'Sample unobstructed section surface, not controls',
              );
              expect(inside, isNot(outside));
              expect(
                contrast(theme.colorScheme.onSurface, inside),
                greaterThan(4.5),
              );
              expect(
                pixel(local.topLeft + const Offset(1, 1)),
                page,
                reason: 'Rounded corner clips to page',
              );
              if (name == 'library') {
                for (final y in [
                  local.top + 24,
                  local.center.dy,
                  local.bottom - 24,
                ]) {
                  expect(
                    pixel(Offset(local.left + 4, y)),
                    inside,
                    reason:
                        'One continuous surface behind all three Library settings',
                  );
                }
              }
              sections[name] = {
                'page': hex(outside),
                'section': hex(inside),
                'contrast': contrast(outside, inside),
                'textContrast': contrast(theme.colorScheme.onSurface, inside),
              };
              rendered.dispose();
            });
          }
          expect(find.byType(Card), findsNWidgets(5));
          measurements.add({
            'scheme': entry.name,
            'theme': dark ? 'dark' : 'light',
            'sectionRole': hex(expectedRole),
            'sections': sections,
          });
          const output = String.fromEnvironment('PROFILE31_VISUAL_DIR');
          if (output.isNotEmpty) {
            for (final bottom in [false, true]) {
              final position = tester
                  .state<ScrollableState>(_scroll())
                  .position;
              position.jumpTo(bottom ? position.maxScrollExtent : 0);
              await tester.pumpAndSettle();
              await tester.runAsync(() async {
                final boundary = tester.renderObject<RenderRepaintBoundary>(
                  find.byKey(const Key('profile-render')),
                );
                final rendered = await boundary.toImage(pixelRatio: 2);
                final data = await rendered.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final dir = Directory(output);
                await dir.create(recursive: true);
                await File(
                  '${dir.path}/${entry.name}-${dark ? 'dark' : 'light'}-${bottom ? 'bottom' : 'top'}.png',
                ).writeAsBytes(data!.buffer.asUint8List());
                rendered.dispose();
              });
            }
            await tester.runAsync(
              () => File('$output/pixel_measurements.json').writeAsString(
                const JsonEncoder.withIndent('  ').convert(measurements),
              ),
            );
          }
          expect(h.gatewayCalls, 0);
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets('export grouped Profile top middle bottom when requested', (
    tester,
  ) async {
    if (!const bool.fromEnvironment('EXPORT_PROFILE3_VISUALS')) return;
    const fontDir = String.fromEnvironment('PROFILE3_FONT_DIR');
    await tester.runAsync(() async {
      final loader = FontLoader('ProfileRoboto');
      for (final name in [
        'roboto-regular.ttf',
        'roboto-medium.ttf',
        'roboto-bold.ttf',
      ]) {
        loader.addFont(
          File('$fontDir/$name').readAsBytes().then(ByteData.sublistView),
        );
      }
      await loader.load();
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '$fontDir/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    });
    for (final dark in [false, true]) {
      for (final (width, scale) in [(390.0, 1.0), (320.0, 1.0), (320.0, 2.0)]) {
        await tester.pumpWidget(const SizedBox());
        final h = await _pump(
          tester,
          size: Size(width, 844),
          scale: scale,
          dark: dark,
          font: 'ProfileRoboto',
        );
        expect(find.byType(SettingsControlContent), findsNWidgets(6));
        final controls = find.byWidgetPredicate((w) => w is BiblioTabs);
        expect(controls, findsNWidgets(6));
        if (scale == 1) {
          for (final element in controls.evaluate()) {
            final control = find.byElementPredicate(
              (e) => identical(e, element),
            );
            final flex = tester.widget<Flex>(
              find.descendant(of: control, matching: find.byType(Flex)),
            );
            expect(flex.direction, Axis.horizontal);
          }
        }
        for (final region in ['top', 'middle', 'bottom']) {
          if (region == 'middle') {
            await tester.ensureVisible(
              find.byKey(const Key('application-mode-settings-row')),
            );
            await tester.pumpAndSettle();
          }
          if (region == 'bottom') {
            await tester.scrollUntilVisible(
              find.byKey(const Key('logs-settings-row')),
              180,
              scrollable: _scroll(),
            );
            final position = tester
                .state<ScrollableState>(
                  find
                      .descendant(
                        of: find.byKey(
                          const PageStorageKey('profile-settings-scroll'),
                        ),
                        matching: find.byType(Scrollable),
                      )
                      .first,
                )
                .position;
            position.jumpTo(position.maxScrollExtent);
            await tester.pumpAndSettle();
          }
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('profile-render')),
            );
            final image = await boundary.toImage(pixelRatio: 2);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final dir = Directory(
              const String.fromEnvironment('PROFILE3_VISUAL_DIR'),
            );
            await dir.create(recursive: true);
            await File(
              '${dir.path}/profile-dark-$dark-width-${width.toInt()}-scale-$scale-$region.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        expect(h.gatewayCalls, 0);
        expect(tester.takeException(), isNull);
      }
    }
  });
}

Future<_Harness> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool dark = false,
  String? font,
  bool useDynamicColors = false,
  ColorScheme? lightScheme,
  ColorScheme? darkScheme,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final h = _Harness();
  addTearDown(h.dispose);
  h.container
      .read(themeModeProvider.notifier)
      .setThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: h.container,
      child: Consumer(
        builder: (_, ref, _) {
          ThemeData theme(ColorScheme colors) {
            final result = buildAppTheme(colors);
            return font == null
                ? result
                : result.copyWith(
                    textTheme: result.textTheme.apply(fontFamily: font),
                  );
          }

          return RepaintBoundary(
            key: const Key('profile-render'),
            child: MaterialApp.router(
              debugShowCheckedModeBanner: false,
              theme: theme(
                lightScheme ??
                    (useDynamicColors
                        ? SampleColorSchemes.green(Brightness.light)
                        : fallbackLightColorScheme),
              ),
              darkTheme: theme(
                darkScheme ??
                    (useDynamicColors
                        ? SampleColorSchemes.green(Brightness.dark)
                        : fallbackDarkColorScheme),
              ),
              themeMode: ref.watch(themeModeProvider),
              routerConfig: h.router,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

class _Harness {
  _Harness() {
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) {
          databaseBuilds++;
          return database;
        }),
        remoteCatalogGatewayProvider.overrideWithValue(
          _NoNetwork(() => gatewayCalls++),
        ),
        remoteCacheServiceProvider.overrideWithValue(cache),
      ],
    );
    router = GoRouter(
      initialLocation: AppRoutes.profilePath,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => AppShell(navigationShell: shell),
          branches: [
            StatefulShellBranch(
              routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/library', builder: (_, _) => const SizedBox()),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: AppRoutes.profilePath,
                  builder: (_, _) => const ProfileScreen(),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: AppRoutes.onlineLibrariesPath,
          name: AppRoutes.onlineLibrariesName,
          builder: (_, _) =>
              const Scaffold(body: Text('Online libraries destination')),
        ),
        GoRoute(
          path: AppRoutes.logsPath,
          builder: (_, _) => const Scaffold(body: Text('LOG destination')),
        ),
      ],
    );
  }
  final database = AppDatabase(NativeDatabase.memory());
  final cache = _Cache();
  late final ProviderContainer container;
  late final GoRouter router;
  int databaseBuilds = 0;
  int gatewayCalls = 0;
  Future<void> dispose() async {
    router.dispose();
    container.dispose();
    await database.close();
  }
}

class _NoNetwork implements RemoteCatalogGateway {
  _NoNetwork(this.called);
  final VoidCallback called;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    called();
    throw StateError('Profile must not request catalog data');
  }
}

class _Cache extends RemoteCacheService {
  _Cache()
    : super(
        cacheDirectory: () => throw StateError('No file access'),
        availableBytes: () => throw StateError('No capacity probe'),
      );
  int clears = 0;
  int bytes = 1024;
  int snapshots = 0;
  int updates = 0;
  RemoteCacheBudget budget = const RemoteCacheBudget.defaultValue();
  @override
  Future<void> updateBudget(RemoteCacheBudget value) async {
    updates++;
    budget = value;
  }

  @override
  Future<RemoteCacheSnapshot> snapshot() async {
    snapshots++;
    return RemoteCacheSnapshot(
      bytes: bytes,
      entryCount: bytes == 0 ? 0 : 1,
      maximumBytes: budget.maximumBytes,
    );
  }

  @override
  Future<void> clear() async {
    clears++;
    bytes = 0;
  }
}

Finder _scroll() => find
    .descendant(
      of: find.byKey(const PageStorageKey('profile-settings-scroll')),
      matching: find.byType(Scrollable),
    )
    .first;

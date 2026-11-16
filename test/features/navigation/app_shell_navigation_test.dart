import 'package:bibliolife/app/router/app_shell.dart';
import 'package:bibliolife/app/theme/app_theme.dart';
import 'package:bibliolife/features/reader/presentation/widgets/reader_stable_components.dart';
import 'package:bibliolife/shared/presentation/widgets/floating_navigation_shell_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpIsland(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    EdgeInsets viewPadding = EdgeInsets.zero,
    int selectedIndex = 0,
    ValueChanged<int>? onDestinationSelected,
    ThemeData? theme,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.viewPadding = FakeViewPadding(
      left: viewPadding.left,
      top: viewPadding.top,
      right: viewPadding.right,
      bottom: viewPadding.bottom,
    );
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? lightTheme,
        home: MediaQuery(
          data: MediaQueryData.fromView(
            tester.view,
          ).copyWith(padding: viewPadding, viewPadding: viewPadding),
          child: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                const Positioned.fill(child: SizedBox.expand()),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom:
                      viewPadding.bottom +
                      AppNavigationPresentation.bottomMargin,
                  child: Center(
                    child: FloatingNavigationIsland(
                      selectedIndex: selectedIndex,
                      onDestinationSelected: onDestinationSelected ?? (_) {},
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('is a centered three-icon Readium-style island', (tester) async {
    await pumpIsland(tester);

    final surface = find.byKey(const Key('navigation-island-surface'));
    final rect = tester.getRect(surface);
    final material = tester.widget<Material>(surface);

    expect(
      rect.left,
      (390 - AppNavigationPresentation.intrinsicSurfaceWidth) / 2,
    );
    expect(
      390 - rect.right,
      (390 - AppNavigationPresentation.intrinsicSurfaceWidth) / 2,
    );
    expect(rect.center.dx, 195);
    expect(rect.width, AppNavigationPresentation.intrinsicSurfaceWidth);
    expect(rect.height, AppNavigationPresentation.surfaceHeight);
    expect(material.color, lightTheme.colorScheme.surface);
    expect(material.elevation, AppNavigationPresentation.elevation);
    expect(material.clipBehavior, Clip.antiAlias);
    expect(
      (material.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(AppNavigationPresentation.surfaceRadius),
    );
    expect(
      (material.shape! as RoundedRectangleBorder).side,
      BorderSide(
        color: lightTheme.colorScheme.outlineVariant,
        width: AppNavigationPresentation.outlineWidth,
      ),
    );

    expect(find.byKey(const Key('navigation-destination-0')), findsOneWidget);
    expect(find.byKey(const Key('navigation-destination-1')), findsOneWidget);
    expect(find.byKey(const Key('navigation-destination-2')), findsOneWidget);
    expect(find.byKey(const Key('navigation-icon-0')), findsOneWidget);
    expect(find.byKey(const Key('navigation-icon-1')), findsOneWidget);
    expect(find.byKey(const Key('navigation-icon-2')), findsOneWidget);
    expect(find.text('Home'), findsNothing);
    expect(find.text('Library'), findsNothing);
    expect(find.text('Profile'), findsNothing);
  });

  testWidgets('main and Readium bottom shells share outline without resizing', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final theme in [lightTheme, darkTheme]) {
      for (final width in [390.0, 412.0]) {
        tester.view.physicalSize = Size(width, 844);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: AppNavigationPresentation.bottomMargin,
                    child: Center(
                      child: FloatingNavigationIsland(
                        selectedIndex: 0,
                        onDestinationSelected: (_) {},
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 16,
                    child: Center(
                      child: ReaderStableChromeSurface(
                        key: const Key('readium-bottom-navbar-shell'),
                        floatingNavigationShell: true,
                        margin: EdgeInsets.zero,
                        child: const SizedBox(width: 288, height: 48),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    top: 100,
                    child: ReaderStableChromeSurface(
                      key: const Key('readium-top-toolbar-shell'),
                      margin: EdgeInsets.zero,
                      child: const SizedBox(width: 288, height: 48),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final mainKey = find.byKey(const Key('navigation-island-surface'));
        final readiumKey = find.byKey(const Key('readium-bottom-navbar-shell'));
        final mainMaterial = tester.widget<Material>(mainKey);
        final readiumMaterial = tester.widget<Material>(
          find.descendant(of: readiumKey, matching: find.byType(Material)),
        );
        final mainShape = mainMaterial.shape! as RoundedRectangleBorder;
        final readiumShape = readiumMaterial.shape! as RoundedRectangleBorder;
        final expectedSide = BorderSide(
          color: theme.colorScheme.outlineVariant,
          width: FloatingNavigationShellStyle.outlineWidth,
        );
        expect(
          mainShape,
          FloatingNavigationShellStyle.shapeFor(tester.element(mainKey)),
        );
        expect(readiumShape, mainShape);
        expect(mainShape.side, expectedSide);
        expect(mainShape.borderRadius, BorderRadius.circular(28));
        expect(mainMaterial.color, theme.colorScheme.surface);
        expect(readiumMaterial.color, theme.colorScheme.surface);
        expect(mainMaterial.elevation, AppNavigationPresentation.elevation);
        expect(readiumMaterial.elevation, 6);
        expect(
          mainMaterial.clipBehavior,
          FloatingNavigationShellStyle.clipBehavior,
        );
        expect(readiumMaterial.clipBehavior, mainMaterial.clipBehavior);

        final mainRect = tester.getRect(mainKey);
        expect(mainRect.width, AppNavigationPresentation.intrinsicSurfaceWidth);
        expect(mainRect.height, AppNavigationPresentation.surfaceHeight);
        expect(mainRect.center.dx, width / 2);
        expect(844 - mainRect.bottom, AppNavigationPresentation.bottomMargin);
        final readiumRect = tester.getRect(readiumKey);
        expect(readiumRect.width, 308);
        expect(readiumRect.height, 64);
        expect(readiumRect.left, (width - 308) / 2);
        expect(readiumRect.top, 16);

        final topMaterial = tester.widget<Material>(
          find.descendant(
            of: find.byKey(const Key('readium-top-toolbar-shell')),
            matching: find.byType(Material),
          ),
        );
        expect(topMaterial.shape, isNull);
        expect(topMaterial.clipBehavior, Clip.none);
        expect(
          topMaterial.borderRadius,
          const BorderRadius.all(ReaderStableTokens.chromeRadius),
        );
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('has one immediate circular selection and equal touch cells', (
    tester,
  ) async {
    await pumpIsland(tester, selectedIndex: 1);

    final circle = tester.getRect(
      find.byKey(const Key('navigation-selected-circle')),
    );
    expect(circle.width, AppNavigationPresentation.selectedCircleSize);
    expect(circle.height, AppNavigationPresentation.selectedCircleSize);
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.byKey(const Key('navigation-selected-circle')),
                )
                .decoration
            as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.color, lightTheme.colorScheme.secondaryContainer);
    expect(decoration.color, isNot(lightTheme.colorScheme.surface));
    expect(
      tester.widget<Icon>(find.byKey(const Key('navigation-icon-1'))).color,
      lightTheme.colorScheme.onSecondaryContainer,
    );
    expect(
      tester.widget<Icon>(find.byKey(const Key('navigation-icon-0'))).color,
      lightTheme.colorScheme.onSurfaceVariant,
    );
    expect(find.byKey(const Key('navigation-island-bar')), findsOneWidget);
    expect(find.byType(Expanded), findsNWidgets(3));
    final boxes = List.generate(
      3,
      (index) =>
          tester.getRect(find.byKey(Key('navigation-destination-$index'))),
    );
    expect(boxes.every((box) => box.width >= 48 && box.height >= 48), isTrue);
    expect(boxes[0].width, closeTo(boxes[1].width, 0.001));
    expect(boxes[1].width, closeTo(boxes[2].width, 0.001));
    expect(find.byType(AnimatedContainer), findsNothing);
    expect(find.byType(AnimatedAlign), findsNothing);
    expect(find.byType(AnimatedPositioned), findsNothing);
    expect(find.byType(AnimatedSwitcher), findsNothing);
    expect(find.byType(TweenAnimationBuilder), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark theme keeps the active circle distinct from the surface', (
    tester,
  ) async {
    await pumpIsland(tester, selectedIndex: 2, theme: darkTheme);

    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.byKey(const Key('navigation-selected-circle')),
                )
                .decoration
            as BoxDecoration;
    expect(decoration.color, darkTheme.colorScheme.secondaryContainer);
    expect(decoration.color, isNot(darkTheme.colorScheme.surface));
    expect(
      tester.widget<Icon>(find.byKey(const Key('navigation-icon-2'))).color,
      darkTheme.colorScheme.onSecondaryContainer,
    );
  });

  testWidgets('icons remain at fixed global centers across selections', (
    tester,
  ) async {
    Future<List<Offset>> iconCentersFor(int selectedIndex) async {
      await pumpIsland(tester, selectedIndex: selectedIndex);
      return List.generate(
        3,
        (index) => tester.getCenter(find.byKey(Key('navigation-icon-$index'))),
      );
    }

    final home = await iconCentersFor(0);
    final library = await iconCentersFor(1);
    final profile = await iconCentersFor(2);

    expect(library, home);
    expect(profile, home);
    expect(home[1].dx - home[0].dx, closeTo(home[2].dx - home[1].dx, 0.001));
    expect(home[0].dx + home[2].dx, closeTo(2 * home[1].dx, 0.001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('respects bottom safe area and stays overflow-free when narrow', (
    tester,
  ) async {
    await pumpIsland(
      tester,
      size: const Size(320, 568),
      viewPadding: const EdgeInsets.only(bottom: 34),
    );
    final rect = tester.getRect(
      find.byKey(const Key('navigation-island-surface')),
    );
    expect(568 - rect.bottom, AppNavigationPresentation.bottomMargin + 34);
    expect(rect.width, AppNavigationPresentation.intrinsicSurfaceWidth);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each destination reports exactly one tap', (tester) async {
    final selected = <int>[];
    await pumpIsland(tester, onDestinationSelected: selected.add);

    for (var index = 0; index < 3; index++) {
      await tester.tap(find.byKey(Key('navigation-destination-$index')));
      await tester.pump();
    }
    expect(selected, [0, 1, 2]);
    expect(tester.takeException(), isNull);
  });
}

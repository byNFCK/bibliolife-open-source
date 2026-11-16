// CorePalette is supplied by the dynamic_color plugin.
// ignore_for_file: deprecated_member_use

import 'dart:ui' as ui;

import 'package:bibliolife/app/theme/app_theme.dart';
import 'package:bibliolife/app/theme/dynamic_color_scheme.dart';
import 'package:bibliolife/shared/presentation/widgets/biblio_tabs.dart';
import 'package:dynamic_color/samples.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:material_color_utilities/material_color_utilities.dart';

void main() {
  final palettes = [
    CorePalette.fromList(CorePalette.of(0xff428a47).asList()),
    CorePalette.fromList(CorePalette.of(0xff9650aa).asList()),
  ];
  for (final brightness in Brightness.values) {
    final schemes = [
      for (final palette in palettes)
        dynamicSchemeFromCorePalette(palette, brightness),
      brightness == Brightness.light
          ? fallbackLightColorScheme
          : fallbackDarkColorScheme,
    ];
    for (var schemeIndex = 0; schemeIndex < schemes.length; schemeIndex++) {
      testWidgets(
        'foreground states in scheme $schemeIndex $brightness',
        (tester) async {
          final scheme = schemes[schemeIndex];
          final selections = <int>[];
          for (final selected in [false, true]) {
            for (final hasIcon in [false, true]) {
              // Both a disabled item and a null callback disable the same tab.
              for (final disabledMode in [0, 1, 2]) {
                final item = BiblioTabItem<int>(
                  id: 0,
                  label: 'Tab',
                  icon: hasIcon ? Icons.book : null,
                  enabled: disabledMode != 1,
                );
                await tester.pumpWidget(
                  _subject(
                    [item],
                    selectedId: selected ? 0 : null,
                    onSelected: selections.add,
                    disableAll: disabledMode == 2,
                    width: 320,
                    scale: 2,
                    theme: buildAppTheme(scheme),
                  ),
                );
                await tester.pumpAndSettle();
                final foreground = selected
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant;
                final expected = disabledMode == 0
                    ? foreground
                    : foreground.withValues(alpha: 0.38);
                expect(
                  tester.widget<Text>(find.text('Tab')).style?.color,
                  expected,
                );
                if (hasIcon) {
                  expect(
                    tester.widget<Icon>(find.byIcon(Icons.book)).color,
                    expected,
                  );
                }
                final semantics = tester
                    .getSemantics(_tab(0))
                    .getSemanticsData();
                expect(
                  semantics.flagsCollection.isSelected,
                  selected ? ui.Tristate.isTrue : ui.Tristate.isFalse,
                );
                expect(
                  semantics.flagsCollection.isEnabled,
                  disabledMode == 0 ? ui.Tristate.isTrue : ui.Tristate.isFalse,
                );
                final previousCount = selections.length;
                await tester.tap(_tab(0));
                expect(
                  selections.length,
                  previousCount + (disabledMode == 0 ? 1 : 0),
                );
                if (selected) {
                  expect(tester.getRect(_capsule), tester.getRect(_tab(0)));
                } else {
                  expect(_capsule, findsNothing);
                }
                expect(tester.takeException(), isNull);
              }
            }
          }
        },
        semanticsEnabled: true,
      );
    }
  }
  for (final count in [1, 2, 3, 5, 8]) {
    testWidgets(
      '$count tabs follow their labels and reveal initial selection',
      (tester) async {
        await tester.pumpWidget(_subject(_items(count), selectedId: count - 1));

        expect(find.byType(InkWell), findsNWidgets(count));
        expect(tester.getSize(_tab(0)).height, 42);
        if (count > 1) {
          expect(
            tester.getSize(_tab(1)).width,
            greaterThan(tester.getSize(_tab(0)).width),
          );
        }
        _expectVisible(tester, count - 1);
        expect(tester.getRect(_capsule), tester.getRect(_tab(count - 1)));
        final track = tester.getRect(_track);
        final viewport = tester.getRect(_scroll);
        final available = tester.getRect(find.byType(BiblioTabs<int>));
        expect(track.height, 50);
        expect(track, viewport.inflate(4));
        expect(track.center.dx, closeTo(available.center.dx, 0.01));
        if (count <= 3) {
          final contentWidth = List.generate(
            count,
            (id) => tester.getSize(_tab(id)).width,
          ).fold(0.0, (total, width) => total + width);
          expect(track.width, closeTo(contentWidth + 8, 0.01));
          expect(track.width, lessThan(available.width));
        } else {
          expect(track.width, closeTo(available.width, 0.01));
        }
        expect(
          _position(tester).maxScrollExtent,
          count <= 3 ? 0 : greaterThan(0),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final brightness in Brightness.values) {
    testWidgets('Android dynamic colors keep a visible track in $brightness', (
      tester,
    ) async {
      final theme = buildAppTheme(SampleColorSchemes.green(brightness));
      final background = theme.scaffoldBackgroundColor;
      expect(theme.colorScheme.surfaceContainerHigh, background);

      await tester.pumpWidget(
        _subject(_items(3), selectedId: null, theme: theme),
      );

      final track = tester.widget<Material>(_track);
      final backgroundLuminance = background.computeLuminance();
      final trackLuminance = track.color!.computeLuminance();
      final contrast = brightness == Brightness.dark
          ? (trackLuminance + 0.05) / (backgroundLuminance + 0.05)
          : (backgroundLuminance + 0.05) / (trackLuminance + 0.05);
      expect(contrast, greaterThan(1.15));
      expect(track.shape, const StadiumBorder());
      expect(track.elevation, 0);
      expect(track.clipBehavior, Clip.antiAlias);
      expect(_capsule, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'long German and Ukrainian labels at large scale in $brightness',
      (tester) async {
        const items = [
          BiblioTabItem(
            id: 0,
            label: 'Sammlungsverwaltung und Buchempfehlungen',
          ),
          BiblioTabItem(id: 1, label: 'Усі книжки з моїх збережених колекцій'),
        ];
        final theme = ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: brightness,
          ),
        );
        await tester.pumpWidget(
          _subject(items, selectedId: 1, width: 205, scale: 2.4, theme: theme),
        );

        final selectedTab = tester.getRect(_tab(1));
        final selectedLabel = tester.getRect(find.text(items[1].label));
        expect(selectedTab.height, greaterThan(42));
        expect(selectedLabel.top - selectedTab.top, closeTo(6, 0.01));
        expect(selectedTab.bottom - selectedLabel.bottom, closeTo(6, 0.01));
        expect(
          tester.widget<Material>(_track).color,
          theme.colorScheme.surfaceContainerHigh,
        );
        final decoration =
            tester.widget<DecoratedBox>(_capsule).decoration as ShapeDecoration;
        expect(decoration.color, theme.colorScheme.secondaryContainer);
        expect(
          tester.widget<Text>(find.text(items[1].label)).style?.color,
          theme.colorScheme.onSecondaryContainer,
        );
        final tab = tester.getSemantics(_tab(1));
        final data = tab.getSemanticsData();
        expect(data.label, items[1].label);
        expect(data.role, ui.SemanticsRole.tab);
        expect(data.flagsCollection.isSelected, ui.Tristate.isTrue);
        expect(data.flagsCollection.isEnabled, ui.Tristate.isTrue);
        expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
        final tabBar = tab.parent!;
        expect(tabBar.getSemanticsData().role, ui.SemanticsRole.tabBar);
        expect(
          tabBar.parent!.getSemanticsData().scrollExtentMax,
          greaterThan(0),
        );
        expect(_position(tester).maxScrollExtent, greaterThan(0));
        _expectVisible(tester, 1);
        expect(tester.takeException(), isNull);
      },
      semanticsEnabled: true,
    );
  }

  testWidgets('a tap reports the ID and a single capsule moves and resizes', (
    tester,
  ) async {
    final selections = <int>[];
    final items = _items(3);
    await tester.pumpWidget(
      _subject(items, selectedId: 0, onSelected: selections.add),
    );
    final start = tester.getRect(_capsule);

    await tester.tap(_tab(2));
    expect(selections, [2]);
    expect(tester.getRect(_capsule), start);

    await tester.pumpWidget(
      _subject(items, selectedId: 2, onSelected: selections.add),
    );
    final end = tester.getRect(_tab(2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_capsule, findsOneWidget);
    expect(
      tester.getRect(_capsule).left,
      inExclusiveRange(start.left, end.left),
    );
    expect(
      tester.getRect(_capsule).width,
      inExclusiveRange(start.width, end.width),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(_capsule), end);
    expect(selections, [2]);
  });

  testWidgets('external updates only scroll as far as needed, including RTL', (
    tester,
  ) async {
    final items = _items(8);
    Future<void> select(int id) => tester.pumpWidget(
      _subject(items, selectedId: id, direction: TextDirection.rtl),
    );

    await select(0);
    expect(
      tester.getCenter(_tab(0)).dx,
      greaterThan(tester.getCenter(_tab(1)).dx),
    );
    await select(1);
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, 0);

    await select(7);
    await tester.pumpAndSettle();
    _expectVisible(tester, 7);
    expect(
      _position(tester).pixels,
      closeTo(_position(tester).maxScrollExtent, 0.01),
    );
    expect(tester.getRect(_capsule), tester.getRect(_tab(7)));
  });

  testWidgets(
    'reorder, relabel, removal and empty lists keep selection controlled',
    (tester) async {
      final selections = <int>[];
      final items = _items(5);
      Future<void> show(List<BiblioTabItem<int>> items) => tester.pumpWidget(
        _subject(items, selectedId: 1, onSelected: selections.add),
      );

      await show(items);
      final selectedElement = tester.element(_tab(1));
      await show([
        items[3],
        items[0],
        items[4],
        items[2],
        const BiblioTabItem(id: 1, label: 'Renamed selected source'),
      ]);
      await tester.pumpAndSettle();
      expect(tester.element(_tab(1)), same(selectedElement));
      _expectVisible(tester, 1);
      expect(tester.getRect(_capsule), tester.getRect(_tab(1)));

      await show(items.where((item) => item.id != 1).toList());
      expect(_capsule, findsNothing);
      await show(const []);
      expect(_scroll, findsNothing);
      expect(selections, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'restores the strip offset on its first frame when selection is visible',
    (tester) async {
      final bucket = PageStorageBucket();
      Future<void> show(List<BiblioTabItem<int>> items) =>
          tester.pumpWidget(_subject(items, selectedId: 4, storage: bucket));
      final items = _items(8);
      await show(items);
      final initialOffset = _position(tester).pixels;
      await tester.timedDrag(
        _scroll,
        const Offset(-90, 0),
        const Duration(milliseconds: 600),
      );
      await tester.pumpAndSettle();
      final savedOffset = _position(tester).pixels;
      expect(savedOffset, greaterThan(initialOffset));
      _expectVisible(tester, 4);

      await show(const []);
      await show(items);
      expect(_position(tester).pixels, closeTo(savedOffset, 0.01));
      _expectVisible(tester, 4);
    },
  );

  testWidgets(
    'supports keyboard activation, disabled items and reduced motion',
    (tester) async {
      final selections = <int>[];
      final items = [
        const BiblioTabItem(id: 0, label: 'Disabled', enabled: false),
        ..._items(8).skip(1),
      ];
      Future<void> select(int id) => tester.pumpWidget(
        _subject(
          items,
          selectedId: id,
          onSelected: selections.add,
          reduceMotion: true,
        ),
      );
      await select(1);
      final disabled = tester.getSemantics(_tab(0)).getSemanticsData();
      expect(disabled.label, 'Disabled');
      expect(disabled.role, ui.SemanticsRole.tab);
      expect(disabled.flagsCollection.isSelected, ui.Tristate.isFalse);
      expect(disabled.flagsCollection.isEnabled, ui.Tristate.isFalse);
      expect(disabled.hasAction(ui.SemanticsAction.tap), isFalse);
      await tester.tapAt(tester.getCenter(_tab(0)));
      expect(selections, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(selections, [1]);

      await select(7);
      await tester.pump();
      _expectVisible(tester, 7);
      expect(tester.getRect(_capsule), tester.getRect(_tab(7)));
    },
    semanticsEnabled: true,
  );
}

List<BiblioTabItem<int>> _items(int count) => [
  for (var id = 0; id < count; id++)
    BiblioTabItem(id: id, label: id == 0 ? 'All' : 'Collection $id'),
];

Finder _tab(int id) => find.byKey(ValueKey(id));
Finder get _scroll => find.byType(SingleChildScrollView);
Finder get _track => find.ancestor(
  of: _scroll,
  matching: find.byWidgetPredicate(
    (widget) => widget is Material && widget.shape is StadiumBorder,
  ),
);
Finder get _capsule => find.descendant(
  of: find.byType(AnimatedPositionedDirectional),
  matching: find.byType(DecoratedBox),
);

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable)).position;

void _expectVisible(WidgetTester tester, int id) {
  final viewport = tester.getRect(_scroll).inflate(0.01);
  final tab = tester.getRect(_tab(id));
  expect(viewport.contains(tab.topLeft), isTrue);
  expect(viewport.contains(tab.bottomRight), isTrue);
}

Widget _subject(
  List<BiblioTabItem<int>> items, {
  required int? selectedId,
  ValueChanged<int>? onSelected,
  double width = 520,
  double scale = 1,
  ThemeData? theme,
  TextDirection direction = TextDirection.ltr,
  bool reduceMotion = false,
  bool disableAll = false,
  PageStorageBucket? storage,
}) => MaterialApp(
  theme: theme,
  home: Scaffold(
    body: Center(
      child: Directionality(
        textDirection: direction,
        child: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduceMotion,
          ),
          child: SizedBox(
            width: width,
            child: PageStorage(
              bucket: storage ?? PageStorageBucket(),
              child: BiblioTabs<int>(
                items: items,
                selectedId: selectedId,
                onSelected: disableAll ? null : onSelected ?? (_) {},
                scrollStorageKey: const PageStorageKey('test-tab-scroll'),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

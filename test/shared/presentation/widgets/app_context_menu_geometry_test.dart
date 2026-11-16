import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_float_menu.dart';

import 'package:bibliolife/shared/presentation/widgets/app_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final direction in TextDirection.values) {
    for (final alignment in [
      Alignment.topRight,
      Alignment.centerRight,
      Alignment.bottomRight,
    ]) {
      testWidgets('measures shared menu $direction $alignment', (tester) async {
        tester.view.physicalSize = const Size(390, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(colorScheme: scheme, fontFamily: 'MenuRoboto'),
            home: Directionality(
              textDirection: direction,
              child: Scaffold(
                body: SafeArea(
                  child: Align(
                    alignment: direction == TextDirection.rtl
                        ? Alignment(-alignment.x, alignment.y)
                        : alignment,
                    child: AppContextMenuButton<int>(
                      tooltip: 'Actions',
                      onSelected: (_) {},
                      actions: const [
                        AppContextMenuAction(
                          value: 1,
                          label: 'Edit book',
                          icon: Icons.edit,
                        ),
                        AppContextMenuAction(
                          value: 2,
                          label: 'Delete book',
                          icon: Icons.delete,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final trigger = tester.getRect(find.byType(MenuAnchor));
        await tester.tap(find.byTooltip('Actions'));
        await tester.pumpAndSettle();
        final surface = find.byWidgetPredicate(
          (w) => w is Material && w.color == scheme.surfaceContainerHigh,
        );
        final popup = tester.getRect(surface);
        final row = tester.getRect(find.byType(MenuItemButton).first);
        final icon = tester.getRect(find.byIcon(Icons.edit));
        final label = tester.getRect(find.text('Edit book'));
        debugPrint(
          'GEOMETRY $direction $alignment trigger=$trigger popup=$popup row=$row icon=$icon label=$label gap=${direction == TextDirection.ltr ? label.left - icon.right : icon.left - label.right}',
        );
        expect(popup.width, 240);
        expect(row.height, 48);
        expect(icon.size, const Size(24, 24));
        expect(
          direction == TextDirection.ltr
              ? label.left - icon.right
              : icon.left - label.right,
          12,
        );
        expect(
          direction == TextDirection.ltr
              ? icon.left - popup.left
              : popup.right - icon.right,
          12,
        );
        expect(row.top - popup.top, 8);
        expect(popup.left, greaterThanOrEqualTo(0));
        expect(popup.right, lessThanOrEqualTo(390));
        expect(popup.top, greaterThanOrEqualTo(0));
        expect(popup.bottom, lessThanOrEqualTo(800));
        expect(
          direction == TextDirection.ltr ? popup.right : popup.left,
          direction == TextDirection.ltr ? trigger.right : trigger.left,
        );
        expect(
          alignment == Alignment.bottomRight
              ? trigger.top - popup.bottom
              : popup.top - trigger.bottom,
          8,
        );
      });
    }
  }

  testWidgets('narrow safe viewport keeps a shared responsive width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(left: 12, right: 12);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: Scaffold(
          body: Center(
            child: AppContextMenuButton<int>(
              tooltip: 'Actions',
              onSelected: (_) {},
              actions: const [
                AppContextMenuAction(value: 1, label: 'Edit', icon: Icons.edit),
                AppContextMenuAction(
                  value: 2,
                  label: 'A much longer action label that wraps',
                  icon: Icons.delete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    final surface = find.byWidgetPredicate(
      (w) => w is Material && w.color == scheme.surfaceContainerHigh,
    );
    final popup = tester.getRect(surface);
    expect(popup.width, 160);
    expect(popup.left, greaterThanOrEqualTo(12));
    expect(popup.right, lessThanOrEqualTo(188));
    for (final item in find.byType(MenuItemButton).evaluate()) {
      expect((item.renderObject! as RenderBox).size.width, 160);
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets('large text and busy disabled rows keep spacing and states', (
    tester,
  ) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: Scaffold(
              body: Center(
                child: MenuAnchor(
                  style: AppContextMenuPresentation.style(context),
                  menuChildren: [
                    const AppContextMenuItem(
                      label: 'Busy action',
                      icon: Icons.refresh,
                      busy: true,
                      onPressed: null,
                    ),
                    const AppContextMenuItem(
                      label: 'Disabled delete',
                      icon: Icons.delete,
                      destructive: true,
                      onPressed: null,
                    ),
                  ],
                  builder: (context, controller, child) => TextButton(
                    onPressed: () => controller.open(),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final surface = find.byWidgetPredicate(
      (w) => w is Material && w.color == scheme.surfaceContainerHigh,
    );
    final popup = tester.getRect(surface);
    final busy = tester.getRect(find.byType(CircularProgressIndicator));
    final busyLabel = tester.getRect(find.text('Busy action'));
    final deleteIcon = tester.getRect(find.byIcon(Icons.delete));
    final deleteLabel = tester.getRect(find.text('Disabled delete'));
    expect(busy.left - popup.left, 15);
    expect(busyLabel.left - busy.right, 15);
    expect(deleteIcon.left - popup.left, 12);
    expect(deleteLabel.left - deleteIcon.right, 12);
    for (final button in tester.widgetList<MenuItemButton>(
      find.byType(MenuItemButton),
    )) {
      expect(button.onPressed, isNull);
      expect(
        button.style!.foregroundColor!.resolve({WidgetState.disabled}),
        scheme.onSurface.withValues(alpha: 0.38),
      );
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets('renders representative shared action sets', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (Platform.environment['MENU_RENDER'] == '1') {
      final fontDir = Platform.environment['MENU_FONT_DIR']!;
      await tester.runAsync(() async {
        final font = FontLoader('MenuRoboto');
        for (final name in ['roboto-regular.ttf', 'roboto-medium.ttf']) {
          font.addFont(
            File('$fontDir/$name').readAsBytes().then(ByteData.sublistView),
          );
        }
        await font.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(
            File(
              '$fontDir/materialicons-regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          );
        await icons.load();
      });
    }
    final sets = <String, List<String>>{
      'details': [
        AppStrings.addToCollection,
        AppStrings.refresh,
        AppStrings.editBook,
        AppStrings.saveBookFile,
        AppStrings.delete,
      ],
      'library': ['Add to favorites', 'Delete'],
      'collection': [AppStrings.editCollection, AppStrings.deleteCollection],
      'home': ['Remove from favorites'],
      'search': ['Open', 'Add to favorites'],
      'light': [AppStrings.editCollection, AppStrings.deleteCollection],
    };
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = previousShadows);

    for (final entry in sets.entries) {
      final key = GlobalKey();
      final scheme = ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: entry.key == 'light' ? Brightness.light : Brightness.dark,
      );
      final iconSets = <String, List<IconData>>{
        'details': [
          Icons.playlist_add,
          Icons.refresh,
          Icons.edit_outlined,
          Icons.save_alt,
          Icons.delete_outline,
        ],
        'library': [Icons.favorite_border, Icons.delete_outline],
        'collection': [Icons.edit_outlined, Icons.delete_outline],
        'home': [Icons.favorite],
        'search': [Icons.open_in_new, Icons.favorite_border],
        'light': [Icons.edit_outlined, Icons.delete_outline],
      };
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: Center(
                child: BookDetailsFloatMenu(
                  onRead: () {},
                  actions: [
                    for (var i = 0; i < entry.value.length; i++)
                      BookDetailsMenuAction(
                        label: entry.value[i],
                        icon: iconSets[entry.key]![i],
                        onSelected: () {},
                        destructive: i == 4,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: entry.key == 'details'
              ? MaterialApp.router(
                  debugShowCheckedModeBanner: false,
                  theme: ThemeData(
                    colorScheme: scheme,
                    fontFamily: 'MenuRoboto',
                  ),
                  routerConfig: router,
                )
              : MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: ThemeData(
                    colorScheme: scheme,
                    fontFamily: 'MenuRoboto',
                  ),
                  home: Scaffold(
                    body: Align(
                      alignment: Alignment.centerRight,
                      child: AppContextMenuButton<int>(
                        tooltip: 'Actions',
                        onSelected: (_) {},
                        actions: [
                          for (var i = 0; i < entry.value.length; i++)
                            AppContextMenuAction(
                              value: i,
                              label: entry.value[i],
                              icon: iconSets[entry.key]![i],
                              destructive:
                                  (entry.key == 'library' ||
                                      entry.key == 'collection' ||
                                      entry.key == 'light') &&
                                  i == 1,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      );
      await tester.tap(
        entry.key == 'details'
            ? find.byKey(const Key('book-details-more-actions'))
            : find.byTooltip('Actions'),
      );
      await tester.pumpAndSettle();
      final surface = find.byWidgetPredicate(
        (w) => w is Material && w.color == scheme.surfaceContainerHigh,
      );
      expect(tester.getRect(surface).width, 240);
      expect(tester.getRect(surface).height, 16 + 48 * entry.value.length);
      for (final item in find.byType(MenuItemButton).evaluate()) {
        expect((item.renderObject! as RenderBox).size.height, 48);
      }
      debugPrint(
        'SET ${entry.key}: ${tester.getRect(surface)} rows=${tester.widgetList<MenuItemButton>(find.byType(MenuItemButton)).length}',
      );
      if (Platform.environment['MENU_RENDER'] == '1' && entry.key != 'search') {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final outputDirectory = Directory('artifacts/test_screenshots');
          await outputDirectory.create(recursive: true);
          await File(
            '${outputDirectory.path}/menu-${entry.key}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
        });
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      router.dispose();
    }
    debugDisableShadows = previousShadows;
  });
}

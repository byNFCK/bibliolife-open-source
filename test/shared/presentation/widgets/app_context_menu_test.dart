import 'package:bibliolife/shared/presentation/widgets/app_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final direction in TextDirection.values) {
      for (final alignment in [Alignment.topRight, Alignment.bottomRight]) {
        testWidgets(
          'menu stays in safe viewport with large localized text: $brightness $direction $alignment',
          (tester) async {
            tester.view.physicalSize = const Size(320, 600);
            tester.view.devicePixelRatio = 1;
            tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetPadding);
            final scheme = ColorScheme.fromSeed(
              seedColor: Colors.teal,
              brightness: brightness,
            );
            final calls = <String>[];
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData(colorScheme: scheme),
                home: Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(2)),
                    child: Directionality(
                      textDirection: direction,
                      child: Scaffold(
                        body: SafeArea(
                          child: Align(
                            alignment: alignment,
                            child: AppContextMenuButton<String>(
                              tooltip: 'Book actions',
                              onSelected: calls.add,
                              actions: const [
                                AppContextMenuAction(
                                  value: 'favorite',
                                  label: 'Вилучити книгу з обраного',
                                  icon: Icons.favorite,
                                  semanticLabel:
                                      'Вилучити книгу з обраного, Moby Dick',
                                ),
                                AppContextMenuAction(
                                  value: 'delete',
                                  label: 'Видалити книгу',
                                  icon: Icons.delete_outline,
                                  destructive: true,
                                ),
                                AppContextMenuAction(
                                  value: 'disabled',
                                  label: 'Недоступна дія',
                                  icon: Icons.edit_outlined,
                                  enabled: false,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.byTooltip('Book actions'));
            await tester.pumpAndSettle();
            final surface = find.byWidgetPredicate(
              (widget) =>
                  widget is Material &&
                  widget.color == scheme.surfaceContainerHigh,
            );
            expect(surface, findsOneWidget);
            final material = tester.widget<Material>(surface);
            expect(material.elevation, 6);
            expect(
              (material.shape! as RoundedRectangleBorder).borderRadius,
              BorderRadius.circular(20),
            );
            final bounds = tester.getRect(surface);
            expect(bounds.left, greaterThanOrEqualTo(0));
            expect(bounds.right, lessThanOrEqualTo(320));
            expect(bounds.top, greaterThanOrEqualTo(24));
            expect(bounds.bottom, lessThanOrEqualTo(576));
            final items = tester
                .widgetList<MenuItemButton>(find.byType(MenuItemButton))
                .toList();
            expect(items.map((item) => item.onPressed != null), [
              true,
              true,
              false,
            ]);
            expect(items[0].leadingIcon, isA<Icon>());
            expect(items[1].style!.foregroundColor!.resolve({}), scheme.error);
            expect(
              items[0].style?.foregroundColor?.resolve({}),
              isNot(scheme.error),
            );
            expect(
              find.bySemanticsLabel('Вилучити книгу з обраного, Moby Dick'),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            await tester.tap(find.text('Вилучити книгу з обраного'));
            await tester.pumpAndSettle();
            expect(calls, ['favorite']);
            expect(find.byType(MenuItemButton), findsNothing);
            await tester.tap(find.byTooltip('Book actions'));
            await tester.pumpAndSettle();
            await tester.tapAt(const Offset(12, 40));
            await tester.pumpAndSettle();
            expect(find.byType(MenuItemButton), findsNothing);
            expect(calls, ['favorite']);
            await tester.tap(find.byTooltip('Book actions'));
            await tester.pumpAndSettle();
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(find.byType(MenuItemButton), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}

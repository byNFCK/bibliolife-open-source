import 'dart:async';
import 'dart:typed_data';
import 'package:bibliolife/app/router/app_router.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_download_queue_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:bibliolife/app/theme/dynamic_color_scheme.dart';
// ignore: depend_on_referenced_packages
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:bibliolife/app/app.dart';
import 'package:bibliolife/app/theme/app_theme.dart';
import 'package:bibliolife/app/theme/theme_mode_provider.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(DynamicColorPlugin.channel, null),
  );

  ProviderContainer makeContainer() {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
    );
    final container = ProviderContainer(
      overrides: [
        appRouterProvider.overrideWithValue(router),
        catalogSourcesBootstrapProvider.overrideWith((ref) async {}),
        remoteDownloadQueueBootstrapProvider.overrideWith((ref) async {}),
      ],
    );
    addTearDown(() {
      container.dispose();
      router.dispose();
    });
    return container;
  }

  testWidgets('one core palette supplies both schemes through theme changes', (
    tester,
  ) async {
    // ignore: deprecated_member_use
    final samples = CorePalette.of(0xff6750a4).asList();
    // ignore: deprecated_member_use
    final palette = CorePalette.fromList(samples);
    var coreCalls = 0;
    var accentCalls = 0;
    messenger.setMockMethodCallHandler(DynamicColorPlugin.channel, (
      call,
    ) async {
      if (call.method == DynamicColorPlugin.methodName) {
        coreCalls++;
        return Int32List.fromList(samples);
      }
      accentCalls++;
      return null;
    });
    final container = makeContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const App()),
    );
    await tester.pump();
    for (final mode in ThemeMode.values) {
      container.read(themeModeProvider.notifier).setThemeMode(mode);
      await tester.pump();
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, mode);
      expect(
        app.theme!.colorScheme,
        dynamicSchemeFromCorePalette(palette, Brightness.light),
      );
      expect(
        app.darkTheme!.colorScheme,
        dynamicSchemeFromCorePalette(palette, Brightness.dark),
      );
    }
    expect(coreCalls, 1);
    expect(accentCalls, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('desktop accent fallback uses original seeded schemes', (
    tester,
  ) async {
    const accent = Color(0xff5371ad);
    messenger.setMockMethodCallHandler(
      DynamicColorPlugin.channel,
      (call) async => call.method == DynamicColorPlugin.accentColorMethodName
          ? accent.toARGB32()
          : null,
    );
    final container = makeContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const App()),
    );
    await tester.pump();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.colorScheme, ColorScheme.fromSeed(seedColor: accent));
    expect(
      app.darkTheme!.colorScheme,
      ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark),
    );
    await tester.pumpWidget(const SizedBox());
  });
  for (final failure in ['null', 'exception']) {
    testWidgets(
      'unavailable palette $failure retains fallback in all theme modes',
      (tester) async {
        var calls = 0;
        messenger.setMockMethodCallHandler(DynamicColorPlugin.channel, (
          call,
        ) async {
          if (call.method == DynamicColorPlugin.methodName) {
            calls++;
            if (failure == 'exception') {
              throw PlatformException(code: 'unavailable');
            }
          }
          return null;
        });
        final container = makeContainer();

        await tester.pumpWidget(
          UncontrolledProviderScope(container: container, child: const App()),
        );
        await tester.pump();
        for (final mode in ThemeMode.values) {
          container.read(themeModeProvider.notifier).setThemeMode(mode);
          await tester.pump();
          final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
          expect(app.themeMode, mode);
          expect(app.theme!.colorScheme, fallbackLightColorScheme);
          expect(app.darkTheme!.colorScheme, fallbackDarkColorScheme);
        }
        expect(calls, 1);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }
  testWidgets(
    'pending request renders fallback and completion after disposal is safe',
    (tester) async {
      final result = Completer<Object?>();
      var calls = 0;
      messenger.setMockMethodCallHandler(DynamicColorPlugin.channel, (call) {
        if (call.method == DynamicColorPlugin.methodName) {
          calls++;
          return result.future;
        }
        return Future.value(null);
      });
      final container = makeContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const App()),
      );
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.theme!.colorScheme, fallbackLightColorScheme);
      expect(app.darkTheme!.colorScheme, fallbackDarkColorScheme);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      result.complete(null);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(calls, 1);
    },
  );
}

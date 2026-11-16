import 'package:bibliolife/app/router/app_router.dart';
import 'package:bibliolife/app/theme/app_theme.dart';
import 'package:bibliolife/app/theme/dynamic_color_scheme.dart';
import 'package:bibliolife/app/theme/theme_mode_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_download_queue_provider.dart';
import 'package:bibliolife/shared/application/logging/app_log_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dynamic_color/dynamic_color.dart';

class App extends ConsumerStatefulWidget {
  const App({
    this.injectedLightColorScheme,
    this.injectedDarkColorScheme,
    super.key,
  });

  final ColorScheme? injectedLightColorScheme;
  final ColorScheme? injectedDarkColorScheme;

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  ColorScheme? _light;
  ColorScheme? _dark;

  @override
  void initState() {
    super.initState();
    if (widget.injectedLightColorScheme == null &&
        widget.injectedDarkColorScheme == null) {
      _loadDynamicColors();
    }
  }

  @override
  void didUpdateWidget(covariant App oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hadInjection =
        oldWidget.injectedLightColorScheme != null ||
        oldWidget.injectedDarkColorScheme != null;
    final hasInjection =
        widget.injectedLightColorScheme != null ||
        widget.injectedDarkColorScheme != null;
    if (hadInjection && !hasInjection && !_requested) _loadDynamicColors();
  }

  bool _requested = false;

  Future<void> _loadDynamicColors() async {
    _requested = true;
    try {
      final palette = await DynamicColorPlugin.getCorePalette();
      if (!mounted) return;
      if (palette != null) {
        final light = dynamicSchemeFromCorePalette(palette, Brightness.light);
        final dark = dynamicSchemeFromCorePalette(palette, Brightness.dark);
        setState(() {
          _light = light;
          _dark = dark;
        });
        return;
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('dynamic_color: Failed to obtain core palette: $error');
      }
    }
    if (!mounted) return;
    try {
      final accent = await DynamicColorPlugin.getAccentColor();
      if (!mounted) return;
      if (accent != null) {
        setState(() {
          _light = ColorScheme.fromSeed(
            seedColor: accent,
            brightness: Brightness.light,
          );
          _dark = ColorScheme.fromSeed(
            seedColor: accent,
            brightness: Brightness.dark,
          );
        });
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('dynamic_color: Failed to obtain accent color: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.read(appLogProvider);
    ref.watch(catalogSourcesBootstrapProvider);
    ref.watch(remoteDownloadQueueBootstrapProvider);
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final injected =
        widget.injectedLightColorScheme != null ||
        widget.injectedDarkColorScheme != null;
    return MaterialApp.router(
      title: 'BiblioLife',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(
        (injected ? widget.injectedLightColorScheme : _light) ??
            fallbackLightColorScheme,
      ),
      darkTheme: buildAppTheme(
        (injected ? widget.injectedDarkColorScheme : _dark) ??
            fallbackDarkColorScheme,
      ),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}

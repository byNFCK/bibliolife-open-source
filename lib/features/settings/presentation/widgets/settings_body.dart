import 'package:bibliolife/features/settings/presentation/widgets/settings_tile.dart';
import 'package:bibliolife/shared/presentation/widgets/biblio_tabs.dart';
import 'package:bibliolife/features/settings/presentation/widgets/settings_segmented_control.dart';
import 'dart:developer' as developer;

import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';

import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/app/router/app_shell.dart';
import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:bibliolife/app/theme/theme_mode_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_cache_settings_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway_provider.dart';
import 'package:bibliolife/features/catalog_sources/data/remote_cache_service.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_cache_budget.dart';
import 'package:bibliolife/features/connectivity/application/app_connectivity_mode_provider.dart';
import 'package:bibliolife/features/connectivity/domain/app_connectivity_mode.dart';
import 'package:bibliolife/features/home/application/providers/home_online_tab_settings_provider.dart';
import 'package:bibliolife/features/home/application/providers/home_default_carousel_provider.dart';
import 'package:bibliolife/features/home/presentation/widgets/home_online_libraries_settings_panel.dart';
import 'package:bibliolife/features/catalog_sources/data/built_in_catalog_sources.dart';
import 'package:bibliolife/features/library/application/providers/library_section_provider.dart';
import 'package:bibliolife/features/settings/presentation/widgets/settings_section.dart';
import 'package:bibliolife/features/settings/presentation/widgets/settings_single_choice_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SettingsBody extends StatelessWidget {
  const SettingsBody({
    required this.showPageTitle,
    required this.shellContext,
    super.key,
  });

  final bool showPageTitle;
  final bool shellContext;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final shellInset = shellContext
        ? MediaQuery.viewPaddingOf(context).bottom +
              AppNavigationPresentation.surfaceHeight +
              AppNavigationPresentation.bottomMargin +
              tokens.pagePadding
        : tokens.pagePadding;
    return ListView(
      key: const PageStorageKey('profile-settings-scroll'),
      padding: EdgeInsets.fromLTRB(
        tokens.pagePadding,
        tokens.pagePadding,
        tokens.pagePadding,
        shellInset,
      ),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showPageTitle) ...[
              Text(
                AppStrings.profile,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: tokens.sectionSpacing * .75),
            ],
            SettingsSection(
              title: AppStrings.appearance,
              cardKey: const Key('settings-section-appearance'),
              children: const [ThemeSettingsTile()],
            ),
            SettingsSection(
              title: AppStrings.library,
              cardKey: const Key('settings-section-library'),
              children: const [
                BookDisplayLayoutSettingTile(),
                LibrarySettingTile(),
                DefaultHomeCarouselSettingTile(),
              ],
            ),
            SettingsSection(
              title: AppStrings.online,
              cardKey: const Key('settings-section-online'),
              children: const [
                ApplicationModeSettingTile(),
                HomeOnlineLibrariesSettingTile(),
                OnlineLibrariesSettingTile(),
              ],
            ),
            const _StorageSettingsSection(),
            SettingsSection(
              title: AppStrings.log,
              cardKey: const Key('settings-section-diagnostics'),
              children: [
                SettingsTile(
                  tileKey: const Key('logs-settings-row'),
                  icon: Icons.receipt_long_outlined,
                  title: AppStrings.log,
                  onTap: () => context.push(AppRoutes.logsPath),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class ThemeSettingsTile extends ConsumerWidget {
  const ThemeSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      SettingsSegmentedControl<ThemeMode>(
        fieldKey: const Key('theme-settings-row'),
        icon: Icons.palette_outlined,
        title: 'App theme',
        description: 'Choose your preferred appearance.',
        selected: ref.watch(themeModeProvider),
        items: const [
          BiblioTabItem(
            id: ThemeMode.system,
            label: AppStrings.system,
            key: Key('theme-option-system'),
          ),
          BiblioTabItem(
            id: ThemeMode.light,
            label: AppStrings.light,
            key: Key('theme-option-light'),
          ),
          BiblioTabItem(
            id: ThemeMode.dark,
            label: AppStrings.dark,
            key: Key('theme-option-dark'),
          ),
        ],
        onSelected: ref.read(themeModeProvider.notifier).setThemeMode,
      );
}

class BookDisplayLayoutSettingTile extends ConsumerWidget {
  const BookDisplayLayoutSettingTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      SettingsSegmentedControl<LibraryViewMode>(
        fieldKey: const Key('book-display-layout-settings-row'),
        icon: Icons.view_quilt_outlined,
        title: AppStrings.bookDisplayLayout,
        selected: ref.watch(libraryViewModeProvider),
        items: const [
          BiblioTabItem(
            id: LibraryViewMode.grid,
            label: 'Grid',
            icon: Icons.grid_view_rounded,
            key: Key('book-display-option-grid'),
          ),
          BiblioTabItem(
            id: LibraryViewMode.list,
            label: 'List',
            icon: Icons.view_list_rounded,
            key: Key('book-display-option-list'),
          ),
        ],
        onSelected: (choice) async {
          try {
            await ref.read(libraryViewModeProvider.notifier).setMode(choice);
          } catch (_) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(AppStrings.libraryPreferenceSaveError),
              ),
            );
          }
        },
      );
}

class LibrarySettingTile extends ConsumerWidget {
  const LibrarySettingTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setting = ref.watch(defaultLibrarySectionProvider);
    final selected = setting.asData?.value ?? LibrarySection.allBooks;
    return SettingsSegmentedControl<LibrarySection>(
      fieldKey: const Key('library-settings-row'),
      icon: Icons.library_books_outlined,
      title: AppStrings.defaultLibraryTab,
      selected: selected,
      items: const [
        BiblioTabItem(
          id: LibrarySection.collection,
          label: AppStrings.collection,
          key: Key('default-library-section-option-collection'),
        ),
        BiblioTabItem(
          id: LibrarySection.follow,
          label: AppStrings.follow,
          key: Key('default-library-section-option-follow'),
        ),
        BiblioTabItem(
          id: LibrarySection.allBooks,
          label: AppStrings.allBooks,
          key: Key('default-library-section-option-all-books'),
        ),
      ],
      onSelected: setting.isLoading
          ? null
          : (choice) => _setDefault(context, ref, choice),
    );
  }

  Future<void> _setDefault(
    BuildContext context,
    WidgetRef ref,
    LibrarySection choice,
  ) async {
    try {
      await ref.read(defaultLibrarySectionProvider.notifier).setDefault(choice);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.libraryPreferenceSaveError)),
      );
    }
  }
}

class DefaultHomeCarouselSettingTile extends ConsumerWidget {
  const DefaultHomeCarouselSettingTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setting = ref.watch(defaultHomeCarouselProvider);
    final selected =
        setting.asData?.value ?? HomeDefaultCarousel.recentlyOpened;
    return SettingsSegmentedControl<HomeDefaultCarousel>(
      fieldKey: const Key('default-home-carousel-settings-row'),
      icon: Icons.home_outlined,
      title: AppStrings.defaultHomeCarousel,
      selected: selected,
      items: const [
        BiblioTabItem(
          id: HomeDefaultCarousel.recentlyOpened,
          label: AppStrings.recentlyOpened,
          key: Key('default-home-carousel-option-recently-opened'),
        ),
        BiblioTabItem(
          id: HomeDefaultCarousel.favorites,
          label: AppStrings.favorites,
          key: Key('default-home-carousel-option-favorites'),
        ),
      ],
      onSelected: setting.isLoading
          ? null
          : (choice) => _setDefault(context, ref, choice),
    );
  }

  Future<void> _setDefault(
    BuildContext context,
    WidgetRef ref,
    HomeDefaultCarousel choice,
  ) async {
    try {
      await ref.read(defaultHomeCarouselProvider.notifier).setDefault(choice);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(AppStrings.homeCarouselPreferenceSaveError),
        ),
      );
    }
  }
}

class ApplicationModeSettingTile extends ConsumerStatefulWidget {
  const ApplicationModeSettingTile({super.key});

  @override
  ConsumerState<ApplicationModeSettingTile> createState() =>
      _ApplicationModeSettingTileState();
}

class _ApplicationModeSettingTileState
    extends ConsumerState<ApplicationModeSettingTile> {
  bool _changing = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appConnectivityModeProvider);
    final online = state.mode == AppConnectivityMode.online;
    final enabled = state.isLoaded && !state.isPersisting && !_changing;
    assert(() {
      developer.log(
        'mode=${state.mode.name} loading=${!state.isLoaded} enabled=$enabled',
        name: 'APP_CONNECTIVITY_SETTINGS_CONTROL_BUILT',
      );
      return true;
    }());
    return SettingsSegmentedControl<AppConnectivityMode>(
      fieldKey: const Key('application-mode-settings-row'),
      icon: online ? Icons.public_outlined : Icons.cloud_off_outlined,
      title: AppStrings.applicationMode,
      selected: state.mode,
      items: const [
        BiblioTabItem(
          id: AppConnectivityMode.offline,
          label: AppStrings.offline,
          key: Key('application-mode-option-offline'),
        ),
        BiblioTabItem(
          id: AppConnectivityMode.online,
          label: AppStrings.online,
          key: Key('application-mode-option-online'),
        ),
      ],
      onSelected: !enabled
          ? null
          : (choice) {
              if (choice != state.mode) _requestModeChange(choice);
            },
    );
  }

  Future<void> _requestModeChange(AppConnectivityMode mode) async {
    if (_changing) return;
    setState(() => _changing = true);
    try {
      final current = ref.read(appConnectivityModeProvider);
      if (mode == AppConnectivityMode.online &&
          !current.hasAcknowledgedOnline) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text(AppStrings.enableOnlineTitle),
            content: const Text(AppStrings.enableOnlineBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(AppStrings.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(AppStrings.enableOnline),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }
      await ref.read(appConnectivityModeProvider.notifier).setMode(mode);
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }
}

class HomeOnlineLibrariesSettingTile extends ConsumerWidget {
  const HomeOnlineLibrariesSettingTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibility =
        ref.watch(homeOnlineTabVisibilityProvider).asData?.value ??
        const <String, bool>{};
    final enabled = builtInCatalogSources
        .where((source) => visibility[source.id] ?? true)
        .length;
    return SettingsTile(
      tileKey: const Key('home-online-libraries-settings-row'),
      icon: Icons.home_outlined,
      title: AppStrings.homeOnlineLibraries,
      value: '$enabled of ${builtInCatalogSources.length} enabled',
      onTap: () => showSettingsModalSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const HomeOnlineLibrariesSelectionSheet(),
      ),
    );
  }
}

class OnlineLibrariesSettingTile extends StatelessWidget {
  const OnlineLibrariesSettingTile({super.key});

  @override
  Widget build(BuildContext context) => SettingsTile(
    tileKey: const Key('online-libraries-settings-row'),
    icon: Icons.public_outlined,
    title: AppStrings.onlineLibraries,
    onTap: () => context.pushNamed(AppRoutes.onlineLibrariesName),
  );
}

// UI-only refresh coordination; clearing still uses the existing confirmation/API.
class _StorageSettingsSection extends StatefulWidget {
  const _StorageSettingsSection();
  @override
  State<_StorageSettingsSection> createState() =>
      _StorageSettingsSectionState();
}

class _StorageSettingsSectionState extends State<_StorageSettingsSection> {
  final _cache = GlobalKey<_OnlineCacheSettingTileState>();
  @override
  Widget build(BuildContext context) => SettingsSection(
    title: AppStrings.storage,
    cardKey: const Key('settings-section-storage'),
    children: [
      OnlineCacheSettingTile(key: _cache),
      ClearOnlineCacheSettingTile(
        onCleared: () => _cache.currentState?._refreshUsage(),
      ),
    ],
  );
}

class OnlineCacheSettingTile extends ConsumerStatefulWidget {
  const OnlineCacheSettingTile({super.key});
  @override
  ConsumerState<OnlineCacheSettingTile> createState() =>
      _OnlineCacheSettingTileState();
  static String _cacheLabel(RemoteCacheBudget budget) =>
      switch (budget.maximumBytes) {
        remoteCacheMinimumMaximumBytes => AppStrings.cacheMinimum,
        remoteCacheMaximumMaximumBytes => AppStrings.cacheMaximum,
        _ => AppStrings.cacheDefault,
      };
}

class _OnlineCacheSettingTileState
    extends ConsumerState<OnlineCacheSettingTile> {
  late Future<RemoteCacheSnapshot> _snapshot;
  bool _changing = false;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _snapshot = ref.read(remoteCacheServiceProvider).snapshot();
  }

  void _refreshUsage() {
    if (mounted) {
      setState(
        () => _snapshot = ref.read(remoteCacheServiceProvider).snapshot(),
      );
    }
  }

  Future<void> _setBudget(int bytes) async {
    if (_changing) return;
    setState(() {
      _changing = true;
      _error = null;
    });
    try {
      await _saveCacheBudget(ref, RemoteCacheBudget.fromStored(bytes));
      if (mounted) {
        setState(() {
          _snapshot = ref.read(remoteCacheServiceProvider).snapshot();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final budget =
        ref.watch(remoteCacheBudgetProvider).asData?.value ??
        const RemoteCacheBudget.defaultValue();
    return FutureBuilder<RemoteCacheSnapshot>(
      future: _snapshot,
      builder: (context, snapshot) {
        final bytes = snapshot.data?.bytes;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsSegmentedControl<int>(
              fieldKey: const Key('online-cache-settings-row'),
              title: 'Online cache limit',
              icon: Icons.storage_outlined,
              description: bytes == null
                  ? AppStrings.cacheCalculatingSize
                  : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB used',
              selected: budget.maximumBytes,
              items: const [
                BiblioTabItem(
                  id: remoteCacheMinimumMaximumBytes,
                  label: AppStrings.cacheMinimum,
                  key: Key('online-cache-limit-512'),
                ),
                BiblioTabItem(
                  id: remoteCacheDefaultMaximumBytes,
                  label: AppStrings.cacheDefault,
                  key: Key('online-cache-limit-1280'),
                ),
                BiblioTabItem(
                  id: remoteCacheMaximumMaximumBytes,
                  label: AppStrings.cacheMaximum,
                  key: Key('online-cache-limit-2048'),
                ),
              ],
              onSelected:
                  _changing ||
                      snapshot.connectionState == ConnectionState.waiting
                  ? null
                  : _setBudget,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  AppStrings.cacheUpdateError,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        );
      },
    );
  }
}

// The same ordered persistence/service path used by the existing cache sheet.
Future<void> _saveCacheBudget(WidgetRef ref, RemoteCacheBudget budget) async {
  await ref.read(remoteCacheSettingsRepositoryProvider).save(budget);
  await ref.read(remoteCacheServiceProvider).updateBudget(budget);
}

class ClearOnlineCacheSettingTile extends ConsumerWidget {
  const ClearOnlineCacheSettingTile({this.onCleared, super.key});
  final VoidCallback? onCleared;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SettingsTile(
    tileKey: const Key('online-cache-clear'),
    icon: Icons.delete_sweep_outlined,
    title: AppStrings.clearOnlineCache,
    destructive: true,
    showChevron: false,
    onTap: () => _clear(context, ref),
  );

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('online-cache-clear-confirmation'),
        title: const Text(AppStrings.cacheClearTitle),
        content: const Text(AppStrings.cacheClearBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(AppStrings.clear),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(remoteCacheServiceProvider).clear();
      if (context.mounted) onCleared?.call();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStrings.cacheClearError)));
    }
  }
}

class RemoteCacheSettingsSheet extends ConsumerStatefulWidget {
  const RemoteCacheSettingsSheet({super.key});

  @override
  ConsumerState<RemoteCacheSettingsSheet> createState() =>
      _RemoteCacheSettingsSheetState();
}

class _RemoteCacheSettingsSheetState
    extends ConsumerState<RemoteCacheSettingsSheet> {
  late Future<RemoteCacheSnapshot> _snapshot;
  bool _changing = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _snapshot = ref.read(remoteCacheServiceProvider).snapshot();
  }

  Future<void> _setBudget(RemoteCacheBudget budget) async {
    if (_changing) return;
    setState(() {
      _changing = true;
      _error = null;
    });
    try {
      await _saveCacheBudget(ref, budget);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected =
        ref.watch(remoteCacheBudgetProvider).asData?.value ??
        const RemoteCacheBudget.defaultValue();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FutureBuilder<RemoteCacheSnapshot>(
          future: _snapshot,
          builder: (context, snapshot) {
            final value = snapshot.data;
            final megabytes = value == null
                ? null
                : value.bytes / (1024 * 1024);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    AppStrings.onlineCache,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    megabytes == null
                        ? AppStrings.cacheCalculatingSize
                        : '${megabytes.toStringAsFixed(1)} MB of ${OnlineCacheSettingTile._cacheLabel(selected)}',
                    key: const Key('online-cache-current-size'),
                  ),
                ),
                const SizedBox(height: 8),
                Semantics(
                  container: true,
                  label: 'Online cache size limit',
                  child: RadioGroup<int>(
                    groupValue: selected.maximumBytes,
                    onChanged: (value) {
                      if (_changing ||
                          snapshot.connectionState == ConnectionState.waiting ||
                          value == null) {
                        return;
                      }
                      _setBudget(RemoteCacheBudget.fromStored(value));
                    },
                    child: Column(
                      key: const Key('online-cache-limit-selector'),
                      children: [
                        _limitTile(
                          AppStrings.cacheMinimum,
                          remoteCacheMinimumMaximumBytes,
                          'online-cache-limit-512',
                        ),
                        _limitTile(
                          AppStrings.cacheDefault,
                          remoteCacheDefaultMaximumBytes,
                          'online-cache-limit-1280',
                        ),
                        _limitTile(
                          AppStrings.cacheMaximum,
                          remoteCacheMaximumMaximumBytes,
                          'online-cache-limit-2048',
                        ),
                      ],
                    ),
                  ),
                ),
                if (_changing) ...[
                  const SizedBox(height: 4),
                  const LinearProgressIndicator(),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    AppStrings.cacheUpdateError,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _limitTile(String label, int value, String key) => RadioListTile<int>(
    key: Key(key),
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: Text(label),
    value: value,
  );
}

// Compatibility wrappers for focused tests and callers that previously used
// these panels directly. The canonical Profile and /settings composition uses
// SettingsBody and the compact rows above.
class LibrarySettingsPanel extends StatelessWidget {
  const LibrarySettingsPanel({super.key});

  @override
  Widget build(BuildContext context) => const KeyedSubtree(
    key: Key('library-settings-section'),
    child: LibrarySettingTile(),
  );
}

class AppearanceSettingsPanel extends StatelessWidget {
  const AppearanceSettingsPanel({this.includeConnectivity = false, super.key});

  final bool includeConnectivity;

  @override
  Widget build(BuildContext context) => const ThemeSettingsTile();
}

class ApplicationModeSettingsPanel extends StatelessWidget {
  const ApplicationModeSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) => const ApplicationModeSettingTile();
}

class RemoteCacheSettingsPanel extends StatelessWidget {
  const RemoteCacheSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) => SettingsSection(
    title: AppStrings.storage,
    children: const [OnlineCacheSettingTile(), ClearOnlineCacheSettingTile()],
  );
}

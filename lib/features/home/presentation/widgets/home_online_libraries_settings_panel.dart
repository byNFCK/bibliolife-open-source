import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/data/built_in_catalog_sources.dart';
import 'package:bibliolife/features/home/application/providers/home_online_tab_settings_provider.dart';
import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared by the settings hub and its selection sheet so every entry point
/// reads and writes the exact same persisted Home preference.
class HomeOnlineLibrariesSettingsPanel extends ConsumerWidget {
  const HomeOnlineLibrariesSettingsPanel({this.showCard = true, super.key});

  final bool showCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configured =
        ref.watch(catalogSourcesProvider).asData?.value ?? const [];
    final configuredById = {for (final source in configured) source.id: source};
    final visibility =
        ref.watch(homeOnlineTabVisibilityProvider).asData?.value ??
        const <String, bool>{};
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(AppStrings.homeOnlineLibraries),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(AppStrings.homeOnlineLibrariesDescription),
          ),
          for (final registered in builtInCatalogSources)
            Builder(
              builder: (context) {
                final source = configuredById[registered.id] ?? registered;
                final visible = visibility[source.id] ?? true;
                return Semantics(
                  container: true,
                  label: 'Show ${source.name} on Home',
                  child: SwitchListTile(
                    key: Key('home-online-library-toggle-${source.id}'),
                    title: Text(source.name),
                    subtitle: Text(
                      _description(source.name, source.supportsSearch),
                    ),
                    value: visible,
                    onChanged: (value) => ref
                        .read(homeOnlineTabSettingsRepositoryProvider)
                        .setVisible(sourceId: source.id, visible: value),
                    secondary: const Icon(Icons.home_outlined),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                );
              },
            ),
        ],
      ),
    );
    if (!showCard) return content;
    return Card(
      key: const Key('home-online-libraries-section'),
      child: content,
    );
  }

  String _description(String name, bool supportsSearch) {
    if (name == 'Standard Ebooks') {
      return AppStrings.homeStandardEbooksDescription;
    }
    if (name == 'Internet Archive') {
      return AppStrings.homeInternetArchiveDescription;
    }
    return supportsSearch
        ? AppStrings.homeSearchIndependentDescription
        : AppStrings.homeProviderIndependentDescription;
  }
}

class HomeOnlineLibrariesSelectionSheet extends StatelessWidget {
  const HomeOnlineLibrariesSelectionSheet({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16),
      child: const HomeOnlineLibrariesSettingsPanel(showCard: false),
    ),
  );
}

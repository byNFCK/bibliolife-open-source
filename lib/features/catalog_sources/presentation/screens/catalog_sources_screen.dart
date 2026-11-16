import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_controller.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/connectivity/application/app_connectivity_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CatalogSourcesScreen extends ConsumerWidget {
  const CatalogSourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(catalogSourcesProvider);
    final offline = !ref.watch(onlineAccessAllowedProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Online libraries')),
      floatingActionButton: Semantics(
        label: 'Add source',
        button: true,
        child: FloatingActionButton.extended(
          onPressed: () => context.pushNamed(AppRoutes.addOnlineLibraryName),
          icon: const Icon(Icons.add),
          label: const Text('Add library'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (offline) const _OfflineNotice(),
          const SizedBox(height: 12),
          const _SectionTitle('Built-in libraries'),
          ...sources.when(
            data: (items) => items
                .where((source) => source.isBuiltIn)
                .map((source) => _SourceCard(source: source)),
            loading: () => const [LinearProgressIndicator()],
            error: (_, _) => const [Text('Unable to load libraries')],
          ),
          const SizedBox(height: 16),
          const _SectionTitle('Custom libraries'),
          ...sources.maybeWhen(
            data: (items) {
              final custom = items
                  .where((source) => !source.isBuiltIn)
                  .toList();
              return custom.isEmpty
                  ? const [
                      Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('No custom libraries yet.'),
                      ),
                    ]
                  : custom
                        .map((source) => _SourceCard(source: source))
                        .toList();
            },
            orElse: () => const [],
          ),
          const SizedBox(height: 88),
        ],
      ),
    );
  }
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice();

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    child: Semantics(
      label: 'Offline mode is enabled. Libraries can be managed locally.',
      child: ListTile(
        leading: Icon(Icons.cloud_off_outlined),
        title: Text('Offline mode is enabled'),
        subtitle: Text(
          'Libraries can be managed, but catalogs cannot be opened or refreshed.',
        ),
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _SourceCard extends ConsumerWidget {
  const _SourceCard({required this.source});
  final CatalogSource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mutation = ref.watch(catalogSourcesControllerProvider);
    final busy = mutation.kind != CatalogSourceMutationKind.idle;
    return Card(
      child: ListTile(
        title: Text(source.name),
        subtitle: Text(
          _description(source),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        leading: Icon(source.isBuiltIn ? Icons.public : Icons.link),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              label: 'Browse ${source.name}',
              button: true,
              enabled: source.isEnabled && source.supportsNavigation,
              child: IconButton(
                tooltip: 'Browse ${source.name}',
                onPressed: source.isEnabled && source.supportsNavigation
                    ? () => context.pushNamed(
                        AppRoutes.browseOnlineLibraryName,
                        pathParameters: {'sourceId': source.id},
                      )
                    : null,
                icon: const Icon(Icons.menu_book_outlined),
              ),
            ),
            if (source.supportsSearch)
              Semantics(
                label: 'Use ${source.name} in Search',
                toggled: source.isEnabled,
                enabled: !busy,
                onTap: busy
                    ? null
                    : () => _setEnabled(context, ref, !source.isEnabled),
                child: ExcludeSemantics(
                  child: Switch(
                    key: Key('online-library-search-toggle-${source.id}'),
                    value: source.isEnabled,
                    onChanged: busy
                        ? null
                        : (enabled) => _setEnabled(context, ref, enabled),
                  ),
                ),
              )
            else if (source.type == CatalogSourceType.internetArchive)
              Semantics(
                label: 'Enable ${source.name} acquisition provider',
                toggled: source.isEnabled,
                enabled: !busy,
                child: ExcludeSemantics(
                  child: Switch(
                    key: Key('online-library-acquisition-toggle-${source.id}'),
                    value: source.isEnabled,
                    onChanged: busy
                        ? null
                        : (enabled) => _setEnabled(context, ref, enabled),
                  ),
                ),
              )
            else if (source.type == CatalogSourceType.standardEbooks)
              const Tooltip(
                message: 'Standard Ebooks is not available in global Search.',
                child: Icon(Icons.search_off_outlined),
              ),
            if (!source.isBuiltIn)
              PopupMenuButton<_CustomAction>(
                enabled: !busy,
                onSelected: (action) => _selectAction(context, ref, action),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _CustomAction.edit,
                    child: Semantics(
                      label: 'Edit ${source.name}',
                      button: true,
                      child: const Text('Edit'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _CustomAction.delete,
                    child: Semantics(
                      label: 'Delete ${source.name}',
                      button: true,
                      child: const Text('Delete'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _setEnabled(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    final changed = await ref
        .read(catalogSourcesControllerProvider.notifier)
        .setEnabled(source.id, enabled);
    if (!changed && context.mounted) _showFailure(context, ref);
  }

  Future<void> _selectAction(
    BuildContext context,
    WidgetRef ref,
    _CustomAction action,
  ) async {
    if (action == _CustomAction.edit) {
      context.pushNamed(
        AppRoutes.editOnlineLibraryName,
        pathParameters: {'sourceId': source.id},
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => _DeleteCatalogSourceDialog(source: source),
    );
  }

  void _showFailure(BuildContext context, WidgetRef ref) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('The library could not be updated. Try again.'),
      ),
    );
    ref.read(catalogSourcesControllerProvider.notifier).clearError();
  }
}

String _description(CatalogSource source) =>
    catalogSourceFreeDownloadDescription(source);

class _DeleteCatalogSourceDialog extends ConsumerStatefulWidget {
  const _DeleteCatalogSourceDialog({required this.source});

  final CatalogSource source;

  @override
  ConsumerState<_DeleteCatalogSourceDialog> createState() =>
      _DeleteCatalogSourceDialogState();
}

class _DeleteCatalogSourceDialogState
    extends ConsumerState<_DeleteCatalogSourceDialog> {
  bool _pending = false;
  bool _failed = false;

  Future<void> _remove() async {
    if (_pending) return;
    setState(() {
      _pending = true;
      _failed = false;
    });
    final deleted = await ref
        .read(catalogSourcesControllerProvider.notifier)
        .delete(widget.source.id);
    if (!mounted) return;
    if (deleted) {
      Navigator.of(context).pop();
      return;
    }
    ref.read(catalogSourcesControllerProvider.notifier).clearError();
    setState(() {
      _pending = false;
      _failed = true;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Semantics(
      label: AppStrings.removeLibrarySourceTitle,
      header: true,
      child: const ExcludeSemantics(
        child: Text(AppStrings.removeLibrarySourceTitle),
      ),
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(AppStrings.removeLibrarySourceBody),
        if (_failed) ...[
          const SizedBox(height: 12),
          Text(
            'The library could not be removed. Try again or Cancel.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: _pending ? null : () => Navigator.of(context).pop(),
        child: const Text(AppStrings.cancel),
      ),
      Semantics(
        label: '${AppStrings.remove} ${widget.source.name}',
        button: true,
        child: FilledButton(
          onPressed: _pending ? null : _remove,
          child: const Text(AppStrings.remove),
        ),
      ),
    ],
  );
}

enum _CustomAction { edit, delete }

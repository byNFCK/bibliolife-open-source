import 'package:bibliolife/features/catalog_sources/application/catalog_sources_controller.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_sources_provider.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source.dart';
import 'package:bibliolife/features/catalog_sources/domain/catalog_source_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CatalogSourceFormScreen extends ConsumerStatefulWidget {
  const CatalogSourceFormScreen({this.sourceId, super.key});
  final String? sourceId;

  @override
  ConsumerState<CatalogSourceFormScreen> createState() =>
      _CatalogSourceFormScreenState();
}

class _CatalogSourceFormScreenState
    extends ConsumerState<CatalogSourceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  bool _initialized = false;

  bool get _isEditing => widget.sourceId != null;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sourceAsync = ref
        .watch(catalogSourcesProvider)
        .whenData((items) => _isEditing ? _findSource(items) : null);
    sourceAsync.whenData((source) {
      if (!_initialized && source != null) {
        _initialized = true;
        _nameController.text = source.name;
        _urlController.text = source.baseUri.toString();
      }
    });
    final mutation = ref.watch(catalogSourcesControllerProvider);
    final source = sourceAsync.when(
      data: (value) => value,
      loading: () => null,
      error: (_, _) => null,
    );
    final missing = _isEditing && sourceAsync.hasValue && source == null;
    final builtIn = source?.isBuiltIn ?? false;
    final busy =
        mutation.kind == CatalogSourceMutationKind.adding ||
        mutation.kind == CatalogSourceMutationKind.updating;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit library' : 'Add library')),
      body: SafeArea(
        child: missing
            ? const Center(child: Text('Library not found'))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (builtIn)
                    const Text('Built-in libraries cannot be edited.'),
                  if (!builtIn) ...[
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _nameController,
                            enabled: !busy,
                            decoration: const InputDecoration(
                              labelText: 'Name',
                            ),
                            textInputAction: TextInputAction.next,
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Enter a library name'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _urlController,
                            enabled: !busy,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                              labelText: 'Catalog URL',
                              hintText: 'https://example.org/opds',
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Enter a catalog URL'
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: busy ? null : _submit,
                            child: Text(_isEditing ? 'Save' : 'Add library'),
                          ),
                        ),
                      ],
                    ),
                    if (mutation.failure != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _failureMessage(mutation.failure!),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final controller = ref.read(catalogSourcesControllerProvider.notifier);
    final saved = _isEditing
        ? await controller.update(
            widget.sourceId!,
            _nameController.text,
            _urlController.text,
          )
        : await controller.add(_nameController.text, _urlController.text);
    if (saved && mounted) Navigator.of(context).pop();
  }

  CatalogSource? _findSource(List<CatalogSource> sources) {
    for (final source in sources) {
      if (source.id == widget.sourceId) return source;
    }
    return null;
  }

  String _failureMessage(CatalogSourceFailure failure) => switch (failure) {
    CatalogSourceFailure.emptyName => 'Enter a library name.',
    CatalogSourceFailure.emptyUrl => 'Enter a catalog URL.',
    CatalogSourceFailure.insecureHttp => 'Use an HTTPS URL.',
    CatalogSourceFailure.unsupportedScheme =>
      'Only HTTPS catalog URLs are supported.',
    CatalogSourceFailure.missingHost ||
    CatalogSourceFailure.malformedUrl => 'Enter a valid catalog URL.',
    CatalogSourceFailure.duplicateUrl => 'This catalog URL is already added.',
    _ => 'The library could not be saved. Try again.',
  };
}

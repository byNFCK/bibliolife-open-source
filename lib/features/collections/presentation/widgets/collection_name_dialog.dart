import 'package:bibliolife/features/collections/domain/repositories/collection_repository.dart';
import 'package:bibliolife/features/collections/application/providers/collection_repository_provider.dart';
import 'package:bibliolife/features/collections/domain/models/library_collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CollectionNameDialog extends StatefulWidget {
  const CollectionNameDialog({
    required this.title,
    required this.initialName,
    required this.onSubmit,
    super.key,
  });

  final String title;
  final String? initialName;
  final Future<void> Function(String name) onSubmit;

  @override
  State<CollectionNameDialog> createState() => _CollectionNameDialogState();
}

class _CollectionNameDialogState extends State<CollectionNameDialog> {
  late final TextEditingController _controller;
  var _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_controller.text.trim().isEmpty) {
      setState(() => _error = 'Enter a collection name.');
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(_controller.text);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on InvalidCollectionName {
      if (mounted) {
        setState(() {
          _error = 'Enter a collection name.';
          _submitting = false;
        });
      }
    } on DuplicateCollectionName {
      if (mounted) {
        setState(() {
          _error = 'A collection with this name already exists.';
          _submitting = false;
        });
      }
    } on CollectionRepositoryFailure {
      if (mounted) {
        setState(() {
          _error = 'Could not save collection.';
          _submitting = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not save collection.';
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: InputDecoration(labelText: 'Name', errorText: _error),
    ),
    actions: [
      TextButton(
        onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _submitting ? null : _submit,
        child: const Text('Save'),
      ),
    ],
  );
}

Future<LibraryCollection?> showCollectionNameDialog(
  BuildContext context,
  WidgetRef ref, {
  LibraryCollection? collection,
}) async {
  LibraryCollection? created;
  await showDialog<void>(
    context: context,
    builder: (_) => CollectionNameDialog(
      title: collection == null ? 'Create collection' : 'Rename collection',
      initialName: collection?.name,
      onSubmit: (name) async {
        final repository = ref.read(collectionRepositoryProvider);
        if (collection == null) {
          created = await repository.create(name);
        } else {
          await repository.rename(collection.id, name);
        }
      },
    ),
  );
  return created;
}

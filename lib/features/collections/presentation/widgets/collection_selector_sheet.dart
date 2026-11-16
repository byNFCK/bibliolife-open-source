import 'package:bibliolife/features/collections/presentation/system_collection_colors.dart';
import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/features/collections/application/providers/collection_providers.dart';
import 'package:bibliolife/features/collections/application/providers/collection_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CollectionSelectorSheet extends ConsumerStatefulWidget {
  const CollectionSelectorSheet({required this.bookId, super.key});

  final String bookId;

  @override
  ConsumerState<CollectionSelectorSheet> createState() =>
      _CollectionSelectorSheetState();
}

class _CollectionSelectorSheetState
    extends ConsumerState<CollectionSelectorSheet> {
  final _pendingCollectionIds = <String>{};

  Future<void> _toggle({
    required String collectionId,
    required bool isMember,
  }) async {
    if (_pendingCollectionIds.contains(collectionId)) return;
    setState(() => _pendingCollectionIds.add(collectionId));
    try {
      final repository = ref.read(collectionRepositoryProvider);
      if (isMember) {
        await repository.removeBook(collectionId, widget.bookId);
      } else {
        await repository.addBook(collectionId, widget.bookId);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update collection.')),
        );
      }
    } finally {
      if (mounted) setState(() => _pendingCollectionIds.remove(collectionId));
    }
  }

  Future<void> _createCollection() async {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    await router.pushNamed(
      AppRoutes.createCollectionName,
      extra: <String>{widget.bookId},
    );
  }

  @override
  Widget build(BuildContext context) {
    final collections = ref.watch(allCollectionsProvider);
    final memberships = ref.watch(collectionsForBookProvider(widget.bookId));
    final memberIds = memberships.asData?.value.map((item) => item.id).toSet();
    return collections.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(child: Text('Could not load collections.')),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('No collections yet.'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('create-collection-from-selector'),
                  onPressed: _createCollection,
                  icon: const Icon(Icons.add),
                  label: const Text('New collection'),
                ),
              ],
            ),
          );
        }
        if (memberIds == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView.builder(
          key: const Key('collection-selector-list'),
          itemCount: items.length + 1,
          itemBuilder: (context, index) {
            if (index == items.length) {
              return Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: OutlinedButton.icon(
                  key: const Key('create-collection-from-selector'),
                  onPressed: _createCollection,
                  icon: const Icon(Icons.add),
                  label: const Text('New collection'),
                ),
              );
            }
            final collection = items[index];
            final isMember = memberIds.contains(collection.id);
            final pending = _pendingCollectionIds.contains(collection.id);
            final scheme = systemCollectionColorScheme(
              collection.id,
              Theme.of(context).brightness,
            );
            return Semantics(
              label:
                  '${collection.name}, ${isMember ? 'selected' : 'not selected'}',
              child: CheckboxListTile(
                key: ValueKey('collection-membership-${collection.id}'),
                value: isMember,
                activeColor: scheme?.primary,
                checkColor: scheme?.onPrimary,
                onChanged: pending
                    ? null
                    : (_) => _toggle(
                        collectionId: collection.id,
                        isMember: isMember,
                      ),
                title: Text(
                  collection.name,
                  style: scheme == null
                      ? null
                      : TextStyle(color: scheme.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            );
          },
        );
      },
    );
  }
}

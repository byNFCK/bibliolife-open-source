import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/app/theme/app_spacing.dart';
import 'package:bibliolife/features/collections/application/providers/collection_providers.dart';
import 'package:bibliolife/features/collections/presentation/widgets/collection_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Reusable collection summary content for standalone and embedded surfaces.
class CollectionsBody extends ConsumerStatefulWidget {
  const CollectionsBody({
    this.scrollKey,
    this.overlapHandle,
    this.padding = const EdgeInsets.symmetric(vertical: 12),
    super.key,
  });

  final Key? scrollKey;
  final SliverOverlapAbsorberHandle? overlapHandle;
  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<CollectionsBody> createState() => _CollectionsBodyState();
}

class _CollectionsBodyState extends ConsumerState<CollectionsBody>
    with AutomaticKeepAliveClientMixin<CollectionsBody> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final collections = ref.watch(collectionSummariesProvider);
    return CustomScrollView(
      key: widget.scrollKey ?? const PageStorageKey('collections-body'),
      semanticChildCount: collections.asData?.value.length,
      slivers: [
        if (widget.overlapHandle case final handle?)
          SliverOverlapInjector(handle: handle),
        collections.when(
          loading: () => const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('Could not load collections.')),
          ),
          data: (items) => items.isEmpty
              ? const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('No collections yet.')),
                )
              : SliverPadding(
                  padding: widget.padding,
                  sliver: SliverList.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: CollectionCard(
                          key: ValueKey(item.collection.id),
                          summary: item,
                          onTap: () => context.pushNamed(
                            AppRoutes.collectionDetailsName,
                            pathParameters: {
                              'collectionId': item.collection.id,
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

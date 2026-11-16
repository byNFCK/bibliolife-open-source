import 'dart:developer' as developer;

import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_modal_card.dart';
import 'package:bibliolife/features/reader/application/controllers/reader_annotation_mutation_controller.dart';
import 'package:bibliolife/features/reader/application/providers/reader_annotation_providers.dart';
import 'package:bibliolife/features/reader/domain/models/reader_annotation.dart';
import 'package:bibliolife/features/reader/domain/models/reader_launch_request.dart';
import 'package:bibliolife/features/reader/presentation/models/annotation_location_label.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Mirrors ReaderAnnotationsBottomSheet.kt native dp values.
abstract final class BookAnnotationsSheetMetrics {
  static const horizontalInset = 20.0;
  static const handleWidth = 36.0;
  static const handleHeight = 4.0;
  static const handleTop = 12.0;
  static const titleSpacing = 12.0;
  static const colorDiameter = 28.0;
  static const cancelWidth = 160.0;
}

class BookAnnotationsScreen extends ConsumerStatefulWidget {
  const BookAnnotationsScreen({
    required this.bookId,
    this.returnToReader = false,
    super.key,
  });

  final String bookId;
  final bool returnToReader;

  @override
  ConsumerState<BookAnnotationsScreen> createState() =>
      _BookAnnotationsScreenState();
}

class BookAnnotationsBottomSheet extends BookAnnotationsScreen {
  const BookAnnotationsBottomSheet({required super.bookId, super.key});
}

class _BookAnnotationsScreenState extends ConsumerState<BookAnnotationsScreen> {
  final _pendingDeleteIds = <String>{};

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      developer.log(
        'ANNOTATIONS_LIST_OPENED bookId=${widget.bookId}',
        name: 'BiblioLife',
      );
    }
  }

  Future<void> _delete(ReaderAnnotation annotation) async {
    if (annotation.bookId != widget.bookId ||
        !_pendingDeleteIds.add(annotation.id)) {
      return;
    }
    setState(() {});
    if (kDebugMode) {
      developer.log(
        'ANNOTATIONS_LIST_ITEM_DELETE_REQUESTED id=${annotation.id}',
        name: 'BiblioLife',
      );
    }
    try {
      await ref
          .read(readerAnnotationMutationControllerProvider.notifier)
          .deleteById(annotation.id);
      if (kDebugMode) {
        developer.log(
          'ANNOTATIONS_LIST_ITEM_DELETE_SUCCESS id=${annotation.id}',
          name: 'BiblioLife',
        );
      }
    } catch (error) {
      if (kDebugMode) {
        developer.log(
          'ANNOTATIONS_LIST_ITEM_DELETE_FAILED '
          'id=${annotation.id} type=${error.runtimeType}',
          name: 'BiblioLife',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete this highlight. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _pendingDeleteIds.remove(annotation.id));
      } else {
        _pendingDeleteIds.remove(annotation.id);
      }
    }
  }

  Future<void> _open(ReaderAnnotation annotation) async {
    if (annotation.bookId != widget.bookId) return;
    if (kDebugMode) {
      developer.log(
        'ANNOTATIONS_LIST_ITEM_OPEN_REQUESTED id=${annotation.id}',
        name: 'BiblioLife',
      );
    }
    final request = ReaderLaunchRequest(
      bookId: widget.bookId,
      initialLocatorJson: annotation.locatorJson,
    );
    if (!request.hasValidExplicitLocator) {
      if (kDebugMode) {
        developer.log(
          'ANNOTATIONS_LIST_LOCATOR_OPEN_FAILED '
          'id=${annotation.id} type=malformed_locator',
          name: 'BiblioLife',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open this highlight location.'),
          ),
        );
      }
      return;
    }
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    await router.pushNamed(
      AppRoutes.readerName,
      pathParameters: {'bookId': widget.bookId},
      extra: request,
    );
  }

  @override
  Widget build(BuildContext context) {
    final annotations = ref.watch(
      sortedReaderAnnotationsForBookProvider(widget.bookId),
    );
    ref.listen(sortedReaderAnnotationsForBookProvider(widget.bookId), (
      previous,
      next,
    ) {
      final count = next.asData?.value.length;
      if (kDebugMode && count != null) {
        developer.log(
          'ANNOTATIONS_LIST_EMISSION '
          'bookId=${widget.bookId} count=$count',
          name: 'BiblioLife',
        );
      }
    });
    return annotations.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => BookAnnotationsErrorState(
        onRetry: () =>
            ref.invalidate(readerAnnotationsForBookProvider(widget.bookId)),
      ),
      data: (items) => items.isEmpty
          ? const BookAnnotationsEmptyState()
          : BookAnnotationsList(
              items: items,
              pendingDeleteIds: _pendingDeleteIds,
              onOpen: _open,
              onDelete: _delete,
            ),
    );
  }
}

class BookAnnotationsList extends StatelessWidget {
  const BookAnnotationsList({
    required this.items,
    required this.pendingDeleteIds,
    required this.onOpen,
    required this.onDelete,
    super.key,
  });

  final List<ReaderAnnotation> items;
  final Set<String> pendingDeleteIds;
  final ValueChanged<ReaderAnnotation> onOpen;
  final ValueChanged<ReaderAnnotation> onDelete;

  @override
  Widget build(BuildContext context) => ListView.separated(
    key: const PageStorageKey('book-annotations-list'),
    padding: const EdgeInsets.symmetric(
      vertical: BookDetailsModalCardMetrics.listVerticalPadding,
    ),
    shrinkWrap: true,
    itemCount: items.length,
    separatorBuilder: (_, _) =>
        const SizedBox(height: BookDetailsModalCardMetrics.cardGap),
    itemBuilder: (context, index) {
      final annotation = items[index];
      return BookAnnotationListTile(
        annotation: annotation,
        locationLabel: AnnotationLocationLabel.fromLocatorJson(
          annotation.locatorJson,
        )?.text,
        deleting: pendingDeleteIds.contains(annotation.id),
        onOpen: () => onOpen(annotation),
        onDelete: () => onDelete(annotation),
      );
    },
  );
}

class BookAnnotationListTile extends StatelessWidget {
  const BookAnnotationListTile({
    required this.annotation,
    required this.locationLabel,
    required this.deleting,
    required this.onOpen,
    required this.onDelete,
    super.key,
  });

  final ReaderAnnotation annotation;
  final String? locationLabel;
  final bool deleting;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final excerpt = annotation.selectedText
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    /*
    return ListTile(
      onTap: onOpen,
      leading: AnnotationColorIndicator(color: annotation.color),
      title: Text(
        excerpt.isEmpty ? 'Highlighted passage' : excerpt,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          ?locationLabel,
          formatAnnotationDate(context, annotation.createdAt),
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: deleting
          ? const SizedBox.square(
              dimension: 40,
              child: Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : IconButton(
              tooltip: 'Delete highlight',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
    );
    */
    /*
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      excerpt.isEmpty ? 'Highlighted passage' : excerpt,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        Text(
                          locationLabel ?? 'Location unavailable',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          formatAnnotationDate(context, annotation.createdAt),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnnotationColorIndicator(color: annotation.color),
                  const SizedBox(height: 4),
                  deleting
                      ? const SizedBox.square(
                          dimension: 40,
                          child: Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          tooltip: 'Delete highlight',
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline),
                        ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    */
    return BookDetailsModalCard(
      title: excerpt.isEmpty ? 'Highlighted passage' : excerpt,
      metadata: [
        ?locationLabel,
        formatAnnotationDate(context, annotation.createdAt),
      ].join(' ${String.fromCharCode(0x00B7)} '),
      onTap: onOpen,
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnnotationColorIndicator(color: annotation.color),
          const SizedBox(height: BookDetailsModalCardMetrics.actionGap),
          deleting
              ? const SizedBox.square(
                  dimension: BookDetailsModalCardMetrics.actionTouchTarget,
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  tooltip: 'Delete highlight',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
        ],
      ),
    );
  }
}

class AnnotationColorIndicator extends StatelessWidget {
  const AnnotationColorIndicator({required this.color, super.key});

  final ReaderAnnotationColor? color;

  @override
  Widget build(BuildContext context) {
    final (value, label) = switch (color) {
      ReaderAnnotationColor.yellow => (
        const Color(0xFFFDD835),
        'Yellow highlight',
      ),
      ReaderAnnotationColor.green => (
        const Color(0xFF43A047),
        'Green highlight',
      ),
      ReaderAnnotationColor.blue => (const Color(0xFF42A5F5), 'Blue highlight'),
      ReaderAnnotationColor.pink => (const Color(0xFFEC407A), 'Pink highlight'),
      _ => (
        Theme.of(context).colorScheme.outlineVariant,
        'Highlight color unavailable',
      ),
    };
    return Semantics(
      label: label,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: value,
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
      ),
    );
  }
}

class BookAnnotationsEmptyState extends StatelessWidget {
  const BookAnnotationsEmptyState({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.format_list_bulleted, size: 48),
          SizedBox(height: 16),
          Text('No annotations yet'),
          SizedBox(height: 8),
          Text(
            'Highlights you create in this book will appear here.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class BookAnnotationsErrorState extends StatelessWidget {
  const BookAnnotationsErrorState({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Could not load annotations.'),
        const SizedBox(height: 8),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

String formatAnnotationDate(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(local.year, local.month, local.day);
  final time = MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(TimeOfDay.fromDateTime(local));
  if (date == today) return 'Today, $time';
  if (date == today.subtract(const Duration(days: 1))) {
    return 'Yesterday, $time';
  }
  return MaterialLocalizations.of(context).formatShortDate(local);
}

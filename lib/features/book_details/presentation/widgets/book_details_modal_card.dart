import 'package:flutter/material.dart';

abstract final class BookDetailsModalCardMetrics {
  static const horizontalPadding = 16.0;
  static const topPadding = 14.0;
  static const bottomPadding = 8.0;
  static const cornerRadius = 20.0;
  static const borderWidth = 1.0;
  static const minimumHeight = 96.0;
  static const cardGap = 12.0;
  static const listVerticalPadding = 16.0;
  static const textToMetadataGap = 12.0;
  static const textToActionGap = 8.0;
  static const actionColumnWidth = 48.0;
  static const actionGap = 4.0;
  static const actionTouchTarget = 48.0;
}

class BookDetailsModalCard extends StatelessWidget {
  const BookDetailsModalCard({
    required this.title,
    required this.metadata,
    required this.action,
    required this.onTap,
    super.key,
  });

  final String title;
  final String? metadata;
  final Widget action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(
      Radius.circular(BookDetailsModalCardMetrics.cornerRadius),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: BookDetailsModalCardMetrics.minimumHeight,
      ),
      child: Material(
        color: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: radius),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: radius,
            border: Border.all(
              color: scheme.outlineVariant,
              width: BookDetailsModalCardMetrics.borderWidth,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                BookDetailsModalCardMetrics.horizontalPadding,
                BookDetailsModalCardMetrics.topPadding,
                BookDetailsModalCardMetrics.bottomPadding,
                BookDetailsModalCardMetrics.bottomPadding,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        if (metadata != null) ...[
                          const SizedBox(
                            height:
                                BookDetailsModalCardMetrics.textToMetadataGap,
                          ),
                          Text(
                            metadata!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(
                    width: BookDetailsModalCardMetrics.textToActionGap,
                  ),
                  SizedBox(
                    width: BookDetailsModalCardMetrics.actionColumnWidth,
                    child: Align(alignment: Alignment.topCenter, child: action),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;
import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:flutter/material.dart';

/// Shared List appearance. Feature adapters own data, progress and actions.
class AppBookListTile extends StatelessWidget {
  const AppBookListTile({
    required this.title,
    required this.cover,
    required this.onOpen,
    this.metadata,
    this.status,
    this.bookStatus,
    this.progressPercent,
    this.actions = const [],
    super.key,
  }) : assert(actions.length <= 1);

  static const coverWidth = 92.0;
  static const coverHeight = 138.0;
  static const coverRadius = 12.0;
  static const coverGap = 16.0;
  static const progressHeight = 28.0;
  static const actionExtent = 48.0;

  final String title;
  final Widget cover;
  final VoidCallback? onOpen;

  /// Author / primary descriptive text, directly below the title.
  final String? metadata;
  final Widget? status;
  final String? bookStatus;
  final int? progressPercent;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final percent = progressPercent?.clamp(0, 100);
    final hasBottom = bookStatus != null || status != null;
    final painter = TextPainter(
      text: TextSpan(
        style: theme.textTheme.titleMedium?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    );
    final firstLineHeight = painter.preferredLineHeight;
    painter.dispose();
    final actionTop = math.max(
      0.0,
      12 + firstLineHeight / 2 - actionExtent / 2,
    );
    return Semantics(
      container: true,
      child: Stack(
        children: [
          InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    key: const Key('book-list-cover'),
                    borderRadius: BorderRadius.circular(coverRadius),
                    child: SizedBox(
                      width: coverWidth,
                      height: coverHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ExcludeSemantics(child: cover),
                          if (percent != null)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Semantics(
                                label: 'Reading progress $percent%',
                                child: ExcludeSemantics(
                                  child: Container(
                                    key: const Key('book-list-progress'),
                                    constraints: const BoxConstraints(
                                      minHeight: progressHeight,
                                    ),
                                    color: Colors.black.withValues(alpha: .72),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '$percent%',
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            height: 1.2,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: coverGap),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: coverHeight),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      key: const Key('book-list-title'),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                            height: 1.2,
                                            color: scheme.onSurface,
                                          ),
                                    ),
                                    if (metadata != null &&
                                        metadata!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        metadata!,
                                        key: const Key('book-list-author'),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              fontSize: 15,
                                              height: 1.25,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: actionExtent,
                                height: actionExtent,
                              ),
                            ],
                          ),
                          if (hasBottom)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: DefaultTextStyle(
                                style: theme.textTheme.bodySmall!.copyWith(
                                  fontSize: 13,
                                  height: 1.25,
                                  color: scheme.onSurfaceVariant,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                child: Column(
                                  key: const Key('book-list-bottom'),
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // An operational indicator owns this area
                                    // until the operation finishes.
                                    if (status == null && bookStatus != null)
                                      Text(
                                        bookStatus!,
                                        key: const Key('book-list-status'),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ?status,
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: actionTop,
            right: 16,
            child: SizedBox(
              key: const Key('book-list-actions'),
              width: actionExtent,
              height: actionExtent,
              child: actions.isEmpty ? null : actions.single,
            ),
          ),
        ],
      ),
    );
  }
}

/// A deliberately disabled future-action affordance, never a fake menu.
class AppBookListActionPlaceholder extends StatelessWidget {
  const AppBookListActionPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: false,
    label: AppStrings.futureBookActions,
    child: ExcludeSemantics(
      child: AbsorbPointer(
        child: IconButton(
          tooltip: AppStrings.futureBookActions,
          onPressed: null,
          icon: Icon(
            Icons.more_vert,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ),
  );
}

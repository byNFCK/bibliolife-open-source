import 'dart:ui' show ImageFilter;

import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:flutter/material.dart';

const _bottomBarBlurSigma = 8.0;
const _bottomBarOpacity = 0.8;

/// The application-wide visual contract for a book in a grid or shelf.
class AppBookCard extends StatelessWidget {
  const AppBookCard({
    required this.title,
    required this.cover,
    required this.onOpen,
    this.author,
    this.progressPercent,
    this.isFavorite = false,
    this.favoriteAvailable = false,
    this.favoriteEnabled = true,
    this.onFavorite,
    this.status,
    this.titleMaxLines = 2,
    this.semanticIdentifier,
    super.key,
  }) : assert(!favoriteAvailable || onFavorite != null);

  final String title;
  final String? author;
  final Widget cover;
  final VoidCallback? onOpen;
  final int? progressPercent;
  final bool isFavorite;
  final bool favoriteAvailable;
  final bool favoriteEnabled;
  final VoidCallback? onFavorite;
  final Widget? status;
  final int titleMaxLines;
  final String? semanticIdentifier;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final scheme = Theme.of(context).colorScheme;
    final panelColor = scheme.surfaceContainerHigh.withValues(
      alpha: _bottomBarOpacity,
    );
    final percent = progressPercent?.clamp(0, 100);
    final hasAuthor = author?.trim().isNotEmpty == true;
    final favoriteLabel = isFavorite
        ? 'Remove from favorites'
        : 'Add to favorites';
    final progressWidget = percent == null
        ? const SizedBox.shrink()
        : Semantics(
            label: 'Reading progress $percent%',
            child: Text(
              '$percent%',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          );
    final label =
        semanticIdentifier ?? (hasAuthor ? '$title by $author' : title);

    return Semantics(
      label: label,
      button: onOpen != null,
      container: true,
      child: Align(
        alignment: Alignment.topLeft,
        heightFactor: 1,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: tokens.bookCardAspectRatio,
                child: Card(
                  key: const Key('app-book-card'),
                  margin: EdgeInsets.zero,
                  color: scheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(tokens.cardRadius),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    clipBehavior: Clip.none,
                    children: [
                      KeyedSubtree(
                        key: const Key('app-book-card-cover'),
                        child: ExcludeSemantics(child: cover),
                      ),
                      if (percent != null || favoriteAvailable)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: tokens.bookCardBottomBarHeight,
                          child: Container(
                            key: percent == null
                                ? null
                                : const Key('app-book-card-bottom-bar'),
                            color: Colors.transparent,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                if (percent != null)
                                  Positioned.fill(
                                    child: ClipRect(
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(
                                          sigmaX: _bottomBarBlurSigma,
                                          sigmaY: _bottomBarBlurSigma,
                                        ),
                                        child: ColoredBox(
                                          key: const Key(
                                            'app-book-card-panel-background',
                                          ),
                                          color: panelColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                favoriteAvailable
                                    ? Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          const Expanded(child: SizedBox()),
                                          progressWidget,
                                          const Expanded(child: SizedBox()),
                                          SizedBox(
                                            width: 48,
                                            height:
                                                tokens.bookCardBottomBarHeight,
                                            child: OverflowBox(
                                              alignment: Alignment.bottomCenter,
                                              minWidth: 48,
                                              maxWidth: 48,
                                              minHeight: 48,
                                              maxHeight: 48,
                                              child: Semantics(
                                                label: favoriteLabel,
                                                button: true,
                                                toggled: isFavorite,
                                                child: IconButton(
                                                  tooltip: favoriteLabel,
                                                  padding: EdgeInsets.zero,
                                                  constraints:
                                                      const BoxConstraints.tightFor(
                                                        width: 48,
                                                        height: 48,
                                                      ),
                                                  onPressed: favoriteEnabled
                                                      ? onFavorite
                                                      : null,
                                                  iconSize: tokens
                                                      .bookCardFavoriteIconSize,
                                                  icon: Transform.translate(
                                                    offset: const Offset(0, 4),
                                                    child: Icon(
                                                      isFavorite
                                                          ? Icons.favorite
                                                          : Icons
                                                                .favorite_border,
                                                      color: isFavorite
                                                          ? scheme.primary
                                                          : scheme
                                                                .onSurfaceVariant,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const Expanded(child: SizedBox()),
                                        ],
                                      )
                                    : Center(child: progressWidget),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: titleMaxLines,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (hasAuthor)
                Text(
                  author!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              if (status != null) ...[const SizedBox(height: 4), status!],
            ],
          ),
        ),
      ),
    );
  }
}

class AppBookCardPlaceholder extends StatelessWidget {
  const AppBookCardPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: tokens.bookCardAspectRatio,
        child: Card(
          key: const Key('app-book-card-placeholder'),
          margin: EdgeInsets.zero,
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.cardRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Expanded(child: ColoredBox(color: scheme.secondaryContainer)),
              Container(
                height: tokens.bookCardBottomBarHeight,
                color: scheme.surfaceContainerHigh,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

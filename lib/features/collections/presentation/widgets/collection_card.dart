import 'package:bibliolife/features/collections/presentation/system_collection_colors.dart';
import 'package:bibliolife/features/collections/domain/models/system_collection.dart';
import 'dart:io';

import 'package:bibliolife/features/collections/domain/models/collection_summary.dart';
import 'package:bibliolife/features/collections/presentation/widgets/collection_cover.dart';
import 'package:bibliolife/shared/models/book_cover_reference.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_image.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_render_profile.dart';
import 'package:flutter/material.dart';

class _CollectionCardGeometry {
  static const aspectRatio = 1.62;
  static const panelTopRadius = 32.0;
  static const panelHeightFraction = 0.4;
  static const centerCoverWidthFraction = 0.34;
  static const sideCoverWidthFraction = 0.29;
  static const coverAspectRatio = 0.66;
  static const coverCornerRadius = 16.0;
  static const iconBadgeSize = 48.0;
  static const panelHorizontalPadding = 24.0;
}

class _CollectionCardColors {
  const _CollectionCardColors({
    required this.outerBackground,
    required this.informationPanel,
    required this.coverAreaCenter,
    required this.coverAreaEdge,
  });

  final Color outerBackground;
  final Color informationPanel;
  final Color coverAreaCenter;
  final Color coverAreaEdge;

  factory _CollectionCardColors.resolve(ColorScheme colors) {
    if (colors.brightness == Brightness.dark) {
      final outerBackground = Color.alphaBlend(
        colors.primary.withValues(alpha: 0.26),
        colors.surfaceContainerHigh,
      );
      return _CollectionCardColors(
        outerBackground: outerBackground,
        informationPanel: Color.alphaBlend(
          colors.primary.withValues(alpha: 0.08),
          colors.surfaceContainer,
        ),
        coverAreaCenter: Color.lerp(
          outerBackground,
          colors.surfaceContainerHighest,
          0.22,
        )!,
        coverAreaEdge: Color.lerp(
          outerBackground,
          colors.surfaceContainer,
          0.18,
        )!,
      );
    }
    final outerBackground = colors.surfaceContainerHigh;
    return _CollectionCardColors(
      outerBackground: outerBackground,
      informationPanel: colors.surfaceContainer,
      coverAreaCenter: Color.lerp(outerBackground, colors.surface, 0.16)!,
      coverAreaEdge: Color.lerp(
        outerBackground,
        colors.surfaceContainer,
        0.14,
      )!,
    );
  }
}

class CollectionCard extends StatelessWidget {
  const CollectionCard({required this.summary, required this.onTap, super.key});

  final CollectionSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final customCoverPath = summary.collection.customCoverPath?.trim();
    return SystemCollectionTheme(
      collectionId: summary.collection.id,
      child: _CollectionCardFrame(
        summary: summary,
        onTap: onTap,
        customCoverPath: customCoverPath,
      ),
    );
  }
}

class _CollectionCardFrame extends StatelessWidget {
  const _CollectionCardFrame({
    required this.summary,
    required this.onTap,
    required this.customCoverPath,
  });

  final CollectionSummary summary;
  final VoidCallback onTap;
  final String? customCoverPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final cardColors = _CollectionCardColors.resolve(colors);
    final countLabel =
        '${summary.bookCount} ${summary.bookCount == 1 ? 'book' : 'books'}';

    final card = LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final availableTextWidth =
            (constraints.maxWidth -
                    2 * _CollectionCardGeometry.panelHorizontalPadding -
                    _CollectionCardGeometry.iconBadgeSize -
                    14 -
                    8 -
                    24)
                .clamp(1.0, double.infinity);
        double textHeight(String value, TextStyle? style, {int? maxLines}) {
          final painter = TextPainter(
            text: TextSpan(text: value, style: style),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            maxLines: maxLines,
          )..layout(maxWidth: availableTextWidth);
          final height = painter.height;
          painter.dispose();
          return height;
        }

        final textHeightTotal =
            textHeight(
              summary.collection.name,
              theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
            ) +
            3 +
            textHeight(countLabel, theme.textTheme.bodySmall);
        final minPanelHeight =
            32 +
            (textHeightTotal > _CollectionCardGeometry.iconBadgeSize
                ? textHeightTotal
                : _CollectionCardGeometry.iconBadgeSize);
        final defaultHeight =
            constraints.maxWidth / _CollectionCardGeometry.aspectRatio;
        final minHeight =
            minPanelHeight / _CollectionCardGeometry.panelHeightFraction;
        final height = defaultHeight > minHeight ? defaultHeight : minHeight;
        return AspectRatio(
          key: const Key('collection-card-aspect-ratio'),
          aspectRatio: constraints.maxWidth / height,
          child: _CollectionCardSurface(
            summary: summary,
            onTap: onTap,
            cardColors: cardColors,
            customCoverPath: customCoverPath,
          ),
        );
      },
    );

    return Semantics(
      button: true,
      label: '${summary.collection.name}, $countLabel',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: card,
      ),
    );
  }
}

class _CollectionCardSurface extends StatelessWidget {
  const _CollectionCardSurface({
    required this.summary,
    required this.onTap,
    required this.cardColors,
    required this.customCoverPath,
  });

  final CollectionSummary summary;
  final VoidCallback onTap;
  final _CollectionCardColors cardColors;
  final String? customCoverPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final outerBackgroundColor = cardColors.outerBackground;
    final informationPanelColor = cardColors.informationPanel;
    final iconBadgeColor = colors.primaryContainer;
    final titleColor = colors.onSurface;
    final subtitleColor = colors.primary;
    final radius = CollectionCover.borderRadius;

    return Material(
      key: const Key('collection-card-surface'),
      color: outerBackgroundColor,
      borderRadius: radius,
      elevation: 1,
      shadowColor: colors.shadow.withValues(alpha: 0.2),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final panelHeight =
                height * _CollectionCardGeometry.panelHeightFraction;

            return Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    key: const Key('collection-card-cover-background'),
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.12),
                        radius: 1.15,
                        colors: [
                          cardColors.coverAreaCenter,
                          outerBackgroundColor,
                          cardColors.coverAreaEdge,
                        ],
                        stops: const [0, 0.62, 1],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: CollectionCover(
                    key: const Key('collection-card-cover-viewport'),
                    imageFile: customCoverPath == null
                        ? null
                        : File(customCoverPath!),
                    placeholder: _CoverPreview(books: summary.recentBooks),
                    semanticLabel: 'Cover of ${summary.collection.name}',
                    imageKey: const Key('collection-card-custom-cover'),
                    cacheWidth: 720,
                    diagnosticSourceType: 'custom-collection',
                    diagnosticId: summary.collection.id,
                    diagnosticProfile: 'collectionCardCustom',
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: MediaQuery.textScalerOf(context).scale(1) > 1
                      ? null
                      : panelHeight,
                  child: DecoratedBox(
                    key: const Key('collection-card-information-panel'),
                    decoration: BoxDecoration(
                      color: informationPanelColor,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(
                          _CollectionCardGeometry.panelTopRadius,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors.shadow.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, -1),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal:
                            _CollectionCardGeometry.panelHorizontalPadding,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          DecoratedBox(
                            key: const Key('collection-card-icon-badge'),
                            decoration: BoxDecoration(
                              color: iconBadgeColor,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: SizedBox.square(
                              dimension: _CollectionCardGeometry.iconBadgeSize,
                              child: Icon(switch (summary.collection.id) {
                                systemFinishedId => Icons.task_alt,
                                systemReadingId => Icons.menu_book,
                                systemToReadId => Icons.bookmark_outline,
                                _ => Icons.collections_bookmark_rounded,
                              }, color: colors.onPrimaryContainer),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  summary.collection.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: titleColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${summary.bookCount} ${summary.bookCount == 1 ? 'book' : 'books'}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: subtitleColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: subtitleColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CoverPreview extends StatelessWidget {
  const _CoverPreview({required this.books});

  final List<CollectionPreviewBook> books;

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return const CollectionCoverPlaceholder(
        style: CollectionCoverPlaceholderStyle.card,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final centerWidth =
            constraints.maxWidth *
            _CollectionCardGeometry.centerCoverWidthFraction;
        final sideWidth =
            constraints.maxWidth *
            _CollectionCardGeometry.sideCoverWidthFraction;
        final centerHeight =
            centerWidth / _CollectionCardGeometry.coverAspectRatio;
        final sideHeight = sideWidth / _CollectionCardGeometry.coverAspectRatio;
        final centerX = constraints.maxWidth / 2;
        final sideOffset = centerWidth * 0.68;

        return Stack(
          clipBehavior: Clip.none,
          children: switch (books.length) {
            1 => [
              _cover(
                book: books[0],
                left: centerX - centerWidth / 2,
                top: 0,
                width: centerWidth,
                height: centerHeight,
                prominent: true,
              ),
            ],
            2 => [
              _cover(
                book: books[1],
                left: centerX - sideOffset - sideWidth / 2,
                top: 12,
                width: sideWidth,
                height: sideHeight,
              ),
              _cover(
                book: books[0],
                left: centerX - centerWidth / 2 + centerWidth * 0.18,
                top: 0,
                width: centerWidth,
                height: centerHeight,
                prominent: true,
              ),
            ],
            _ => [
              _cover(
                book: books[1],
                left: centerX - sideOffset - sideWidth / 2,
                top: 12,
                width: sideWidth,
                height: sideHeight,
              ),
              _cover(
                book: books[2],
                left: centerX + sideOffset - sideWidth / 2,
                top: 12,
                width: sideWidth,
                height: sideHeight,
              ),
              _cover(
                book: books[0],
                left: centerX - centerWidth / 2,
                top: 0,
                width: centerWidth,
                height: centerHeight,
                prominent: true,
              ),
            ],
          },
        );
      },
    );
  }

  Widget _cover({
    required CollectionPreviewBook book,
    required double left,
    required double top,
    required double width,
    required double height,
    bool prominent = false,
  }) => Positioned(
    left: left,
    top: top,
    width: width,
    height: height,
    child: _PreviewCover(book: book, prominent: prominent),
  );
}

class _PreviewCover extends StatelessWidget {
  const _PreviewCover({required this.book, required this.prominent});

  final CollectionPreviewBook book;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(
          _CollectionCardGeometry.coverCornerRadius,
        ),
        boxShadow: prominent
            ? [
                BoxShadow(
                  color: colors.shadow.withValues(alpha: 0.16),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          _CollectionCardGeometry.coverCornerRadius,
        ),
        child: BookCoverImage(
          cover: book.coverPath == null
              ? const BookCoverReference.missing()
              : BookCoverReference.local(book.coverPath!),
          title: book.title,
          cacheWidth: 160,
          cacheHeight: 240,
          profile: BookCoverRenderProfile.compactList,
          diagnosticSourceType: 'collection-preview',
          diagnosticId: 'book:${book.id}',
          placeholder: ColoredBox(
            color: colors.surfaceContainerHighest,
            child: Center(
              child: Icon(
                Icons.menu_book_outlined,
                color: colors.onSurfaceVariant,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

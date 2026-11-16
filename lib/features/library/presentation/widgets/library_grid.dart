import 'dart:math' as math;

import 'package:bibliolife/app/theme/app_spacing.dart';
import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_book_card.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';

class LibraryGrid extends StatelessWidget {
  const LibraryGrid({
    required this.books,
    required this.width,
    this.padding,
    this.sliverKey,
    this.itemKeyPrefix = 'library-book-card',
    super.key,
  });

  static const _tileAspectRatio = 0.48;

  final List<LibraryBook> books;
  final double width;
  final EdgeInsets? padding;
  final Key? sliverKey;
  final String itemKeyPrefix;

  @override
  Widget build(BuildContext context) {
    final crossAxisCount = switch (width) {
      < 600 => 2,
      < 900 => 3,
      _ => 4,
    };

    final tokens = context.appTokens;
    final contentPadding =
        padding ??
        EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.md,
          bottom: MediaQuery.viewPaddingOf(context).bottom + 96,
        );
    final tileWidth = math.max(
      0.0,
      (width -
              contentPadding.horizontal -
              (crossAxisCount - 1) * tokens.bookCardGridGap) /
          crossAxisCount,
    );
    final textTheme = Theme.of(context).textTheme;
    final titleHeight = _lineHeight(context, textTheme.titleSmall);
    final authorHeight = _lineHeight(context, textTheme.bodySmall);
    // AppBookCard lays out the cover, up to two title lines, and one author
    // line. Keep the original grid proportions whenever that content fits.
    final minimumTileHeight =
        tileWidth / tokens.bookCardAspectRatio +
        AppSpacing.sm +
        (2 * titleHeight).ceil() +
        authorHeight.ceil();

    return SliverPadding(
      padding: contentPadding,
      sliver: SliverGrid.builder(
        key: sliverKey,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: tokens.bookCardGridGap,
          crossAxisSpacing: tokens.bookCardGridGap,
          mainAxisExtent: math.max(
            tileWidth / _tileAspectRatio,
            minimumTileHeight,
          ),
        ),
        itemCount: books.length,
        addAutomaticKeepAlives: false,
        itemBuilder: (context, index) {
          final book = books[index];
          return LibraryBookCard(
            key: ValueKey('$itemKeyPrefix-${book.id}'),
            book: book,
          );
        },
      ),
    );
  }

  double _lineHeight(BuildContext context, TextStyle? style) {
    var effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
    if (MediaQuery.boldTextOf(context)) {
      effectiveStyle = effectiveStyle.merge(
        const TextStyle(fontWeight: FontWeight.bold),
      );
    }
    final painter = TextPainter(
      text: TextSpan(style: effectiveStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    );
    try {
      return painter.preferredLineHeight;
    } finally {
      painter.dispose();
    }
  }
}

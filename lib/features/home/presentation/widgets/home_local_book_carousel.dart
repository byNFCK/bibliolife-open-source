import 'dart:math' as math;

import 'package:bibliolife/app/theme/app_spacing.dart';
import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:bibliolife/features/home/presentation/widgets/book_carousel_section.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';

class HomeLocalBookCarousel extends StatelessWidget {
  const HomeLocalBookCarousel({
    required this.title,
    required this.books,
    required this.itemCount,
    required this.itemBuilder,
    super.key,
  });

  final String title;
  final List<LibraryBook> books;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final textTheme = Theme.of(context).textTheme;
    final textScaler = MediaQuery.textScalerOf(context);
    final viewportHeight = books
        .map(
          (book) => _cardHeight(
            context,
            book,
            tokens: tokens,
            titleStyle: textTheme.titleSmall,
            authorStyle: textTheme.bodySmall,
            textScaler: textScaler,
          ),
        )
        .reduce(math.max);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: BookCarouselSection(
        title: title,
        itemCount: itemCount,
        itemBuilder: itemBuilder,
        emptyLabel: '',
        carouselHeight: viewportHeight,
      ),
    );
  }

  static double _cardHeight(
    BuildContext context,
    LibraryBook book, {
    required AppThemeTokens tokens,
    required TextStyle? titleStyle,
    required TextStyle? authorStyle,
    required TextScaler textScaler,
  }) {
    final textWidth = tokens.bookCardWidth;
    final titleHeight = _textHeight(
      context,
      book.title,
      titleStyle,
      textScaler,
      textWidth,
      maxLines: 2,
    );
    final author = book.author?.trim();
    final authorHeight = author == null || author.isEmpty
        ? 0.0
        : _textHeight(
            context,
            author,
            authorStyle,
            textScaler,
            textWidth,
            maxLines: 2,
          );
    return textWidth / tokens.bookCardAspectRatio +
        AppSpacing.sm +
        titleHeight +
        authorHeight;
  }

  static double _textHeight(
    BuildContext context,
    String text,
    TextStyle? style,
    TextScaler textScaler,
    double maxWidth, {
    required int maxLines,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: textScaler,
      maxLines: maxLines,
    )..layout(maxWidth: maxWidth);
    return painter.height;
  }
}

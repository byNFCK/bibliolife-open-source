import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/app/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:bibliolife/features/home/presentation/widgets/home_section_header.dart';

class BookCarouselSection extends StatelessWidget {
  const BookCarouselSection({
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
    required this.emptyLabel,
    this.onSeeAll,
    this.carouselHeight,
    super.key,
  });

  final String title;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final String emptyLabel;
  final VoidCallback? onSeeAll;
  final double? carouselHeight;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HomeSectionHeader(
            title: title,
            actions: [
              if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  child: const Text(AppStrings.seeAll),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (itemCount == 0)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: tokens.pagePadding),
              child: Text(
                emptyLabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            SizedBox(
              height: carouselHeight ?? 360,
              child: ListView.separated(
                key: PageStorageKey('carousel-$title'),
                padding: EdgeInsets.symmetric(horizontal: tokens.pagePadding),
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: itemCount,
                separatorBuilder: (_, _) => SizedBox(width: tokens.carouselGap),
                itemBuilder: itemBuilder,
              ),
            ),
        ],
      ),
    );
  }
}

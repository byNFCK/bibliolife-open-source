import 'package:bibliolife/features/home/domain/models/home_feed_ranking.dart';
import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:flutter/material.dart';

class HomeRankingSubtitle extends StatelessWidget {
  const HomeRankingSubtitle({required this.ranking, super.key});

  final HomeFeedRanking ranking;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      context.appTokens.pagePadding,
      8,
      context.appTokens.pagePadding,
      12,
    ),
    child: Semantics(
      label: ranking.explanation == null
          ? ranking.label
          : '${ranking.label}. ${ranking.explanation}',
      child: Text(
        ranking.label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}

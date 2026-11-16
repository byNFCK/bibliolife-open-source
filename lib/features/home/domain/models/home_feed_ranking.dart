enum HomeFeedRankingMethod {
  weeklyPopularity,
  providerRelevance,
  recentlyAdded,
}

enum HomeFeedRankingEvidence { exactProviderReported, providerFallback }

/// Provider-scoped ranking metadata for a Home discovery page.
///
/// A score is deliberately carried only with its provider. Consumers must not
/// compare a Gutenberg download count with an Internet Archive popularity
/// value, for example.
class HomeFeedRanking {
  const HomeFeedRanking({
    required this.method,
    required this.evidence,
    required this.label,
    this.period,
    this.explanation,
  });

  const HomeFeedRanking.weeklyPopularity()
    : method = HomeFeedRankingMethod.weeklyPopularity,
      evidence = HomeFeedRankingEvidence.exactProviderReported,
      label = 'Popular in the last 7 days',
      period = const Duration(days: 7),
      explanation = null;

  const HomeFeedRanking.googleRelevance()
    : method = HomeFeedRankingMethod.providerRelevance,
      evidence = HomeFeedRankingEvidence.providerFallback,
      label = 'Recommended by Google Books',
      period = null,
      explanation =
          'Google Books does not publish a weekly popularity ranking.';

  const HomeFeedRanking.recentlyAdded()
    : method = HomeFeedRankingMethod.recentlyAdded,
      evidence = HomeFeedRankingEvidence.providerFallback,
      label = 'Recently added',
      period = null,
      explanation = null;

  final HomeFeedRankingMethod method;
  final HomeFeedRankingEvidence evidence;
  final String label;
  final Duration? period;
  final String? explanation;

  bool get isExactWeeklyPopularity =>
      method == HomeFeedRankingMethod.weeklyPopularity &&
      evidence == HomeFeedRankingEvidence.exactProviderReported;
}

class HomeFeedPublicationRanking {
  const HomeFeedPublicationRanking({
    this.rank,
    this.providerScore,
    this.period,
    required this.method,
    required this.evidence,
  });

  final int? rank;
  final num? providerScore;
  final Duration? period;
  final HomeFeedRankingMethod method;
  final HomeFeedRankingEvidence evidence;
}

import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/features/book_details/presentation/models/book_details_formatters.dart';
import 'package:bibliolife/features/reader/domain/models/reading_progress.dart';
import 'package:flutter/material.dart';

class BookDetailsProgress extends StatelessWidget {
  const BookDetailsProgress({required this.progress, super.key});

  final ReadingProgress? progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(
      context,
    ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant);
    final page = readingPageLabel(progress);
    final percent = readingProgressPercent(progress?.progression);

    if (page == null) {
      return Center(
        child: _ProgressItem(
          label: '${AppStrings.progress}: $percent%',
          style: style,
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: _ProgressItem(
            label: '${AppStrings.page}: $page',
            style: style,
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: _ProgressItem(
            label: '${AppStrings.progress}: $percent%',
            style: style,
          ),
        ),
      ],
    );
  }
}

class _ProgressItem extends StatelessWidget {
  const _ProgressItem({required this.label, required this.style});

  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Text(label, style: style, textAlign: TextAlign.center),
    );
  }
}

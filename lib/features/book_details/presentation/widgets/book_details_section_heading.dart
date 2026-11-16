import 'package:bibliolife/app/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class BookDetailsSectionHeading extends StatelessWidget {
  const BookDetailsSectionHeading({
    required this.label,
    required this.child,
    super.key,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        header: true,
        child: Text(
          label,
          key: Key('book-details-section-heading-$label'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      child,
    ],
  );
}

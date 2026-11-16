import 'package:bibliolife/app/theme/app_spacing.dart';
import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:flutter/material.dart';

class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({
    required this.title,
    this.subtitle,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (subtitle case final subtitle?) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.appTokens.pagePadding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (actions.isEmpty) return text;
          final maxTextWidth = constraints.maxWidth < 180
              ? constraints.maxWidth
              : (constraints.maxWidth - 96)
                    .clamp(180, constraints.maxWidth)
                    .toDouble();
          return Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxTextWidth),
                child: text,
              ),
              Row(mainAxisSize: MainAxisSize.min, children: actions),
            ],
          );
        },
      ),
    );
  }
}

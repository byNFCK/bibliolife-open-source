import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:bibliolife/app/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class HomeSearchEntry extends StatelessWidget {
  const HomeSearchEntry({
    required this.onTap,
    required this.onFilters,
    required this.onResetFilters,
    required this.hasCustomFilters,
    super.key,
  });

  final VoidCallback onTap;
  final VoidCallback onFilters;
  final VoidCallback onResetFilters;
  final bool hasCustomFilters;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.appTokens.pagePadding,
        0,
        context.appTokens.pagePadding,
        AppSpacing.md,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Semantics(
            label: 'Search books',
            button: true,
            onTap: onTap,
            excludeSemantics: true,
            child: ExcludeSemantics(
              child: Material(
                color: scheme.surfaceContainerHigh,
                shape: StadiumBorder(
                  side: BorderSide(color: scheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      const SizedBox(width: 20),
                      const Icon(Icons.search),
                      const SizedBox(width: 16),
                      Expanded(
                        child: InkWell(
                          key: const Key('home-search-action'),
                          onTap: onTap,
                          child: const Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Search books'),
                          ),
                        ),
                      ),
                      if (hasCustomFilters)
                        IconButton(
                          tooltip: 'Reset filters',
                          onPressed: onResetFilters,
                          icon: const Icon(Icons.filter_alt_off_outlined),
                        ),
                      IconButton(
                        tooltip: 'Search filters',
                        onPressed: onFilters,
                        icon: const Icon(Icons.filter_alt_outlined),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

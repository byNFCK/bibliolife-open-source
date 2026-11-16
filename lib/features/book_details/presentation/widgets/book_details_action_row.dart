import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:flutter/material.dart';

class BookDetailsActionRow extends StatelessWidget {
  const BookDetailsActionRow({
    required this.bookmarkActive,
    required this.tocAvailable,
    required this.favoriteActive,
    required this.favoritePending,
    required this.onBookmark,
    required this.onToc,
    required this.onFavorite,
    super.key,
  });

  final bool bookmarkActive;
  final bool tocAvailable;
  final bool favoriteActive;
  final bool favoritePending;
  final VoidCallback onBookmark;
  final VoidCallback onToc;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Divider(color: Theme.of(context).colorScheme.outlineVariant),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                key: const Key('toc-action'),
                label: 'Table of contents',
                active: false,
                icon: Icons.toc,
                onPressed: tocAvailable ? onToc : null,
              ),
            ),
            Expanded(
              child: _ActionButton(
                key: const Key('bookmark-action'),
                label: 'Bookmarks and annotations',
                active: bookmarkActive,
                icon: bookmarkActive ? Icons.bookmark : Icons.bookmark_border,
                onPressed: onBookmark,
              ),
            ),
            Expanded(
              child: _ActionButton(
                key: const Key('favorite-action'),
                label: favoriteActive
                    ? AppStrings.removeFromFavorites
                    : AppStrings.addToFavorites,
                active: favoriteActive,
                icon: favoriteActive ? Icons.favorite : Icons.favorite_border,
                onPressed: favoritePending ? null : onFavorite,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.active,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool active;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.clamp(0.0, 92.0).toDouble();
        return Center(
          child: Semantics(
            excludeSemantics: true,
            button: true,
            enabled: onPressed != null,
            selected: active,
            label: label,
            onTap: onPressed,
            child: Tooltip(
              message: label,
              child: SizedBox(
                width: width,
                height: 56,
                child: IconButton(
                  onPressed: onPressed,
                  style: IconButton.styleFrom(
                    backgroundColor: active
                        ? scheme.secondaryContainer
                        : scheme.surfaceContainerHigh,
                    foregroundColor: active
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant,
                    disabledBackgroundColor: scheme.surfaceContainerHigh,
                    disabledForegroundColor: scheme.onSurfaceVariant.withValues(
                      alpha: 0.38,
                    ),
                    side: BorderSide(
                      color: active ? scheme.secondary : scheme.outline,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 12,
                    ),
                    shape: const StadiumBorder(),
                  ),
                  icon: Icon(icon),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

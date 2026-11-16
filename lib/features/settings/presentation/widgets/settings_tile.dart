import 'package:flutter/material.dart';

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    required this.title,
    this.icon,
    this.subtitle,
    this.value,
    this.showChevron = true,
    this.destructive = false,
    this.onTap,
    this.tileKey,
    super.key,
  });

  final String title;
  final IconData? icon;
  final String? subtitle;
  final String? value;
  final bool showChevron;
  final bool destructive;
  final VoidCallback? onTap;
  final Key? tileKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = destructive ? scheme.error : scheme.onSurface;
    final iconColor = destructive ? scheme.error : scheme.onSurfaceVariant;
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.bodyLarge!.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      color: foreground,
    );
    final valueStyle = theme.textTheme.bodyMedium!.copyWith(
      fontSize: 13,
      color: destructive ? scheme.error : scheme.onSurfaceVariant,
    );
    return Semantics(
      key: tileKey,
      container: true,
      button: onTap != null,
      enabled: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final painter = TextPainter(
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              );
              double width(String text, TextStyle style) {
                painter.text = TextSpan(text: text, style: style);
                painter.layout();
                return painter.width;
              }

              final available =
                  constraints.maxWidth -
                  (icon == null ? 0 : 32) -
                  (showChevron ? 28 : 0);
              final stacked =
                  value != null &&
                  width(title, titleStyle) + width(value!, valueStyle) + 16 >
                      available;
              painter.dispose();
              final heading = Text(title, style: titleStyle);
              final current = value == null
                  ? null
                  : Text(value!, style: valueStyle);
              return ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 26),
                child: Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 20, color: iconColor),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (stacked) ...[
                            heading,
                            const SizedBox(height: 4),
                            ?current,
                          ] else
                            Row(
                              children: [
                                Expanded(child: heading),
                                if (current != null) ...[
                                  const SizedBox(width: 12),
                                  current,
                                ],
                              ],
                            ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(subtitle!, style: valueStyle),
                          ],
                        ],
                      ),
                    ),
                    if (showChevron) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right, size: 20, color: iconColor),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

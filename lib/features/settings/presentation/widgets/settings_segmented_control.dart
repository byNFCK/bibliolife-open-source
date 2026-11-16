import 'package:bibliolife/features/settings/presentation/widgets/settings_control_content.dart';
import 'package:bibliolife/shared/presentation/widgets/biblio_tabs.dart';
import 'package:flutter/material.dart';

/// Controlled inline preference. Providers and persistence stay with the caller.
class SettingsSegmentedControl<T extends Object> extends StatelessWidget {
  const SettingsSegmentedControl({
    required this.title,
    required this.icon,
    required this.items,
    required this.selected,
    required this.onSelected,
    this.description,
    this.fieldKey,
    super.key,
  });
  final String title;
  final IconData icon;
  final List<BiblioTabItem<T>> items;
  final T selected;
  final ValueChanged<T>? onSelected;
  final String? description;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabs = BiblioTabs<T>(
      items: items,
      selectedId: selected,
      onSelected: onSelected,
      stackWhenNarrow: true,
      expandToFill: true,
      horizontalLabelPadding: 6,
      minimumItemHeight: 48,
    );
    return SettingsControlContent(
      key: fieldKey,
      title: title,
      icon: icon,
      description: description,
      // Only Profile light-mode tracks use the stronger semantic surface role.
      child: theme.brightness == Brightness.dark
          ? tabs
          : Theme(
              data: theme.copyWith(
                colorScheme: theme.colorScheme.copyWith(
                  surfaceContainerHigh:
                      theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              child: tabs,
            ),
    );
  }
}

import 'package:flutter/material.dart';

class SettingsChoice<T> {
  const SettingsChoice({
    required this.value,
    required this.label,
    this.subtitle,
    this.key,
  });

  final T value;
  final String label;
  final String? subtitle;
  final Key? key;
}

Future<T?> showSettingsModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) => showModalBottomSheet<T>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: isScrollControlled,
  builder: builder,
);

Future<T?> showSettingsSingleChoiceSheet<T>({
  required BuildContext context,
  required String title,
  required T selected,
  required List<SettingsChoice<T>> choices,
}) => showSettingsModalSheet<T>(
  context: context,
  builder: (_) => SettingsSingleChoiceSheet<T>(
    title: title,
    selected: selected,
    choices: choices,
  ),
);

class SettingsSingleChoiceSheet<T> extends StatelessWidget {
  const SettingsSingleChoiceSheet({
    required this.title,
    required this.selected,
    required this.choices,
    super.key,
  });

  final String title;
  final T selected;
  final List<SettingsChoice<T>> choices;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: RadioGroup<T>(
        groupValue: selected,
        onChanged: (value) {
          if (value != null) Navigator.of(context).pop(value);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final choice in choices)
              RadioListTile<T>(
                key: choice.key,
                title: Text(choice.label),
                subtitle: choice.subtitle == null
                    ? null
                    : Text(choice.subtitle!),
                value: choice.value,
              ),
          ],
        ),
      ),
    ),
  );
}

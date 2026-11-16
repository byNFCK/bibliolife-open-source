import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/features/settings/presentation/widgets/settings_body.dart';
import 'package:flutter/material.dart';

export 'package:bibliolife/features/settings/presentation/widgets/settings_body.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text(AppStrings.settings)),
    body: const SafeArea(
      child: SettingsBody(showPageTitle: false, shellContext: false),
    ),
  );
}

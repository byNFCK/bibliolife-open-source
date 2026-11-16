import 'package:bibliolife/features/settings/presentation/widgets/settings_body.dart';
import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: SafeArea(
      child: SettingsBody(showPageTitle: true, shellContext: true),
    ),
  );
}

import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/shared/application/logging/app_log_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppLogScreen extends ConsumerStatefulWidget {
  const AppLogScreen({super.key});

  @override
  ConsumerState<AppLogScreen> createState() => _AppLogScreenState();
}

class _AppLogScreenState extends ConsumerState<AppLogScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(appLogProvider.notifier)
          .info(category: 'App', message: 'LOG page opened');
    });
  }

  Future<void> _copyLogs() async {
    final logs = ref.read(appLogProvider.notifier);
    logs.info(category: 'App', message: 'COPY invoked');
    final snapshot = logs.formattedText;
    try {
      await Clipboard.setData(ClipboardData(text: snapshot));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(AppStrings.logsCopied)));
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(AppStrings.logsCopyError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(appLogProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.log),
        actions: [
          TextButton.icon(
            key: const Key('app-log-copy'),
            onPressed: _copyLogs,
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text(AppStrings.copy),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: entries.isEmpty
          ? const Center(child: Text(AppStrings.noLogsYet))
          : ListView.builder(
              key: const Key('app-log-list'),
              itemCount: entries.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: SelectableText(
                  entries[index].toLogLine(),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                ),
              ),
            ),
    );
  }
}

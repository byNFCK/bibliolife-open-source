import 'package:bibliolife/shared/presentation/widgets/app_modal_sheet_scaffold.dart';
import 'package:flutter/material.dart';

Future<T?> showBookDetailsModalSheet<T>({
  required BuildContext context,
  required String title,
  required Widget content,
  bool useRootNavigator = false,
  String footerLabel = 'Cancel',
}) => showAppModalSheet<T>(
  context: context,
  useRootNavigator: useRootNavigator,
  title: title,
  footer: AppModalSheetSingleActionFooter(
    horizontalPadding: 12,
    label: footerLabel,
  ),
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: content,
  ),
);

/// Compatibility wrapper around the shared application modal shell.
class BookDetailsModalSheetScaffold extends StatelessWidget {
  const BookDetailsModalSheetScaffold({
    required this.title,
    required this.content,
    this.headerExtension,
    super.key,
  });

  final String title;
  final Widget content;
  final Widget? headerExtension;

  @override
  Widget build(BuildContext context) => AppModalSheetScaffold(
    title: title,
    headerExtension: headerExtension,
    footer: const AppModalSheetSingleActionFooter(horizontalPadding: 12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: content,
    ),
  );
}

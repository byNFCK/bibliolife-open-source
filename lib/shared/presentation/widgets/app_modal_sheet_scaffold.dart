import 'package:flutter/material.dart';

abstract final class AppModalSheetTokens {
  static const sheetRadius = Radius.circular(32);
  static const maxHeightFactor = .75;
  static const horizontalPadding = 20.0;
  static const headerTopPadding = 12.0;
  static const titleVerticalPadding = 12.0;
  static const dragHandleWidth = 36.0;
  static const dragHandleHeight = 4.0;
  static const footerVerticalPadding = 12.0;
  static const buttonHeight = 48.0;
  static const cancelWidth = 160.0;
}

const appModalSheetAnimation = AnimationStyle(
  duration: Duration(milliseconds: 200),
  reverseDuration: Duration(milliseconds: 160),
);

Future<T?> showAppModalSheet<T>({
  required BuildContext context,
  required String title,
  required Widget child,
  Widget? headerExtension,
  Widget? footer,
  double? maxHeightFactor,
  bool useRootNavigator = false,
}) => showModalBottomSheet<T>(
  context: context,
  useRootNavigator: useRootNavigator,
  isScrollControlled: true,
  useSafeArea: false,
  enableDrag: true,
  backgroundColor: Colors.transparent,
  sheetAnimationStyle: appModalSheetAnimation,
  builder: (_) => AppModalSheetScaffold(
    title: title,
    maxHeightFactor: maxHeightFactor,
    headerExtension: headerExtension,
    footer: footer,
    child: child,
  ),
);

class AppModalSheetScaffold extends StatelessWidget {
  const AppModalSheetScaffold({
    required this.title,
    required this.child,
    this.headerExtension,
    this.footer,
    this.maxHeightFactor,
    this.backgroundOpacity = 1,
    this.backgroundOpacityDuration = kThemeChangeDuration,
    this.foregroundOpacity = 1,
    this.foregroundOpacityDuration = kThemeChangeDuration,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? headerExtension;
  final Widget? footer;
  final double? maxHeightFactor;
  final double backgroundOpacity;
  final Duration backgroundOpacityDuration;
  final double foregroundOpacity;
  final Duration foregroundOpacityDuration;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final factor = maxHeightFactor ?? AppModalSheetTokens.maxHeightFactor;
    final maxHeight =
        (MediaQuery.sizeOf(context).height -
            MediaQuery.paddingOf(context).bottom) *
        factor;
    return ConstrainedBox(
      key: const Key('app-modal-sheet'),
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Material(
        animationDuration: backgroundOpacityDuration,
        color: scheme.surfaceContainerLow.withValues(
          alpha: scheme.surfaceContainerLow.a * backgroundOpacity,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: AppModalSheetTokens.sheetRadius,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedOpacity(
              opacity: foregroundOpacity,
              duration: foregroundOpacityDuration,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      top: AppModalSheetTokens.headerTopPadding,
                    ),
                    child: Container(
                      key: const Key('app-modal-drag-handle'),
                      width: AppModalSheetTokens.dragHandleWidth,
                      height: AppModalSheetTokens.dragHandleHeight,
                      decoration: BoxDecoration(
                        color: scheme.onSurfaceVariant.withValues(alpha: .45),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Semantics(
                    header: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppModalSheetTokens.horizontalPadding,
                        vertical: AppModalSheetTokens.titleVerticalPadding,
                      ),
                      child: Center(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ),
                  ),
                  if (headerExtension != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppModalSheetTokens.horizontalPadding,
                        0,
                        AppModalSheetTokens.horizontalPadding,
                        AppModalSheetTokens.titleVerticalPadding,
                      ),
                      child: headerExtension,
                    ),
                  AppModalSheetDivider(
                    key: const Key('reader-menu-upper-decorative-strip'),
                    color: scheme.outlineVariant,
                  ),
                ],
              ),
            ),
            Flexible(fit: FlexFit.loose, child: child),
            if (footer != null) ...[
              AnimatedOpacity(
                opacity: foregroundOpacity,
                duration: foregroundOpacityDuration,
                child: AppModalSheetDivider(
                  key: const Key('reader-menu-lower-decorative-strip'),
                  color: scheme.outlineVariant,
                ),
              ),
              AnimatedOpacity(
                opacity: foregroundOpacity,
                duration: foregroundOpacityDuration,
                child: footer!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AppModalSheetDivider extends StatelessWidget {
  const AppModalSheetDivider({required this.color, super.key});
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppModalSheetTokens.horizontalPadding,
    ),
    child: Divider(height: 1, color: color),
  );
}

class AppModalSheetSingleActionFooter extends StatelessWidget {
  const AppModalSheetSingleActionFooter({
    this.onCancel,
    this.label = 'Cancel',
    this.horizontalPadding = AppModalSheetTokens.horizontalPadding,
    super.key,
  });

  final VoidCallback? onCancel;
  final String label;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: AppModalSheetTokens.footerVerticalPadding,
      ),
      child: SizedBox(
        width: AppModalSheetTokens.cancelWidth,
        height: AppModalSheetTokens.buttonHeight,
        child: OutlinedButton(
          onPressed: onCancel ?? () => Navigator.of(context).maybePop(),
          child: Text(label),
        ),
      ),
    ),
  );
}

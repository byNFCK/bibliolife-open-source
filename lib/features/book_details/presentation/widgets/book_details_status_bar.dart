import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared artwork/status-bar treatment for both details routes.
class BookDetailsStatusBar extends StatelessWidget {
  const BookDetailsStatusBar({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final statusInset = MediaQuery.paddingOf(context).top;
    final background = theme.scaffoldBackgroundColor;
    final overlayStyle =
        theme.appBarTheme.systemOverlayStyle ?? const SystemUiOverlayStyle();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: theme.brightness,
        systemStatusBarContrastEnforced: false,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (statusInset > 0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: statusInset + 8,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        background.withValues(alpha: dark ? 0.70 : 0.78),
                        background.withValues(alpha: dark ? 0.64 : 0.72),
                        background.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.45, 1],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

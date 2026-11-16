import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:bibliolife/shared/presentation/widgets/floating_navigation_shell_style.dart';

abstract final class AppNavigationPresentation {
  // Shared Flutter navigation-surface metrics.
  static const outerHorizontalMargin = 20.0;
  static const bottomMargin = 18.0;
  static const surfaceHorizontalPadding = 10.0;
  static const surfaceVerticalPadding = 8.0;
  static const actionSpacing = 8.0;
  static const touchTarget = 48.0;
  static const surfaceRadius = FloatingNavigationShellStyle.radius;
  static const elevation = 6.0;
  static const outlineWidth = FloatingNavigationShellStyle.outlineWidth;
  static const iconSize = 24.0;
  static const selectedCircleSize = 40.0;
  static const surfaceHeight = touchTarget + (surfaceVerticalPadding * 2);
  static const intrinsicSurfaceWidth =
      (surfaceHorizontalPadding * 2) +
      (touchTarget * 2) +
      112.0 +
      (actionSpacing * 2);
}

class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _onDestinationSelected(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        key: const Key('production-app-shell'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        extendBody: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                key: const Key('app-shell-content'),
                child: navigationShell,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom:
                  MediaQuery.viewPaddingOf(context).bottom +
                  AppNavigationPresentation.bottomMargin,
              child: Center(
                child: FloatingNavigationIsland(
                  selectedIndex: navigationShell.currentIndex,
                  onDestinationSelected: _onDestinationSelected,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FloatingNavigationIsland extends StatelessWidget {
  const FloatingNavigationIsland({
    required this.selectedIndex,
    required this.onDestinationSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const Key('navigation-island-surface'),
      // The shared Flutter navigation surface uses colorSurface and the
      // shared floating-shell outline.
      color: scheme.surface,
      elevation: AppNavigationPresentation.elevation,
      shape: FloatingNavigationShellStyle.shapeFor(context),
      clipBehavior: FloatingNavigationShellStyle.clipBehavior,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppNavigationPresentation.surfaceHorizontalPadding,
          vertical: AppNavigationPresentation.surfaceVerticalPadding,
        ),
        child: SizedBox(
          width:
              AppNavigationPresentation.intrinsicSurfaceWidth -
              (AppNavigationPresentation.surfaceHorizontalPadding * 2),
          height: AppNavigationPresentation.touchTarget,
          child: _NavigationDestinations(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
          ),
        ),
      ),
    );
  }
}

class _NavigationDestinations extends StatelessWidget {
  const _NavigationDestinations({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const _labels = ['Home', 'Library', 'Profile'];
  static const _icons = [
    Icons.home_outlined,
    Icons.local_library_outlined,
    Icons.person_outline,
  ];
  static const _selectedIcons = [Icons.home, Icons.local_library, Icons.person];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final usePrimaryFallback = scheme.secondaryContainer == scheme.surface;
    final activeBackground = usePrimaryFallback
        ? scheme.primaryContainer
        : scheme.secondaryContainer;
    final activeIconColor = usePrimaryFallback
        ? scheme.onPrimaryContainer
        : scheme.onSecondaryContainer;
    return Row(
      key: const Key('navigation-island-bar'),
      children: [
        for (var index = 0; index < _labels.length; index++)
          Expanded(
            child: _NavigationDestination(
              index: index,
              label: _labels[index],
              icon: index == selectedIndex
                  ? _selectedIcons[index]
                  : _icons[index],
              selected: index == selectedIndex,
              color: index == selectedIndex
                  ? activeIconColor
                  : scheme.onSurfaceVariant,
              activeBackground: activeBackground,
              onTap: () => onDestinationSelected(index),
            ),
          ),
      ],
    );
  }
}

class _NavigationDestination extends StatelessWidget {
  const _NavigationDestination({
    required this.index,
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.activeBackground,
    required this.onTap,
  });

  final int index;
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final Color activeBackground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: SizedBox(
        key: Key('navigation-destination-$index'),
        width: AppNavigationPresentation.touchTarget,
        height: AppNavigationPresentation.touchTarget,
        child: InkResponse(
          radius: AppNavigationPresentation.touchTarget / 2,
          containedInkWell: true,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: onTap,
          child: Center(
            child: selected
                ? DecoratedBox(
                    key: const Key('navigation-selected-circle'),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: activeBackground,
                    ),
                    child: SizedBox.square(
                      dimension: AppNavigationPresentation.selectedCircleSize,
                      child: Center(
                        child: Icon(
                          icon,
                          key: Key('navigation-icon-$index'),
                          size: AppNavigationPresentation.iconSize,
                          color: color,
                        ),
                      ),
                    ),
                  )
                : Icon(
                    icon,
                    key: Key('navigation-icon-$index'),
                    size: AppNavigationPresentation.iconSize,
                    color: color,
                  ),
          ),
        ),
      ),
    );
  }
}

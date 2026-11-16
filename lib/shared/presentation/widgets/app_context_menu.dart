import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Visual tokens taken from the approved Book Details action popup.
class AppContextMenuPresentation {
  static const preferredWidth = 240.0;
  static const cornerRadius = 20.0;
  static const elevation = 6.0;
  static const verticalPadding = 8.0;
  static const rowHeight = 48.0;
  static const rowHorizontalPadding = 12.0;
  static const iconSize = 24.0;
  static const iconLabelGap = 12.0;
  static const triggerGap = 8.0;
  static double width(BuildContext context) {
    final mediaWidth = MediaQuery.sizeOf(context).width;
    final view = View.of(context);
    final viewportWidth = mediaWidth > 0
        ? mediaWidth
        : view.physicalSize.width / view.devicePixelRatio;
    return math.min(
      preferredWidth,
      math.max(
        0,
        viewportWidth - MediaQuery.paddingOf(context).horizontal - 16,
      ),
    );
  }

  static Offset alignmentOffset(BuildContext context) =>
      Offset(-width(context), triggerGap);

  static MenuStyle style(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MenuStyle(
      backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
      elevation: const WidgetStatePropertyAll(elevation),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(vertical: verticalPadding),
      ),
      minimumSize: WidgetStatePropertyAll(Size(width(context), 0)),
      maximumSize: WidgetStatePropertyAll(
        Size(width(context), double.infinity),
      ),
      alignment: AlignmentDirectional.bottomEnd,
      visualDensity: VisualDensity.standard,
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cornerRadius),
          side: BorderSide(color: colors.outlineVariant),
        ),
      ),
    );
  }
}

class AppContextMenuAction<T> {
  const AppContextMenuAction({
    required this.value,
    required this.label,
    required this.icon,
    this.enabled = true,
    this.destructive = false,
    this.busy = false,
    this.semanticLabel,
    this.key,
  });
  final T value;
  final String label;
  final IconData icon;
  final bool enabled;
  final bool destructive;
  final bool busy;
  final String? semanticLabel;
  final Key? key;
}

/// Shared row for Book Details and its contextual-menu consumers.
class AppContextMenuItem extends StatelessWidget {
  const AppContextMenuItem({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
    this.busy = false,
    this.semanticLabel,
    super.key,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool destructive;
  final bool busy;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: AppContextMenuPresentation.rowHeight,
        maxWidth: AppContextMenuPresentation.width(context),
      ),
      child: SizedBox(
        width: AppContextMenuPresentation.width(context),
        child: MenuItemButton(
          onPressed: onPressed,
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(
              Size(0, AppContextMenuPresentation.rowHeight),
            ),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(
                horizontal: AppContextMenuPresentation.rowHorizontalPadding,
              ),
            ),
            visualDensity: VisualDensity.standard,
            textStyle: WidgetStatePropertyAll(
              Theme.of(context).textTheme.labelLarge,
            ),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return colors.onSurface.withValues(alpha: 0.38);
              }
              return destructive ? colors.error : colors.onSurface;
            }),
          ),
          leadingIcon: busy
              ? const SizedBox.square(
                  dimension: AppContextMenuPresentation.iconSize,
                  child: Center(
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : Icon(icon, size: AppContextMenuPresentation.iconSize),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.max(
                0,
                AppContextMenuPresentation.width(context) -
                    2 * AppContextMenuPresentation.rowHorizontalPadding -
                    AppContextMenuPresentation.iconSize -
                    AppContextMenuPresentation.iconLabelGap,
              ),
            ),
            child: Text(label, semanticsLabel: semanticLabel),
          ),
        ),
      ),
    );
  }
}

/// Anchored Material menu; each caller retains its action values and callbacks.
class AppContextMenuButton<T> extends StatefulWidget {
  const AppContextMenuButton({
    required this.actions,
    required this.onSelected,
    required this.tooltip,
    this.onOpen,
    super.key,
  });
  final List<AppContextMenuAction<T>> actions;
  final ValueChanged<T> onSelected;
  final String tooltip;
  final VoidCallback? onOpen;

  @override
  State<AppContextMenuButton<T>> createState() =>
      _AppContextMenuButtonState<T>();
}

class _AppContextMenuButtonState<T> extends State<AppContextMenuButton<T>> {
  final _controller = MenuController();
  final _focus = FocusNode();
  bool _open = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: !_open,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _open) _controller.close();
    },
    child: MenuAnchor(
      controller: _controller,
      childFocusNode: _focus,
      consumeOutsideTap: true,
      alignmentOffset: AppContextMenuPresentation.alignmentOffset(context),
      style: AppContextMenuPresentation.style(context),
      onOpen: () {
        setState(() => _open = true);
        widget.onOpen?.call();
      },
      onClose: () {
        if (mounted) setState(() => _open = false);
      },
      menuChildren: [
        for (final action in widget.actions)
          AppContextMenuItem(
            key: action.key,
            label: action.label,
            icon: action.icon,
            destructive: action.destructive,
            busy: action.busy,
            semanticLabel: action.semanticLabel,
            onPressed: action.enabled
                ? () {
                    _controller.close();
                    widget.onSelected(action.value);
                  }
                : null,
          ),
      ],
      child: IconButton(
        tooltip: widget.tooltip,
        focusNode: _focus,
        icon: const Icon(Icons.more_vert),
        onPressed: () {
          if (_controller.isOpen) {
            _controller.close();
          } else {
            _controller.open();
          }
        },
      ),
    ),
  );
}

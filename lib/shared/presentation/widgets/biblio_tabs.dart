import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:bibliolife/app/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class BiblioTabItem<T extends Object> {
  const BiblioTabItem({
    required this.id,
    required this.label,
    this.enabled = true,
    this.icon,
    this.key,
  });

  final T id;
  final String label;
  final bool enabled;
  final IconData? icon;
  final Key? key;
}

/// A content-sized, controlled tab strip. The caller owns selection and decides
/// what to select when an item is removed.
class BiblioTabs<T extends Object> extends StatelessWidget {
  const BiblioTabs({
    required this.items,
    required this.selectedId,
    required this.onSelected,
    this.scrollStorageKey,
    this.stackWhenNarrow = false,
    this.expandToFill = false,
    this.horizontalLabelPadding = _labelPadding,
    this.minimumItemHeight = 42,
    super.key,
  });

  final List<BiblioTabItem<T>> items;
  final T? selectedId;

  /// When null, all tabs remain visible but cannot be selected.
  final ValueChanged<T>? onSelected;
  final PageStorageKey<String>? scrollStorageKey;

  /// Settings may grow vertically instead of scrolling or truncating options.
  /// Existing navigation strips retain their content-sized scrolling behavior.
  final bool stackWhenNarrow;
  final bool expandToFill;
  final double horizontalLabelPadding;
  final double minimumItemHeight;

  static const _labelPadding = 14.0;
  static const _maxItemWidth = 320.0;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final select = onSelected;
    final theme = Theme.of(context);
    final textDirection = Directionality.of(context);
    final textStyle = theme.textTheme.labelLarge!.copyWith(
      fontWeight: MediaQuery.boldTextOf(context)
          ? FontWeight.bold
          : FontWeight.w600,
    );
    final textScaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackPadding = math.min(AppSpacing.xs, constraints.maxWidth / 2);
        final availableWidth = constraints.maxWidth - 2 * trackPadding;
        final itemWidthLimit = math.min(availableWidth, _maxItemWidth);
        final labelPadding = math.min(
          horizontalLabelPadding,
          itemWidthLimit / 4,
        );
        final painter = TextPainter(
          textDirection: textDirection,
          textScaler: textScaler,
          locale: locale,
          maxLines: 1,
        );
        final widths = <double>[];
        double contentWidth = 0;
        double labelHeight = 0;
        _TabExtent? selected;
        try {
          for (final item in items) {
            painter.text = TextSpan(text: item.label, style: textStyle);
            painter.layout(maxWidth: itemWidthLimit - 2 * labelPadding);
            labelHeight = math.max(labelHeight, painter.height);
            final width = math.min(
              itemWidthLimit,
              math.max(
                kMinInteractiveDimension,
                painter.width.ceilToDouble() +
                    2 * labelPadding +
                    (item.icon == null ? 0 : 26),
              ),
            );
            if (item.id == selectedId) {
              selected = (start: contentWidth, width: width);
            }
            widths.add(width);
            contentWidth += width;
          }
        } finally {
          painter.dispose();
        }

        final stacked =
            stackWhenNarrow &&
            (expandToFill
                ? widths.any((width) => width > availableWidth / items.length)
                : contentWidth > availableWidth);
        if (expandToFill && !stacked) {
          final equalWidth = availableWidth / items.length;
          widths.fillRange(0, widths.length, equalWidth);
          contentWidth = availableWidth;
          final index = items.indexWhere((item) => item.id == selectedId);
          selected = index < 0
              ? null
              : (start: index * equalWidth, width: equalWidth);
        }
        final itemHeight = math.max(48.0, labelHeight + 12);
        final selectedIndex = items.indexWhere((item) => item.id == selectedId);
        final viewportWidth = stacked
            ? availableWidth
            : math.min(availableWidth, contentWidth);
        final colors = theme.colorScheme;
        final pageColor = theme.scaffoldBackgroundColor;
        // Android CorePalette schemes can resolve surfaceContainerHigh to surface.
        final trackColor = colors.surfaceContainerHigh == pageColor
            ? Color.alphaBlend(
                colors.onSurface.withValues(alpha: 0.10),
                pageColor,
              )
            : colors.surfaceContainerHigh;
        final duration = MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 200);
        const capsuleShape = StadiumBorder();
        final ShapeBorder trackShape = stacked
            ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))
            : capsuleShape;

        return Center(
          heightFactor: 1,
          child: Material(
            color: trackColor,
            shape: trackShape,
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: EdgeInsets.all(trackPadding),
              child: SizedBox(
                width: viewportWidth,
                child: _BiblioTabScroll(
                  key: scrollStorageKey,
                  viewportWidth: viewportWidth,
                  contentWidth: stacked ? availableWidth : contentWidth,
                  selected: stacked ? null : selected,
                  duration: duration,
                  // The scroll view owns its own semantic node. Inside it,
                  // the tab bar can expose only tabs as direct children.
                  child: Semantics(
                    role: SemanticsRole.tabBar,
                    container: true,
                    explicitChildNodes: true,
                    child: Stack(
                      children: [
                        if (selected != null)
                          AnimatedPositionedDirectional(
                            duration: duration,
                            curve: Curves.easeInOut,
                            start: stacked ? 0 : selected.start,
                            width: stacked ? availableWidth : selected.width,
                            top: stacked ? selectedIndex * itemHeight : 0,
                            bottom: stacked ? null : 0,
                            height: stacked ? itemHeight : null,
                            child: DecoratedBox(
                              decoration: ShapeDecoration(
                                shape: capsuleShape,
                                color: colors.secondaryContainer,
                              ),
                            ),
                          ),
                        Flex(
                          direction: stacked ? Axis.vertical : Axis.horizontal,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var index = 0; index < items.length; index++)
                              _BiblioTab(
                                key:
                                    items[index].key ??
                                    ValueKey(items[index].id),
                                label: items[index].label,
                                width: stacked ? availableWidth : widths[index],
                                minHeight: stacked
                                    ? itemHeight
                                    : minimumItemHeight,
                                icon: items[index].icon,
                                labelPadding: labelPadding,
                                selected: items[index].id == selectedId,
                                textStyle: textStyle,
                                onTap: items[index].enabled && select != null
                                    ? () => select(items[index].id)
                                    : null,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BiblioTab extends StatelessWidget {
  const _BiblioTab({
    required super.key,
    required this.label,
    required this.width,
    required this.labelPadding,
    required this.selected,
    required this.textStyle,
    required this.onTap,
    required this.minHeight,
    this.icon,
  });

  final String label;
  final double width;
  final double labelPadding;
  final bool selected;
  final TextStyle textStyle;
  final VoidCallback? onTap;
  final double minHeight;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected
        ? colors.onSecondaryContainer
        : colors.onSurfaceVariant;
    final color = onTap == null
        ? foreground.withValues(alpha: 0.38)
        : foreground;

    return Semantics(
      container: true,
      role: SemanticsRole.tab,
      label: label,
      selected: selected,
      enabled: onTap != null,
      inMutuallyExclusiveGroup: true,
      onTap: onTap,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          excludeFromSemantics: true,
          customBorder: const StadiumBorder(),
          child: Container(
            width: width,
            constraints: BoxConstraints(minHeight: minHeight),
            padding: EdgeInsets.symmetric(
              horizontal: labelPadding,
              vertical: 6,
            ),
            child: Center(
              heightFactor: 1,
              child: ExcludeSemantics(
                child: icon == null
                    ? Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: textStyle.copyWith(color: color),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 20, color: color),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: textStyle.copyWith(color: color),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

typedef _TabExtent = ({double start, double width});

class _BiblioTabScroll extends StatefulWidget {
  const _BiblioTabScroll({
    super.key,
    required this.viewportWidth,
    required this.contentWidth,
    required this.selected,
    required this.duration,
    required this.child,
  });

  final double viewportWidth;
  final double contentWidth;
  final _TabExtent? selected;
  final Duration duration;
  final Widget child;

  @override
  State<_BiblioTabScroll> createState() => _BiblioTabScrollState();
}

class _BiblioTabScrollState extends State<_BiblioTabScroll> {
  late final _controller = ScrollController(
    initialScrollOffset: _visibleOffset(
      (widget.key == null
                  ? null
                  : PageStorage.maybeOf(context)?.readState(context))
              as double? ??
          0,
    ),
    keepScrollOffset: false,
  );

  double _visibleOffset(double offset) {
    final selected = widget.selected;
    if (selected != null) {
      final end = selected.start + selected.width;
      offset = offset.clamp(
        math.min(end - widget.viewportWidth, selected.start),
        selected.start,
      );
    }
    return offset.clamp(0.0, widget.contentWidth - widget.viewportWidth);
  }

  @override
  void didUpdateWidget(covariant _BiblioTabScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected == oldWidget.selected &&
        widget.viewportWidth == oldWidget.viewportWidth &&
        widget.contentWidth == oldWidget.contentWidth) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final target = _visibleOffset(_controller.offset);
      if ((target - _controller.offset).abs() < 0.01) return;
      if (widget.duration == Duration.zero) {
        _controller.jumpTo(target);
      } else {
        _controller.animateTo(
          target,
          duration: widget.duration,
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollEndNotification>(
        onNotification: (notification) {
          if (widget.key != null && notification.depth == 0) {
            PageStorage.maybeOf(
              context,
            )?.writeState(context, notification.metrics.pixels);
          }
          return false;
        },
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          child: widget.child,
        ),
      );
}

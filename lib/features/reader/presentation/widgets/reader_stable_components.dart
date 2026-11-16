import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:bibliolife/shared/presentation/widgets/floating_navigation_shell_style.dart';
import 'package:bibliolife/shared/presentation/widgets/app_modal_sheet_scaffold.dart';
import 'package:bibliolife/shared/presentation/widgets/biblio_tabs.dart';
import 'package:bibliolife/features/reader/performance/reader_performance.dart';
import 'package:bibliolife/features/reader/presentation/models/reader_ui_controller.dart';

/// Shared measurements copied from the stable native Readium reader chrome and
/// the current Flutter modal-sheet presentation.
abstract final class ReaderStableTokens {
  static const sliderInteractionOpacity = .15;
  static const sliderInteractionDuration = Duration(milliseconds: 150);
  static const chromeRadius = Radius.circular(
    FloatingNavigationShellStyle.radius,
  );
  static const sheetRadius = Radius.circular(32);
  static const menuCardRadius = Radius.circular(20);
  static const sheetMaxHeightFactor = .75;
  static const sheetHandleWidth = 36.0;
  static const sheetHandleHeight = 4.0;
  static const sheetHeaderTopPadding = 12.0;
  static const sheetTitleVerticalPadding = 12.0;
  static const sheetHorizontalPadding = 20.0;
  static const sheetFooterVerticalPadding = 12.0;
  static const sheetCancelWidth = 160.0;
  static const sheetButtonHeight = 48.0;
  static const menuMaxHeightFactor = .75;
  static const menuRowGap = 12.0;
  static const menuRowMinimumHeight = 48.0;
  static const menuContentTopPadding = 16.0;
  static const menuContentBottomPadding = 16.0;
}

/// The Android Material3 reader uses `colorSurfaceVariant` for the title/TOC
/// pill and the reading-position pill. Keep this semantic role shared by the
/// Flutter equivalents instead of substituting a nearby surface-container
/// tone.
abstract final class ReaderChromeReferenceTokens {
  static Color controlBackground(BuildContext context) {
    // `ColorScheme.surfaceVariant` is the Flutter semantic counterpart of
    // Android Material3's `colorSurfaceVariant` used by the stable reader.
    // ignore: deprecated_member_use
    return Theme.of(context).colorScheme.surfaceVariant;
  }

  static Color controlForeground(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;
}

class ReaderStableChromeSurface extends StatelessWidget {
  const ReaderStableChromeSurface({
    required this.margin,
    required this.child,
    this.floatingNavigationShell = false,
    super.key,
  });

  final EdgeInsets margin;
  final Widget child;
  final bool floatingNavigationShell;

  @override
  Widget build(BuildContext context) {
    final shellShape = floatingNavigationShell
        ? FloatingNavigationShellStyle.shapeFor(context)
        : null;
    return Padding(
      padding: margin,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 6,
        shadowColor: Colors.black54,
        shape: shellShape,
        borderRadius: shellShape == null
            ? const BorderRadius.all(ReaderStableTokens.chromeRadius)
            : null,
        clipBehavior: floatingNavigationShell
            ? FloatingNavigationShellStyle.clipBehavior
            : Clip.none,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: child,
        ),
      ),
    );
  }
}

class ReaderStableIconButton extends StatelessWidget {
  const ReaderStableIconButton({
    required this.tooltip,
    required this.asset,
    required this.onPressed,
    this.color,
    super.key,
  });

  final String tooltip;
  final String asset;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        icon: SvgPicture.asset(
          asset,
          width: 24,
          height: 24,
          colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
        ),
      ),
    );
  }
}

/// The canonical presentation contract for every Readium menu.
///
/// The saved-items menu is the baseline: all reader menus use this exact
/// route, barrier, animation, safe-area policy, geometry, header and footer
/// contract. Menu-specific widgets provide content only.
Future<T?> showReaderMenu<T>({
  required BuildContext context,
  required String title,
  required Widget child,
  Widget? headerExtension,
  Widget? footer,
  ReaderUiController? sliderInteractionController,
}) async {
  ReaderPerformance.mark('READER_PERF_MENU_OPEN_START', type: title);
  Widget buildSheet(BuildContext _) => PopScope<T>(
    canPop: true,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) {
        ReaderPerformance.mark('READER_PERF_MENU_CLOSE_START', type: title);
      }
    },
    child: ReaderMenuPerformanceScope(
      type: title,
      child: ReaderPerformanceFirstFrame(
        marker: 'READER_PERF_MENU_FIRST_FRAME',
        settledMarker: 'READER_PERF_MENU_SETTLED',
        type: title,
        child: ReaderMenuScaffold(
          title: title,
          headerExtension: headerExtension,
          footer: footer,
          sliderInteractionController: sliderInteractionController,
          child: child,
        ),
      ),
    ),
  );
  final controller = sliderInteractionController;
  if (controller == null) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: appModalSheetAnimation,
      builder: buildSheet,
    );
  }
  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  return navigator.push<T>(
    _ReaderSliderFocusBottomSheetRoute<T>(
      builder: buildSheet,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      isScrollControlled: true,
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      backgroundColor: Colors.transparent,
      modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: false,
      sheetAnimationStyle: appModalSheetAnimation,
      sliderController: controller,
      sliderFocusDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : ReaderStableTokens.sliderInteractionDuration,
    ),
  );
}

class _ReaderSliderFocusBottomSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _ReaderSliderFocusBottomSheetRoute({
    required super.builder,
    required super.capturedThemes,
    required super.isScrollControlled,
    required super.barrierLabel,
    required super.barrierOnTapHint,
    required super.backgroundColor,
    required super.modalBarrierColor,
    required super.isDismissible,
    required super.enableDrag,
    required super.useSafeArea,
    required super.sheetAnimationStyle,
    required this.sliderController,
    required this.sliderFocusDuration,
  });

  final ReaderUiController sliderController;
  final Duration sliderFocusDuration;

  @override
  Widget buildModalBarrier() => AnimatedBuilder(
    animation: sliderController,
    builder: (context, child) => AnimatedOpacity(
      opacity: sliderController.isSliderInteractionActive
          ? ReaderStableTokens.sliderInteractionOpacity
          : 1,
      duration: sliderFocusDuration,
      child: child,
    ),
    child: super.buildModalBarrier(),
  );
}

class ReaderMenuScaffold extends StatelessWidget {
  const ReaderMenuScaffold({
    required this.title,
    required this.child,
    this.headerExtension,
    this.footer,
    this.sliderInteractionController,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? headerExtension;
  final Widget? footer;
  final ReaderUiController? sliderInteractionController;

  @override
  Widget build(BuildContext context) {
    final controller = sliderInteractionController;
    if (controller == null) {
      return AppModalSheetScaffold(
        title: title,
        maxHeightFactor: ReaderStableTokens.menuMaxHeightFactor,
        headerExtension: headerExtension,
        footer: footer,
        child: child,
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final active = controller.isSliderInteractionActive;
        final opacity = active
            ? ReaderStableTokens.sliderInteractionOpacity
            : 1.0;
        final animationDuration = MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : ReaderStableTokens.sliderInteractionDuration;
        return _ReaderSliderInteractionScope(
          activeSliderId: controller.activeSliderId,
          backgroundAnimationDuration: animationDuration,
          child: AppModalSheetScaffold(
            title: title,
            maxHeightFactor: ReaderStableTokens.menuMaxHeightFactor,
            headerExtension: headerExtension,
            footer: footer,
            backgroundOpacity: opacity,
            backgroundOpacityDuration: animationDuration,
            foregroundOpacity: opacity,
            foregroundOpacityDuration: animationDuration,
            child: child,
          ),
        );
      },
    );
  }
}

class _ReaderSliderInteractionScope extends InheritedWidget {
  const _ReaderSliderInteractionScope({
    required this.activeSliderId,
    required this.backgroundAnimationDuration,
    required super.child,
  });

  final ReaderSliderId? activeSliderId;
  final Duration backgroundAnimationDuration;

  static _ReaderSliderInteractionScope? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_ReaderSliderInteractionScope>();

  @override
  bool updateShouldNotify(_ReaderSliderInteractionScope oldWidget) =>
      activeSliderId != oldWidget.activeSliderId ||
      backgroundAnimationDuration != oldWidget.backgroundAnimationDuration;
}

class ReaderSliderFocusOpacity extends StatelessWidget {
  const ReaderSliderFocusOpacity({
    required this.child,
    this.sliderId,
    this.activeSliderId,
    super.key,
  });

  final Widget child;
  final ReaderSliderId? sliderId;
  final ReaderSliderId? activeSliderId;

  @override
  Widget build(BuildContext context) {
    final scope = _ReaderSliderInteractionScope.maybeOf(context);
    final active = activeSliderId ?? scope?.activeSliderId;
    final opacity = active != null && active != sliderId
        ? ReaderStableTokens.sliderInteractionOpacity
        : 1.0;
    final duration =
        scope?.backgroundAnimationDuration ??
        (MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : ReaderStableTokens.sliderInteractionDuration);
    return AnimatedOpacity(opacity: opacity, duration: duration, child: child);
  }
}

class ReaderMenuFooter extends StatelessWidget {
  const ReaderMenuFooter({
    required this.onCancel,
    required this.onApply,
    this.applyLabel = 'Apply',
    super.key,
  });

  final VoidCallback? onCancel;
  final VoidCallback? onApply;
  final String applyLabel;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        ReaderStableTokens.sheetHorizontalPadding,
        ReaderStableTokens.sheetFooterVerticalPadding,
        ReaderStableTokens.sheetHorizontalPadding,
        ReaderStableTokens.sheetFooterVerticalPadding,
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onCancel,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(
                  ReaderStableTokens.sheetButtonHeight,
                ),
              ),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: onApply,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(
                  ReaderStableTokens.sheetButtonHeight,
                ),
              ),
              child: Text(applyLabel),
            ),
          ),
        ],
      ),
    ),
  );
}

typedef ReaderMenuSingleActionFooter = AppModalSheetSingleActionFooter;

class ReaderMenuCard extends StatelessWidget {
  const ReaderMenuCard({
    required this.child,
    this.minimumHeight = 96,
    this.borderRadius = ReaderStableTokens.menuCardRadius,
    super.key,
  });

  final Widget child;
  final double minimumHeight;
  final Radius borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sliderInteraction = _ReaderSliderInteractionScope.maybeOf(context);
    return Material(
      color: sliderInteraction?.activeSliderId != null
          ? scheme.surfaceContainerHigh.withValues(alpha: 0)
          : scheme.surfaceContainerHigh,
      animationDuration:
          sliderInteraction?.backgroundAnimationDuration ??
          kThemeChangeDuration,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(borderRadius),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(
            alpha: sliderInteraction?.activeSliderId != null
                ? ReaderStableTokens.sliderInteractionOpacity
                : 1,
          ),
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minimumHeight),
        child: child,
      ),
    );
  }
}

class ReaderMenuSection extends StatelessWidget {
  const ReaderMenuSection({
    required this.title,
    required this.child,
    super.key,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => ReaderMenuCard(
    minimumHeight: 0,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReaderSliderFocusOpacity(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    ),
  );
}

class ReaderStableSettingSlider extends StatefulWidget {
  const ReaderStableSettingSlider({
    required this.sliderId,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    super.key,
  });

  final ReaderSliderId sliderId;
  final String label;
  final double value;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final Object? Function(ReaderSliderId) onInteractionStart;
  final void Function(ReaderSliderId, Object?) onInteractionEnd;

  @override
  State<ReaderStableSettingSlider> createState() =>
      _ReaderStableSettingSliderState();
}

class _ReaderStableSettingSliderState extends State<ReaderStableSettingSlider> {
  late double _value = widget.value;
  var _isInteracting = false;
  Object? _interactionToken;

  void _startInteraction() {
    if (_isInteracting) return;
    _isInteracting = true;
    _interactionToken = widget.onInteractionStart(widget.sliderId);
  }

  void _endInteraction() {
    if (!_isInteracting) return;
    _isInteracting = false;
    widget.onInteractionEnd(widget.sliderId, _interactionToken);
    _interactionToken = null;
  }

  @override
  void didUpdateWidget(covariant ReaderStableSettingSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isInteracting &&
        (!widget.enabled ||
            oldWidget.onInteractionEnd != widget.onInteractionEnd ||
            oldWidget.sliderId != widget.sliderId)) {
      oldWidget.onInteractionEnd(oldWidget.sliderId, _interactionToken);
      _interactionToken = null;
      _isInteracting = false;
    }
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  @override
  void dispose() {
    _endInteraction();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: ReaderSliderFocusOpacity(
                child: Text(widget.label, style: theme.textTheme.bodyLarge),
              ),
            ),
            ReaderSliderFocusOpacity(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Text(
                    _value.toStringAsFixed(1),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(trackHeight: 4),
          child: ReaderSliderFocusOpacity(
            key: ValueKey('reader-slider-focus-${widget.sliderId.name}'),
            sliderId: widget.sliderId,
            child: Slider(
              value: _value.clamp(widget.min, widget.max),
              min: widget.min,
              max: widget.max,
              onChangeStart: widget.enabled ? (_) => _startInteraction() : null,
              onChanged: !widget.enabled
                  ? null
                  : (value) {
                      setState(() => _value = value);
                      widget.onChanged(value);
                    },
              onChangeEnd: widget.enabled
                  ? (value) {
                      try {
                        widget.onChangeEnd(value);
                      } finally {
                        _endInteraction();
                      }
                    }
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

class ReaderSettingsChoiceField<T extends Object> extends StatelessWidget {
  const ReaderSettingsChoiceField({
    required this.label,
    required this.items,
    required this.selectedId,
    required this.onSelected,
    super.key,
  });

  final String label;
  final List<BiblioTabItem<T>> items;
  final T? selectedId;
  final ValueChanged<T>? onSelected;

  @override
  Widget build(BuildContext context) => ReaderSliderFocusOpacity(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 10),
        BiblioTabs<T>(
          items: items,
          selectedId: selectedId,
          onSelected: onSelected,
        ),
      ],
    ),
  );
}

class ReaderSettingsDropdownField<T> extends StatelessWidget {
  const ReaderSettingsDropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    super.key,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ReaderSliderFocusOpacity(
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          const SizedBox(width: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 150, maxWidth: 210),
            child: DropdownButtonFormField<T>(
              initialValue: value,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(),
              ),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class ReaderSettingsSwitchRow extends StatelessWidget {
  const ReaderSettingsSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => ReaderSliderFocusOpacity(
    child: SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      minTileHeight: ReaderStableTokens.menuRowMinimumHeight,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      value: value,
      onChanged: onChanged,
    ),
  );
}

class ReaderSettingsFieldDivider extends StatelessWidget {
  const ReaderSettingsFieldDivider({super.key});

  @override
  Widget build(BuildContext context) => ReaderSliderFocusOpacity(
    child: SizedBox(
      height: 24,
      child: Center(
        child: SizedBox(
          height: 1,
          width: double.infinity,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
    ),
  );
}

class ReaderMenuLoading extends StatelessWidget {
  const ReaderMenuLoading({this.label, super.key});

  final String? label;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        if (label != null) ...[const SizedBox(height: 12), Text(label!)],
      ],
    ),
  );
}

class ReaderMenuEmpty extends StatelessWidget {
  const ReaderMenuEmpty({
    required this.title,
    this.message,
    this.asset,
    super.key,
  });

  final String title;
  final String? message;
  final String? asset;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (asset != null) ...[
            SvgPicture.asset(
              asset!,
              width: 48,
              height: 48,
              colorFilter: ColorFilter.mode(
                Theme.of(context).colorScheme.onSurfaceVariant,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class ReaderMenuError extends StatelessWidget {
  const ReaderMenuError({
    required this.title,
    this.message = 'Close and reopen this menu to try again.',
    this.onRetry,
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/readium/stable/ic_reader_annotations.svg',
            width: 48,
            height: 48,
            colorFilter: ColorFilter.mode(
              Theme.of(context).colorScheme.onSurfaceVariant,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

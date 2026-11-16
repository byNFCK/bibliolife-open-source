import 'package:bibliolife/shared/presentation/widgets/app_context_menu.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_primary_action.dart';
import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class BookDetailsMenuAction {
  const BookDetailsMenuAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.enabled = true,
    this.busy = false,
    this.destructive = false,
    this.semanticLabel,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;
  final bool enabled;
  final bool busy;
  final bool destructive;
  final String? semanticLabel;
}

class BookDetailsFloatMenu extends StatefulWidget {
  const BookDetailsFloatMenu({
    required this.onRead,
    required this.actions,
    this.onMenuOpen,
    super.key,
  });

  final VoidCallback onRead;
  final List<BookDetailsMenuAction> actions;
  final VoidCallback? onMenuOpen;

  @override
  State<BookDetailsFloatMenu> createState() => _BookDetailsFloatMenuState();
}

class _BookDetailsFloatMenuState extends State<BookDetailsFloatMenu> {
  static const _triggerWidth = 56.0;

  final _menuController = MenuController();
  var _menuOpen = false;
  GoRouterDelegate? _routerDelegate;
  String? _routeLocation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final delegate = GoRouter.of(context).routerDelegate;
    if (_routerDelegate == delegate) return;
    _routerDelegate?.removeListener(_handleRouteChange);
    _routerDelegate = delegate..addListener(_handleRouteChange);
    _routeLocation = delegate.currentConfiguration.uri.toString();
  }

  void _handleRouteChange() {
    final location = _routerDelegate?.currentConfiguration.uri.toString();
    if (location == _routeLocation) return;
    _routeLocation = location;
    if (_menuController.isOpen) _menuController.close();
  }

  @override
  void dispose() {
    _routerDelegate?.removeListener(_handleRouteChange);
    super.dispose();
  }

  void _toggleMenu() {
    if (_menuController.isOpen) {
      _menuController.close();
    } else {
      _menuController.open();
    }
  }

  void _onMenuOpen() {
    if (mounted) setState(() => _menuOpen = true);
    widget.onMenuOpen?.call();
  }

  void _onMenuClose() {
    if (mounted) setState(() => _menuOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope<void>(
      canPop: !_menuOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _menuOpen) _menuController.close();
      },
      child: SizedBox(
        key: const Key('book-details-action-row'),
        width: double.infinity,
        height: 56,
        child: Row(
          children: [
            Expanded(
              child: FilledButton(
                key: const Key('continue-reading'),
                onPressed: widget.onRead,
                style: bookDetailsPrimaryActionStyle(context),
                child: const Text(AppStrings.continueReading),
              ),
            ),
            const SizedBox(key: Key('book-details-action-gap'), width: 6),
            Material(
              key: const Key('book-details-menu-button'),
              color: colors.primaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              clipBehavior: Clip.antiAlias,
              child: MenuAnchor(
                controller: _menuController,
                alignmentOffset: AppContextMenuPresentation.alignmentOffset(
                  context,
                ),
                consumeOutsideTap: true,
                onOpen: _onMenuOpen,
                onClose: _onMenuClose,
                style: AppContextMenuPresentation.style(context),
                menuChildren: [
                  if (widget.actions.isEmpty)
                    const AppContextMenuItem(
                      key: Key('book-details-empty-menu-action'),
                      label: AppStrings.noAdditionalBookActions,
                      icon: Icons.info_outline,
                      onPressed: null,
                    ),
                  for (final action in widget.actions)
                    AppContextMenuItem(
                      key: ValueKey('book-details-menu-${action.label}'),
                      label: action.label,
                      icon: action.icon,
                      busy: action.busy,
                      destructive: action.destructive,
                      semanticLabel: action.semanticLabel,
                      onPressed: action.enabled
                          ? () {
                              _menuController.close();
                              action.onSelected();
                            }
                          : null,
                    ),
                ],
                child: SizedBox(
                  width: _triggerWidth,
                  height: 56,
                  child: IconButton(
                    key: const Key('book-details-more-actions'),
                    tooltip: AppStrings.moreBookActions,
                    onPressed: _toggleMenu,
                    color: colors.onPrimaryContainer,
                    icon: const Icon(Icons.more_horiz),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

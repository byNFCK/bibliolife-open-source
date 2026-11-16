import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:flutter/material.dart';

/// The original Description surface and expansion treatment, shared by the
/// book-details blocks without changing Description's rendered design.
class ExpandableBookDetailsSection extends StatelessWidget {
  const ExpandableBookDetailsSection({
    required this.expanded,
    required this.canExpand,
    required this.semanticsLabel,
    required this.toggleKey,
    required this.child,
    required this.onToggle,
    this.expandedChild,
    this.semanticContainer = true,
    this.explicitChildNodes = false,
    super.key,
  });

  final bool expanded;
  final bool canExpand;
  final String semanticsLabel;
  final Key toggleKey;
  final Widget child;
  final Widget? expandedChild;
  final VoidCallback onToggle;
  final bool semanticContainer;
  final bool explicitChildNodes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final showButton = canExpand || expanded;
    final borderRadius = BorderRadius.circular(context.appTokens.cardRadius);
    final shape = RoundedRectangleBorder(
      side: BorderSide(color: scheme.outlineVariant),
      borderRadius: borderRadius,
    );

    return AnimatedSize(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 200),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: showButton ? 24 : 0),
            child: Semantics(
              container: semanticContainer,
              explicitChildNodes: explicitChildNodes,
              button: canExpand,
              expanded: canExpand ? expanded : null,
              label: semanticsLabel,
              hint: canExpand
                  ? (expanded ? AppStrings.less : AppStrings.more)
                  : null,
              onTap: canExpand ? onToggle : null,
              child: Material(
                color: Colors.transparent,
                shape: shape,
                clipBehavior: Clip.antiAlias,
                child: Ink(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: borderRadius,
                  ),
                  child: InkWell(
                    key: toggleKey,
                    onTap: canExpand ? onToggle : null,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        16,
                        16,
                        showButton ? 32 : 16,
                      ),
                      child: expanded && expandedChild != null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [child, expandedChild!],
                            )
                          : child,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (showButton)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(
                      context.appTokens.buttonRadius,
                    ),
                  ),
                  child: ExcludeSemantics(
                    child: OutlinedButton(
                      onPressed: onToggle,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(96, 48),
                        backgroundColor: scheme.surface,
                        foregroundColor: scheme.onSurface,
                        side: BorderSide(color: scheme.outline),
                        shape: const StadiumBorder(),
                      ),
                      child: Text(expanded ? AppStrings.less : AppStrings.more),
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

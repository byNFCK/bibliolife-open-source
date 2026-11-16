import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/features/book_details/presentation/models/book_details_formatters.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/expandable_book_details_section.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_section_heading.dart';
import 'package:flutter/material.dart';

class BookDescriptionPanel extends StatefulWidget {
  const BookDescriptionPanel({required this.description, super.key});

  final String? description;

  @override
  State<BookDescriptionPanel> createState() => _BookDescriptionPanelState();
}

class _BookDescriptionPanelState extends State<BookDescriptionPanel> {
  var _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final text = normalizeBookDetailsText(widget.description);
    if (text.isEmpty) return const SizedBox.shrink();
    final textStyle = Theme.of(context).textTheme.bodyLarge;

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(
            text: '${AppStrings.description}: $text',
            style: textStyle,
          ),
          maxLines: 3,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth - 32);
        final canExpand = painter.didExceedMaxLines;

        return BookDetailsSectionHeading(
          label: AppStrings.description,
          child: ExpandableBookDetailsSection(
            expanded: _expanded,
            canExpand: canExpand,
            semanticsLabel: text,
            toggleKey: const Key('description-toggle'),
            onToggle: _toggle,
            child: ExcludeSemantics(
              child: Text(
                text,
                key: const Key('book-description-text'),
                maxLines: _expanded ? null : 3,
                overflow: _expanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: textStyle,
              ),
            ),
          ),
        );
      },
    );
  }
}

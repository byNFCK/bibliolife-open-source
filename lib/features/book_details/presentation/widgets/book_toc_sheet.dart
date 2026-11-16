import 'package:bibliolife/features/book_details/domain/models/book_toc_snapshot.dart';
import 'package:bibliolife/shared/presentation/widgets/app_modal_sheet_scaffold.dart';
import 'package:flutter/material.dart';

/// Shared Flutter table-of-contents sheet and card presentation.
abstract final class BookTocPresentation {
  static const sheetRadius = 32.0;
  static const maxHeightFraction = .75;
  static const horizontalPadding = 20.0;
  static const headerTopPadding = 12.0;
  static const titleVerticalPadding = 12.0;
  static const dragHandleWidth = 36.0;
  static const dragHandleHeight = 4.0;
  static const listVerticalInset = 16.0;
  static const rowMinimumHeight = 48.0;
  static const rowRadius = 20.0;
  static const rowGap = 12.0;
  static const rowContentStart = 16.0;
  static const rowContentTop = 14.0;
  static const rowContentEnd = 8.0;
  static const rowContentBottom = 8.0;
  static const nestedIndent = 16.0;
  static const footerVerticalPadding = 12.0;
  static const cancelWidth = 160.0;
}

Future<T?> showBookTocSheet<T>({
  required BuildContext context,
  required List<BookTocEntry> entries,
  required ValueChanged<BookTocEntry> onOpen,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: false,
  enableDrag: true,
  backgroundColor: Colors.transparent,
  sheetAnimationStyle: appModalSheetAnimation,
  builder: (_) => BookTocModalSheet(entries: entries, onOpen: onOpen),
);

class BookTocModalSheet extends StatelessWidget {
  const BookTocModalSheet({
    required this.entries,
    required this.onOpen,
    super.key,
  });

  final List<BookTocEntry> entries;
  final ValueChanged<BookTocEntry> onOpen;

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: const Key('book-toc-drag-handle'),
    child: AppModalSheetScaffold(
      key: const Key('book-toc-modal'),
      title: 'Table of contents',
      maxHeightFactor: BookTocPresentation.maxHeightFraction,
      footer: const AppModalSheetSingleActionFooter(),
      child: BookTocSheet(entries: entries, onOpen: onOpen),
    ),
  );
}

class BookTocSheet extends StatelessWidget {
  const BookTocSheet({required this.entries, required this.onOpen, super.key});
  final List<BookTocEntry> entries;
  final ValueChanged<BookTocEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    final rows = <({BookTocEntry entry, int depth})>[];
    void flatten(List<BookTocEntry> values, int depth) {
      for (final entry in values) {
        rows.add((entry: entry, depth: depth));
        flatten(entry.children, depth + 1);
      }
    }

    flatten(entries, 0);
    return ListView.separated(
      key: const Key('book-toc-list'),
      padding: const EdgeInsets.symmetric(
        horizontal: BookTocPresentation.horizontalPadding,
        vertical: BookTocPresentation.listVerticalInset,
      ),
      itemCount: rows.length,
      separatorBuilder: (_, _) =>
          const SizedBox(height: BookTocPresentation.rowGap),
      itemBuilder: (context, index) {
        final row = rows[index];
        return _BookTocRow(row: row, index: index, onOpen: onOpen);
      },
    );
  }
}

class _BookTocRow extends StatelessWidget {
  const _BookTocRow({
    required this.row,
    required this.index,
    required this.onOpen,
  });
  final ({BookTocEntry entry, int depth}) row;
  final int index;
  final ValueChanged<BookTocEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final indent = row.depth.clamp(0, 3) * BookTocPresentation.nestedIndent;
    return Semantics(
      button: true,
      label: row.entry.title,
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BookTocPresentation.rowRadius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: InkWell(
          key: Key('book-toc-entry-$index'),
          borderRadius: BorderRadius.circular(BookTocPresentation.rowRadius),
          onTap: () => onOpen(row.entry),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: BookTocPresentation.rowMinimumHeight,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                BookTocPresentation.rowContentStart + indent,
                BookTocPresentation.rowContentTop,
                BookTocPresentation.rowContentEnd,
                BookTocPresentation.rowContentBottom,
              ),
              child: Text(
                row.entry.title,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

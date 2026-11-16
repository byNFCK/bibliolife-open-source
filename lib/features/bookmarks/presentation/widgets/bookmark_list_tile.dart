import 'package:bibliolife/features/bookmarks/domain/models/library_bookmark.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_modal_card.dart';
import 'package:flutter/material.dart';

class BookmarkListTile extends StatefulWidget {
  const BookmarkListTile({
    required this.bookmark,
    required this.onOpen,
    this.onEdit,
    this.showPagePosition = true,
    required this.onDelete,
    super.key,
  });
  final LibraryBookmark bookmark;
  final VoidCallback onOpen;
  final Future<void> Function()? onEdit;
  final bool showPagePosition;
  final Future<void> Function() onDelete;

  @override
  State<BookmarkListTile> createState() => _BookmarkListTileState();
}

class _BookmarkListTileState extends State<BookmarkListTile> {
  var _editing = false;
  var _deleting = false;

  Future<void> _edit() async {
    final onEdit = widget.onEdit;
    if (onEdit == null) return;
    if (_editing) return;
    setState(() => _editing = true);
    try {
      await onEdit();
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _delete() async {
    if (_deleting) return;
    setState(() => _deleting = true);
    try {
      await widget.onDelete();
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  String get _label =>
      widget.bookmark.title ??
      widget.bookmark.chapterTitle ??
      (!widget.showPagePosition || widget.bookmark.position == null
          ? null
          : 'Page ${widget.bookmark.position}') ??
      (widget.bookmark.progression == null
          ? 'Saved location'
          : '${(widget.bookmark.progression!.clamp(0, 1) * 100).round()}%');
  @override
  Widget build(BuildContext context) {
    return BookDetailsModalCard(
      title: _label,
      metadata: _subtitle,
      onTap: widget.onOpen,
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onEdit != null) ...[
            SizedBox.square(
              dimension: BookDetailsModalCardMetrics.actionTouchTarget,
              child: IconButton(
                tooltip: 'Edit bookmark',
                onPressed: _editing ? null : _edit,
                icon: const Icon(Icons.edit_outlined),
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: BookDetailsModalCardMetrics.actionGap),
          ],
          SizedBox.square(
            dimension: BookDetailsModalCardMetrics.actionTouchTarget,
            child: IconButton(
              tooltip: 'Delete bookmark',
              onPressed: _deleting ? null : _delete,
              icon: const Icon(Icons.delete_outline),
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String? get _subtitle {
    final values = <String>[];
    if (widget.bookmark.chapterTitle != null &&
        widget.bookmark.chapterTitle != _label) {
      values.add(widget.bookmark.chapterTitle!);
    }
    if (widget.bookmark.progression != null) {
      values.add(
        '${(widget.bookmark.progression!.clamp(0, 1) * 100).round()}%',
      );
    }
    if (widget.showPagePosition &&
        widget.bookmark.position != null &&
        _label != 'Page ${widget.bookmark.position}') {
      values.add('Page ${widget.bookmark.position}');
    }
    final note = widget.bookmark.note?.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (note != null && note.isNotEmpty) values.add(note);
    return values.isEmpty ? null : values.join(' • ');
  }
}

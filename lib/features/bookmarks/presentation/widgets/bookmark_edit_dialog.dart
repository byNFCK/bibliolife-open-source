import 'package:bibliolife/features/bookmarks/domain/models/bookmark_metadata_update.dart';
import 'package:bibliolife/features/bookmarks/domain/models/library_bookmark.dart';
import 'package:flutter/material.dart';

class BookmarkEditDialog extends StatefulWidget {
  const BookmarkEditDialog({
    required this.bookmark,
    required this.onSave,
    super.key,
  });
  final LibraryBookmark bookmark;
  final Future<void> Function(BookmarkMetadataUpdate update) onSave;
  @override
  State<BookmarkEditDialog> createState() => _BookmarkEditDialogState();
}

class _BookmarkEditDialogState extends State<BookmarkEditDialog> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  var _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.bookmark.title);
    _note = TextEditingController(text: widget.bookmark.note);
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        BookmarkMetadataUpdate(
          title: Changed(_title.text),
          note: Changed(_note.text),
        ),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not update bookmark. Try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit bookmark'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        TextField(
          controller: _note,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Note'),
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: const Text('Save'),
      ),
    ],
  );
}

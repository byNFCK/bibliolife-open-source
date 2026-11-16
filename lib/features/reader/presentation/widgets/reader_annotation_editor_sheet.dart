import 'package:bibliolife/features/reader/domain/models/reader_annotation.dart';
import 'package:flutter/material.dart';

/// Shared Flutter editor used for annotations opened from any reader surface.
class ReaderAnnotationEditorSheet extends StatefulWidget {
  const ReaderAnnotationEditorSheet({
    required this.annotation,
    required this.onSave,
    required this.onDelete,
    super.key,
  });

  final ReaderAnnotation annotation;
  final Future<void> Function(
    String? note,
    ReaderAnnotationStyle style,
    ReaderAnnotationColor color,
  )
  onSave;
  final Future<void> Function() onDelete;

  @override
  State<ReaderAnnotationEditorSheet> createState() =>
      _ReaderAnnotationEditorSheetState();
}

class _ReaderAnnotationEditorSheetState
    extends State<ReaderAnnotationEditorSheet> {
  late final TextEditingController _note = TextEditingController(
    text: widget.annotation.note ?? '',
  );
  late ReaderAnnotationStyle _style = widget.annotation.style;
  late ReaderAnnotationColor _color = widget.annotation.color;
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.onSave(_note.text, _style, _color);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await widget.onDelete();
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: 20,
      right: 20,
      top: 16,
      bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.annotation.selectedText,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          enabled: !_busy,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Note',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<ReaderAnnotationStyle>(
          initialValue: _style,
          decoration: const InputDecoration(labelText: 'Style'),
          items: [
            for (final value in ReaderAnnotationStyle.values)
              DropdownMenuItem(value: value, child: Text(value.storageValue)),
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() => _style = value ?? _style),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<ReaderAnnotationColor>(
          initialValue: _color,
          decoration: const InputDecoration(labelText: 'Color'),
          items: [
            for (final value in ReaderAnnotationColor.values)
              DropdownMenuItem(value: value, child: Text(value.storageValue)),
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() => _color = value ?? _color),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            TextButton(
              onPressed: _busy ? null : _delete,
              child: const Text('Delete'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    ),
  );
}

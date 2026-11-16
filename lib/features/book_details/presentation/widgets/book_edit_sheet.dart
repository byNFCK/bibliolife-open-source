import 'dart:typed_data';

import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/features/book_details/application/providers/book_cover_picker_provider.dart';
import 'package:bibliolife/features/book_details/application/providers/book_details_edit_service_provider.dart';
import 'package:bibliolife/features/book_details/application/providers/original_book_metadata_resolver_provider.dart';
import 'package:bibliolife/features/book_details/application/services/book_details_edit_service.dart';
import 'package:bibliolife/features/book_details/application/services/original_book_metadata_resolver.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_cover.dart';
import 'package:bibliolife/shared/models/book_cover_provenance.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BookEditSheet extends ConsumerStatefulWidget {
  const BookEditSheet({required this.book, super.key});

  final LibraryBook book;

  @override
  ConsumerState<BookEditSheet> createState() => _BookEditSheetState();
}

class _BookEditSheetState extends ConsumerState<BookEditSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _authorController;
  late final String _initialTitle;
  late final String _initialAuthor;
  Uint8List? _coverBytes;
  String? _coverExtension;
  BookCoverProvenance? _draftCoverProvenance;
  var _removeManualCover = false;
  var _clearCoverOnSave = false;
  var _cleanupReplacedManualCover = false;
  var _restoreApplied = false;
  var _restoring = false;
  var _saving = false;
  var _saved = false;
  var _pickingCover = false;
  String? _error;
  List<String>? _restoredAuthors;
  String? _restoredAuthor;

  @override
  void initState() {
    super.initState();
    _initialTitle = widget.book.title;
    _initialAuthor = widget.book.author ?? widget.book.authors.join(', ');
    _titleController = TextEditingController(text: widget.book.title);
    _authorController = TextEditingController(text: _initialAuthor);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    if (_pickingCover || _saving || _restoring) return;
    setState(() {
      _pickingCover = true;
      _error = null;
    });
    try {
      final picked = await ref.read(bookCoverPickerProvider).pickCover();
      if (picked != null && mounted) {
        setState(() {
          _coverBytes = picked.bytes;
          _coverExtension = picked.extension;
          _draftCoverProvenance = BookCoverProvenance.manual;
          _removeManualCover = false;
          _clearCoverOnSave = false;
          _cleanupReplacedManualCover = _restoreApplied;
        });
      }
    } on Object {
      if (mounted) setState(() => _error = AppStrings.bookCoverPickError);
    } finally {
      if (mounted) setState(() => _pickingCover = false);
    }
  }

  void _removeCover() {
    setState(() {
      _coverBytes = null;
      _coverExtension = null;
      _draftCoverProvenance = null;
      if (_restoreApplied) {
        _clearCoverOnSave = true;
        _removeManualCover = false;
        _cleanupReplacedManualCover = true;
      } else {
        _clearCoverOnSave = false;
        _removeManualCover =
            widget.book.coverProvenance == BookCoverProvenance.manual;
      }
      _error = null;
    });
  }

  Future<void> _restoreOriginal() async {
    if (_restoring || _saving || _pickingCover) return;
    setState(() {
      _restoring = true;
      _error = null;
    });
    try {
      final original = await ref
          .read(originalBookMetadataResolverProvider)
          .resolve(widget.book);
      if (!mounted) return;
      setState(() {
        _titleController.text = original.title;
        _authorController.text = original.author ?? '';
        _restoredAuthor = original.author;
        _restoredAuthors = original.authors;
        _restoreApplied = true;
        _coverBytes = original.coverBytes;
        _coverExtension = original.coverExtension;
        _draftCoverProvenance = original.coverBytes == null
            ? null
            : BookCoverProvenance.embedded;
        _clearCoverOnSave = original.coverBytes == null;
        _removeManualCover = false;
        _cleanupReplacedManualCover = true;
      });
    } on OriginalBookMetadataUnavailable {
      if (mounted) setState(() => _error = AppStrings.restoreOriginalError);
    } on Object {
      if (mounted) setState(() => _error = AppStrings.restoreOriginalError);
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = AppStrings.bookEditInvalidTitle);
      return;
    }
    if (_saving || _pickingCover || _restoring) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final authorUnchangedSinceRestore =
        _restoreApplied &&
        _authorController.text.trim() == (_restoredAuthor ?? '').trim();
    try {
      await ref
          .read(bookDetailsEditServiceProvider)
          .save(
            bookId: widget.book.id,
            title: title,
            author: _authorController.text,
            updateTitle: _restoreApplied || title != _initialTitle.trim(),
            updateAuthor:
                _restoreApplied ||
                _authorController.text.trim() != _initialAuthor.trim(),
            replacementCoverBytes: _coverBytes,
            replacementCoverExtension: _coverExtension,
            replacementCoverProvenance: _draftCoverProvenance,
            replacementAuthors: authorUnchangedSinceRestore
                ? _restoredAuthors
                : null,
            removeManualCover: _removeManualCover,
            clearCover: _clearCoverOnSave,
            cleanupReplacedManualCover: _cleanupReplacedManualCover,
          );
      if (mounted) {
        _saved = true;
        Navigator.of(context).pop(true);
      }
    } on InvalidBookTitle {
      if (mounted) setState(() => _error = AppStrings.bookEditInvalidTitle);
    } on InvalidBookCover {
      if (mounted) setState(() => _error = AppStrings.collectionCoverInvalid);
    } on Object {
      if (mounted) setState(() => _error = AppStrings.bookEditSaveError);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasManualCover =
        widget.book.coverProvenance == BookCoverProvenance.manual;
    return PopScope<void>(
      canPop: (!_saving || _saved) && !_pickingCover && !_restoring,
      child: LayoutBuilder(
        builder: (context, constraints) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppStrings.editBook,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      key: const Key('book-edit-cancel'),
                      tooltip: AppStrings.cancel,
                      onPressed: _saving || _pickingCover || _restoring
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Center(
                  child: SizedBox(
                    width: 168,
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: _coverBytes == null
                          ? (_removeManualCover || _clearCoverOnSave)
                                ? const _MissingCoverPreview()
                                : BookDetailsCover(book: widget.book)
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.memory(
                                _coverBytes!,
                                key: const Key('book-edit-selected-cover'),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const _MissingCoverPreview(),
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      key: const Key('book-edit-change-cover'),
                      onPressed: _saving || _pickingCover ? null : _pickCover,
                      icon: _pickingCover
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.image_outlined),
                      label: const Text(AppStrings.changeBookCover),
                    ),
                    if (hasManualCover ||
                        _coverBytes != null ||
                        _clearCoverOnSave)
                      TextButton.icon(
                        key: const Key('book-edit-remove-cover'),
                        onPressed: _saving || _restoring || _pickingCover
                            ? null
                            : _removeCover,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text(AppStrings.removeBookCover),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('book-edit-restore-original'),
                    onPressed: _saving || _pickingCover || _restoring
                        ? null
                        : _restoreOriginal,
                    icon: _restoring
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.restore),
                    label: const Text(AppStrings.restoreOriginal),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('book-edit-title'),
                  controller: _titleController,
                  enabled: !_saving && !_restoring,
                  maxLines: 1,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: AppStrings.bookTitle,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('book-edit-author'),
                  controller: _authorController,
                  enabled: !_saving && !_restoring,
                  maxLines: 1,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: AppStrings.author,
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    key: const Key('book-edit-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving || _pickingCover || _restoring
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text(AppStrings.cancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const Key('book-edit-save'),
                        onPressed: _saving || _pickingCover || _restoring
                            ? null
                            : _save,
                        child: _saving
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(AppStrings.save),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MissingCoverPreview extends StatelessWidget {
  const _MissingCoverPreview();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Center(child: Icon(Icons.menu_book_outlined, size: 48)),
  );
}

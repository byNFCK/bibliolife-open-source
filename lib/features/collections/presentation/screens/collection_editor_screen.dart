import 'package:bibliolife/features/collections/presentation/system_collection_colors.dart';
import 'package:bibliolife/features/collections/domain/models/system_collection.dart';
import 'dart:async';
import 'dart:io';

import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/features/collections/application/providers/collection_editor_providers.dart';
import 'package:bibliolife/features/collections/application/providers/collection_providers.dart';
import 'package:bibliolife/features/collections/application/providers/collection_repository_provider.dart';
import 'package:bibliolife/features/collections/domain/models/library_collection.dart';
import 'package:bibliolife/features/collections/domain/repositories/collection_repository.dart';
import 'package:bibliolife/features/collections/presentation/widgets/collection_book_selector_sheet.dart';
import 'package:bibliolife/features/collections/presentation/widgets/collection_draft_books_sliver.dart';
import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:bibliolife/features/collections/presentation/widgets/collection_cover.dart';
import 'package:bibliolife/features/library/application/providers/library_providers.dart';
import 'package:bibliolife/features/metadata/application/providers/cover_storage_service_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

class CollectionEditorScreen extends ConsumerStatefulWidget {
  const CollectionEditorScreen({
    this.collectionId,
    this.initialBookIds = const <String>{},
    super.key,
  });

  final String? collectionId;
  final Set<String> initialBookIds;

  bool get isCreate => collectionId == null;

  @override
  ConsumerState<CollectionEditorScreen> createState() =>
      _CollectionEditorScreenState();
}

class _CollectionEditorScreenState
    extends ConsumerState<CollectionEditorScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  final _nameFocusNode = FocusNode();
  final _descriptionFocusNode = FocusNode();
  final _uuid = const Uuid();

  Set<String> _selectedBookIds = const {};
  Set<String> _initialBookIds = const {};
  String? _initialCoverPath;
  String? _draftCoverPath;
  String? _initialName;
  String? _initialDescription;
  final _bookScrollController = ScrollController(keepScrollOffset: false);
  final _layoutOffsets = <LibraryViewMode, double>{};
  late LibraryViewMode _layoutMode;
  int _layoutRevision = 0;
  bool _restoringLayout = false;
  bool _ready = false;
  bool _saving = false;
  bool _handlingBack = false;
  bool _saved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _layoutMode = ref.read(libraryViewModeProvider);
    _nameController = TextEditingController();
    _descriptionController = TextEditingController();
    _selectedBookIds = Set.unmodifiable(widget.initialBookIds);
    _initialBookIds = Set.unmodifiable(widget.initialBookIds);
    if (widget.isCreate) {
      _ready = true;
    } else {
      unawaited(_loadExisting());
    }
  }

  @override
  void dispose() {
    _bookScrollController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _nameFocusNode.dispose();
    _descriptionFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    try {
      final collection = await ref.read(
        collectionByIdProvider(widget.collectionId!).future,
      );
      if (collection == null) throw CollectionNotFound(widget.collectionId!);
      final books = await ref.read(
        booksInCollectionProvider(widget.collectionId!).future,
      );
      if (!mounted) return;
      _nameController.text = collection.name;
      _descriptionController.text = collection.description ?? '';
      _initialName = collection.name;
      _initialDescription = _trimmedDescription(_descriptionController.text);
      _initialBookIds = Set.unmodifiable(books.map((book) => book.id));
      _selectedBookIds = Set.of(_initialBookIds);
      _initialCoverPath = collection.customCoverPath;
      _draftCoverPath = collection.customCoverPath;
      setState(() => _ready = true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _ready = true;
          _error = AppStrings.collectionLoadError;
        });
      }
    }
  }

  bool get _hasValidName =>
      CollectionName.tryParse(_nameController.text) != null;

  bool get _isDirty {
    if (!_ready) return false;
    final name = CollectionName.tryParse(_nameController.text)?.displayName;
    final description = _trimmedDescription(_descriptionController.text);
    if (widget.isCreate) {
      return _nameController.text.isNotEmpty ||
          description != null ||
          _draftCoverPath != null ||
          !_selectedBookIds.equalTo(_initialBookIds);
    }
    return name != _initialName ||
        description != _initialDescription ||
        _draftCoverPath != _initialCoverPath ||
        !_selectedBookIds.equalTo(_initialBookIds);
  }

  String? _trimmedDescription(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _pickCover() async {
    try {
      final picked = await ref.read(collectionCoverPickerProvider).pickCover();
      if (picked == null || !mounted) return;
      final storage = ref.read(coverStorageServiceProvider);
      final stored = await storage.storeValidatedCollectionCover(
        collectionKey: 'draft-${_uuid.v4()}',
        bytes: picked.bytes,
        extension: picked.extension,
      );
      if (!mounted) return;
      if (stored == null) {
        setState(() => _error = AppStrings.collectionCoverInvalid);
        return;
      }
      final previousDraft = _draftCoverPath;
      if (_isTemporaryCover(previousDraft)) {
        await storage.deleteStoredCover(previousDraft);
      }
      setState(() {
        _draftCoverPath = stored;
        _error = null;
      });
    } on Object {
      if (mounted) {
        setState(() => _error = AppStrings.collectionCoverSaveError);
      }
    }
  }

  Future<void> _removeCover() async {
    final previousDraft = _draftCoverPath;
    if (_isTemporaryCover(previousDraft)) {
      await ref
          .read(coverStorageServiceProvider)
          .deleteStoredCover(previousDraft);
    }
    if (mounted) {
      setState(() {
        _draftCoverPath = null;
        _error = null;
      });
    }
  }

  bool _isTemporaryCover(String? path) =>
      path != null && path != _initialCoverPath;

  Future<void> _openBookSelector() async {
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CollectionBookSelectorSheet(
        initialSelectedBookIds: _selectedBookIds,
        accentScheme: systemCollectionColorScheme(
          widget.collectionId ?? '',
          Theme.of(context).brightness,
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _selectedBookIds = Set.unmodifiable(selected));
    }
  }

  void _removeBook(String bookId) {
    setState(() {
      _selectedBookIds = Set.unmodifiable(
        _selectedBookIds.where((id) => id != bookId),
      );
    });
  }

  Future<void> _save() async {
    if (_saving || !_ready) return;
    if (!_hasValidName) {
      setState(() => _error = AppStrings.collectionInvalidName);
      _nameFocusNode.requestFocus();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final repository = ref.read(collectionRepositoryProvider);
    final finalCoverPath = _draftCoverPath;
    try {
      final saved = await repository.saveEditor(
        collectionId: widget.collectionId,
        name: _nameController.text,
        description: _descriptionController.text,
        customCoverPath: finalCoverPath,
        selectedBookIds: _selectedBookIds,
      );
      if (_initialCoverPath != null && _initialCoverPath != finalCoverPath) {
        await ref
            .read(coverStorageServiceProvider)
            .deleteStoredCover(_initialCoverPath);
      }
      _saved = true;
      if (mounted) Navigator.of(context).pop(saved);
    } on InvalidCollectionName {
      if (mounted) setState(() => _error = AppStrings.collectionInvalidName);
    } on DuplicateCollectionName {
      if (mounted) setState(() => _error = AppStrings.collectionDuplicateName);
    } on CollectionBookNotFound {
      if (mounted) {
        setState(() => _error = 'One selected book is no longer available.');
      }
    } on CollectionRepositoryFailure {
      if (mounted) setState(() => _error = AppStrings.collectionSaveError);
    } catch (_) {
      if (mounted) setState(() => _error = AppStrings.collectionSaveError);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleBack() async {
    if (_handlingBack || _saved) return;
    _handlingBack = true;
    try {
      var discard = true;
      if (_isDirty) {
        discard =
            await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text(AppStrings.discardChanges),
                content: const Text('Your changes have not been saved.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text(AppStrings.cancel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text(AppStrings.discard),
                  ),
                ],
              ),
            ) ??
            false;
      }
      if (!discard) return;
      await _cleanupTemporaryCover();
      if (mounted) Navigator.of(context).pop();
    } finally {
      _handlingBack = false;
    }
  }

  Future<void> _cleanupTemporaryCover() async {
    if (_isTemporaryCover(_draftCoverPath)) {
      await ref
          .read(coverStorageServiceProvider)
          .deleteStoredCover(_draftCoverPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SystemCollectionTheme(
      collectionId: widget.collectionId ?? '',
      child: PopScope<void>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_handleBack());
        },
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              key: const Key('collection-editor-back'),
              tooltip: AppStrings.back,
              onPressed: _handleBack,
              icon: const Icon(Icons.arrow_back),
            ),
            title: Text(
              widget.isCreate
                  ? AppStrings.createCollection
                  : AppStrings.editCollection,
            ),
            actions: [
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _nameController,
                builder: (context, _, _) => IconButton(
                  key: const Key('collection-editor-save'),
                  tooltip: AppStrings.save,
                  onPressed: _saving || !_ready || !_hasValidName
                      ? null
                      : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                ),
              ),
            ],
          ),
          body: !_ready
              ? const Center(child: CircularProgressIndicator())
              : _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final allBooks = ref.watch(allBooksProvider);
    final mode = ref.watch(libraryViewModeProvider);
    if (!_bookScrollController.hasClients) _layoutMode = mode;
    ref.listen(libraryViewModeProvider, (_, next) {
      if (_bookScrollController.hasClients && !_restoringLayout) {
        _layoutOffsets[_layoutMode] = _bookScrollController.offset;
      }
      _layoutMode = next;
      final revision = ++_layoutRevision;
      _restoringLayout = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            revision != _layoutRevision ||
            !_bookScrollController.hasClients) {
          return;
        }
        final position = _bookScrollController.position;
        _bookScrollController.jumpTo(
          (_layoutOffsets[next] ?? 0)
              .clamp(position.minScrollExtent, position.maxScrollExtent)
              .toDouble(),
        );
        _restoringLayout = false;
      });
    });
    final books = allBooks.asData?.value
        .where((book) => _selectedBookIds.contains(book.id))
        .toList(growable: false);
    return CustomScrollView(
      key: const Key('collection-editor-scroll'),
      controller: _bookScrollController,
      slivers: [
        if (_error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                _error!,
                key: const Key('collection-editor-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CollectionCoverUploader(
                  path: _draftCoverPath,
                  onPick: _pickCover,
                  onRemove: _draftCoverPath == null ? null : _removeCover,
                ),
                const SizedBox(height: 20),
                TextField(
                  key: const Key('collection-editor-name'),
                  readOnly:
                      widget.collectionId != null &&
                      isSystemCollection(widget.collectionId!),
                  controller: _nameController,
                  focusNode: _nameFocusNode,
                  maxLength: 60,
                  maxLines: 1,
                  buildCounter: _counterBuilder(
                    const Key('collection-editor-name-counter'),
                  ),
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _descriptionFocusNode.requestFocus(),
                  decoration: InputDecoration(
                    labelText: AppStrings.collectionName,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('collection-editor-description'),
                  controller: _descriptionController,
                  focusNode: _descriptionFocusNode,
                  maxLength: 5000,
                  minLines: 4,
                  maxLines: 6,
                  buildCounter: _counterBuilder(
                    const Key('collection-editor-description-counter'),
                  ),
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    labelText: AppStrings.description,
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('collection-editor-add-book'),
                    onPressed: _openBookSelector,
                    icon: const Icon(Icons.add),
                    label: const Text(AppStrings.addBook),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 12),
                Text(
                  AppStrings.addedBooks,
                  key: const Key('collection-editor-added-books-heading'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        if (allBooks.hasError)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Could not load books.'),
            ),
          )
        else if (allBooks.isLoading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (books == null || books.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: Text(AppStrings.noBooksAddedYet),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              mode == LibraryViewMode.grid ? 16 : 0,
              0,
              mode == LibraryViewMode.grid ? 16 : 0,
              32,
            ),
            sliver: CollectionDraftBooksSliver(
              books: books,
              mode: mode,
              itemPrefix: 'collection-editor-book',
              actionBuilder: (book) => IconButton(
                key: ValueKey('collection-editor-remove-${book.id}'),
                tooltip: 'Remove ${book.title}',
                onPressed: () => _removeBook(book.id),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
      ],
    );
  }

  InputCounterWidgetBuilder _counterBuilder(Key key) =>
      (context, {required currentLength, required isFocused, maxLength}) =>
          Text('$currentLength / $maxLength', key: key);
}

class _CollectionCoverUploader extends StatelessWidget {
  const _CollectionCoverUploader({
    required this.path,
    required this.onPick,
    required this.onRemove,
  });

  final String? path;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: path == null ? AppStrings.uploadCover : AppStrings.changeCover,
      child: InkWell(
        key: const Key('collection-editor-cover-uploader'),
        onTap: onPick,
        borderRadius: CollectionCover.borderRadius,
        child: CollectionCover(
          key: const Key('collection-editor-cover-viewport'),
          imageFile: path == null ? null : File(path!),
          placeholder: CollectionCoverPlaceholder(
            style: path == null
                ? CollectionCoverPlaceholderStyle.editorUpload
                : CollectionCoverPlaceholderStyle.editorImage,
          ),
          semanticLabel: AppStrings.collectionCover,
          imageKey: const Key('collection-editor-custom-cover'),
          cacheWidth: 480,
          diagnosticSourceType: 'custom-collection-editor',
          diagnosticId: path,
          diagnosticProfile: 'details',
          overlay: path == null
              ? null
              : Positioned(
                  top: 8,
                  right: 8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CoverAction(
                        key: const Key('collection-editor-change-cover'),
                        tooltip: AppStrings.changeCover,
                        icon: Icons.edit_outlined,
                        onPressed: onPick,
                      ),
                      if (onRemove != null)
                        _CoverAction(
                          key: const Key('collection-editor-remove-cover'),
                          tooltip: AppStrings.removeCover,
                          icon: Icons.delete_outline,
                          onPressed: onRemove!,
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _CoverAction extends StatelessWidget {
  const _CoverAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.88),
    shape: const CircleBorder(),
    child: IconButton(tooltip: tooltip, onPressed: onPressed, icon: Icon(icon)),
  );
}

extension on Set<String> {
  bool equalTo(Set<String> other) =>
      length == other.length && containsAll(other);
}

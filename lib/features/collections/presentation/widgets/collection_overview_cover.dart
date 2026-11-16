import 'dart:io';

import 'package:bibliolife/features/collections/presentation/widgets/collection_book_cover.dart';
import 'package:bibliolife/features/collections/presentation/widgets/collection_cover.dart';
import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/features/metadata/application/providers/cover_storage_service_provider.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CollectionOverviewCover extends ConsumerStatefulWidget {
  const CollectionOverviewCover({
    required this.collectionId,
    required this.customCoverPath,
    required this.books,
    super.key,
  });

  final String collectionId;
  final String? customCoverPath;
  final List<LibraryBook> books;

  @override
  ConsumerState<CollectionOverviewCover> createState() =>
      _CollectionOverviewCoverState();
}

class _CollectionOverviewCoverState
    extends ConsumerState<CollectionOverviewCover> {
  Future<bool>? _customCoverValidity;
  String? _validatedPath;

  @override
  void initState() {
    super.initState();
    _refreshCustomCoverValidation();
  }

  @override
  void didUpdateWidget(covariant CollectionOverviewCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customCoverPath != widget.customCoverPath) {
      _refreshCustomCoverValidation();
    }
  }

  void _refreshCustomCoverValidation() {
    final path = widget.customCoverPath;
    _validatedPath = path;
    _customCoverValidity = path == null
        ? null
        : ref.read(coverStorageServiceProvider).hasValidStoredCover(path);
  }

  @override
  Widget build(BuildContext context) {
    return _buildCover(context);
  }

  Widget _buildCover(BuildContext context) {
    final validity = _customCoverValidity;
    if (validity == null || _validatedPath == null) {
      return CollectionCover(
        key: const Key('collection-details-cover'),
        placeholder: _RecentBookCoverPreview(books: widget.books),
        semanticLabel: AppStrings.collectionCover,
      );
    }
    return FutureBuilder<bool>(
      future: validity,
      builder: (context, snapshot) {
        final valid = snapshot.data == true;
        return CollectionCover(
          key: const Key('collection-details-cover'),
          imageFile: valid ? File(_validatedPath!) : null,
          placeholder: valid
              ? const CollectionCoverPlaceholder(
                  style: CollectionCoverPlaceholderStyle.detailsImageError,
                )
              : _RecentBookCoverPreview(books: widget.books),
          semanticLabel: AppStrings.collectionCover,
          imageKey: valid ? const Key('collection-details-custom-cover') : null,
          cacheWidth: 720,
          diagnosticSourceType: 'custom-collection-details',
          diagnosticId: widget.collectionId,
          diagnosticProfile: 'details',
        );
      },
    );
  }
}

class _RecentBookCoverPreview extends StatelessWidget {
  const _RecentBookCoverPreview({required this.books});

  final List<LibraryBook> books;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visibleBooks = books.take(3).toList(growable: false);
    if (visibleBooks.isEmpty) {
      return const CollectionCoverPlaceholder(
        style: CollectionCoverPlaceholderStyle.details,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.surfaceContainerHigh, colors.surfaceContainer],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final centerHeight = constraints.maxHeight * 0.9;
          final centerWidth = centerHeight * 0.66;
          final sideWidth = centerWidth * 0.82;
          final sideHeight = sideWidth / 0.66;
          final centerX = constraints.maxWidth / 2;
          final sideOffset = centerWidth * 0.64;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (visibleBooks.length >= 3)
                _positionedBook(
                  book: visibleBooks[1],
                  left: centerX - sideOffset - sideWidth / 2,
                  top: (constraints.maxHeight - sideHeight) / 2 + 8,
                  width: sideWidth,
                  height: sideHeight,
                ),
              if (visibleBooks.length >= 2)
                _positionedBook(
                  book: visibleBooks.last,
                  left: centerX + sideOffset - sideWidth / 2,
                  top: (constraints.maxHeight - sideHeight) / 2 + 8,
                  width: sideWidth,
                  height: sideHeight,
                ),
              _positionedBook(
                book: visibleBooks.first,
                left: centerX - centerWidth / 2,
                top: (constraints.maxHeight - centerHeight) / 2,
                width: centerWidth,
                height: centerHeight,
                prominent: true,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _positionedBook({
    required LibraryBook book,
    required double left,
    required double top,
    required double width,
    required double height,
    bool prominent = false,
  }) {
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: prominent
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: CollectionBookCover(book: book),
        ),
      ),
    );
  }
}

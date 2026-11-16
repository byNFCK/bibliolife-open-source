import 'package:bibliolife/shared/models/book_cover_reference.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_image.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_render_profile.dart';
import 'package:flutter/material.dart';

class CollectionBookCover extends StatelessWidget {
  const CollectionBookCover({required this.book, super.key});

  final LibraryBook book;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BookCoverImage(
      cover: book.coverPath == null
          ? const BookCoverReference.missing()
          : BookCoverReference.local(book.coverPath!),
      title: book.title,
      diagnosticSourceType: 'collection-details-preview',
      diagnosticId: 'book:${book.id}',
      placeholder: ColoredBox(
        color: scheme.secondaryContainer,
        child: Center(
          child: Icon(
            Icons.menu_book_outlined,
            size: 44,
            color: scheme.onSecondaryContainer,
          ),
        ),
      ),
      profile: BookCoverRenderProfile.localLibraryGrid,
    );
  }
}

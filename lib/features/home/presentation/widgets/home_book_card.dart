import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:bibliolife/features/home/domain/models/book_reading_progress.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_book_card.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter/material.dart';

class HomeBookCard extends StatelessWidget {
  const HomeBookCard({
    required this.book,
    this.progress,
    this.onOpen,
    super.key,
  });

  final LibraryBook book;
  final BookReadingProgress? progress;
  final ValueChanged<String>? onOpen;

  @override
  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return SizedBox(
      width: tokens.bookCardWidth,
      child: LibraryBookCard(
        book: book,
        progressPercent: progress?.percent ?? 0,
        onOpen: onOpen,
      ),
    );
  }
}

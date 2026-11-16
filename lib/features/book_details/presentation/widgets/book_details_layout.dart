import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:bibliolife/features/book_details/presentation/models/book_details_formatters.dart';
import 'package:bibliolife/features/book_details/presentation/models/book_details_view_data.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_description_panel.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_cover.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_metadata_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

class BookDetailsLayout extends StatelessWidget {
  static const _contentConstraints = BoxConstraints(maxWidth: 720);

  const BookDetailsLayout({
    required this.data,
    required this.onBack,
    required this.cover,
    required this.primaryAction,
    this.afterPrimaryAction = const [],
    this.trailingContent = const [],
    super.key,
  });

  final BookDetailsViewData data;
  final VoidCallback onBack;
  final BookDetailsCover cover;
  final Widget primaryAction;
  final List<Widget> afterPrimaryAction;
  final List<Widget> trailingContent;

  @override
  Widget build(BuildContext context) {
    final title = normalizeBookDetailsText(data.title).isEmpty
        ? AppStrings.untitledBook
        : normalizeBookDetailsText(data.title);
    final author = data.authors
        .map(normalizeBookDetailsText)
        .where((value) => value.isNotEmpty)
        .join(', ');
    final description = normalizeBookDetailsText(data.description);
    final tokens = context.appTokens;
    final backButton = BookDetailsBackButton(
      onPressed: onBack,
      overArtwork: cover.isHero,
    );
    return CustomScrollView(
      key: const PageStorageKey('book-details-scroll'),
      slivers: [
        if (cover.isHero)
          SliverToBoxAdapter(
            child: Stack(
              children: [
                cover,
                SafeArea(
                  bottom: false,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: _contentConstraints,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: tokens.pagePadding,
                        ),
                        child: Align(
                          alignment: AlignmentDirectional.topStart,
                          heightFactor: 1,
                          child: Semantics(
                            sortKey: const OrdinalSortKey(0),
                            child: backButton,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        SliverToBoxAdapter(
          child: SafeArea(
            top: false,
            bottom: false,
            left: cover.isHero,
            right: cover.isHero,
            child: Center(
              child: ConstrainedBox(
                constraints: _contentConstraints,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    tokens.pagePadding,
                    cover.isHero ? 6 : 4,
                    tokens.pagePadding,
                    48,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!cover.isHero) ...[
                        backButton,
                        const SizedBox(height: 12),
                        cover,
                        const SizedBox(height: 24),
                      ],
                      Text(
                        title,
                        key: const Key('book-details-title'),
                        maxLines: cover.isHero ? null : 2,
                        overflow: cover.isHero ? null : TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (author.isNotEmpty) ...[
                        SizedBox(height: cover.isHero ? 8 : 12),
                        BookDetailsAuthorRow(author: author),
                      ],
                      SizedBox(height: cover.isHero ? 14 : 18),
                      primaryAction,
                      for (final widget in afterPrimaryAction) ...[
                        const SizedBox(height: 18),
                        widget,
                      ],
                      const SizedBox(height: 28),
                      if (description.isNotEmpty) ...[
                        BookDescriptionPanel(description: description),
                        const SizedBox(height: 24),
                      ],
                      BookMoreInformationSection.fromViewData(data: data),
                      const SizedBox(height: 16),
                      BookMetadataProvenanceNote.fromViewData(data: data),
                      for (final widget in trailingContent) ...[
                        const SizedBox(height: 16),
                        widget,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class BookDetailsAuthorRow extends StatelessWidget {
  const BookDetailsAuthorRow({required this.author, super.key});

  final String author;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${AppStrings.author}, $author',
    child: ExcludeSemantics(
      child: Row(
        key: const Key('book-author'),
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.history_edu_outlined,
            size: 22,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              author,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class BookDetailsBackButton extends StatelessWidget {
  const BookDetailsBackButton({
    required this.onPressed,
    this.overArtwork = false,
    super.key,
  });

  final VoidCallback onPressed;
  final bool overArtwork;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      key: const Key('book-details-back'),
      tooltip: AppStrings.back,
      onPressed: onPressed,
      iconSize: overArtwork ? 42 : null,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(48),
        padding: overArtwork ? EdgeInsets.zero : null,
        backgroundColor: overArtwork
            ? Colors.transparent
            : colors.surfaceContainerLow,
        foregroundColor: colors.onSurfaceVariant,
      ),
      icon: overArtwork
          ? Icon(
              Icons.chevron_left_rounded,
              color: colors.onSurface,
              shadows: [Shadow(color: colors.surface, blurRadius: 4)],
            )
          : const Icon(Icons.arrow_back),
    );
  }
}

import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/presentation/widgets/remote_catalog_book_card.dart';
import 'package:bibliolife/features/catalog_sources/presentation/widgets/remote_catalog_book_tile.dart';
import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:flutter/material.dart';

/// Shared lazy publication region; callers retain lifecycle, routing and scroll.
class RemoteCatalogPublicationSliver extends StatelessWidget {
  const RemoteCatalogPublicationSliver({
    required this.publications,
    required this.onOpen,
    required this.sourceId,
    required this.mode,
    this.gridKey = const Key('catalog-publication-grid'),
    this.listKey = const Key('catalog-publication-list'),
    this.itemKeyPrefix = 'catalog-publication',
    super.key,
  });

  final List<RemoteCatalogPublicationSummary> publications;
  final ValueChanged<RemoteCatalogPublicationSummary> onOpen;
  final String sourceId;
  final LibraryViewMode mode;
  final Key gridKey;
  final Key listKey;
  final String itemKeyPrefix;

  @override
  Widget build(BuildContext context) {
    if (mode == LibraryViewMode.list) {
      return SliverList.builder(
        key: listKey,
        itemCount: publications.length,
        addAutomaticKeepAlives: false,
        itemBuilder: (context, index) => RemoteCatalogBookTile(
          key: ValueKey('$itemKeyPrefix-${publications[index].remoteId}'),
          publication: publications[index],
          sourceId: sourceId,
          onOpen: () => onOpen(publications[index]),
        ),
      );
    }
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = switch (constraints.crossAxisExtent) {
          < 600 => 2,
          < 900 => 3,
          _ => 4,
        };
        final gap = context.appTokens.bookCardGridGap;
        final width =
            (constraints.crossAxisExtent - gap * (crossAxisCount - 1)) /
            crossAxisCount;
        // Lazy rows retain natural metadata height and the shared theme gap.
        // A fixed-extent SliverGrid would change the existing card geometry.
        return SliverList.separated(
          key: gridKey,
          itemCount: (publications.length / crossAxisCount).ceil(),
          addAutomaticKeepAlives: false,
          itemBuilder: (context, row) {
            final first = row * crossAxisCount;
            return Row(
              key: ValueKey('catalog-row-${publications[first].remoteId}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (
                  var column = 0;
                  column < crossAxisCount &&
                      first + column < publications.length;
                  column++
                ) ...[
                  if (column > 0) SizedBox(width: gap),
                  SizedBox(
                    width: width,
                    child: RemoteCatalogBookCard(
                      key: ValueKey(
                        '$itemKeyPrefix-${publications[first + column].remoteId}',
                      ),
                      publication: publications[first + column],
                      onOpen: () => onOpen(publications[first + column]),
                      sourceId: sourceId,
                    ),
                  ),
                ],
              ],
            );
          },
          separatorBuilder: (_, _) => SizedBox(height: gap),
        );
      },
    );
  }
}

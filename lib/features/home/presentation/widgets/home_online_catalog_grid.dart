import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_book_tile.dart';
import 'package:bibliolife/features/catalog_sources/presentation/widgets/remote_catalog_book_tile.dart';
import 'package:bibliolife/shared/presentation/widgets/app_book_list_tile.dart';
import 'package:bibliolife/app/router/book_details_navigation.dart';
import 'package:bibliolife/app/theme/app_spacing.dart';
import 'package:bibliolife/app/theme/app_theme_tokens.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/remote_publication_details_screen.dart';
import 'package:bibliolife/features/catalog_sources/presentation/widgets/remote_catalog_book_card.dart';
import 'package:bibliolife/features/home/domain/models/online_home_section.dart';
import 'package:bibliolife/features/home/domain/models/home_online_book_state.dart';
import 'package:bibliolife/features/home/domain/models/remote_home_publication_identity.dart';
import 'package:bibliolife/features/home/application/providers/home_online_state_provider.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_book_card.dart';
import 'package:bibliolife/shared/presentation/widgets/app_book_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HomeOnlineCatalogGrid extends StatelessWidget {
  const HomeOnlineCatalogGrid({
    required this.books,
    this.slots = const [],
    this.mode = LibraryViewMode.grid,
    super.key,
  });

  final List<OnlineHomeBook> books;
  final List<OnlineHomeSlot> slots;
  final LibraryViewMode mode;

  @override
  Widget build(BuildContext context) {
    final visibleSlots = slots.isEmpty
        ? [
            for (var index = 0; index < books.length; index++)
              OnlineHomeSlot.loaded(
                slotId: index,
                sourceIndex: index,
                attempt: 0,
                book: books[index],
              ),
          ]
        : slots;
    if (mode == LibraryViewMode.list) {
      return SliverPadding(
        padding: EdgeInsets.zero,
        sliver: SliverList.builder(
          key: const PageStorageKey('home-online-list'),
          itemCount: visibleSlots.length,
          addAutomaticKeepAlives: false,
          findChildIndexCallback: (key) => _slotIndexForKey(key, visibleSlots),
          itemBuilder: (_, index) {
            final slot = visibleSlots[index];
            return _HomeOnlineGridSlot(
              key: _slotKey(slot),
              child: slot.isPending
                  ? const HomeOnlineReservedBookRow()
                  : _HomeOnlineBookCard(
                      key: _bookKey(slot.book!),
                      book: slot.book!,
                      isList: true,
                    ),
            );
          },
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
        final gridWidth = constraints.crossAxisExtent - AppSpacing.md * 2;
        final tileWidth =
            (gridWidth - gap * (crossAxisCount - 1)) / crossAxisCount;
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          sliver: SliverGrid(
            key: const PageStorageKey('home-online-grid'),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: gap,
              crossAxisSpacing: gap,
              mainAxisExtent: _cardExtent(context, tileWidth),
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final slot = visibleSlots[index];
                return _HomeOnlineGridSlot(
                  key: _slotKey(slot),
                  child: switch (slot.visualState) {
                    OnlineHomeSlotVisualState.unresolved =>
                      const HomeOnlineReservedBookCard(),
                    OnlineHomeSlotVisualState.loaded => _HomeOnlineBookCard(
                      key: _bookKey(slot.book!),
                      book: slot.book!,
                    ),
                  },
                );
              },
              childCount: visibleSlots.length,
              addAutomaticKeepAlives: false,
              findChildIndexCallback: (key) =>
                  _slotIndexForKey(key, visibleSlots),
            ),
          ),
        );
      },
    );
  }

  static double _cardExtent(BuildContext context, double width) {
    final tokens = context.appTokens;
    final textTheme = Theme.of(context).textTheme;
    final textScaler = MediaQuery.textScalerOf(context);
    final titleHeight = _textHeight(
      context,
      textTheme.titleSmall,
      textScaler,
      lines: 2,
    );
    final authorHeight = _textHeight(
      context,
      textTheme.bodySmall,
      textScaler,
      lines: 2,
    );
    final statusHeight = _textHeight(
      context,
      textTheme.labelMedium,
      textScaler,
      lines: 1,
    ).clamp(16.0, double.infinity).toDouble();
    // AppBookCard bounds its title, author, and status. Reserving their
    // maximum heights gives SliverGrid a stable extent without changing the
    // card's own visual hierarchy.
    return width / tokens.bookCardAspectRatio +
        8 +
        titleHeight +
        authorHeight +
        4 +
        statusHeight;
  }

  static double _textHeight(
    BuildContext context,
    TextStyle? style,
    TextScaler textScaler, {
    required int lines,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: List.filled(lines, 'A').join('\n'), style: style),
      textDirection: Directionality.of(context),
      textScaler: textScaler,
    )..layout();
    return painter.height;
  }

  static ValueKey<String> _slotKey(OnlineHomeSlot slot) =>
      ValueKey('home-online-slot-${slot.slotId}');

  static ValueKey<String> _bookKey(OnlineHomeBook book) => ValueKey(
    'home-online-${RemoteHomePublicationIdentity.canonical(sourceId: book.sourceId, publication: book.publication)}',
  );

  static int? _slotIndexForKey(Key key, List<OnlineHomeSlot> slots) {
    for (var index = 0; index < slots.length; index++) {
      if (_slotKey(slots[index]) == key) return index;
    }
    return null;
  }
}

class _HomeOnlineGridSlot extends StatelessWidget {
  const _HomeOnlineGridSlot({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class HomeOnlineReservedBookCard extends StatelessWidget {
  const HomeOnlineReservedBookCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppBookCardPlaceholder(
      key: ValueKey('home-online-placeholder-card'),
    );
  }
}

class _HomeOnlineBookCard extends ConsumerWidget {
  const _HomeOnlineBookCard({
    required this.book,
    this.isList = false,
    super.key,
  });

  final OnlineHomeBook book;
  final bool isList;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = homeOnlineIdentity(book.sourceId, book.id);
    final state = ref.watch(
      homeOnlineStateProvider.select(
        (snapshot) =>
            snapshot.byPublication[identity] ??
            const HomeOnlineBookState.idle(),
      ),
    );
    final localBook = ref.watch(
      homeOnlineStateProvider.select(
        (snapshot) => snapshot.localBooksByPublication[identity],
      ),
    );
    final stateLabel = state.label;
    void onOpen() => openBookDetailsForPublication(
      context,
      sourceId: book.sourceId,
      importedBookId: localBook?.id,
      remoteDetailsRequest: RemotePublicationDetailsRequest(
        sourceId: book.sourceId,
        sourceName: book.sourceName,
        publication: book.publication,
      ),
    );
    if (isList) {
      // List rows already describe local availability with the universal
      // reading status. Keep the legacy availability indicator in Grid only.
      final status =
          stateLabel == null || state.phase == HomeOnlineBookPhase.inLibrary
          ? null
          : _HomeOnlineStateIndicator(state: state, inheritListStyle: true);
      if (localBook != null) {
        return LibraryBookTile(book: localBook, onOpen: onOpen, status: status);
      }
      return RemoteCatalogBookTile(
        publication: book.publication,
        sourceId: book.sourceId,
        onOpen: onOpen,
        status: status,
      );
    }
    if (localBook != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LibraryBookCard(
            book: localBook,
            coverKey: ValueKey(
              '${localBook.id}-${localBook.coverPath ?? 'placeholder'}',
            ),
            onOpen: (_) => onOpen(),
          ),
          if (stateLabel != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _HomeOnlineStateIndicator(state: state),
          ],
        ],
      );
    }
    return RemoteCatalogBookCard(
      publication: book.publication,
      onOpen: onOpen,
      sourceId: book.sourceId,
      status: stateLabel == null
          ? null
          : _HomeOnlineStateIndicator(state: state),
    );
  }
}

class _HomeOnlineStateIndicator extends StatelessWidget {
  const _HomeOnlineStateIndicator({
    required this.state,
    this.inheritListStyle = false,
  });

  final HomeOnlineBookState state;
  final bool inheritListStyle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = state.progress;
    final isDownloading = state.phase == HomeOnlineBookPhase.downloading;
    final label = isDownloading && progress != null
        ? 'Downloading ${(progress * 100).round()}%'
        : state.label!;
    return Semantics(
      label: label,
      liveRegion: true,
      child: ExcludeSemantics(
        child: AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          child: Row(
            key: ValueKey('${state.phase}-$label'),
            children: [
              if (isDownloading)
                SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2,
                  ),
                )
              else
                Icon(_icon(state.phase), size: 16, color: scheme.primary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: inheritListStyle
                      ? null
                      : Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: state.phase == HomeOnlineBookPhase.failed
                              ? scheme.error
                              : scheme.primary,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _icon(HomeOnlineBookPhase phase) => switch (phase) {
    HomeOnlineBookPhase.queued => Icons.schedule,
    HomeOnlineBookPhase.readyToAdd => Icons.library_add_outlined,
    HomeOnlineBookPhase.importing => Icons.sync,
    HomeOnlineBookPhase.inLibrary => Icons.offline_pin_outlined,
    HomeOnlineBookPhase.failed => Icons.refresh,
    HomeOnlineBookPhase.idle ||
    HomeOnlineBookPhase.downloading => Icons.download_outlined,
  };
}

/// Reserved slot geometry uses the same row foundation, without book actions.
class HomeOnlineReservedBookRow extends StatelessWidget {
  const HomeOnlineReservedBookRow({super.key});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AppBookListTile(
      title: '',
      metadata: ' ',
      onOpen: null,
      cover: ColoredBox(
        color: Theme.of(context).colorScheme.secondaryContainer,
      ),
      status: const SizedBox(height: 16),
    ),
  );
}

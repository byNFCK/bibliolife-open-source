import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:bibliolife/features/home/domain/models/home_feed_ranking.dart';

class OnlineHomeSection {
  const OnlineHomeSection({
    required this.id,
    required this.title,
    required this.books,
    required this.searchCapability,
    this.ranking,
    this.isLoadingMore = false,
    this.loadMoreFailed = false,
    this.hasMore = false,
    this.isInitialResolving = false,
    this.slots = const [],
  });

  final String id;
  final String title;
  final List<OnlineHomeBook> books;
  final RemoteCatalogSearchCapability searchCapability;
  final HomeFeedRanking? ranking;
  final bool isLoadingMore;
  final bool loadMoreFailed;
  final bool hasMore;
  final bool isInitialResolving;
  final List<OnlineHomeSlot> slots;

  List<OnlineHomeSlot> get presentationSlots => slots.isNotEmpty
      ? slots
      : [
          for (var index = 0; index < books.length; index++)
            OnlineHomeSlot.loaded(
              slotId: index,
              sourceIndex: index,
              attempt: 0,
              book: books[index],
            ),
        ];

  OnlineHomeSection copyWith({
    List<OnlineHomeBook>? books,
    bool? isLoadingMore,
    bool? loadMoreFailed,
    bool? hasMore,
    bool? isInitialResolving,
    List<OnlineHomeSlot>? slots,
    HomeFeedRanking? ranking,
  }) => OnlineHomeSection(
    id: id,
    title: title,
    books: books ?? this.books,
    searchCapability: searchCapability,
    ranking: ranking ?? this.ranking,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
    hasMore: hasMore ?? this.hasMore,
    isInitialResolving: isInitialResolving ?? this.isInitialResolving,
    slots: slots ?? this.slots,
  );
}

class OnlineHomeSlot {
  const OnlineHomeSlot.pending({
    required this.slotId,
    required this.sourceIndex,
    required this.attempt,
  }) : book = null;

  const OnlineHomeSlot.loaded({
    required this.slotId,
    required this.sourceIndex,
    required this.attempt,
    required this.book,
  });

  final int slotId;
  final int sourceIndex;
  final int attempt;
  final OnlineHomeBook? book;

  bool get isPending => book == null;

  OnlineHomeSlotVisualState get visualState => switch (book) {
    null => OnlineHomeSlotVisualState.unresolved,
    _ => OnlineHomeSlotVisualState.loaded,
  };

  OnlineHomeSlot fill(OnlineHomeBook value) => OnlineHomeSlot.loaded(
    slotId: slotId,
    sourceIndex: sourceIndex,
    attempt: attempt,
    book: value,
  );

  OnlineHomeSlot reassign(int nextSourceIndex) => OnlineHomeSlot.pending(
    slotId: slotId,
    sourceIndex: nextSourceIndex,
    attempt: attempt + 1,
  );
}

enum OnlineHomeSlotVisualState { unresolved, loaded }

class OnlineHomeBook {
  const OnlineHomeBook({
    required this.sourceId,
    required this.sourceName,
    required this.publication,
  });

  final String sourceId;
  final String sourceName;
  final RemoteCatalogPublicationSummary publication;

  String get id => publication.remoteId;
  String get title => publication.title;
  String? get author =>
      publication.authors.isEmpty ? null : publication.authors.join(', ');
}

class OnlineLibraryUnavailable implements Exception {
  const OnlineLibraryUnavailable();
}

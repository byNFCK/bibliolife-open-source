import 'package:bibliolife/shared/presentation/presenters/book_reading_progress_availability.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_providers.dart';
import 'package:bibliolife/shared/presentation/presenters/book_list_status_presenter.dart';
import 'package:bibliolife/core/performance/online_pipeline_performance.dart';
import 'package:bibliolife/features/catalog_sources/data/remote_cache_service.dart';
import 'package:bibliolife/shared/presentation/widgets/app_book_list_tile.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/presentation/widgets/remote_catalog_book_cover.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_render_profile.dart';
import 'package:flutter/material.dart';

/// Compact remote-publication presentation. Routing and optional status belong
/// to the caller; local favorite/delete and acquisition actions are not inferred.
class RemoteCatalogBookTile extends ConsumerWidget {
  const RemoteCatalogBookTile({
    required this.publication,
    required this.onOpen,
    this.sourceId,
    this.canonicalId,
    this.performanceSession,
    this.remoteCache,
    this.status,
    this.statusPublication,
    super.key,
  });

  final RemoteCatalogPublicationSummary publication;
  final VoidCallback onOpen;
  final String? sourceId;
  final String? canonicalId;
  final OnlineSearchPerformanceSession? performanceSession;
  final RemoteCacheService? remoteCache;
  final Widget? status;
  final RemoteCatalogPublicationSummary? statusPublication;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localBooks = ref.watch(catalogLocalBooksProvider);
    final local = localBooks?[(sourceId, publication.remoteId)];
    final progress = local == null
        ? null
        : ref.watch(readingProgressProvider(local.id)).asData?.value;
    final ambiguousLocal =
        localBooks?.containsKey((sourceId, publication.remoteId)) == true &&
        local == null;
    final label = local != null
        ? BookListStatusPresenter.local(local)
        : status != null || localBooks == null || ambiguousLocal
        ? null
        : BookListStatusPresenter.remote(statusPublication ?? publication);
    final author = publication.authors.join(', ');
    return AppBookListTile(
      onOpen: onOpen,
      cover: RemoteCatalogBookCover(
        publication: publication,
        sourceId: sourceId,
        canonicalId: canonicalId,
        performanceSession: performanceSession,
        remoteCache: remoteCache,
        profile: BookCoverRenderProfile.compactList,
      ),
      title: publication.title,
      metadata: author.isEmpty ? null : author,
      bookStatus: label,
      progressPercent: availableBookReadingProgress(
        ref,
        local,
        progress == null ? null : (progress.progression * 100).round(),
      ),
      status: status,
      actions: const [AppBookListActionPlaceholder()],
    );
  }
}

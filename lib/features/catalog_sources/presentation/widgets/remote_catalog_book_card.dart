import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bibliolife/shared/presentation/presenters/book_reading_progress_availability.dart';
import 'package:bibliolife/features/reader/application/providers/reading_progress_providers.dart';
import 'package:bibliolife/features/catalog_sources/presentation/widgets/remote_catalog_book_cover.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/data/remote_cache_service.dart';
import 'package:bibliolife/core/performance/online_pipeline_performance.dart';
import 'package:bibliolife/shared/presentation/widgets/app_book_card.dart';
import 'package:flutter/material.dart';

/// Remote-catalog adapter. Remote favorites are unavailable until a publication
/// has an existing imported-local mapping, so the shared action space is empty.
class RemoteCatalogBookCard extends ConsumerWidget {
  const RemoteCatalogBookCard({
    required this.publication,
    required this.onOpen,
    this.progressPercent,
    this.cover,
    this.status,
    this.sourceId,
    this.canonicalId,
    this.performanceSession,
    this.remoteCache,
    super.key,
  });

  final RemoteCatalogPublicationSummary publication;
  final VoidCallback onOpen;
  final int? progressPercent;
  final Widget? cover;
  final Widget? status;
  final String? sourceId;
  final String? canonicalId;
  final OnlineSearchPerformanceSession? performanceSession;
  final RemoteCacheService? remoteCache;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = sourceId == null
        ? null
        : ref.watch(catalogLocalBooksProvider)?[(
            sourceId,
            publication.remoteId,
          )];
    final persisted = local == null
        ? null
        : ref.watch(readingProgressProvider(local.id)).asData?.value;
    final author = publication.authors.isEmpty
        ? 'Unknown author'
        : publication.authors.join(', ');
    return Semantics(
      label: 'Open ${publication.title}, $author',
      button: true,
      onTap: onOpen,
      excludeSemantics: true,
      child: AppBookCard(
        title: publication.title,
        author: author,
        cover:
            cover ??
            RemoteCatalogBookCover(
              publication: publication,
              sourceId: sourceId,
              canonicalId: canonicalId,
              performanceSession: performanceSession,
              remoteCache: remoteCache,
            ),
        progressPercent: availableBookReadingProgress(
          ref,
          local,
          progressPercent ??
              (persisted == null
                  ? null
                  : (persisted.progression * 100).round()),
        ),
        onOpen: onOpen,
        status: status,
      ),
    );
  }
}

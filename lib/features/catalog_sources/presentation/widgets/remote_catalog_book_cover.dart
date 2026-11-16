import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/data/remote_cache_service.dart';
import 'package:bibliolife/core/performance/online_pipeline_performance.dart';
import 'package:bibliolife/shared/models/book_cover_reference.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_image.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_render_profile.dart';
import 'package:flutter/material.dart';

/// Shared remote source selection and fallback; the profile changes decode size.
class RemoteCatalogBookCover extends StatelessWidget {
  const RemoteCatalogBookCover({
    required this.publication,
    this.sourceId,
    this.canonicalId,
    this.performanceSession,
    this.remoteCache,
    this.profile = BookCoverRenderProfile.searchGrid,
    super.key,
  });

  final RemoteCatalogPublicationSummary publication;
  final String? sourceId;
  final String? canonicalId;
  final OnlineSearchPerformanceSession? performanceSession;
  final RemoteCacheService? remoteCache;
  final BookCoverRenderProfile profile;

  @override
  Widget build(BuildContext context) {
    final location = selectRemoteCoverForProfile(
      preferred: publication.coverLocation,
      candidates: publication.imageCandidates,
      sourceId: sourceId,
      profile: profile,
    );
    final placeholder = ColoredBox(
      key: const Key('remote-book-cover-placeholder'),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Center(
        child: Icon(
          Icons.menu_book_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
    final cover = location == null
        ? const BookCoverReference.missing()
        : BookCoverReference.remote(
            location.uri,
            sourceId: sourceId,
            remoteId: publication.remoteId,
            canonicalId: canonicalId,
          );
    return BookCoverImage(
      cover: cover,
      title: publication.title,
      placeholder: placeholder,
      profile: profile,
      performanceSession: performanceSession,
      remoteCache: remoteCache,
    );
  }
}

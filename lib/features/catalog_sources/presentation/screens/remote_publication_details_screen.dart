import 'package:bibliolife/features/book_details/presentation/widgets/book_details_primary_action.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_status_bar.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_catalog_gateway_provider.dart';
import 'dart:async';

import 'package:bibliolife/core/network/request_cancellation.dart';
import 'package:bibliolife/core/performance/online_pipeline_performance.dart';
import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/app/router/book_details_navigation.dart';
import 'package:bibliolife/features/book_details/presentation/models/book_classification.dart';
import 'package:bibliolife/features/book_details/presentation/models/book_details_view_data.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_cover.dart';
import 'package:bibliolife/features/book_details/presentation/widgets/book_details_layout.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_download_queue_facade.dart';
import 'package:bibliolife/features/catalog_sources/application/local_search_result_assembler.dart';
import 'package:bibliolife/features/catalog_sources/domain/canonical_acquisition_resolution.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_download_queue_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_publication_details_resolver.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_publication_details_resolver_provider.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_book_download_plan.dart';
import 'package:bibliolife/features/catalog_sources/domain/canonical_book.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_access_hint.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_page.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_download_task.dart';
import 'package:bibliolife/features/library/application/providers/library_repository_provider.dart';
import 'package:bibliolife/features/library/application/providers/library_providers.dart';
import 'package:bibliolife/shared/models/book_cover_reference.dart';
import 'package:bibliolife/shared/presentation/widgets/book_cover_render_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class RemotePublicationDetailsRequest {
  const RemotePublicationDetailsRequest({
    required this.sourceId,
    required this.sourceName,
    required this.publication,
    this.canonicalBook,
  });

  final String sourceId;
  final String sourceName;
  final RemoteCatalogPublicationSummary publication;
  final CanonicalBook? canonicalBook;
}

class RemotePublicationDetailsScreen extends ConsumerStatefulWidget {
  const RemotePublicationDetailsScreen({this.request, super.key});

  final RemotePublicationDetailsRequest? request;

  @override
  ConsumerState<RemotePublicationDetailsScreen> createState() =>
      _RemotePublicationDetailsScreenState();
}

class _RemotePublicationDetailsScreenState
    extends ConsumerState<RemotePublicationDetailsScreen> {
  final _classificationCache = BookDetailsClassificationCache();
  RemotePublicationDetailsResolution? _resolution;
  AcquisitionResolution? _acquisitionResolution;
  Object? _resolutionError;
  var _isResolving = false;
  CancellationTokenSource? _metadataTask;

  @override
  void initState() {
    super.initState();
    _startResolutionForCurrentRequest();
  }

  @override
  void didUpdateWidget(covariant RemotePublicationDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request != widget.request) {
      _startResolutionForCurrentRequest();
    }
  }

  void _startResolutionForCurrentRequest() {
    _metadataTask?.cancel(RequestCancellationReason.retrySuperseded);
    _metadataTask = null;
    final request = widget.request;
    if (request == null) return;
    if (request.canonicalBook != null) {
      _resolveCanonicalAcquisition();
      return;
    }
    final plan = const RemoteBookDownloadPlanner()
        .create(sourceId: request.sourceId, publication: request.publication)
        .plan;
    if (plan?.acquisitionUri != null && plan!.supported && !plan.isIndirect) {
      _resolution = RemotePublicationDetailsResolution.downloadable(
        request.publication,
      );
      return;
    }
    _resolveDetails();
  }

  Future<void> _resolveCanonicalAcquisition() async {
    final request = widget.request;
    final canonical = request?.canonicalBook;
    if (request == null || canonical == null) return;
    final task = _replaceMetadataTask();
    onlinePerformanceMarker('details_metadata_started');
    setState(() {
      _isResolving = true;
      _resolution = null;
      _acquisitionResolution = null;
      _resolutionError = null;
    });
    try {
      final resolution = await MetadataRequestScope.run(
        MetadataRequestContext(
          token: task.token,
          sourceId: request.sourceId,
          priority: MetadataRequestPriority.details,
        ),
        () => ref.read(canonicalAcquisitionResolverProvider).resolve(canonical),
      );
      if (!mounted || widget.request != request) return;
      setState(() {
        _acquisitionResolution = resolution;
        _isResolving = false;
      });
      onlinePerformanceMarker('details_metadata_completed');
    } on RequestCancelledException {
      onlinePerformanceMarker('details_metadata_cancelled');
      return;
    } on Object catch (error) {
      if (!mounted || widget.request != request) return;
      setState(() {
        _resolutionError = error;
        _isResolving = false;
      });
    }
  }

  Future<void> _resolveDetails() async {
    final request = widget.request;
    if (request == null) return;
    final task = _replaceMetadataTask();
    onlinePerformanceMarker('details_metadata_started');
    setState(() {
      _isResolving = true;
      _resolution = null;
      _resolutionError = null;
    });
    try {
      final resolution = await MetadataRequestScope.run(
        MetadataRequestContext(
          token: task.token,
          sourceId: request.sourceId,
          priority: MetadataRequestPriority.details,
        ),
        () => ref
            .read(remotePublicationDetailsResolverProvider)
            .resolve(
              sourceId: request.sourceId,
              publication: request.publication,
            ),
      );
      if (!mounted || widget.request != request) return;
      setState(() {
        _resolution = resolution;
        _isResolving = false;
      });
      onlinePerformanceMarker('details_metadata_completed');
    } on RequestCancelledException {
      onlinePerformanceMarker('details_metadata_cancelled');
      return;
    } on Object catch (error) {
      if (!mounted || widget.request != request) return;
      setState(() {
        _resolutionError = error;
        _isResolving = false;
      });
    }
  }

  CancellationTokenSource _replaceMetadataTask() {
    _metadataTask?.cancel(RequestCancellationReason.retrySuperseded);
    return _metadataTask = CancellationTokenSource();
  }

  @override
  void dispose() {
    if (_isResolving) onlinePerformanceMarker('details_metadata_cancelled');
    _metadataTask?.cancel(RequestCancellationReason.screenClosed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.request;
    if (current == null) {
      return const Scaffold(
        body: SafeArea(
          child: Center(
            child: Text('Publication metadata is no longer available.'),
          ),
        ),
      );
    }
    final canonicalResolution = _acquisitionResolution;
    final routePublication =
        canonicalResolution?.selectedPublication ??
        _resolution?.publication ??
        current.publication;
    final publication =
        current.canonicalBook?.displayPublication ?? routePublication;
    final plan =
        canonicalResolution?.downloadPlan ??
        const RemoteBookDownloadPlanner()
            .create(sourceId: current.sourceId, publication: routePublication)
            .plan;
    final remoteData =
        RemoteBookDetailsViewDataMapper(
          classificationCache: _classificationCache,
        ).map(
          publication: publication,
          sourceName: current.sourceName,
          plan: plan,
          downloadProviderName: _downloadProviderName(
            canonicalResolution?.selected?.sourceId,
            metadataSourceName: current.sourceName,
          ),
        );
    final remoteCover = _remoteCover(
      publication,
      sourceId: current.sourceId,
      canonicalId: current.canonicalBook?.canonicalId,
    );
    final localIdentity = LocalBookIdentityTarget(
      sourceId: plan?.sourceId ?? current.sourceId,
      remotePublicationId:
          plan?.publicationRemoteId ?? routePublication.remoteId,
      title: plan?.publicationTitle ?? routePublication.title,
      authors: plan?.authors ?? routePublication.authors,
      language: plan?.remoteMetadata?.language ?? routePublication.language,
      identifiers:
          plan?.remoteMetadata?.identifiers ?? routePublication.identifiers,
      publishedDate:
          plan?.remoteMetadata?.publishedDate ?? routePublication.publishedDate,
      publicationLocation:
          plan?.remoteMetadata?.publicationLocation?.toString() ??
          routePublication.detailsLocation?.toString(),
      acquisitionLocation: plan?.acquisitionUri?.toString(),
      aliases:
          current.canonicalBook?.sources
              .map(
                (source) => LocalBookIdentityAlias(
                  sourceId: source.sourceId,
                  remotePublicationId: source.remoteId,
                  publicationLocation: source.detailsLocation?.toString(),
                  acquisitionLocations: source.publication.acquisitions.map(
                    (acquisition) => acquisition.href,
                  ),
                ),
              )
              .toList(growable: false) ??
          const [],
    );
    return Scaffold(
      body: SafeArea(
        top: false,
        left: false,
        right: false,
        child: BookDetailsStatusBar(
          child: _isResolving
              ? BookDetailsLayout(
                  data: remoteData,
                  onBack: () => _back(context),
                  cover: BookDetailsCover.remote(
                    title: remoteData.title,
                    cover: remoteCover,
                    remoteCache: remoteCover is RemoteBookCover
                        ? ref.watch(remoteCacheServiceProvider)
                        : null,
                  ),
                  primaryAction: const _ResolvingAction(),
                )
              : _resolutionError != null
              ? BookDetailsLayout(
                  data: remoteData,
                  onBack: () => _back(context),
                  cover: BookDetailsCover.remote(
                    title: remoteData.title,
                    cover: remoteCover,
                    remoteCache: remoteCover is RemoteBookCover
                        ? ref.watch(remoteCacheServiceProvider)
                        : null,
                  ),
                  primaryAction: _ResolutionFailureAction(
                    onRetry: current.canonicalBook == null
                        ? _resolveDetails
                        : _resolveCanonicalAcquisition,
                  ),
                )
              : canonicalResolution != null &&
                    !canonicalResolution.hasDirectDownload
              ? BookDetailsLayout(
                  data: remoteData,
                  onBack: () => _back(context),
                  cover: BookDetailsCover.remote(
                    title: remoteData.title,
                    cover: remoteCover,
                    remoteCache: remoteCover is RemoteBookCover
                        ? ref.watch(remoteCacheServiceProvider)
                        : null,
                  ),
                  primaryAction: _CanonicalAcquisitionAction(
                    resolution: canonicalResolution,
                    onRetry: _resolveCanonicalAcquisition,
                  ),
                )
              : _resolution?.availability ==
                    RemotePublicationAvailability.metadataOnly
              ? BookDetailsLayout(
                  data: remoteData,
                  onBack: () => _back(context),
                  cover: BookDetailsCover.remote(
                    title: remoteData.title,
                    cover: remoteCover,
                    remoteCache: remoteCover is RemoteBookCover
                        ? ref.watch(remoteCacheServiceProvider)
                        : null,
                  ),
                  primaryAction: _MetadataOnlyAction(
                    message: _resolution?.unavailableMessage,
                    hints: routePublication.accessHints,
                  ),
                )
              : _resolution?.availability ==
                        RemotePublicationAvailability.unavailable ||
                    plan?.acquisitionUri == null ||
                    plan!.isIndirect
              ? BookDetailsLayout(
                  data: remoteData,
                  onBack: () => _back(context),
                  cover: BookDetailsCover.remote(
                    title: remoteData.title,
                    cover: remoteCover,
                    remoteCache: remoteCover is RemoteBookCover
                        ? ref.watch(remoteCacheServiceProvider)
                        : null,
                  ),
                  primaryAction: _UnavailableAction(
                    message:
                        _resolution?.unavailableMessage ??
                        'This library did not provide a downloadable EPUB for this title.',
                  ),
                )
              : _ObservedRemoteDetails(
                  data: remoteData,
                  plan: plan,
                  localIdentity: localIdentity,
                  facade: ref.read(remoteDownloadQueueFacadeProvider),
                  cover: remoteCover,
                ),
        ),
      ),
    );
  }
}

String? _downloadProviderName(
  String? sourceId, {
  required String metadataSourceName,
}) {
  final provider = switch (sourceId) {
    'builtin-internet-archive' => 'Internet Archive',
    'builtin-open-library' => 'Open Library',
    'builtin-project-gutenberg' => 'Project Gutenberg',
    'builtin-google-books' => 'Google Books',
    _ => null,
  };
  return provider == null || provider == metadataSourceName ? null : provider;
}

class _CanonicalAcquisitionAction extends StatelessWidget {
  const _CanonicalAcquisitionAction({
    required this.resolution,
    required this.onRetry,
  });

  final AcquisitionResolution resolution;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final selected = resolution.selected;
    final (label, message) = switch (resolution.availability) {
      AcquisitionAvailability.previewAvailable => (
        'Preview available',
        'This title has a preview, but no verified downloadable EPUB.',
      ),
      AcquisitionAvailability.externalReadingAvailable => (
        'Read online',
        'This provider offers an external reader, not a downloadable EPUB.',
      ),
      AcquisitionAvailability.borrowingRequired => (
        'Borrow on Open Library',
        'This title requires borrowing or another authenticated access flow.',
      ),
      AcquisitionAvailability.purchaseAvailable => (
        'Buy',
        'This title has a purchase link, not a downloadable EPUB.',
      ),
      AcquisitionAvailability.allAcquisitionSourcesFailed => (
        'Retry availability check',
        'Acquisition sources could not be checked. Book metadata remains available.',
      ),
      _ => (
        'Download unavailable',
        'No verified public EPUB is available for this title.',
      ),
    };
    final retry =
        resolution.availability ==
        AcquisitionAvailability.allAcquisitionSourcesFailed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message, key: const Key('canonical-acquisition-message')),
        if (selected != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Provider: ${selected.sourceId}'),
          ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('canonical-acquisition-action'),
          style: bookDetailsPrimaryActionStyle(context),
          onPressed: retry ? onRetry : null,
          child: Text(label),
        ),
      ],
    );
  }
}

class _ObservedRemoteDetails extends ConsumerWidget {
  const _ObservedRemoteDetails({
    required this.data,
    required this.plan,
    required this.localIdentity,
    required this.facade,
    required this.cover,
  });

  final BookDetailsViewData data;
  final RemoteBookDownloadPlan plan;
  final LocalBookIdentityTarget localIdentity;
  final RemoteDownloadQueueFacade facade;
  final BookCoverReference cover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the provider subscribed so a second action observes a local import
    // that completed while this remote Details route remained stale.
    ref.watch(allBooksProvider);
    return StreamBuilder<RemoteDownloadUiState>(
      stream: facade.observeByIdentity(
        plan.sourceId,
        plan.publicationRemoteId,
        plan.acquisitionUri!,
      ),
      initialData: const RemoteDownloadUiState.idle(),
      builder: (context, snapshot) {
        final state = snapshot.data ?? const RemoteDownloadUiState.idle();
        final localId = state.task?.importedBookId;
        if ((state.phase == RemoteDownloadUiPhase.imported ||
                state.phase == RemoteDownloadUiPhase.duplicate) &&
            localId != null) {
          final localAsync = ref.watch(bookByIdProvider(localId));
          final localBook = localAsync.asData?.value;
          if (localAsync.hasValue && localBook == null && state.task != null) {
            unawaited(facade.reconcileImported(state.task!.id));
          }
          if (localBook != null) {
            return _RemoteToLocalDetailsRedirect(bookId: localBook.id);
          }
          return _content(context, ref, state);
        }
        return _content(context, ref, state);
      },
    );
  }

  Widget _content(
    BuildContext context,
    WidgetRef ref,
    RemoteDownloadUiState state,
  ) => BookDetailsLayout(
    data: data,
    onBack: () => _back(context),
    cover: BookDetailsCover.remote(
      title: data.title,
      cover: cover,
      remoteCache: cover is RemoteBookCover
          ? ref.watch(remoteCacheServiceProvider)
          : null,
    ),
    primaryAction: _RemotePrimaryAction(
      state: state,
      onActivate: () => _activate(context, ref, state),
    ),
    afterPrimaryAction: [
      if (state.phase == RemoteDownloadUiPhase.downloading ||
          state.phase == RemoteDownloadUiPhase.queued ||
          _failureMessage(state) != null)
        _RemoteActions(state: state, facade: facade),
    ],
  );

  Future<void> _activate(
    BuildContext context,
    WidgetRef ref,
    RemoteDownloadUiState state,
  ) async {
    final task = state.task;
    switch (state.phase) {
      case RemoteDownloadUiPhase.idle:
        final observedLocalBooks = ref.read(allBooksProvider).asData?.value;
        final local = LocalBookIdentityIndex(
          observedLocalBooks ??
              await ref.read(libraryRepositoryProvider).getAllBooks(),
        ).match(localIdentity)?.book;
        if (local != null && context.mounted) {
          await context.pushNamed(
            AppRoutes.bookDetailsName,
            pathParameters: {'bookId': local.id},
          );
          return;
        }
        await facade.enqueueOrReuse(plan);
      case RemoteDownloadUiPhase.interrupted:
      case RemoteDownloadUiPhase.failed:
      case RemoteDownloadUiPhase.cancelled:
        if (task != null) await facade.retry(task.id);
      case RemoteDownloadUiPhase.imported:
      case RemoteDownloadUiPhase.duplicate:
        final id = task?.importedBookId;
        if (id != null && context.mounted) {
          await context.pushNamed(
            AppRoutes.readerName,
            pathParameters: {'bookId': id},
          );
        }
      case RemoteDownloadUiPhase.queued:
      case RemoteDownloadUiPhase.downloading:
      case RemoteDownloadUiPhase.completedTemporary:
      case RemoteDownloadUiPhase.importing:
        break;
    }
  }
}

BookCoverReference _remoteCover(
  RemoteCatalogPublicationSummary publication, {
  required String sourceId,
  String? canonicalId,
}) {
  final location = selectRemoteCoverForProfile(
    preferred: publication.coverLocation,
    candidates: publication.imageCandidates,
    sourceId: sourceId,
    profile: BookCoverRenderProfile.details,
  );
  return location == null
      ? const BookCoverReference.missing()
      : BookCoverReference.remote(
          location.uri,
          sourceId: sourceId,
          remoteId: publication.remoteId,
          canonicalId: canonicalId,
        );
}

class _RemoteActions extends StatelessWidget {
  const _RemoteActions({required this.state, required this.facade});

  final RemoteDownloadUiState state;
  final RemoteDownloadQueueFacade facade;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (state.phase == RemoteDownloadUiPhase.downloading)
        LinearProgressIndicator(value: state.progress),
      if (state.phase == RemoteDownloadUiPhase.downloading ||
          state.phase == RemoteDownloadUiPhase.queued)
        TextButton(
          onPressed: state.task == null
              ? null
              : () => facade.cancel(state.task!.id),
          child: const Text('Cancel'),
        ),
      if (_failureMessage(state) case final message?)
        Text(
          message,
          key: const Key('remote-download-failure'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}

class _RemoteToLocalDetailsRedirect extends StatefulWidget {
  const _RemoteToLocalDetailsRedirect({required this.bookId});

  final String bookId;

  @override
  State<_RemoteToLocalDetailsRedirect> createState() =>
      _RemoteToLocalDetailsRedirectState();
}

class _RemoteToLocalDetailsRedirectState
    extends State<_RemoteToLocalDetailsRedirect> {
  var _redirectScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_redirectScheduled) return;
    _redirectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) replaceWithCanonicalLocalBookDetails(context, widget.bookId);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _RemotePrimaryAction extends StatelessWidget {
  const _RemotePrimaryAction({required this.state, required this.onActivate});

  final RemoteDownloadUiState state;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final enabled = switch (state.phase) {
      RemoteDownloadUiPhase.idle ||
      RemoteDownloadUiPhase.interrupted ||
      RemoteDownloadUiPhase.failed ||
      RemoteDownloadUiPhase.cancelled ||
      RemoteDownloadUiPhase.imported ||
      RemoteDownloadUiPhase.duplicate => true,
      _ => false,
    };
    final label = switch (state.phase) {
      RemoteDownloadUiPhase.idle => 'Download',
      RemoteDownloadUiPhase.queued => 'Queued',
      RemoteDownloadUiPhase.downloading =>
        state.progress == null
            ? 'Downloading'
            : 'Downloading ${(state.progress! * 100).round()}%',
      RemoteDownloadUiPhase.completedTemporary ||
      RemoteDownloadUiPhase.importing => 'Adding to library',
      RemoteDownloadUiPhase.imported ||
      RemoteDownloadUiPhase.duplicate => 'Read',
      RemoteDownloadUiPhase.interrupted ||
      RemoteDownloadUiPhase.failed => 'Retry',
      RemoteDownloadUiPhase.cancelled => 'Download',
    };
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        key: const Key('remote-primary-action'),
        onPressed: enabled ? onActivate : null,
        style: bookDetailsPrimaryActionStyle(context),
        child: Text(label),
      ),
    );
  }
}

class _ResolvingAction extends StatelessWidget {
  const _ResolvingAction();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      style: bookDetailsPrimaryActionStyle(context),
      onPressed: null,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Flexible(child: Text('Checking availability')),
        ],
      ),
    ),
  );
}

class _ResolutionFailureAction extends StatelessWidget {
  const _ResolutionFailureAction({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Could not load download options. Check your connection and retry.',
      ),
      const SizedBox(height: 12),
      FilledButton(
        style: bookDetailsPrimaryActionStyle(context),
        onPressed: onRetry,
        child: const Text('Retry availability check'),
      ),
    ],
  );
}

class _UnavailableAction extends StatelessWidget {
  const _UnavailableAction({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(message, key: const Key('remote-epub-unavailable-message')),
      const SizedBox(height: 12),
      FilledButton(
        style: bookDetailsPrimaryActionStyle(context),
        onPressed: null,
        child: const Text('Download unavailable'),
      ),
    ],
  );
}

class _MetadataOnlyAction extends StatelessWidget {
  const _MetadataOnlyAction({this.message, required this.hints});

  final String? message;
  final List<RemoteCatalogAccessHint> hints;

  @override
  Widget build(BuildContext context) {
    final labels = <String>{
      for (final hint in hints)
        switch (hint.type) {
          RemoteCatalogAccessType.preview => 'Preview available',
          RemoteCatalogAccessType.externalRead => 'External reading available',
          RemoteCatalogAccessType.purchase => 'Purchase available',
          _ => '',
        },
    }..remove('');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (message != null) Text(message!),
        for (final label in labels)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(label)),
        const SizedBox(height: 12),
        FilledButton(
          style: bookDetailsPrimaryActionStyle(context),
          onPressed: null,
          child: const Text('Download unavailable'),
        ),
      ],
    );
  }
}

String? _failureMessage(RemoteDownloadUiState state) {
  final task = state.task;
  if (state.phase == RemoteDownloadUiPhase.cancelled) return null;
  if (state.phase == RemoteDownloadUiPhase.interrupted) {
    return 'Download interrupted by app restart.';
  }
  if (state.phase != RemoteDownloadUiPhase.failed || task == null) return null;
  if (task.failure == RemoteDownloadFailureCategory.accessDenied) {
    return 'Online access is disabled. Enable Online mode and retry.';
  }
  if (task.failure == RemoteDownloadFailureCategory.importFailure) {
    return 'The book could not be saved to the library.';
  }
  return 'The download failed.';
}

void _back(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(AppRoutes.homePath);
  }
}

import 'package:bibliolife/features/catalog_sources/presentation/widgets/remote_catalog_publication_sliver.dart';
import 'package:bibliolife/features/library/application/providers/library_view_mode_provider.dart';
import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/features/catalog_sources/application/catalog_browser_controller.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/remote_publication_details_screen.dart';

class CatalogBrowserScreen extends ConsumerStatefulWidget {
  const CatalogBrowserScreen({required this.sourceId, super.key});

  final String sourceId;

  @override
  ConsumerState<CatalogBrowserScreen> createState() =>
      _CatalogBrowserScreenState();
}

class _CatalogBrowserScreenState extends ConsumerState<CatalogBrowserScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(catalogBrowserControllerProvider(widget.sourceId).notifier)
            .openRoot();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = catalogBrowserControllerProvider(widget.sourceId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    return PopScope(
      canPop: !state.canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && state.canGoBack) controller.goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(state.sourceName ?? 'Online library'),
          leading: state.canGoBack
              ? IconButton(
                  tooltip: 'Back in catalog',
                  onPressed: controller.goBack,
                  icon: const Icon(Icons.arrow_back),
                )
              : null,
          actions: [
            if (state.page?.searchCapability.isSupported ?? false)
              IconButton(
                tooltip: 'Search ${state.sourceName ?? 'library'}',
                onPressed: () => context.pushNamed(
                  AppRoutes.searchOnlineLibraryName,
                  pathParameters: {'sourceId': widget.sourceId},
                  extra: state.page!.searchCapability,
                ),
                icon: const Icon(Icons.search),
              ),
            IconButton(
              tooltip: 'Refresh catalog',
              onPressed: state.isLoading || state.page == null
                  ? null
                  : controller.refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: _BrowserBody(state: state, controller: controller),
        ),
      ),
    );
  }
}

class _BrowserBody extends ConsumerWidget {
  const _BrowserBody({required this.state, required this.controller});

  final CatalogBrowserState state;
  final CatalogBrowserController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.page == null && state.isLoading) {
      return Center(
        child: Semantics(
          label: 'Loading catalog',
          liveRegion: true,
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (state.page == null && state.failure != null) {
      return _FailurePanel(failure: state.failure!, onRetry: controller.retry);
    }
    final page = state.page;
    if (page == null) return const SizedBox.shrink();
    final mode = ref.watch(libraryViewModeProvider);
    return CustomScrollView(
      key: PageStorageKey((state.sourceId, page.location, mode)),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          page.title,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      if (state.loading == CatalogBrowserLoading.navigation ||
                          state.loading == CatalogBrowserLoading.refresh) ...[
                        const SizedBox(height: 12),
                        Semantics(
                          label: 'Loading catalog',
                          liveRegion: true,
                          child: const LinearProgressIndicator(),
                        ),
                      ],
                      if (state.failure != null) ...[
                        const SizedBox(height: 12),
                        _FailurePanel(
                          failure: state.failure!,
                          onRetry: controller.retry,
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (page.navigation.isEmpty && page.publications.isEmpty)
                        const Text('This catalog page is empty.'),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.builder(
                  itemCount: page.navigation.length,
                  itemBuilder: (context, index) {
                    final entry = page.navigation[index];
                    return Semantics(
                      key: ValueKey(entry.location),
                      label: 'Open category ${entry.title}',
                      button: true,
                      child: ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(entry.title),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: state.isLoading
                            ? null
                            : () => controller.openNavigation(entry.location),
                      ),
                    );
                  },
                ),
              ),
              if (page.publications.isNotEmpty)
                SliverPadding(
                  padding: mode == LibraryViewMode.grid
                      ? const EdgeInsets.symmetric(horizontal: 16)
                      : EdgeInsets.zero,
                  sliver: RemoteCatalogPublicationSliver(
                    publications: page.publications,
                    sourceId: state.sourceId,
                    mode: mode,
                    onOpen: (publication) => context.pushNamed(
                      AppRoutes.publicationOnlineLibraryName,
                      pathParameters: {'sourceId': state.sourceId},
                      extra: RemotePublicationDetailsRequest(
                        sourceId: state.sourceId,
                        sourceName: state.sourceName ?? 'Online library',
                        publication: publication,
                      ),
                    ),
                  ),
                ),
              if (state.hasNextPage)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Semantics(
                      label: state.loading == CatalogBrowserLoading.nextPage
                          ? 'Loading next page'
                          : 'Load more catalog results',
                      button: true,
                      child: FilledButton.tonalIcon(
                        onPressed: state.isLoading
                            ? null
                            : controller.loadNextPage,
                        icon: state.loading == CatalogBrowserLoading.nextPage
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.expand_more),
                        label: const Text('Load more'),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FailurePanel extends StatelessWidget {
  const _FailurePanel({required this.failure, required this.onRetry});

  final RemoteCatalogFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final offline = failure == RemoteCatalogFailure.accessDenied;
    return Semantics(
      liveRegion: true,
      label: offline ? 'Catalog unavailable while Offline' : _message(failure),
      child: Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_message(failure)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(onPressed: onRetry, child: const Text('Retry')),
                  if (offline)
                    TextButton(
                      onPressed: () =>
                          context.pushNamed(AppRoutes.settingsName),
                      child: const Text('Connectivity settings'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _message(RemoteCatalogFailure failure) => switch (failure) {
    RemoteCatalogFailure.accessDenied =>
      'Online access is disabled. Enable it in connectivity settings.',
    RemoteCatalogFailure.timeout => 'The catalog request timed out.',
    RemoteCatalogFailure.httpStatus =>
      'The catalog server could not complete the request.',
    RemoteCatalogFailure.transport =>
      'The catalog could not be reached. Check your connection.',
    RemoteCatalogFailure.unsupportedCatalogFormat =>
      'This catalog format is not supported.',
    RemoteCatalogFailure.malformedCatalogResponse =>
      'The catalog returned an invalid response.',
    RemoteCatalogFailure.sourceDisabled => 'This library source is disabled.',
    RemoteCatalogFailure.sourceNotFound => 'This library source was not found.',
    RemoteCatalogFailure.invalidSourceOrLocation =>
      'This library has an invalid catalog location.',
    RemoteCatalogFailure.emptyResponse => 'The catalog returned no content.',
    RemoteCatalogFailure.responseTooLarge =>
      'The catalog response is too large.',
    RemoteCatalogFailure.insecureRedirect =>
      'The catalog redirected to an insecure location.',
    _ => 'The catalog could not be loaded.',
  };
}

import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/app/router/app_shell.dart';
import 'package:bibliolife/features/home/presentation/screens/home_screen.dart';
import 'package:bibliolife/features/library/presentation/screens/library_screen.dart';
import 'package:bibliolife/features/search/presentation/screens/search_screen.dart';
import 'package:bibliolife/features/settings/presentation/screens/settings_screen.dart';
import 'package:bibliolife/features/profile/presentation/screens/profile_screen.dart';
import 'package:bibliolife/features/reader/presentation/screens/reader_route_screen.dart';
import 'package:bibliolife/features/reader/domain/models/reader_launch_request.dart';
import 'package:bibliolife/features/book_details/presentation/screens/book_details_screen.dart';
import 'package:bibliolife/features/collections/presentation/screens/collections_screen.dart';
import 'package:bibliolife/features/collections/presentation/screens/collection_details_screen.dart';
import 'package:bibliolife/features/collections/presentation/screens/collection_editor_screen.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/catalog_sources_screen.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/catalog_source_form_screen.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/catalog_browser_screen.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/catalog_search_screen.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/multi_catalog_search_screen.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_search.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/remote_publication_details_screen.dart';
import 'package:bibliolife/features/catalog_sources/presentation/screens/downloads_screen.dart';
import 'package:bibliolife/features/app_logs/presentation/screens/app_log_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.homePath,
    routes: [
      GoRoute(
        path: AppRoutes.downloadsPath,
        name: AppRoutes.downloadsName,
        builder: (context, state) => const DownloadsScreen(),
      ),
      GoRoute(
        path: AppRoutes.onlineLibrariesPath,
        name: AppRoutes.onlineLibrariesName,
        builder: (context, state) => const CatalogSourcesScreen(),
      ),
      GoRoute(
        path: AppRoutes.addOnlineLibraryPath,
        name: AppRoutes.addOnlineLibraryName,
        builder: (context, state) => const CatalogSourceFormScreen(),
      ),
      GoRoute(
        path: AppRoutes.editOnlineLibraryPath,
        name: AppRoutes.editOnlineLibraryName,
        builder: (context, state) =>
            CatalogSourceFormScreen(sourceId: state.pathParameters['sourceId']),
      ),
      GoRoute(
        path: AppRoutes.browseOnlineLibraryPath,
        name: AppRoutes.browseOnlineLibraryName,
        builder: (context, state) => CatalogBrowserScreen(
          sourceId: state.pathParameters['sourceId'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.searchOnlineLibraryPath,
        name: AppRoutes.searchOnlineLibraryName,
        builder: (context, state) => state.uri.queryParameters['all'] == 'true'
            ? const MultiCatalogSearchScreen()
            : CatalogSearchScreen(
                sourceId: state.pathParameters['sourceId'] ?? '',
                capability: state.extra is RemoteCatalogSearchCapability
                    ? state.extra! as RemoteCatalogSearchCapability
                    : const RemoteCatalogSearchCapability.unsupported(),
              ),
      ),
      GoRoute(
        path: AppRoutes.publicationOnlineLibraryPath,
        name: AppRoutes.publicationOnlineLibraryName,
        pageBuilder: (context, state) => NoTransitionPage(
          key: state.pageKey,
          child: RemotePublicationDetailsScreen(
            request: state.extra is RemotePublicationDetailsRequest
                ? state.extra! as RemotePublicationDetailsRequest
                : null,
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.searchPath,
        name: AppRoutes.searchName,
        builder: (context, state) => const SearchScreen(),
      ),
      GoRoute(
        path: AppRoutes.settingsPath,
        name: AppRoutes.settingsName,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.logsPath,
        name: AppRoutes.logsName,
        builder: (context, state) => const AppLogScreen(),
      ),
      GoRoute(
        path: AppRoutes.bookDetailsPath,
        name: AppRoutes.bookDetailsName,
        pageBuilder: (context, state) => NoTransitionPage(
          key: state.pageKey,
          child: BookDetailsScreen(
            bookId: state.pathParameters['bookId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.collectionsPath,
        name: AppRoutes.collectionsName,
        builder: (context, state) => const CollectionsScreen(),
      ),
      GoRoute(
        path: AppRoutes.createCollectionPath,
        name: AppRoutes.createCollectionName,
        builder: (context, state) => CollectionEditorScreen(
          initialBookIds: state.extra is Set<String>
              ? state.extra! as Set<String>
              : const {},
        ),
      ),
      GoRoute(
        path: AppRoutes.editCollectionPath,
        name: AppRoutes.editCollectionName,
        builder: (context, state) => CollectionEditorScreen(
          collectionId: state.pathParameters['collectionId'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.collectionDetailsPath,
        name: AppRoutes.collectionDetailsName,
        builder: (context, state) => CollectionDetailsScreen(
          collectionId: state.pathParameters['collectionId'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.readerPath,
        name: AppRoutes.readerName,
        pageBuilder: (context, state) {
          final bookId = state.pathParameters['bookId']!;
          final request = state.extra is ReaderLaunchRequest
              ? state.extra as ReaderLaunchRequest
              : null;
          return CustomTransitionPage<void>(
            key: state.pageKey,
            transitionDuration: const Duration(milliseconds: 260),
            reverseTransitionDuration: const Duration(milliseconds: 220),
            child: ReaderRouteScreen(
              bookId: bookId,
              formatHint: request?.bookId == bookId
                  ? request?.formatHint
                  : null,
              source: request?.bookId == bookId ? request!.source : 'other',
              initialLocatorJson: request?.bookId == bookId
                  ? request?.validExplicitLocator
                  : null,
            ),
            transitionsBuilder: (context, animation, secondary, child) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, .025),
                    end: Offset.zero,
                  ).animate(curved),
                  child: child,
                ),
              );
            },
          );
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.homePath,
                name: AppRoutes.homeName,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.libraryPath,
                name: AppRoutes.libraryName,
                builder: (context, state) => const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profilePath,
                name: AppRoutes.profileName,
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

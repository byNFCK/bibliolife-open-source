import 'package:bibliolife/core/database/database_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_book_download_provider.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_download_queue_coordinator.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_download_queue_facade.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_temporary_epub_import_provider.dart';
import 'package:bibliolife/features/catalog_sources/data/drift_remote_download_task_repository.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_download_task_repository.dart';
import 'package:bibliolife/features/library/application/providers/library_repository_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final remoteDownloadTaskRepositoryProvider =
    Provider<RemoteDownloadTaskRepository>(
      (ref) =>
          DriftRemoteDownloadTaskRepository(ref.watch(appDatabaseProvider)),
    );
final remoteDownloadQueueCoordinatorProvider =
    Provider<RemoteDownloadQueueCoordinator>(
      (ref) => RemoteDownloadQueueCoordinator(
        ref.watch(remoteDownloadTaskRepositoryProvider),
        ref.watch(remoteBookDownloaderProvider),
      ),
    );
final remoteDownloadQueueFacadeProvider = Provider<RemoteDownloadQueueFacade>((
  ref,
) {
  final library = ref.watch(libraryRepositoryProvider);
  final facade = RemoteDownloadQueueFacade(
    ref.watch(remoteDownloadTaskRepositoryProvider),
    ref.watch(remoteDownloadQueueCoordinatorProvider),
    ref.watch(remoteTemporaryEpubImporterProvider),
    ref.watch(remoteDownloadTemporaryDirectoryProvider),
    (id) async => await library.getBookById(id) != null,
  );
  ref.onDispose(facade.dispose);
  return facade;
});
final remoteDownloadTasksProvider = StreamProvider(
  (ref) => ref.watch(remoteDownloadQueueFacadeProvider).watchAll(),
);
final remoteDownloadQueueBootstrapProvider = FutureProvider<void>((ref) async {
  await ref.watch(remoteDownloadQueueFacadeProvider).reconcileOnStartup();
});

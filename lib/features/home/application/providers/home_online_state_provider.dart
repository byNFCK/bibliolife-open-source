import 'package:bibliolife/features/catalog_sources/application/remote_download_queue_provider.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_download_task.dart';
import 'package:bibliolife/features/home/domain/models/home_online_book_state.dart';
import 'package:bibliolife/features/home/domain/models/remote_home_publication_identity.dart';
import 'package:bibliolife/features/library/application/providers/library_providers.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final homeOnlineStateProvider = Provider<HomeOnlineStateSnapshot>((ref) {
  final tasks =
      ref.watch(remoteDownloadTasksProvider).asData?.value ??
      const <RemoteDownloadTask>[];
  final books = ref.watch(allBooksProvider).asData?.value ?? const [];
  return buildHomeOnlineStateSnapshot(tasks: tasks, books: books);
});

HomeOnlineStateSnapshot buildHomeOnlineStateSnapshot({
  required List<RemoteDownloadTask> tasks,
  required List<LibraryBook> books,
}) {
  final localBooksByPublication = {
    for (final book in books)
      if (book.catalogSourceId != null && book.remotePublicationId != null)
        _identity(book.catalogSourceId!, book.remotePublicationId!): book,
  };
  final localIdentities = localBooksByPublication.keys.toSet();
  final states = <String, HomeOnlineBookState>{};

  for (final task in tasks) {
    final identity = _identity(task.sourceId, task.publicationRemoteId);
    final phase = localIdentities.contains(identity)
        ? HomeOnlineBookPhase.inLibrary
        : _phase(task.state);
    if (phase == HomeOnlineBookPhase.idle) continue;
    states.putIfAbsent(
      identity,
      () => HomeOnlineBookState(
        phase: phase,
        downloadedBytes: task.downloadedBytes,
        totalBytes: task.totalBytes,
      ),
    );
  }
  for (final identity in localIdentities) {
    states[identity] = const HomeOnlineBookState(
      phase: HomeOnlineBookPhase.inLibrary,
    );
  }

  final count = tasks.where((task) {
    return task.state == RemoteDownloadTaskState.queued ||
        task.state == RemoteDownloadTaskState.downloading ||
        task.state == RemoteDownloadTaskState.completedTemporary ||
        task.state == RemoteDownloadTaskState.importing;
  }).length;
  return HomeOnlineStateSnapshot(
    byPublication: Map.unmodifiable(states),
    downloadsCount: count,
    localBooksByPublication: Map.unmodifiable(localBooksByPublication),
  );
}

String homeOnlineIdentity(String sourceId, String publicationId) =>
    _identity(sourceId, publicationId);

String _identity(String sourceId, String publicationId) =>
    RemoteHomePublicationIdentity.canonicalRemoteId(
      sourceId: sourceId,
      remotePublicationId: publicationId,
    ) ??
    '$sourceId\u0000$publicationId';

HomeOnlineBookPhase _phase(RemoteDownloadTaskState state) => switch (state) {
  RemoteDownloadTaskState.queued => HomeOnlineBookPhase.queued,
  RemoteDownloadTaskState.downloading => HomeOnlineBookPhase.downloading,
  RemoteDownloadTaskState.completedTemporary => HomeOnlineBookPhase.readyToAdd,
  RemoteDownloadTaskState.importing => HomeOnlineBookPhase.importing,
  RemoteDownloadTaskState.imported ||
  RemoteDownloadTaskState.duplicate => HomeOnlineBookPhase.idle,
  RemoteDownloadTaskState.failed ||
  RemoteDownloadTaskState.pausedByAppRestart => HomeOnlineBookPhase.failed,
  RemoteDownloadTaskState.cancelled ||
  RemoteDownloadTaskState.deleted => HomeOnlineBookPhase.idle,
};

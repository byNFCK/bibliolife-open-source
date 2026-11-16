import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/features/catalog_sources/application/remote_download_queue_provider.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_download_task.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(remoteDownloadTasksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: tasks.when(
        data: (items) => items.isEmpty
            ? const Center(child: Text('No downloads yet.'))
            : ListView(children: items.map((t) => _TaskTile(t)).toList()),
        error: (_, _) => const Center(child: Text('Downloads unavailable.')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile(this.task);
  final RemoteDownloadTask task;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facade = ref.read(remoteDownloadQueueFacadeProvider);
    final active = task.state == RemoteDownloadTaskState.downloading;
    return ListTile(
      title: Text(task.title),
      subtitle: Text(
        '${task.authors.join(', ')} · ${task.state.name}${active ? ' · ${task.downloadedBytes} bytes' : ''}',
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          if (active)
            IconButton(
              tooltip: 'Cancel download: ${task.title}',
              onPressed: () => facade.cancel(task.id),
              icon: const Icon(Icons.cancel_outlined),
            ),
          if (task.canRetry)
            IconButton(
              tooltip: 'Retry download: ${task.title}',
              onPressed: () => facade.retry(task.id),
              icon: const Icon(Icons.refresh),
            ),
          if (task.importedBookId case final id?)
            IconButton(
              tooltip: 'Open book: ${task.title}',
              onPressed: () => context.pushNamed(
                AppRoutes.readerName,
                pathParameters: {'bookId': id},
              ),
              icon: const Icon(Icons.menu_book),
            ),
          if (task.importedBookId != null)
            IconButton(
              tooltip: 'Go to Library: ${task.title}',
              onPressed: () => context.goNamed(AppRoutes.libraryName),
              icon: const Icon(Icons.local_library_outlined),
            ),
          if (task.state == RemoteDownloadTaskState.completedTemporary)
            IconButton(
              tooltip: 'Add to library: ${task.title}',
              onPressed: () => facade.importCompleted(task.id),
              icon: const Icon(Icons.library_add_outlined),
            ),
          if (task.state == RemoteDownloadTaskState.completedTemporary)
            IconButton(
              tooltip: 'Delete temporary file: ${task.title}',
              onPressed: () => facade.deleteTemporaryEpub(task.id),
              icon: const Icon(Icons.delete_outline),
            ),
          if (!task.isActive &&
              task.state != RemoteDownloadTaskState.completedTemporary)
            IconButton(
              tooltip: 'Remove history: ${task.title}',
              onPressed: () => facade.removeHistory(task.id),
              icon: const Icon(Icons.clear),
            ),
        ],
      ),
    );
  }
}

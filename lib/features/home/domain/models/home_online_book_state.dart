import 'package:bibliolife/shared/models/library_book.dart';

enum HomeOnlineBookPhase {
  idle,
  queued,
  downloading,
  readyToAdd,
  importing,
  inLibrary,
  failed,
}

class HomeOnlineBookState {
  const HomeOnlineBookState({
    required this.phase,
    this.downloadedBytes = 0,
    this.totalBytes,
  });

  const HomeOnlineBookState.idle()
    : phase = HomeOnlineBookPhase.idle,
      downloadedBytes = 0,
      totalBytes = null;

  final HomeOnlineBookPhase phase;
  final int downloadedBytes;
  final int? totalBytes;

  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (downloadedBytes / total).clamp(0, 1);
  }

  String? get label => switch (phase) {
    HomeOnlineBookPhase.idle => null,
    HomeOnlineBookPhase.queued => 'Queued',
    HomeOnlineBookPhase.downloading => 'Downloading',
    HomeOnlineBookPhase.readyToAdd => 'Ready to add',
    HomeOnlineBookPhase.importing => 'Importing',
    HomeOnlineBookPhase.inLibrary => 'In library',
    HomeOnlineBookPhase.failed => 'Retry',
  };

  @override
  bool operator ==(Object other) =>
      other is HomeOnlineBookState &&
      other.phase == phase &&
      other.downloadedBytes == downloadedBytes &&
      other.totalBytes == totalBytes;

  @override
  int get hashCode => Object.hash(phase, downloadedBytes, totalBytes);
}

class HomeOnlineStateSnapshot {
  const HomeOnlineStateSnapshot({
    required this.byPublication,
    required this.downloadsCount,
    this.localBooksByPublication = const {},
  });

  final Map<String, HomeOnlineBookState> byPublication;
  final int downloadsCount;
  final Map<String, LibraryBook> localBooksByPublication;
}

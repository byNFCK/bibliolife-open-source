import 'package:bibliolife/features/bookmarks/domain/models/library_bookmark.dart';
import 'package:bibliolife/features/reader/domain/models/reader_bookmark_target.dart';

enum ReaderBookmarkCommandStatus {
  added,
  alreadyExists,
  removed,
  navigated,
  notReady,
  unsupported,
  failed,
  disposed,
}

final class ReaderBookmarkCommandResult {
  const ReaderBookmarkCommandResult(this.status, {this.bookmark, this.error});

  const ReaderBookmarkCommandResult.added(LibraryBookmark bookmark)
    : this(ReaderBookmarkCommandStatus.added, bookmark: bookmark);

  const ReaderBookmarkCommandResult.alreadyExists(LibraryBookmark bookmark)
    : this(ReaderBookmarkCommandStatus.alreadyExists, bookmark: bookmark);

  const ReaderBookmarkCommandResult.removed()
    : this(ReaderBookmarkCommandStatus.removed);

  const ReaderBookmarkCommandResult.navigated()
    : this(ReaderBookmarkCommandStatus.navigated);

  const ReaderBookmarkCommandResult.notReady()
    : this(ReaderBookmarkCommandStatus.notReady);

  const ReaderBookmarkCommandResult.unsupported()
    : this(ReaderBookmarkCommandStatus.unsupported);

  const ReaderBookmarkCommandResult.failed([Object? error])
    : this(ReaderBookmarkCommandStatus.failed, error: error);

  const ReaderBookmarkCommandResult.disposed()
    : this(ReaderBookmarkCommandStatus.disposed);

  final ReaderBookmarkCommandStatus status;
  final LibraryBookmark? bookmark;
  final Object? error;

  bool get isSuccess =>
      status == ReaderBookmarkCommandStatus.added ||
      status == ReaderBookmarkCommandStatus.alreadyExists ||
      status == ReaderBookmarkCommandStatus.removed ||
      status == ReaderBookmarkCommandStatus.navigated;
}

final class ReaderBookmarkState {
  const ReaderBookmarkState({
    this.bookmarks = const <LibraryBookmark>[],
    this.currentTarget,
    this.isLoading = true,
    this.error,
    this.pendingFingerprint,
    this.pendingBookmarkId,
  });

  final List<LibraryBookmark> bookmarks;
  final ReaderBookmarkTarget? currentTarget;
  final bool isLoading;
  final Object? error;
  final String? pendingFingerprint;
  final String? pendingBookmarkId;

  bool get isCurrentPositionBookmarked {
    final target = currentTarget;
    if (target == null) return false;
    return bookmarks.any(
      (bookmark) => bookmark.fingerprint == target.fingerprint,
    );
  }

  ReaderBookmarkState copyWith({
    List<LibraryBookmark>? bookmarks,
    ReaderBookmarkTarget? currentTarget,
    bool clearCurrentTarget = false,
    bool? isLoading,
    Object? error,
    bool clearError = false,
    String? pendingFingerprint,
    bool clearPendingFingerprint = false,
    String? pendingBookmarkId,
    bool clearPendingBookmarkId = false,
  }) => ReaderBookmarkState(
    bookmarks: bookmarks ?? this.bookmarks,
    currentTarget: clearCurrentTarget
        ? null
        : currentTarget ?? this.currentTarget,
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : error ?? this.error,
    pendingFingerprint: clearPendingFingerprint
        ? null
        : pendingFingerprint ?? this.pendingFingerprint,
    pendingBookmarkId: clearPendingBookmarkId
        ? null
        : pendingBookmarkId ?? this.pendingBookmarkId,
  );
}

extension ReaderBookmarkFingerprint on LibraryBookmark {
  String get fingerprint =>
      ReaderLocatorBookmarkTarget.tryParse(
        locatorJson: locatorJson,
        progression: progression,
        chapterTitle: chapterTitle,
        href: href,
      )?.fingerprint ??
      (position == null ? 'legacy:$locatorJson' : 'page:$position');
}

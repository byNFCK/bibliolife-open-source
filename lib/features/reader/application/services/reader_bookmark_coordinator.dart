// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:bibliolife/features/bookmarks/domain/models/library_bookmark.dart';
import 'package:bibliolife/features/bookmarks/domain/models/bookmark_metadata_update.dart';
import 'package:bibliolife/features/bookmarks/domain/repositories/bookmark_repository.dart';
import 'package:bibliolife/features/reader/domain/models/reader_bookmark.dart';
import 'package:bibliolife/features/reader/domain/models/reader_bookmark_target.dart';
import 'package:bibliolife/features/reader/domain/models/reader_kind.dart';
import 'package:flutter/foundation.dart';

typedef ReaderBookmarkNavigator =
    Future<bool> Function(ReaderBookmarkTarget target);

/// Coordinates one active reader route with the application bookmark store.
///
/// The coordinator never talks to a native bridge. Format adapters provide the
/// current target and navigation callback; the repository remains the source
/// of truth for saved rows.
final class ReaderBookmarkCoordinator extends ChangeNotifier {
  ReaderBookmarkCoordinator({
    required this.bookId,
    required this.readerKind,
    required BookmarkRepository repository,
    required ReaderBookmarkNavigator navigator,
  }) : _repository = repository,
       _navigator = navigator;

  final String bookId;
  final ReaderKind readerKind;
  final BookmarkRepository _repository;
  final ReaderBookmarkNavigator _navigator;

  StreamSubscription<List<LibraryBookmark>>? _subscription;
  ReaderBookmarkState _state = const ReaderBookmarkState();
  ReaderBookmarkTarget? _currentTarget;
  final Set<String> _pendingAdds = <String>{};
  final Set<String> _pendingDeletes = <String>{};
  final Set<String> _pendingNavigation = <String>{};
  var _started = false;
  var _disposed = false;

  ReaderBookmarkState get state => _state;
  ReaderBookmarkTarget? get currentBookmarkTarget => _currentTarget;
  bool get isCurrentPositionBookmarked => state.isCurrentPositionBookmarked;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    try {
      _subscription = _repository
          .watchBookmarksForBook(bookId)
          .listen(_replaceBookmarks, onError: _handleRepositoryError);
    } catch (error) {
      _handleRepositoryError(error, StackTrace.current);
    }
  }

  Future<void> reload() async {
    if (_disposed) return;
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
    _setState(_state.copyWith(isLoading: true, clearError: true));
    await start();
  }

  void updateCurrentTarget(ReaderBookmarkTarget? target) {
    if (_disposed || target == _currentTarget) return;
    _currentTarget = target;
    _setState(
      _state.copyWith(
        currentTarget: target,
        clearCurrentTarget: target == null,
      ),
    );
  }

  Future<ReaderBookmarkCommandResult> addBookmark() async {
    if (_disposed) return const ReaderBookmarkCommandResult.disposed();
    final target = _currentTarget;
    if (target == null) return const ReaderBookmarkCommandResult.notReady();
    final fingerprint = target.fingerprint;
    if (_pendingAdds.contains(fingerprint)) {
      final existing = _findByFingerprint(fingerprint);
      return existing == null
          ? const ReaderBookmarkCommandResult.notReady()
          : ReaderBookmarkCommandResult.alreadyExists(existing);
    }
    final existing = _findByFingerprint(fingerprint);
    if (existing != null) {
      return ReaderBookmarkCommandResult.alreadyExists(existing);
    }
    _pendingAdds.add(fingerprint);
    _setState(_state.copyWith(pendingFingerprint: fingerprint));
    try {
      final created = await _repository.createBookmark(
        bookId: bookId,
        locatorJson: _locatorJson(target),
        href: _href(target),
        progression: _progression(target),
        chapterTitle: _chapterTitle(target),
        position: _page(target),
      );
      if (_disposed) return const ReaderBookmarkCommandResult.disposed();
      _upsertBookmark(created);
      return created.fingerprint == fingerprint
          ? ReaderBookmarkCommandResult.added(created)
          : ReaderBookmarkCommandResult.alreadyExists(created);
    } catch (error) {
      if (_disposed) return const ReaderBookmarkCommandResult.disposed();
      _setState(_state.copyWith(error: error));
      return ReaderBookmarkCommandResult.failed(error);
    } finally {
      _pendingAdds.remove(fingerprint);
      _clearPendingFingerprint(fingerprint);
    }
  }

  Future<ReaderBookmarkCommandResult> removeCurrentBookmark() async {
    if (_disposed) return const ReaderBookmarkCommandResult.disposed();
    final target = _currentTarget;
    if (target == null) return const ReaderBookmarkCommandResult.notReady();
    final bookmark = _findByFingerprint(target.fingerprint);
    if (bookmark == null) return const ReaderBookmarkCommandResult.notReady();
    if (!_pendingDeletes.add(bookmark.id)) {
      return const ReaderBookmarkCommandResult.notReady();
    }
    _setState(_state.copyWith(pendingBookmarkId: bookmark.id));
    try {
      await _repository.deleteBookmark(bookmark.id);
      if (_disposed) return const ReaderBookmarkCommandResult.disposed();
      _state = _state.copyWith(
        bookmarks: _state.bookmarks
            .where((value) => value.id != bookmark.id)
            .toList(growable: false),
        clearPendingBookmarkId: true,
        clearError: true,
      );
      notifyListeners();
      return const ReaderBookmarkCommandResult.removed();
    } catch (error) {
      if (!_disposed) _setState(_state.copyWith(error: error));
      return _disposed
          ? const ReaderBookmarkCommandResult.disposed()
          : ReaderBookmarkCommandResult.failed(error);
    } finally {
      _pendingDeletes.remove(bookmark.id);
      if (!_disposed && _state.pendingBookmarkId == bookmark.id) {
        _setState(_state.copyWith(clearPendingBookmarkId: true));
      }
    }
  }

  Future<ReaderBookmarkCommandResult> deleteBookmark(
    LibraryBookmark bookmark,
  ) async {
    if (_disposed) return const ReaderBookmarkCommandResult.disposed();
    if (bookmark.bookId != bookId) {
      return const ReaderBookmarkCommandResult.failed();
    }
    if (!_pendingDeletes.add(bookmark.id)) {
      return const ReaderBookmarkCommandResult.notReady();
    }
    _setState(_state.copyWith(pendingBookmarkId: bookmark.id));
    try {
      await _repository.deleteBookmark(bookmark.id);
      if (_disposed) return const ReaderBookmarkCommandResult.disposed();
      _state = _state.copyWith(
        bookmarks: _state.bookmarks
            .where((value) => value.id != bookmark.id)
            .toList(growable: false),
        clearPendingBookmarkId: true,
        clearError: true,
      );
      notifyListeners();
      return const ReaderBookmarkCommandResult.removed();
    } catch (error) {
      if (!_disposed) _setState(_state.copyWith(error: error));
      return _disposed
          ? const ReaderBookmarkCommandResult.disposed()
          : ReaderBookmarkCommandResult.failed(error);
    } finally {
      _pendingDeletes.remove(bookmark.id);
      if (!_disposed && _state.pendingBookmarkId == bookmark.id) {
        _setState(_state.copyWith(clearPendingBookmarkId: true));
      }
    }
  }

  Future<ReaderBookmarkCommandResult> goToBookmark(
    LibraryBookmark bookmark,
  ) async {
    if (_disposed) return const ReaderBookmarkCommandResult.disposed();
    if (bookmark.bookId != bookId) {
      return const ReaderBookmarkCommandResult.failed();
    }
    final target = _targetFor(bookmark);
    if (target == null) {
      _setState(_state.copyWith(error: const InvalidBookmarkLocator()));
      return const ReaderBookmarkCommandResult.failed();
    }
    if (!_pendingNavigation.add(bookmark.id)) {
      return const ReaderBookmarkCommandResult.notReady();
    }
    try {
      final navigated = await _navigator(target);
      if (_disposed) return const ReaderBookmarkCommandResult.disposed();
      return navigated
          ? const ReaderBookmarkCommandResult.navigated()
          : const ReaderBookmarkCommandResult.failed();
    } catch (error) {
      if (!_disposed) _setState(_state.copyWith(error: error));
      return _disposed
          ? const ReaderBookmarkCommandResult.disposed()
          : ReaderBookmarkCommandResult.failed(error);
    } finally {
      _pendingNavigation.remove(bookmark.id);
    }
  }

  Future<void> updateBookmark(
    LibraryBookmark bookmark,
    BookmarkMetadataUpdate update,
  ) async {
    if (_disposed || bookmark.bookId != bookId) {
      throw StateError('bookmark_coordinator_disposed_or_mismatched');
    }
    final updated = await _repository.updateBookmarkMetadata(
      bookmarkId: bookmark.id,
      update: update,
    );
    if (!_disposed) _upsertBookmark(updated);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pendingAdds.clear();
    _pendingDeletes.clear();
    _pendingNavigation.clear();
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
  }

  void _replaceBookmarks(List<LibraryBookmark> incoming) {
    if (_disposed) return;
    final valid = <LibraryBookmark>[];
    final seen = <String>{};
    for (final bookmark in incoming) {
      if (bookmark.bookId != bookId) continue;
      final target = _targetFor(bookmark);
      if (target == null || !seen.add(target.fingerprint)) continue;
      valid.add(bookmark);
    }
    _setState(
      _state.copyWith(
        bookmarks: List<LibraryBookmark>.unmodifiable(valid),
        isLoading: false,
        clearError: true,
      ),
    );
  }

  void _handleRepositoryError(Object error, [StackTrace? _]) {
    if (_disposed) return;
    _setState(_state.copyWith(isLoading: false, error: error));
  }

  void _upsertBookmark(LibraryBookmark bookmark) {
    final target = _targetFor(bookmark);
    if (target == null) return;
    final next = [
      ..._state.bookmarks.where((value) => value.id != bookmark.id),
      bookmark,
    ];
    _setState(
      _state.copyWith(
        bookmarks: List<LibraryBookmark>.unmodifiable(next),
        isLoading: false,
        clearError: true,
      ),
    );
  }

  LibraryBookmark? _findByFingerprint(String fingerprint) {
    for (final bookmark in _state.bookmarks) {
      if (_targetFor(bookmark)?.fingerprint == fingerprint) return bookmark;
    }
    return null;
  }

  ReaderBookmarkTarget? _targetFor(LibraryBookmark bookmark) {
    if (readerKind == ReaderKind.epub) {
      return ReaderLocatorBookmarkTarget.tryParse(
        locatorJson: bookmark.locatorJson,
        progression: bookmark.progression,
        chapterTitle: bookmark.chapterTitle,
        href: bookmark.href,
      );
    }
    final page = bookmark.position;
    return page == null || page < 1
        ? null
        : ReaderPageBookmarkTarget(pageIndex: page);
  }

  String _locatorJson(ReaderBookmarkTarget target) => switch (target) {
    ReaderLocatorBookmarkTarget(:final locatorJson) => locatorJson,
    ReaderPageBookmarkTarget(:final pageIndex) =>
      '{"type":"page","page":$pageIndex}',
  };

  String? _href(ReaderBookmarkTarget target) => switch (target) {
    ReaderLocatorBookmarkTarget(:final href) => href,
    ReaderPageBookmarkTarget() => null,
  };

  double? _progression(ReaderBookmarkTarget target) => switch (target) {
    ReaderLocatorBookmarkTarget(:final progression) => progression,
    ReaderPageBookmarkTarget() => null,
  };

  String? _chapterTitle(ReaderBookmarkTarget target) => switch (target) {
    ReaderLocatorBookmarkTarget(:final chapterTitle) => chapterTitle,
    ReaderPageBookmarkTarget() => null,
  };

  int? _page(ReaderBookmarkTarget target) => switch (target) {
    ReaderLocatorBookmarkTarget() => null,
    ReaderPageBookmarkTarget(:final pageIndex) => pageIndex,
  };

  void _clearPendingFingerprint(String fingerprint) {
    if (_disposed || _state.pendingFingerprint != fingerprint) return;
    _setState(_state.copyWith(clearPendingFingerprint: true));
  }

  void _setState(ReaderBookmarkState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }
}

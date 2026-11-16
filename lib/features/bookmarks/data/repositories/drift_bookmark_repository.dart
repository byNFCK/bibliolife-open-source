import 'dart:convert';

import 'package:bibliolife/core/database/app_database.dart';
import 'package:bibliolife/features/bookmarks/data/mappers/bookmark_mapper.dart';
import 'package:bibliolife/features/bookmarks/domain/models/bookmark_metadata_update.dart';
import 'package:bibliolife/features/bookmarks/domain/models/library_bookmark.dart';
import 'package:bibliolife/features/bookmarks/domain/models/bookmark_location_key.dart';
import 'package:bibliolife/features/bookmarks/domain/repositories/bookmark_repository.dart';
import 'package:uuid/uuid.dart';

class DriftBookmarkRepository implements BookmarkRepository {
  DriftBookmarkRepository(
    this._dao, {
    String Function()? idGenerator,
    DateTime Function()? clock,
  }) : _idGenerator = idGenerator ?? const Uuid().v4,
       _clock = clock ?? DateTime.now;

  final BookmarksDao _dao;
  final String Function() _idGenerator;
  final DateTime Function() _clock;

  @override
  Stream<List<LibraryBookmark>> watchBookmarksForBook(String bookId) => _dao
      .watchForBook(_bookIdOrThrow(bookId))
      .map((rows) => rows.map((row) => row.toLibraryBookmark()).toList());

  @override
  Stream<List<LibraryBookmark>> watchAllBookmarks() => _dao.watchAll().map(
    (rows) => rows.map((row) => row.toLibraryBookmark()).toList(),
  );

  @override
  Future<LibraryBookmark?> getBookmarkById(String bookmarkId) async =>
      (await _dao.findById(bookmarkId))?.toLibraryBookmark();

  @override
  Future<LibraryBookmark> createBookmark({
    required String bookId,
    required String locatorJson,
    String? href,
    double? progression,
    String? chapterTitle,
    int? position,
    String? title,
    String? note,
  }) async {
    final normalizedBookId = _bookIdOrThrow(bookId);
    final normalizedLocator = _locatorOrThrow(locatorJson);
    _validateProgression(progression);
    if (position != null && position < 1) {
      throw const InvalidBookmarkProgression();
    }
    if (!await _dao.bookExists(normalizedBookId)) {
      throw MissingBookmarkBook(normalizedBookId);
    }
    final key = BookmarkLocationKey.fromValues(
      bookId: normalizedBookId,
      locatorJson: normalizedLocator,
      href: href,
      position: position,
      progression: progression,
    );
    if (key == null) throw const InvalidBookmarkLocator();
    return _dao.inTransaction(() async {
      final existing = await _matching(key);
      if (existing.isNotEmpty) return existing.first;
      final now = _clock();
      final bookmark = LibraryBookmark(
        id: _idGenerator(),
        bookId: normalizedBookId,
        locatorJson: normalizedLocator,
        href: _trimOrNull(href),
        progression: progression,
        position: position,
        chapterTitle: _trimOrNull(chapterTitle),
        title: _titleOrThrow(title),
        note: _noteOrThrow(note),
        createdAt: now,
        updatedAt: now,
      );
      await _dao.insertBookmark(bookmark.toBookmarksCompanion());
      return bookmark;
    });
  }

  @override
  Future<LibraryBookmark> updateBookmarkMetadata({
    required String bookmarkId,
    required BookmarkMetadataUpdate update,
  }) async {
    final current = await getBookmarkById(bookmarkId);
    if (current == null) {
      throw MissingBookmark(bookmarkId);
    }
    final title = switch (update.title) {
      Changed(:final value) => _titleOrThrow(value),
      Unchanged() => current.title,
    };
    final note = switch (update.note) {
      Changed(:final value) => _noteOrThrow(value),
      Unchanged() => current.note,
    };
    if (title == current.title && note == current.note) {
      return current;
    }
    final updatedAt = _clock();
    final updated = await _dao.updateBookmarkMetadata(
      id: current.id,
      title: title,
      note: note,
      updatedAt: updatedAt,
    );
    if (!updated) {
      throw MissingBookmark(bookmarkId);
    }
    return LibraryBookmark(
      id: current.id,
      bookId: current.bookId,
      locatorJson: current.locatorJson,
      href: current.href,
      progression: current.progression,
      position: current.position,
      chapterTitle: current.chapterTitle,
      title: title,
      note: note,
      createdAt: current.createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<void> deleteBookmark(String bookmarkId) async {
    await _dao.deleteById(bookmarkId);
  }

  @override
  Future<void> deleteBookmarksForBook(String bookId) async {
    await _dao.deleteForBook(_bookIdOrThrow(bookId));
  }

  @override
  Future<int> countBookmarksForBook(String bookId) =>
      _dao.countForBook(_bookIdOrThrow(bookId));

  @override
  Future<bool> isBookmarked(BookmarkLocationKey key) async =>
      (await _matching(key)).isNotEmpty;

  @override
  Future<void> removeBookmarksAt(BookmarkLocationKey key) =>
      _dao.inTransaction(() async {
        final matches = await _matching(key);
        await _dao.deleteByIds(matches.map((value) => value.id));
      });

  Future<List<LibraryBookmark>> _matching(BookmarkLocationKey key) async =>
      (await _dao.getForBook(key.bookId))
          .map((row) => row.toLibraryBookmark())
          .where(
            (bookmark) =>
                BookmarkLocationKey.fromValues(
                  bookId: bookmark.bookId,
                  locatorJson: bookmark.locatorJson,
                  href: bookmark.href,
                  position: bookmark.position,
                  progression: bookmark.progression,
                  readerKind: key.readerKind,
                ) ==
                key,
          )
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  String _bookIdOrThrow(String value) {
    final id = value.trim();
    if (id.isEmpty) {
      throw MissingBookmarkBook(id);
    }
    return id;
  }

  String _locatorOrThrow(String value) {
    final locator = value.trim();
    if (locator.isEmpty) {
      throw const InvalidBookmarkLocator();
    }
    try {
      if (jsonDecode(locator) is! Map<String, dynamic>) {
        throw const InvalidBookmarkLocator();
      }
    } on FormatException {
      throw const InvalidBookmarkLocator();
    }
    return locator;
  }

  void _validateProgression(double? value) {
    if (value != null && (!value.isFinite || value < 0 || value > 1)) {
      throw const InvalidBookmarkProgression();
    }
  }

  String? _trimOrNull(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  String? _titleOrThrow(String? value) {
    final normalized = _trimOrNull(value);
    if ((normalized?.length ?? 0) > 200) {
      throw const InvalidBookmarkTitle();
    }
    return normalized;
  }

  String? _noteOrThrow(String? value) {
    final normalized = _trimOrNull(value);
    if ((normalized?.length ?? 0) > 5000) throw const InvalidBookmarkNote();
    return normalized;
  }
}

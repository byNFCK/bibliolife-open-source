import 'dart:async';

import 'package:bibliolife/features/bookmarks/domain/models/bookmark_location_key.dart';
import 'package:bibliolife/features/bookmarks/domain/models/bookmark_metadata_update.dart';
import 'package:bibliolife/features/bookmarks/domain/models/library_bookmark.dart';
import 'package:bibliolife/features/bookmarks/domain/repositories/bookmark_repository.dart';
import 'package:bibliolife/features/reader/application/services/reader_bookmark_coordinator.dart';
import 'package:bibliolife/features/reader/domain/models/reader_bookmark.dart';
import 'package:bibliolife/features/reader/domain/models/reader_bookmark_target.dart';
import 'package:bibliolife/features/reader/domain/models/reader_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const locator =
      '{"type":"application/xhtml+xml","href":"chapter.xhtml",'
      '"locations":{"progression":0.25,"fragments":["p1"]}}';

  test('locator target preserves bytes and canonicalizes fingerprint', () {
    final target = ReaderLocatorBookmarkTarget.tryParse(
      locatorJson: locator,
      progression: .25,
      chapterTitle: 'Розділ',
      href: 'chapter.xhtml',
    );
    expect(target, isNotNull);
    expect(target!.locatorJson, locator);
    expect(target.progression, .25);
    expect(target.chapterTitle, 'Розділ');
    expect(
      target.fingerprint,
      ReaderLocatorBookmarkTarget.tryParse(
        locatorJson:
            '{"locations":{"fragments":["p1"],"progression":0.25},'
            '"href":"chapter.xhtml","type":"application/xhtml+xml"}',
      )!.fingerprint,
    );
    expect(
      ReaderLocatorBookmarkTarget.tryParse(locatorJson: '{"href":""}'),
      isNull,
    );
    expect(ReaderPageBookmarkTarget(pageIndex: 4).fingerprint, 'page:4');
  });

  test(
    'EPUB coordinator deduplicates, removes and navigates by locator',
    () async {
      final repository = _FakeBookmarkRepository();
      ReaderBookmarkTarget? navigated;
      final coordinator = ReaderBookmarkCoordinator(
        bookId: 'book',
        readerKind: ReaderKind.epub,
        repository: repository,
        navigator: (target) async {
          navigated = target;
          return true;
        },
      );
      await coordinator.start();
      coordinator.updateCurrentTarget(
        ReaderLocatorBookmarkTarget.tryParse(
          locatorJson: locator,
          progression: .25,
          chapterTitle: 'Розділ',
          href: 'chapter.xhtml',
        ),
      );
      await repository.emit(const <LibraryBookmark>[]);

      final first = await coordinator.addBookmark();
      final repeated = await coordinator.addBookmark();
      expect(first.status, ReaderBookmarkCommandStatus.added);
      expect(repeated.status, ReaderBookmarkCommandStatus.alreadyExists);
      expect(repository.createCalls, 1);
      expect(coordinator.isCurrentPositionBookmarked, isTrue);

      final bookmark = first.bookmark!;
      expect((await coordinator.goToBookmark(bookmark)).isSuccess, isTrue);
      expect((navigated! as ReaderLocatorBookmarkTarget).locatorJson, locator);
      expect((await coordinator.removeCurrentBookmark()).isSuccess, isTrue);
      expect(coordinator.isCurrentPositionBookmarked, isFalse);
      coordinator.dispose();
      coordinator.dispose();
    },
  );

  test('location keys include reader kind and full Readium location', () {
    final epub = BookmarkLocationKey.fromValues(
      bookId: 'book',
      locatorJson: locator,
      readerKind: 'epub',
    );
    final pdf = BookmarkLocationKey.fromValues(
      bookId: 'book',
      locatorJson: locator,
      readerKind: 'pdf',
    );
    final otherPosition = BookmarkLocationKey.fromValues(
      bookId: 'book',
      locatorJson: locator.replaceAll('p1', 'p2'),
      readerKind: 'epub',
    );
    expect(epub, isNot(pdf));
    expect(epub, isNot(otherPosition));
  });
}

class _FakeBookmarkRepository implements BookmarkRepository {
  final _events = StreamController<List<LibraryBookmark>>.broadcast();
  final _rows = <LibraryBookmark>[];
  int createCalls = 0;
  int _id = 0;

  Future<void> emit(List<LibraryBookmark> rows) async {
    _events.add(rows);
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Stream<List<LibraryBookmark>> watchBookmarksForBook(String bookId) async* {
    yield List<LibraryBookmark>.unmodifiable(_rows);
    yield* _events.stream;
  }

  @override
  Stream<List<LibraryBookmark>> watchAllBookmarks() => _events.stream;

  @override
  Future<LibraryBookmark?> getBookmarkById(String bookmarkId) async =>
      _rows.where((row) => row.id == bookmarkId).firstOrNull;

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
    createCalls++;
    final value = LibraryBookmark(
      id: 'bookmark-${++_id}',
      bookId: bookId,
      locatorJson: locatorJson,
      href: href,
      progression: progression,
      position: position,
      chapterTitle: chapterTitle,
      title: title,
      note: note,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    _rows.add(value);
    await emit(List<LibraryBookmark>.unmodifiable(_rows));
    return value;
  }

  @override
  Future<LibraryBookmark> updateBookmarkMetadata({
    required String bookmarkId,
    required BookmarkMetadataUpdate update,
  }) async => (await getBookmarkById(bookmarkId))!;

  @override
  Future<void> deleteBookmark(String bookmarkId) async {
    _rows.removeWhere((row) => row.id == bookmarkId);
    await emit(List<LibraryBookmark>.unmodifiable(_rows));
  }

  @override
  Future<void> deleteBookmarksForBook(String bookId) async {}

  @override
  Future<int> countBookmarksForBook(String bookId) async => _rows.length;

  @override
  Future<bool> isBookmarked(BookmarkLocationKey key) async => false;

  @override
  Future<void> removeBookmarksAt(BookmarkLocationKey key) async {}
}

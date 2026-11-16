import 'package:bibliolife/features/bookmarks/domain/models/library_bookmark.dart';
import 'package:bibliolife/features/bookmarks/presentation/widgets/bookmark_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LibraryBookmark bookmark({
    String? title,
    String? chapterTitle,
    int? position,
  }) => LibraryBookmark(
    id: 'id',
    bookId: 'book',
    locatorJson: '{}',
    href: null,
    progression: .25,
    position: position,
    chapterTitle: chapterTitle,
    title: title,
    note: null,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  Future<void> pump(WidgetTester tester, LibraryBookmark value) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookmarkListTile(
              bookmark: value,
              onOpen: () {},
              onEdit: () async {},
              onDelete: () async {},
            ),
          ),
        ),
      );
  testWidgets('shows position as secondary metadata when title exists', (
    tester,
  ) async {
    await pump(tester, bookmark(title: 'Named', position: 42));
    expect(find.text('Named'), findsOneWidget);
    expect(find.textContaining('Page 42'), findsOneWidget);
  });
  testWidgets('uses position as fallback without duplicate secondary label', (
    tester,
  ) async {
    await pump(tester, bookmark(position: 42));
    expect(find.text('Page 42'), findsOneWidget);
  });
}

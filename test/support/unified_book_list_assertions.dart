import 'package:bibliolife/shared/presentation/widgets/app_book_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Check actual screen composition, not merely the shared widget in isolation.
void expectUnifiedBookList(WidgetTester tester) {
  final rows = find.byType(AppBookListTile).hitTestable();
  expect(rows, findsWidgets);
  for (final element in rows.evaluate()) {
    final row = find.byElementPredicate(
      (candidate) => identical(candidate, element),
    );
    final bounds = tester.getRect(row);
    final viewport = tester.getRect(
      find.ancestor(of: row, matching: find.byType(Scrollable)).first,
    );
    final viewportWidth = viewport.width;
    final cover = tester.getRect(
      find.descendant(
        of: row,
        matching: find.byKey(const Key('book-list-cover')),
      ),
    );
    final title = tester.getRect(
      find.descendant(
        of: row,
        matching: find.byKey(const Key('book-list-title')),
      ),
    );
    final action = tester.getRect(
      find.descendant(
        of: row,
        matching: find.byKey(const Key('book-list-actions')),
      ),
    );
    expect(bounds.left, closeTo(viewport.left, .01));
    expect(bounds.width, closeTo(viewportWidth, .01));
    expect(cover.size, const Size(92, 138));
    expect(cover.left - viewport.left, 16);
    expect(title.left - viewport.left, 124);
    expect(action.right - viewport.left, closeTo(viewportWidth - 16, .01));
    expect(action.size, const Size(48, 48));
    expect(title.right, lessThanOrEqualTo(action.left + .01));
    final tile = element.widget as AppBookListTile;
    expect(tile.actions.length, lessThanOrEqualTo(1));
    final icon = find.descendant(
      of: row,
      matching: find.byIcon(Icons.more_vert),
    );
    if (icon.evaluate().isNotEmpty) {
      final context = tester.element(row);
      final scale = MediaQuery.textScalerOf(context).scale(18);
      expect(
        tester.getCenter(icon).dy,
        closeTo(title.top + scale * 1.2 / 2, 2),
      );
    }
    if (tile.bookStatus != null || tile.status != null) {
      final bottom = tester.getRect(
        find.descendant(
          of: row,
          matching: find.byKey(const Key('book-list-bottom')),
        ),
      );
      expect(bottom.left, title.left);
      expect(bottom.bottom, greaterThanOrEqualTo(cover.bottom - .01));
    }

    final list = find
        .ancestor(of: row, matching: find.byType(SliverList))
        .first;
    expect(
      find.descendant(of: list, matching: find.byType(Divider)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              RegExp(r'^(EPUB|PDF)$').hasMatch(widget.data ?? ''),
        ),
      ),
      findsNothing,
    );
  }
}

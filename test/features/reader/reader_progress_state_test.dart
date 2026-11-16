import 'package:bibliolife/features/reader/domain/models/reader_progress_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reflowable position is secondary to authoritative progression', () {
    final state = ReaderProgressState.reflowable(
      progression: .63,
      logicalPosition: 42,
      totalLogicalPositions: 100,
    );

    expect(state.metric, ReaderProgressMetric.reflowablePosition);
    expect(state.label, 'Progress 63%');
    expect(state.progression, .63);
    expect(state.current, 41);
    expect(state.total, 100);
  });

  test('repeated and jumping logical positions are accepted unchanged', () {
    final repeated = ReaderProgressState.reflowable(
      progression: .41,
      logicalPosition: 20,
      totalLogicalPositions: 90,
    );
    final nextViewportSamePosition = ReaderProgressState.reflowable(
      progression: .43,
      logicalPosition: 20,
      totalLogicalPositions: 90,
    );
    final laterJump = ReaderProgressState.reflowable(
      progression: .51,
      logicalPosition: 27,
      totalLogicalPositions: 90,
    );

    expect(nextViewportSamePosition.label, 'Progress 43%');
    expect(nextViewportSamePosition.label, isNot(contains('Position')));
    expect(
      nextViewportSamePosition.progression,
      greaterThan(repeated.progression),
    );
    expect(laterJump.label, 'Progress 51%');
  });

  test(
    'missing position falls back to progression without fabricating zero',
    () {
      final state = ReaderProgressState.reflowable(progression: .184);

      expect(state.label, 'Progress 18%');
      expect(state.label, isNot(contains('0')));
      expect(state.canSeek, isTrue);
    },
  );

  test('fixed-layout page remains discrete and exact', () {
    final state = ReaderProgressState.page(page: 7, total: 19);

    expect(state.metric, ReaderProgressMetric.fixedPage);
    expect(state.label, 'Page 7 of 19');
    expect(state.pageFor(.5), 10);
  });

  test('publication-scoped rendered page is discrete and exact', () {
    final state = ReaderProgressState.renderedPage(
      pageIndex: 3,
      pageCount: 7,
      progression: .5,
      publicationScoped: true,
    );

    expect(state.metric, ReaderProgressMetric.renderedPage);
    expect(state.label, 'Page 4 of 7');
    expect(state.progression, .5);
    expect(state.pageFor(.5), 4);
  });

  test('resource-local rendered page never claims a global total', () {
    final state = ReaderProgressState.renderedPage(
      pageIndex: 3,
      pageCount: 7,
      progression: .42,
      publicationScoped: false,
    );

    expect(state.label, 'Page 4');
    expect(state.total, 0);
    expect(state.progression, .42);
  });
}

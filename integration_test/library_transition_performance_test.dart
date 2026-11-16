import 'package:bibliolife/main.dart' as app;
import 'package:bibliolife/features/library/presentation/widgets/library_book_card.dart';
import 'package:bibliolife/features/library/presentation/widgets/library_book_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Library transition performance benchmark',
    (tester) async {
      app.main();
      await tester.pump();
      await _waitFor(tester, _navigationLibrary);
      await tester.tap(_navigationLibrary);
      await _settle(tester);

      await _verifyLibraryData(tester);
      final retention = _PageRetentionSnapshot.capture(tester);
      _marker('phase=benchmark_start');

      _marker('phase=warmup_start');
      var current = 'collection';
      for (final target in const [
        'follow',
        'all_books',
        'follow',
        'collection',
      ]) {
        await _transition(
          tester,
          input: 'tap',
          from: current,
          to: target,
          measured: false,
          scope: 'warmup',
        );
        current = target;
      }
      _marker('phase=warmup_end result=completed');

      _marker('phase=tap_measurement_start');
      for (var sample = 1; sample <= 10; sample++) {
        await _transition(
          tester,
          input: 'tap',
          from: 'collection',
          to: 'follow',
          measured: true,
          scope: 'tap',
          sample: sample,
        );
        await _transition(
          tester,
          input: 'tap',
          from: 'follow',
          to: 'collection',
          measured: true,
          scope: 'tap',
          sample: sample,
        );
      }

      await _transition(
        tester,
        input: 'tap',
        from: 'collection',
        to: 'follow',
        measured: false,
        scope: 'tap_setup',
      );
      current = 'follow';
      for (var sample = 1; sample <= 10; sample++) {
        await _transition(
          tester,
          input: 'tap',
          from: current,
          to: 'all_books',
          measured: true,
          scope: 'tap',
          sample: sample,
        );
        current = 'all_books';
        await _transition(
          tester,
          input: 'tap',
          from: current,
          to: 'follow',
          measured: true,
          scope: 'tap',
          sample: sample,
        );
        current = 'follow';
      }

      await _transition(
        tester,
        input: 'tap',
        from: 'follow',
        to: 'collection',
        measured: false,
        scope: 'tap_setup',
      );
      current = 'collection';
      for (var sample = 1; sample <= 5; sample++) {
        await _transition(
          tester,
          input: 'tap',
          from: current,
          to: 'all_books',
          measured: true,
          scope: 'tap',
          sample: sample,
        );
        current = 'all_books';
        await _transition(
          tester,
          input: 'tap',
          from: current,
          to: 'collection',
          measured: true,
          scope: 'tap',
          sample: sample,
        );
        current = 'collection';
      }
      _marker('phase=tap_measurement_end result=completed');

      _marker('phase=swipe_measurement_start');
      for (var sample = 1; sample <= 10; sample++) {
        await _transition(
          tester,
          input: 'swipe',
          from: 'collection',
          to: 'follow',
          measured: true,
          scope: 'swipe',
          sample: sample,
        );
        await _transition(
          tester,
          input: 'swipe',
          from: 'follow',
          to: 'collection',
          measured: true,
          scope: 'swipe',
          sample: sample,
        );
      }

      await _transition(
        tester,
        input: 'swipe',
        from: 'collection',
        to: 'follow',
        measured: false,
        scope: 'swipe_setup',
      );
      current = 'follow';
      for (var sample = 1; sample <= 10; sample++) {
        await _transition(
          tester,
          input: 'swipe',
          from: current,
          to: 'all_books',
          measured: true,
          scope: 'swipe',
          sample: sample,
        );
        current = 'all_books';
        await _transition(
          tester,
          input: 'swipe',
          from: current,
          to: 'follow',
          measured: true,
          scope: 'swipe',
          sample: sample,
        );
        current = 'follow';
      }
      _marker('phase=swipe_measurement_end result=completed');

      final retentionResult = retention.compare(tester);
      _marker(
        'phase=retention_check result=${retentionResult.allStable ? 'stable' : 'changed'} '
        'page_controller_same=${retentionResult.pageControllerSame} '
        'collection_root_same=${retentionResult.collectionRootSame} '
        'follow_root_same=${retentionResult.followRootSame} '
        'all_books_root_same=${retentionResult.allBooksRootSame}',
      );
      expect(retentionResult.allStable, isTrue);

      await _runScrollStateRegression(tester);
      _marker('phase=benchmark_end result=completed');
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

final _navigationLibrary = find.byKey(const Key('navigation-destination-1'));
final _pageView = find.byKey(const Key('library-page-view'));

final class _PageRetentionSnapshot {
  const _PageRetentionSnapshot({
    required this.pageController,
    required this.collectionRoot,
    required this.followRoot,
    required this.allBooksRoot,
  });

  factory _PageRetentionSnapshot.capture(WidgetTester tester) {
    return _PageRetentionSnapshot(
      pageController: tester.widget<PageView>(_pageView).controller,
      collectionRoot: tester.element(_pageRoot('collection')),
      followRoot: tester.element(_pageRoot('follow')),
      allBooksRoot: tester.element(_pageRoot('all_books')),
    );
  }

  final PageController? pageController;
  final Element collectionRoot;
  final Element followRoot;
  final Element allBooksRoot;

  _PageRetentionResult compare(WidgetTester tester) {
    final currentController = tester.widget<PageView>(_pageView).controller;
    return _PageRetentionResult(
      pageControllerSame: identical(pageController, currentController),
      collectionRootSame: identical(
        collectionRoot,
        tester.element(_pageRoot('collection')),
      ),
      followRootSame: identical(
        followRoot,
        tester.element(_pageRoot('follow')),
      ),
      allBooksRootSame: identical(
        allBooksRoot,
        tester.element(_pageRoot('all_books')),
      ),
    );
  }
}

final class _PageRetentionResult {
  const _PageRetentionResult({
    required this.pageControllerSame,
    required this.collectionRootSame,
    required this.followRootSame,
    required this.allBooksRootSame,
  });

  final bool pageControllerSame;
  final bool collectionRootSame;
  final bool followRootSame;
  final bool allBooksRootSame;

  bool get allStable =>
      pageControllerSame &&
      collectionRootSame &&
      followRootSame &&
      allBooksRootSame;
}

Finder _tab(String section) => find.byKey(
  Key('library-tab-${section == 'all_books' ? 'all-books' : section}'),
);

Finder _pageRoot(String section) => find.byKey(switch (section) {
  'collection' => const PageStorageKey<String>('library-collection-page'),
  'follow' => const ValueKey<String>('library-follow-page'),
  'all_books' => const ValueKey<String>('library-all-books-page'),
  _ => const ValueKey<String>('library-unknown-page'),
}, skipOffstage: false);

Future<void> _verifyLibraryData(WidgetTester tester) async {
  await _goToSection(tester, 'collection');
  expect(_pageRoot('collection'), findsOneWidget);
  await _goToSection(tester, 'follow');
  expect(_pageRoot('follow'), findsOneWidget);
  await _goToSection(tester, 'all_books');
  expect(_pageRoot('all_books'), findsOneWidget);
  await _settle(tester);

  final cards = find.byType(LibraryBookCard).evaluate().length;
  final tiles = find.byType(LibraryBookTile).evaluate().length;
  final books = cards + tiles;
  _marker('phase=data_verified all_books_items=$books');
  expect(books, greaterThan(0));

  await _goToSection(tester, 'collection');
}

Future<void> _goToSection(WidgetTester tester, String section) async {
  await tester.tap(_tab(section));
  await _settle(tester);
  await _waitFor(tester, _pageRoot(section));
}

Future<void> _transition(
  WidgetTester tester, {
  required String input,
  required String from,
  required String to,
  required bool measured,
  required String scope,
  int? sample,
}) async {
  if (from == to) {
    throw StateError('Benchmark transition must change section: $from');
  }
  final measuredValue = measured ? 'true' : 'false';
  _marker(
    'phase=transition_start input=$input from=$from to=$to '
    'measured=$measuredValue scope=$scope sample=${sample ?? 0}',
  );

  if (input == 'tap') {
    await tester.tap(_tab(to));
  } else {
    final rect = tester.getRect(_pageView);
    final distance = rect.width * 0.68;
    await tester.fling(
      _pageView,
      Offset(toIndex(to) > toIndex(from) ? -distance : distance, 0),
      900,
    );
  }
  await _settle(tester);
  await _waitFor(tester, _pageRoot(to));

  _marker(
    'phase=transition_end input=$input from=$from to=$to '
    'measured=$measuredValue scope=$scope sample=${sample ?? 0}',
  );
}

Future<void> _runScrollStateRegression(WidgetTester tester) async {
  _marker('phase=scroll_regression_start');
  await _goToSection(tester, 'all_books');
  final root = _pageRoot('all_books');
  final scrollable = find.descendant(
    of: root,
    matching: find.byType(Scrollable),
  );
  if (scrollable.evaluate().isEmpty) {
    _marker('phase=scroll_regression_end result=no_scrollable');
    return;
  }

  final before = tester.state<ScrollableState>(scrollable).position.pixels;
  await tester.fling(scrollable, const Offset(0, -520), 900);
  await _settle(tester);
  final after = tester.state<ScrollableState>(scrollable).position.pixels;
  if (after <= before + 1) {
    _marker('phase=scroll_regression_end result=not_scrollable');
    return;
  }

  await _goToSection(tester, 'follow');
  await _goToSection(tester, 'all_books');
  final restored = tester
      .state<ScrollableState>(
        find.descendant(
          of: _pageRoot('all_books'),
          matching: find.byType(Scrollable),
        ),
      )
      .position
      .pixels;
  final preserved = (restored - after).abs() <= 2;
  _marker(
    'phase=scroll_regression_end result=${preserved ? 'preserved' : 'changed'} '
    'before=$before after=$after restored=$restored',
  );
  expect(preserved, isTrue);
}

int toIndex(String section) => switch (section) {
  'collection' => 0,
  'follow' => 1,
  'all_books' => 2,
  _ => throw ArgumentError.value(section, 'section'),
};

Future<void> _settle(WidgetTester tester) async {
  var idlePumps = 0;
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (tester.binding.hasScheduledFrame) {
      idlePumps = 0;
      continue;
    }
    idlePumps += 1;
    if (idlePumps >= 2) return;
  }
  throw TestFailure('Timed out waiting for the Library transition to settle');
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 120; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  throw TestFailure('Timed out waiting for $finder');
}

void _marker(String value) {
  // ignore: avoid_print
  print('LIBRARY_BENCHMARK $value');
}

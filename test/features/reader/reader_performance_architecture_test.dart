import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reader route uses a bounded transform transition and async ownership',
    () {
      final router = File('lib/app/router/app_router.dart').readAsStringSync();
      final local = File(
        'lib/features/reader/presentation/screens/local_reader_body.dart',
      ).readAsStringSync();
      final adapter = File(
        'lib/features/reader/presentation/models/readium_epub_reader_controller.dart',
      ).readAsStringSync();

      expect(router, contains('CustomTransitionPage<void>'));
      expect(router, contains('FadeTransition'));
      expect(router, contains('SlideTransition'));
      expect(router, isNot(contains('BackdropFilter')));
      expect(local, contains('unawaited(_initializeAnnotations(_adapter))'));
      expect(local, contains('unawaited(_annotationCoordinator?.dispose())'));
      expect(adapter, contains('Future<void> disposeAndWait()'));
      expect(adapter, contains('_disposal = () async {'));
      expect(adapter, contains('await diagnosticSubscription?.cancel()'));
      expect(adapter, contains('await controller?.dispose()'));
      expect(adapter, contains('return _disposal ?? Future<void>.value()'));
    },
  );

  test('system UI and viewport are outside high-frequency rebuild paths', () {
    final unified = File(
      'lib/features/reader/presentation/widgets/unified_reader_screen.dart',
    ).readAsStringSync();
    final local = File(
      'lib/features/reader/presentation/screens/local_reader_body.dart',
    ).readAsStringSync();
    final hostStart = local.indexOf('class _ReadiumEpubViewportHostState');
    final hostEnd = local.indexOf('class _ComicViewport', hostStart);
    final host = local.substring(hostStart, hostEnd);

    expect(unified, contains("Key('reader-stable-viewport-boundary')"));
    expect(unified, isNot(contains('addListener(_syncSystemUi)')));
    expect(host, isNot(contains('AnimatedBuilder')));
    expect(host, contains('removeListener(_adapterChanged)'));
    expect(host, contains('oldWidget.adapter.removeListener(_adapterChanged)'));
    expect(host, contains('widget.adapter.addListener(_adapterChanged)'));
    expect(host, contains('identical(controller, _renderedController)'));
    expect(host, contains('configuration == _renderedConfiguration'));
  });

  test('reader menus use the stable modal route and lazy large lists', () {
    final stable = File(
      'lib/features/reader/presentation/widgets/reader_stable_components.dart',
    ).readAsStringSync();
    final unified = File(
      'lib/features/reader/presentation/widgets/unified_reader_screen.dart',
    ).readAsStringSync();
    final search = File(
      'lib/features/reader/presentation/widgets/reader_search_sheet.dart',
    ).readAsStringSync();
    final saved = File(
      'lib/features/reader/presentation/widgets/reader_saved_items_sheet.dart',
    ).readAsStringSync();

    expect(stable, contains('showModalBottomSheet<T>'));
    expect(stable, contains('sheetAnimationStyle: appModalSheetAnimation'));
    expect(stable, isNot(contains('ReaderMenuRoute')));
    expect(stable, isNot(contains('IgnorePointer(child: ColoredBox')));
    expect(stable, isNot(contains('clipBehavior: Clip.hardEdge')));
    expect(stable, isNot(contains('BackdropFilter')));
    expect(unified, contains('ListView.separated'));
    expect(search, contains('ListView.builder'));
    expect(saved, contains('ListView.separated'));
    expect(saved, isNot(contains('Listenable.merge([widget.controller')));
  });

  test('performance diagnostics remain explicitly opt in', () {
    final source = File(
      'lib/features/reader/performance/reader_performance.dart',
    ).readAsStringSync();
    expect(source, contains("'BIBLIOLIFE_READER_PERF_LOGS'"));
    expect(source, contains('defaultValue: false'));
    expect(source, contains('READER_PERF_FRAME_SUMMARY'));
  });

  test('menu diagnostics classify menu lifecycle and scroll timing', () {
    final source = File(
      'lib/features/reader/performance/reader_performance.dart',
    ).readAsStringSync();
    final stable = File(
      'lib/features/reader/presentation/widgets/reader_stable_components.dart',
    ).readAsStringSync();

    expect(source, contains('READER_PERF_MENU_SUMMARY'));
    expect(source, contains('READER_PERF_MENU_SCROLL'));
    expect(source, contains('over33='));
    expect(source, contains('rowBuilds='));
    expect(source, contains('nativePositionEvents='));
    expect(source, contains('nativeRenderedPageEvents='));
    expect(source, contains('nativeChapterEvents='));
    expect(source, contains('controllerNotifications='));
    expect(source, contains('backgroundReaderRebuilds='));
    expect(source, contains('backgroundChromeBuilds='));
    expect(source, contains('viewportWrapperBuilds='));
    expect(source, contains('platformViewBackend='));
    expect(
      source,
      contains('ReadiumAndroidCompositionDiagnostics.activeBackendLabel'),
    );
    expect(stable, contains('ReaderMenuPerformanceScope'));
  });

  test('equal native position payloads are structurally deduplicated', () {
    final adapter = File(
      'lib/features/reader/presentation/models/readium_epub_reader_controller.dart',
    ).readAsStringSync();

    expect(
      adapter,
      contains('sameReadiumPositionForPerformance(position, _lastPosition)'),
    );
    expect(adapter, contains('avoiding duplicate'));
    expect(adapter, contains('recordNativePositionEvent'));
  });

  test(
    'saved-item tabs use transform-only switching and toc rows are cached',
    () {
      final saved = File(
        'lib/features/reader/presentation/widgets/reader_saved_items_sheet.dart',
      ).readAsStringSync();
      final unified = File(
        'lib/features/reader/presentation/widgets/unified_reader_screen.dart',
      ).readAsStringSync();

      expect(saved, contains('IndexedStack'));
      expect(saved, isNot(contains('FadeTransition')));
      expect(saved, contains('PageStorageKey'));
      expect(
        unified,
        contains('late List<({ReaderTocEntry entry, int depth})> _rows'),
      );
      expect(
        unified,
        contains("ValueKey('reader-toc-entry-\${row.entry.id}')"),
      );
    },
  );
}

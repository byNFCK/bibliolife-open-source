import 'dart:async';

import 'package:bibliolife/features/reader/presentation/widgets/reader_stable_components.dart';
import 'package:bibliolife/features/reader/domain/models/reader_capabilities.dart';
import 'package:bibliolife/features/reader/domain/models/reader_kind.dart';
import 'package:bibliolife/features/reader/domain/models/reader_progress_state.dart';
import 'package:bibliolife/features/reader/presentation/models/reader_ui_controller.dart';
import 'package:bibliolife/features/reader/domain/models/reader_settings.dart';
import 'package:bibliolife/features/reader/presentation/widgets/unified_reader_screen.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:bibliolife/shared/presentation/widgets/app_modal_sheet_scaffold.dart';
import 'package:bibliolife/shared/presentation/widgets/biblio_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reader menu invocation always mounts the canonical scaffold', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              key: const Key('open-reader-menu'),
              onPressed: () => showReaderMenu<void>(
                context: context,
                title: 'Bookmarks and annotations',
                child: const SizedBox(height: 120, child: Text('content')),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-reader-menu')));
    await tester.pumpAndSettle();

    expect(find.byType(ReaderMenuScaffold), findsOneWidget);
    expect(find.byKey(const Key('app-modal-sheet')), findsOneWidget);
  });

  testWidgets('modal barrier keeps full viewport bounds during entrance', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showReaderMenu<void>(
                context: context,
                title: 'Bounds test',
                child: const SizedBox(height: 180),
              ),
              child: const Text('Open bounds test'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open bounds test'));
    await tester.pump(const Duration(milliseconds: 32));
    final barrier = find.byType(ModalBarrier).last;
    final first = tester.getRect(barrier);
    await tester.pump(const Duration(milliseconds: 64));
    final second = tester.getRect(barrier);

    expect(first, second);
    expect(
      first,
      Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio,
    );
  });

  testWidgets('reader modal completes twenty open and close cycles', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showReaderMenu<void>(
                context: context,
                title: 'Lifecycle test',
                child: const SizedBox(height: 120),
              ),
              child: const Text('Open lifecycle test'),
            ),
          ),
        ),
      ),
    );

    for (var cycle = 0; cycle < 20; cycle++) {
      await tester.tap(find.text('Open lifecycle test'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('app-modal-sheet')), findsOneWidget);
      Navigator.of(
        tester.element(find.byKey(const Key('app-modal-sheet'))),
      ).pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('app-modal-sheet')), findsNothing);
    }
  });

  testWidgets('reader menus share the canonical sheet shell', (tester) async {
    for (final title in const [
      'Reading progress',
      'Bookmarks and annotations',
      'Reader settings',
      'Table of contents',
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderMenuScaffold(
              title: title,
              footer: const ReaderMenuSingleActionFooter(),
              child: const SizedBox(
                height: 120,
                child: Center(child: Text('content')),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('app-modal-sheet')), findsOneWidget);
      expect(find.byKey(const Key('app-modal-drag-handle')), findsOneWidget);
      expect(find.text(title), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('content'), findsOneWidget);
    }
  });

  testWidgets('reader shell keeps footer reachable with keyboard insets', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(viewInsets: EdgeInsets.only(bottom: 420)),
        child: const MaterialApp(
          home: Scaffold(
            body: ReaderMenuScaffold(
              title: 'Reader settings',
              footer: ReaderMenuSingleActionFooter(),
              child: SizedBox(height: 300, child: Text('settings')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final footer = tester.getBottomRight(find.text('Cancel')).dy;
    expect(footer, lessThanOrEqualTo(600));
    expect(find.byKey(const Key('app-modal-drag-handle')), findsOneWidget);
  });

  testWidgets('reader settings choice forwards the selected BiblioTabs ID', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderSettingsChoiceField<int>(
            label: 'Test setting',
            items: const [
              BiblioTabItem(id: 0, label: 'First'),
              BiblioTabItem(id: 1, label: 'Second'),
            ],
            selectedId: selected,
            onSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    expect(find.byType(BiblioTabs<int>), findsOneWidget);
    await tester.tap(find.text('Second'));
    await tester.pump();
    expect(selected, 1);
  });

  testWidgets('progress uses one canonical upper and lower decorative strip', (
    tester,
  ) async {
    final controller = _ReaderMenuController()
      ..setProgress(ReaderProgressState.page(page: 2, total: 10));
    await _pumpReader(tester, controller);

    await tester.tap(find.text('Progress 11%'));
    await tester.pumpAndSettle();

    _expectCanonicalStripGeometry(tester);
    expect(find.byType(Divider), findsNWidgets(2));
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('Go to position'), findsOneWidget);
  });

  testWidgets('progress slider fades reader surfaces and releases on dispose', (
    tester,
  ) async {
    for (final width in [390.0, 412.0]) {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      final controller = _ReaderMenuController();
      controller.setProgress(
        ReaderProgressState.progression(progression: .2),
        seek: (value) async => controller.setProgress(
          ReaderProgressState.progression(progression: value),
        ),
      );
      await _pumpReader(tester, controller);
      expect(
        find.ancestor(
          of: find.byKey(const Key('reader-stable-viewport-boundary')),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );

      await tester.tap(find.text('Progress 20%'));
      await tester.pumpAndSettle();
      var slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, .2);
      expect(slider.onChanged, isNotNull);
      expect(_sheetMaterial(tester).color!.a, closeTo(1, .001));

      slider.onChangeStart!(.2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(controller.isSliderInteractionActive, isTrue);
      expect(controller.activeSliderId, ReaderSliderId.progress);
      expect(_sheetMaterial(tester).color!.a, closeTo(.15, .01));
      expect(
        _focusOpacity(tester, 'reader-slider-focus-progress'),
        closeTo(1, .001),
      );
      expect(
        _effectiveOpacity(
          tester,
          find.descendant(
            of: find.byKey(const Key('reader-slider-focus-progress')),
            matching: find.byType(Slider),
          ),
        ),
        closeTo(1, .001),
      );
      expect(
        _effectiveOpacity(tester, find.byType(ModalBarrier).last),
        closeTo(.15, .001),
      );
      expect(
        _effectiveOpacities(tester, find.text('Progress 20%')),
        everyElement(closeTo(.15, .001)),
      );
      expect(
        _effectiveOpacity(tester, find.byTooltip('Reader settings')),
        closeTo(.15, .001),
      );
      expect(
        find.ancestor(
          of: find.byKey(const Key('reader-stable-viewport-boundary')),
          matching: find.byType(AnimatedOpacity),
        ),
        findsNothing,
      );
      expect(
        tester
            .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
            .any((widget) => (widget.opacity - .15).abs() < .001),
        isTrue,
      );

      slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(.35);
      slider.onChanged!(.4);
      await tester.pump();
      expect(controller.isSliderInteractionActive, isTrue);
      expect(_sheetMaterial(tester).color!.a, closeTo(.15, .01));
      expect(tester.takeException(), isNull);

      final newerToken = controller.beginSliderInteraction(
        ReaderSliderId.fontSize,
      );
      slider.onChangeEnd!(.4);
      expect(controller.isSliderInteractionActive, isTrue);
      expect(controller.activeSliderId, ReaderSliderId.fontSize);
      controller.endSliderInteraction(ReaderSliderId.fontSize, newerToken);
      await tester.pump(const Duration(milliseconds: 150));
      expect(controller.isSliderInteractionActive, isFalse);
      expect(_sheetMaterial(tester).color!.a, closeTo(1, .01));

      slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(.4);
      expect(controller.isSliderInteractionActive, isTrue);
      Navigator.of(
        tester.element(find.byKey(const Key('app-modal-sheet'))),
      ).pop();
      await tester.pumpAndSettle();
      expect(controller.isSliderInteractionActive, isFalse);
      controller.dispose();
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('settings slider stays clear while all other settings UI fades', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final width in [390.0, 412.0]) {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      final controller = _ReaderMenuController(
        settingsCapabilities: _allSliderCapabilities,
      );
      controller.setProgress(ReaderProgressState.progression(progression: .2));
      await _pumpReader(tester, controller);

      await tester.tap(find.byTooltip('Reader settings'));
      await tester.pumpAndSettle();
      var slider = tester.widget<Slider>(find.byType(Slider).first);
      expect(_sheetMaterial(tester).color!.a, closeTo(1, .001));
      expect(slider.onChanged, isNotNull);

      slider.onChangeStart!(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(controller.isSliderInteractionActive, isTrue);
      expect(controller.activeSliderId, ReaderSliderId.fontSize);
      expect(_sheetMaterial(tester).color!.a, closeTo(.15, .01));
      expect(
        _focusOpacity(tester, 'reader-slider-focus-fontSize'),
        closeTo(1, .001),
      );
      expect(
        _effectiveOpacity(
          tester,
          find.descendant(
            of: find.byKey(const Key('reader-slider-focus-fontSize')),
            matching: find.byType(Slider),
          ),
        ),
        closeTo(1, .001),
      );
      for (final id in [
        ReaderSliderId.fontWeight,
        ReaderSliderId.lineHeight,
        ReaderSliderId.margins,
        ReaderSliderId.pageSpacing,
      ]) {
        expect(
          _focusOpacity(tester, 'reader-slider-focus-${id.name}'),
          closeTo(.15, .001),
        );
        expect(
          _effectiveOpacity(
            tester,
            find.descendant(
              of: find.byKey(Key('reader-slider-focus-${id.name}')),
              matching: find.byType(Slider),
            ),
          ),
          closeTo(.15, .001),
        );
      }
      expect(
        _effectiveOpacity(tester, find.text('Appearance')),
        closeTo(.15, .001),
      );
      expect(
        _effectiveOpacity(tester, find.text('Font weight')),
        closeTo(.15, .001),
      );
      expect(_effectiveOpacity(tester, find.text('Theme')), closeTo(.15, .001));
      expect(_effectiveOpacity(tester, find.text('Apply')), closeTo(.15, .001));
      expect(
        _effectiveOpacity(tester, find.text('Cancel').last),
        closeTo(.15, .001),
      );
      expect(
        find.ancestor(
          of: find.byKey(const Key('reader-stable-viewport-boundary')),
          matching: find.byType(AnimatedOpacity),
        ),
        findsNothing,
      );
      expect(
        tester
            .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
            .where((opacity) => (opacity.opacity - .15).abs() < .001)
            .length,
        greaterThan(6),
      );
      final transparentCard = tester
          .widgetList<Material>(
            find.descendant(
              of: find.byKey(const Key('app-modal-sheet')),
              matching: find.byType(Material),
            ),
          )
          .firstWhere((material) => material.color?.a == 0);
      expect(
        transparentCard.animationDuration,
        const Duration(milliseconds: 150),
      );

      slider = tester.widget<Slider>(find.byType(Slider).first);
      slider.onChanged!(1.2);
      slider.onChanged!(1.4);
      await tester.pump();
      expect(controller.isSliderInteractionActive, isTrue);
      expect(controller.activeSliderId, ReaderSliderId.fontSize);
      slider = tester.widget<Slider>(find.byType(Slider).first);
      slider.onChangeEnd!(1.4);
      await tester.pumpAndSettle();
      expect(controller.isSliderInteractionActive, isFalse);
      expect(_sheetMaterial(tester).color!.a, closeTo(1, .01));
      expect(
        _focusOpacity(tester, 'reader-slider-focus-fontSize'),
        closeTo(1, .001),
      );
      final nextSliderToken = controller.beginSliderInteraction(
        ReaderSliderId.lineHeight,
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(controller.activeSliderId, ReaderSliderId.lineHeight);
      expect(
        _focusOpacity(tester, 'reader-slider-focus-lineHeight'),
        closeTo(1, .001),
      );
      expect(
        _focusOpacity(tester, 'reader-slider-focus-fontSize'),
        closeTo(.15, .001),
      );
      controller.endSliderInteraction(
        ReaderSliderId.lineHeight,
        nextSliderToken,
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull);

      Navigator.of(
        tester.element(find.byKey(const Key('app-modal-sheet'))),
      ).pop();
      await tester.pumpAndSettle();
      controller.dispose();
    }
  });

  testWidgets('settings sliders preview during drag and commit only on Apply', (
    tester,
  ) async {
    final controller = _ReaderMenuController(
      settingsCapabilities: _allSliderCapabilities,
    );
    controller.setProgress(ReaderProgressState.progression(progression: .2));
    await _pumpReader(tester, controller);
    await tester.tap(find.byTooltip('Reader settings'));
    await tester.pumpAndSettle();

    final targets = <ReaderSliderId, double>{
      ReaderSliderId.fontSize: 1.6,
      ReaderSliderId.fontWeight: 1.4,
      ReaderSliderId.lineHeight: 1.7,
      ReaderSliderId.margins: 2.2,
      ReaderSliderId.pageSpacing: 18,
    };
    var expectedSettings = ReaderSettingsState.readiumDefaults;
    for (final entry in targets.entries) {
      final sliderFinder = find.descendant(
        of: find.byKey(Key('reader-slider-focus-${entry.key.name}')),
        matching: find.byType(Slider),
      );
      var slider = tester.widget<Slider>(sliderFinder);
      slider.onChangeStart!(entry.value);
      final gesture = controller.settings.startedGestures.last;
      expect(gesture.sliderId, entry.key);
      final previewsBeforeCadence = controller.settings.previews.length;
      slider.onChanged!(entry.value);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pumpAndSettle();
      expect(
        controller.settings.previews.length,
        greaterThan(previewsBeforeCadence),
      );
      expect(
        controller.settings.diagnosticPreviews.last.gesture!.id,
        gesture.id,
      );
      expect(
        controller.settings.diagnosticPreviews.last.gesture!.sliderId,
        entry.key,
      );
      expectedSettings = _settingsWithSliderValue(
        expectedSettings,
        entry.key,
        entry.value,
      );
      expect(
        controller.settings.previews.last.toJson(),
        expectedSettings.toJson(),
        reason: entry.key.name,
      );
      final previewCount = controller.settings.previews.length;
      slider = tester.widget<Slider>(sliderFinder);
      slider.onChangeEnd!(entry.value);
      await tester.pumpAndSettle();
      expect(controller.settings.endedGestures.last.id, gesture.id);
      expect(controller.settings.previews.length, greaterThan(previewCount));
      expect(controller.activeSliderId, isNull);
    }

    expect(controller.settings.commits, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();
    expect(controller.settings.commits, hasLength(1));
    expect(controller.settings.restores, isEmpty);
    expect(controller.settings.commits.single, expectedSettings);
    controller.dispose();
  });

  testWidgets('settings slider coalesces samples and flushes exact end value', (
    tester,
  ) async {
    final controller = _ReaderMenuController(
      settingsCapabilities: _allSliderCapabilities,
      usePreviewRequestHost: true,
    );
    controller.setProgress(ReaderProgressState.progression(progression: .2));
    await _pumpReader(tester, controller);
    await tester.tap(find.byTooltip('Reader settings'));
    await tester.pumpAndSettle();
    final sliderFinder = find.descendant(
      of: find.byKey(const Key('reader-slider-focus-lineHeight')),
      matching: find.byType(Slider),
    );
    var slider = tester.widget<Slider>(sliderFinder);
    slider.onChangeStart!(1.0);
    for (var sample = 0; sample < 26; sample++) {
      slider.onChanged!(1.01 + sample * .01);
    }
    expect(controller.requestSettingsHost!.previewRequests, isEmpty);
    slider.onChangeEnd!(1.37);
    await tester.pumpAndSettle();

    final requests = controller.requestSettingsHost!.previewRequests;
    expect(requests, hasLength(1));
    expect(requests.single.settings.spacing!.lineHeight, 1.37);
    expect(requests.single.requestId, 1);
    controller.dispose();
  });

  testWidgets(
    'gesture baseline survives active preview and releases after exact final commit',
    (tester) async {
      final controller = _ReaderMenuController(
        settingsCapabilities: _allSliderCapabilities,
        usePreviewRequestHost: true,
      );
      controller.setProgress(ReaderProgressState.progression(progression: .2));
      final host = controller.requestSettingsHost!;
      host.holdFirstPreview = true;
      await _pumpReader(tester, controller);
      await tester.tap(find.byTooltip('Reader settings'));
      await tester.pumpAndSettle();
      final finder = find.descendant(
        of: find.byKey(const Key('reader-slider-focus-fontSize')),
        matching: find.byType(Slider),
      );
      final slider = tester.widget<Slider>(finder);
      slider.onChangeStart!(1.0);
      slider.onChanged!(1.2);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();
      expect(host.firstPreviewStarted.isCompleted, true);
      slider.onChangeEnd!(1.73);
      await tester.pump();
      expect(host.releasedBaselines, isEmpty);
      host.releaseFirstPreview.complete();
      await tester.pumpAndSettle();
      expect(host.previewRequests.last.settings.typography!.fontSize, 1.73);
      expect(host.releasedBaselines.single.cancelled, false);
      expect(host.releasedBaselines.single.previewCount, 2);
      expect(host.diagnosticPreviews.map((p) => p.gesture?.id).toSet(), {
        host.startedGestures.single.id,
      });
      controller.dispose();
    },
  );

  testWidgets('settings Cancel restores the initial state after live preview', (
    tester,
  ) async {
    final controller = _ReaderMenuController(
      settingsCapabilities: _allSliderCapabilities,
    );
    controller.setProgress(ReaderProgressState.progression(progression: .2));
    await _pumpReader(tester, controller);
    await tester.tap(find.byTooltip('Reader settings'));
    await tester.pumpAndSettle();
    final sliderFinder = find.descendant(
      of: find.byKey(const Key('reader-slider-focus-fontSize')),
      matching: find.byType(Slider),
    );
    var slider = tester.widget<Slider>(sliderFinder);
    slider.onChanged!(1.8);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();
    expect(controller.settings.previews, isNotEmpty);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel').last);
    await tester.pumpAndSettle();
    expect(controller.settings.commits, isEmpty);
    expect(controller.settings.restores, hasLength(1));
    expect(
      controller.settings.restores.single,
      ReaderSettingsState.readiumDefaults,
    );
    controller.dispose();
  });

  testWidgets(
    'rapid settings preview supersedes the active native request before waiting',
    (tester) async {
      final controller = _ReaderMenuController(
        settingsCapabilities: _allSliderCapabilities,
        usePreviewRequestHost: true,
      );
      controller.setProgress(ReaderProgressState.progression(progression: .2));
      final host = controller.requestSettingsHost!;
      host.holdFirstPreview = true;
      await _pumpReader(tester, controller);
      await tester.tap(find.byTooltip('Reader settings'));
      await tester.pumpAndSettle();
      final sliderFinder = find.descendant(
        of: find.byKey(const Key('reader-slider-focus-fontSize')),
        matching: find.byType(Slider),
      );

      tester.widget<Slider>(sliderFinder).onChanged!(1.2);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();
      expect(host.firstPreviewStarted.isCompleted, isTrue);
      tester.widget<Slider>(sliderFinder).onChanged!(1.7);
      await tester.pump();
      tester.widget<Slider>(sliderFinder).onChanged!(1.5);
      await tester.pump();
      tester.widget<Slider>(sliderFinder).onChanged!(1.7);
      await tester.pump(const Duration(milliseconds: 120));
      expect(host.supersededBefore, isEmpty);
      expect(host.supersededBefore, isEmpty);
      expect(host.previewRequests.map((request) => request.requestId), [1]);
      host.releaseFirstPreview.complete();
      await tester.pumpAndSettle();

      expect(host.previewRequests.map((request) => request.requestId), [1, 2]);
      expect(host.previewRequests.last.settings.typography!.fontSize, 1.7);
      controller.dispose();
    },
  );

  testWidgets('settings Cancel signals supersede before awaiting rollback', (
    tester,
  ) async {
    final controller = _ReaderMenuController(
      settingsCapabilities: _allSliderCapabilities,
      usePreviewRequestHost: true,
    );
    controller.setProgress(ReaderProgressState.progression(progression: .2));
    final host = controller.requestSettingsHost!;
    host.holdFirstPreview = true;
    await _pumpReader(tester, controller);
    await tester.tap(find.byTooltip('Reader settings'));
    await tester.pumpAndSettle();
    final sliderFinder = find.descendant(
      of: find.byKey(const Key('reader-slider-focus-fontSize')),
      matching: find.byType(Slider),
    );
    tester.widget<Slider>(sliderFinder).onChanged!(1.5);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
    expect(host.firstPreviewStarted.isCompleted, isTrue);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel').last);
    await tester.pumpAndSettle();
    expect(host.supersededBefore, [2]);
    expect(host.previewRequests.map((request) => request.requestId), [1]);

    host.releaseFirstPreview.complete();
    await tester.pumpAndSettle();
    expect(host.previewRequests.map((request) => request.requestId), [1, 2]);
    expect(
      host.previewRequests.last.settings.toJson(),
      ReaderSettingsState.readiumDefaults.toJson(),
    );
    controller.dispose();
  });

  testWidgets('progress interaction clears when seekability is lost', (
    tester,
  ) async {
    final controller = _ReaderMenuController();
    controller.setProgress(
      ReaderProgressState.progression(progression: .2),
      seek: (_) async {},
    );
    await _pumpReader(tester, controller);
    await tester.tap(find.text('Progress 20%'));
    await tester.pumpAndSettle();

    tester.widget<Slider>(find.byType(Slider)).onChangeStart!(.2);
    expect(controller.isSliderInteractionActive, isTrue);

    controller.setProgress(const ReaderProgressState.unknown());
    await tester.pump();
    expect(controller.isSliderInteractionActive, isFalse);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);

    Navigator.of(
      tester.element(find.byKey(const Key('app-modal-sheet'))),
    ).pop();
    await tester.pumpAndSettle();
    controller.dispose();
  });

  testWidgets(
    'progress release ends finger ownership before owned final settles',
    (tester) async {
      final host = _MenuScrubHost();
      final controller = _ReaderMenuController(scrubHost: host)
        ..setProgress(
          ReaderProgressState.progression(progression: .2),
          seek: (_) async {},
        );
      await _pumpReader(tester, controller);
      await tester.tap(find.text('Progress 20%'));
      await tester.pumpAndSettle();

      var slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(.2);
      slider.onChanged!(.35);
      await tester.pump();
      expect(host.previews, isNotEmpty);
      expect(controller.activeSliderId, ReaderSliderId.progress);

      slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeEnd!(.4);
      await tester.pump();
      expect(host.finals.single.target, .4);
      expect(controller.activeSliderId, isNull);

      host.finalRelease.complete();
      await tester.pumpAndSettle();
      expect(controller.activeSliderId, isNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Go to position'));
      await tester.pumpAndSettle();
      expect(host.finals, hasLength(2));
      expect(host.closed, isEmpty);
      controller.dispose();
    },
  );

  testWidgets(
    'new progress gesture opens while old final awaits and late result cannot end new gesture',
    (tester) async {
      final host = _MenuScrubHost();
      final controller = _ReaderMenuController(scrubHost: host)
        ..setProgress(
          ReaderProgressState.progression(progression: .2),
          seek: (_) async {},
        );
      await _pumpReader(tester, controller);
      await tester.tap(find.text('Progress 20%'));
      await tester.pumpAndSettle();
      var slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(.2);
      slider.onChanged!(.35);
      await tester.pump();
      slider.onChangeEnd!(.4);
      await tester.pump();
      expect(host.finals.single.sessionId, 2);
      expect(controller.activeSliderId, isNull);
      slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(.4);
      expect(host.openCount, 2);
      expect(host.invalidated, isNot(contains(2)));
      slider.onChanged!(.7);
      await tester.pump();
      expect(host.openCount, 2);
      expect(
        host.previews.last,
        .35,
      ); // New values coalesce behind the old drain.
      expect(controller.activeSliderId, ReaderSliderId.progress);
      host.finalRelease.complete();
      await tester.pumpAndSettle();
      expect(host.previews.last, .7);
      expect(controller.activeSliderId, ReaderSliderId.progress);
      tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(.8123456789);
      await tester.pumpAndSettle();
      expect(host.finals.map((f) => f.sessionId), [2, 4]);
      expect(host.finals.last.target, .8123456789);
      expect(controller.activeSliderId, isNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Go to position'));
      await tester.pumpAndSettle();
      controller.dispose();
    },
  );

  for (final viaBarrier in [false, true]) {
    testWidgets(
      'dismiss via ${viaBarrier ? "barrier" : "Back"} fences UI while keeping final command authoritative',
      (tester) async {
        final host = _MenuScrubHost();
        final controller = _ReaderMenuController(scrubHost: host)
          ..setProgress(
            ReaderProgressState.progression(progression: .2),
            seek: (_) async {},
          );
        await _pumpReader(tester, controller);
        await tester.tap(find.text('Progress 20%'));
        await tester.pumpAndSettle();
        var slider = tester.widget<Slider>(find.byType(Slider));
        slider.onChangeStart!(.2);
        slider.onChanged!(.6);
        await tester.pump();
        slider.onChangeEnd!(.6);
        await tester.pump();
        if (viaBarrier) {
          await tester.tapAt(const Offset(10, 10));
        } else {
          await tester.binding.handlePopRoute();
        }
        // Do not finish the route animation before checking revocation.
        expect(host.invalidated, isNot(contains(2)));
        host.finalRelease.complete();
        await tester.pumpAndSettle();
        expect(find.text('Go to position'), findsNothing);
        expect(tester.takeException(), isNull);
        final fence = host.diagnostics.lastWhere(
          (e) => e['kind'] == 'progress_ui_callback_fence',
        );
        expect(fence['commandStillAuthoritative'], true);
        controller.dispose();
      },
    );
  }

  for (final pendingFinal in [false, true]) {
    testWidgets(
      'Cancel and Go remain enabled during ${pendingFinal ? "final" : "preview"}; Cancel dismisses immediately',
      (tester) async {
        final host = _MenuScrubHost()..holdPreview = true;
        final controller = _ReaderMenuController(scrubHost: host)
          ..setProgress(
            ReaderProgressState.progression(progression: .2),
            seek: (_) async {},
          );
        await _pumpReader(tester, controller);
        await tester.tap(find.text('Progress 20%'));
        await tester.pumpAndSettle();
        var slider = tester.widget<Slider>(find.byType(Slider));
        slider.onChangeStart!(.2);
        slider.onChanged!(.5);
        await tester.pump();
        if (pendingFinal) {
          slider.onChangeEnd!(.5);
          await tester.pump();
        }
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Cancel'),
              )
              .onPressed,
          isNotNull,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Go to position'),
              )
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
        expect(controller.activeSliderId, isNull);
        expect(host.invalidated, contains(1));
        // Retained callbacks during the reverse animation cannot reopen authority.
        final openedBefore = host.openCount;
        slider.onChangeStart!(.5);
        slider.onChanged!(.8);
        slider.onChangeEnd!(.8);
        expect(host.openCount, openedBefore);

        await tester.pumpAndSettle();
        expect(find.text('Go to position'), findsNothing);
        expect(host.restores, isEmpty);
        // Open a new modal while the old callback is still pending.
        await tester.tap(find.text('Progress 20%'));
        await tester.pumpAndSettle();
        host.previewRelease.complete();
        host.finalRelease.complete();
        await tester.pumpAndSettle();
        expect(find.text('Go to position'), findsOneWidget);
        expect(
          find.byKey(const Key('reader-progress-scrub-error')),
          findsNothing,
        );
        await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
        await tester.pumpAndSettle();
        controller.dispose();
      },
    );
  }

  testWidgets(
    'Go supersedes pending final immediately; Cancel revokes new command',
    (tester) async {
      final host = _MenuScrubHost();
      final controller = _ReaderMenuController(scrubHost: host)
        ..setProgress(
          ReaderProgressState.progression(progression: .2),
          seek: (_) async {},
        );
      await _pumpReader(tester, controller);
      await tester.tap(find.text('Progress 20%'));
      await tester.pumpAndSettle();
      var slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(.2);
      slider.onChanged!(.4);
      await tester.pump();
      slider.onChangeEnd!(.4);
      await tester.pump();
      expect(host.finals.single.target, .4);
      slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(.8123456789);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Go to position'));
      await tester.pump();
      expect(host.finals.map((f) => f.target), [.4]);
      expect(
        host.diagnostics.where(
          (e) =>
              e['kind'] == 'progress_navigation_command' &&
              e['commandType'] == 'go_to_position' &&
              e['result'] == 'created',
        ),
        hasLength(1),
      );
      expect(host.finals.map((f) => f.sessionId), [2]);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(host.invalidated, contains(2));
      expect(find.text('Go to position'), findsNothing);
      host.finalRelease.completeError(StateError('late old failure'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(host.restores, [.2]);
      controller.dispose();
    },
  );

  testWidgets(
    'Go is disabled for unavailable target while Cancel remains enabled',
    (tester) async {
      final host = _MenuScrubHost();
      final controller = _ReaderMenuController(scrubHost: host)
        ..setProgress(
          ReaderProgressState.progression(progression: .2),
          seek: (_) async {},
        );
      await _pumpReader(tester, controller);
      await tester.tap(find.text('Progress 20%'));
      await tester.pumpAndSettle();
      controller.setProgress(const ReaderProgressState.unknown());
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Go to position'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Cancel'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();
      final accepted = host.diagnostics.singleWhere(
        (e) => e['kind'] == 'progress_ui_action',
      );
      expect(accepted['action'], 'cancel');
      expect(accepted['result'], 'accepted');
      expect(host.originCaptures, 1);
      controller.dispose();
    },
  );

  testWidgets(
    'Cancel closes immediately and rolls back canonical origin after failed final',
    (tester) async {
      final host = _MenuScrubHost()..failFinal = true;
      final controller = _ReaderMenuController(scrubHost: host)
        ..setProgress(
          ReaderProgressState.progression(progression: .2),
          seek: (_) async {},
        );
      await _pumpReader(tester, controller);
      await tester.tap(find.text('Progress 20%'));
      await tester.pumpAndSettle();
      var slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(.2);
      slider.onChanged!(.5);
      await tester.pump();
      slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeEnd!(.5);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('reader-progress-scrub-error')),
        findsOneWidget,
      );
      expect(find.text('Go to position'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(host.restores, [.2]);
      expect(find.text('Go to position'), findsNothing);
      controller.dispose();
    },
  );

  testWidgets(
    'progress preserves discrete page seeks and Cancel closes before seek completes',
    (tester) async {
      final seekStarted = Completer<void>();
      final releaseSeek = Completer<void>();
      final controller = _ReaderMenuController();
      controller.setProgress(
        ReaderProgressState.page(page: 1, total: 7),
        seek: (value) async {
          if (!seekStarted.isCompleted) seekStarted.complete();
          await releaseSeek.future;
          controller.setProgress(
            ReaderProgressState.page(
              page: controller.progress.pageFor(value),
              total: 7,
            ),
          );
        },
      );
      await _pumpReader(tester, controller);

      await tester.tap(find.text('Progress 0%'));
      await tester.pumpAndSettle();
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.divisions, 6);
      slider.onChanged!(.47);
      slider.onChangeEnd!(.47);
      await tester.pump();

      expect(find.text('Progress 50%'), findsWidgets);
      expect(find.textContaining('Page '), findsNothing);
      expect(seekStarted.isCompleted, isTrue);
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Cancel'))
          .onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      expect(find.text('Go to position'), findsNothing);

      releaseSeek.complete();
      await tester.pumpAndSettle();
      expect(find.text('Go to position'), findsNothing);
    },
  );

  testWidgets(
    'rendered progress seeks 50 to 76 and reopen uses settled state',
    (tester) async {
      double? requested;
      final controller = _ReaderMenuController();
      controller.setProgress(
        ReaderProgressState.renderedPage(
          pageIndex: 10,
          pageCount: 21,
          progression: .5,
          publicationScoped: true,
        ),
        seek: (value) async {
          requested = value;
          controller.setProgress(
            ReaderProgressState.renderedPage(
              pageIndex: 15,
              pageCount: 21,
              progression: .75,
              publicationScoped: true,
            ),
          );
        },
      );
      await _pumpReader(tester, controller);

      await tester.tap(find.text('Progress 50%'));
      await tester.pumpAndSettle();
      var slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, .5);
      expect(slider.divisions, isNull);
      slider.onChanged!(.76);
      slider.onChangeEnd!(.76);
      await tester.pumpAndSettle();
      expect(requested, .76);
      expect(find.text('Progress 75%'), findsWidgets);
      expect(find.textContaining('Page '), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Go to position'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Progress 75%'));
      await tester.pumpAndSettle();
      slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, .75);
    },
  );

  testWidgets('reflowable progress keeps a continuous progression slider', (
    tester,
  ) async {
    double? sought;
    final controller = _ReaderMenuController();
    controller.setProgress(
      ReaderProgressState.reflowable(
        progression: .2,
        logicalPosition: 8,
        totalLogicalPositions: 40,
      ),
      seek: (value) async {
        sought = value;
        controller.setProgress(
          ReaderProgressState.reflowable(
            progression: value,
            logicalPosition: 8,
            totalLogicalPositions: 40,
          ),
        );
      },
    );
    await _pumpReader(tester, controller);

    await tester.tap(find.text('Progress 20%'));
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.divisions, isNull);
    slider.onChanged!(.473);
    slider.onChangeEnd!(.473);
    await tester.pumpAndSettle();

    expect(sought, closeTo(.473, .0001));
    expect(find.text('Progress 47%'), findsWidgets);
  });

  testWidgets(
    'Settings uses one canonical upper and lower decorative strip outside footer safe area',
    (tester) async {
      final controller = _ReaderMenuController()
        ..setProgress(ReaderProgressState.page(page: 2, total: 10));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(padding: const EdgeInsets.only(bottom: 32)),
              child: UnifiedReaderScreen(
                book: _readerBook,
                controller: controller,
                viewport: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Reader settings'));
      await tester.pumpAndSettle();

      _expectCanonicalStripGeometry(tester);
      expect(find.byType(Divider), findsNWidgets(2));
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
    },
  );
}

void _expectCanonicalStripGeometry(WidgetTester tester) {
  final upperFinder = find.byKey(
    const Key('reader-menu-upper-decorative-strip'),
  );
  final lowerFinder = find.byKey(
    const Key('reader-menu-lower-decorative-strip'),
  );
  final upper = tester.getRect(upperFinder);
  final lower = tester.getRect(lowerFinder);
  final upperStrip = tester.widget<AppModalSheetDivider>(upperFinder);
  final lowerStrip = tester.widget<AppModalSheetDivider>(lowerFinder);
  expect(upper.height, 1);
  expect(lower.height, upper.height);
  expect(lower.width, upper.width);
  expect(lower.left, upper.left);
  expect(lower.right, upper.right);
  expect(lowerStrip.color, upperStrip.color);
}

Material _sheetMaterial(WidgetTester tester) => tester.widget<Material>(
  find
      .descendant(
        of: find.byKey(const Key('app-modal-sheet')),
        matching: find.byType(Material),
      )
      .first,
);

double _focusOpacity(WidgetTester tester, String key) => tester
    .widget<AnimatedOpacity>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .opacity;

List<double> _effectiveOpacities(WidgetTester tester, Finder target) => [
  for (final element in target.evaluate()) _opacityForElement(element),
];

double _effectiveOpacity(WidgetTester tester, Finder target) =>
    _effectiveOpacities(tester, target).first;

double _opacityForElement(Element element) {
  var opacity = 1.0;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is AnimatedOpacity) opacity *= widget.opacity;
    return true;
  });
  return opacity;
}

Future<void> _pumpReader(
  WidgetTester tester,
  _ReaderMenuController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: UnifiedReaderScreen(
        book: _readerBook,
        controller: controller,
        viewport: const ColoredBox(color: Colors.black),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _readerBook = LibraryBook(
  id: 'reader-menu-test',
  title: 'Reader menu test',
  sortTitle: null,
  author: null,
  description: null,
  filePath: '/reader-menu-test.epub',
  fileName: 'reader-menu-test.epub',
  fileExtension: BookFormat.epub.normalizedExtension,
  format: BookFormat.epub,
  mediaType: null,
  coverPath: null,
  language: null,
  publisher: null,
  publishedDate: null,
  isbn: null,
  pageCount: null,
  fileSizeBytes: 0,
  dateAdded: DateTime(2026),
  lastOpenedAt: null,
  isFavorite: false,
);

class _ReaderMenuController extends ReaderUiController {
  _ReaderMenuController({
    ReaderSettingsCapabilities settingsCapabilities =
        ReaderSettingsCapabilities.readiumOriginal,
    this._scrubHost,
    bool usePreviewRequestHost = false,
  }) : _settings = _ReaderMenuSettings(settingsCapabilities),
       _requestSettings = usePreviewRequestHost
           ? _ReaderMenuSettingsWithRequests(settingsCapabilities)
           : null,
       super(capabilities: ReaderCapabilities.forKind(ReaderKind.epub));

  final _ReaderMenuSettings _settings;
  final _ReaderMenuSettingsWithRequests? _requestSettings;
  final ReaderProgressScrubHost? _scrubHost;

  _ReaderMenuSettings get settings => _settings;
  _ReaderMenuSettingsWithRequests? get requestSettingsHost => _requestSettings;

  @override
  ReaderSettingsHost get readerSettings => _requestSettings ?? _settings;

  @override
  ReaderProgressScrubHost? get progressScrubHost => _scrubHost;
}

class _MenuScrubHost
    implements
        ReaderProgressScrubHost,
        ReaderProgressDiagnosticHost,
        ReaderProgressOriginHost {
  int originCaptures = 0;
  final canonicalOrigin = const _MenuProgressOrigin();
  @override
  ReaderProgressOrigin captureProgressOrigin() {
    originCaptures++;
    return canonicalOrigin;
  }

  @override
  Future<void> restoreProgressOrigin({
    required ReaderProgressOrigin origin,
    required int sessionId,
    required int requestId,
    required ReaderProgressCommandIdentity command,
  }) async {
    if (!identical(origin, canonicalOrigin)) throw StateError('wrong origin');
    restores.add(origin.totalProgression!);
  }

  final diagnostics = <Map<String, Object?>>[];
  @override
  void progressDiagnostic(Map<String, Object?> fields) =>
      diagnostics.add(fields);
  int openCount = 0;
  final previews = <double>[];
  final previewRelease = Completer<void>();
  bool holdPreview = false;
  final invalidated = <int>[];
  final finals = <_ScrubAction>[];
  final closed = <int>[];
  final finalRelease = Completer<void>();
  final restores = <double>[];
  var failFinal = false;
  var active = false;

  @override
  Future<int> openProgressScrub({
    bool checkpointCurrentPosition = true,
    ReaderProgressCommandIdentity? command,
  }) async {
    active = true;
    return ++openCount;
  }

  @override
  Future<void> previewProgressScrub({
    required int sessionId,
    required int requestId,
    required double target,
    ReaderProgressCommandIdentity? command,
  }) async {
    previews.add(target);
    if (holdPreview) await previewRelease.future;
  }

  @override
  Future<void> finishProgressScrub({
    required int sessionId,
    required int requestId,
    required double target,
    ReaderProgressCommandIdentity? command,
  }) async {
    finals.add(_ScrubAction(sessionId, target));
    if (failFinal) {
      active = false;
      throw StateError('final_failed');
    }
    await finalRelease.future;
    if (sessionId == openCount) active = false;
  }

  @override
  Future<void> restoreProgressScrub({
    required int sessionId,
    required int requestId,
    required double target,
  }) async {
    restores.add(target);
    active = false;
  }

  @override
  Future<void> closeProgressScrub(int sessionId) async {
    closed.add(sessionId);
    active = false;
  }

  @override
  Future<void> invalidateProgressScrub(int sessionId) async {
    invalidated.add(sessionId);
    if (sessionId == openCount) active = false;
  }

  @override
  bool isProgressScrubActive(int sessionId) => active && sessionId == openCount;
}

class _ScrubAction {
  const _ScrubAction(this.sessionId, this.target);
  final int sessionId;
  final double target;
}

class _ReaderMenuSettings
    implements ReaderSettingsHost, ReaderSettingsDiagnosticHost {
  _ReaderMenuSettings(this.settingsCapabilities);

  ReaderSettingsState _value = ReaderSettingsState.readiumDefaults;
  final previews = <ReaderSettingsState>[];
  final commits = <ReaderSettingsState>[];
  final restores = <ReaderSettingsState>[];
  final startedGestures = <ReaderSettingsDiagnosticGesture>[];
  final endedGestures = <ReaderSettingsDiagnosticGesture>[];
  final diagnosticPreviews =
      <
        ({
          ReaderSettingsState settings,
          ReaderSettingsDiagnosticGesture? gesture,
        })
      >[];
  var _gestureId = 0;

  @override
  final ReaderSettingsCapabilities settingsCapabilities;

  @override
  ReaderSettingsState get state => _value;

  @override
  Future<void> previewSettings(ReaderSettingsState settings) async {
    previews.add(settings);
    _value = settings;
  }

  @override
  Future<void> commitSettings(ReaderSettingsState settings) async {
    commits.add(settings);
    _value = settings;
  }

  @override
  Future<void> restoreSettings(ReaderSettingsState settings) async {
    restores.add(settings);
    _value = settings;
  }

  @override
  ReaderSettingsDiagnosticGesture beginSettingsDiagnostic(
    ReaderSliderId sliderId,
    double uiValue,
  ) {
    final gesture = ReaderSettingsDiagnosticGesture(
      id: ++_gestureId,
      sliderId: sliderId,
      uiStartValue: uiValue,
    );
    startedGestures.add(gesture);
    return gesture;
  }

  @override
  void endSettingsDiagnostic(
    ReaderSettingsDiagnosticGesture gesture,
    double uiValue,
  ) => endedGestures.add(gesture);

  @override
  Future<void> previewSettingsWithDiagnostics(
    ReaderSettingsState settings, {
    required ReaderSettingsDiagnosticGesture? gesture,
  }) {
    diagnosticPreviews.add((settings: settings, gesture: gesture));
    return previewSettings(settings);
  }

  @override
  void logSettingsDiagnosticAction(String action) {}
}

class _ReaderMenuSettingsWithRequests extends _ReaderMenuSettings
    implements
        ReaderSettingsPreviewRequestHost,
        ReaderSettingsGestureBaselineHost {
  _ReaderMenuSettingsWithRequests(super.settingsCapabilities);

  final previewRequests = <({int requestId, ReaderSettingsState settings})>[];
  final supersededBefore = <int>[];
  final firstPreviewStarted = Completer<void>();
  final releaseFirstPreview = Completer<void>();
  var holdFirstPreview = false;
  var _requestId = 0;
  final releasedBaselines = <({int id, bool cancelled, int previewCount})>[];

  @override
  Future<void> finishSettingsGestureBaseline(
    ReaderSettingsDiagnosticGesture gesture, {
    bool cancelled = false,
  }) async {
    releasedBaselines.add((
      id: gesture.id,
      cancelled: cancelled,
      previewCount: previewRequests.length,
    ));
  }

  @override
  Future<void> cancelSettingsGestureBaselines() async {}

  @override
  int allocateSettingsPreviewRequestId() => ++_requestId;

  @override
  Future<void> supersedeSettingsPreviewsBefore(int requestId) async {
    supersededBefore.add(requestId);
  }

  @override
  Future<void> previewSettingsWithRequestId(
    ReaderSettingsState settings, {
    required int requestId,
    required ReaderSettingsDiagnosticGesture? gesture,
  }) async {
    previewRequests.add((requestId: requestId, settings: settings));
    if (holdFirstPreview && requestId == 1) {
      firstPreviewStarted.complete();
      await releaseFirstPreview.future;
      holdFirstPreview = false;
    }
    await previewSettingsWithDiagnostics(settings, gesture: gesture);
  }
}

ReaderSettingsState _settingsWithSliderValue(
  ReaderSettingsState current,
  ReaderSliderId sliderId,
  double value,
) {
  return switch (sliderId) {
    ReaderSliderId.fontSize => current.copyWith(
      typography: current.typography!.copyWith(fontSize: value),
    ),
    ReaderSliderId.fontWeight => current.copyWith(
      typography: current.typography!.copyWith(fontWeight: value),
    ),
    ReaderSliderId.lineHeight => current.copyWith(
      spacing: current.spacing!.copyWith(lineHeight: value),
    ),
    ReaderSliderId.margins => current.copyWith(
      spacing: current.spacing!.copyWith(textMargins: value),
    ),
    ReaderSliderId.pageSpacing => current.copyWith(
      spacing: current.spacing!.copyWith(pageGap: value),
    ),
    ReaderSliderId.progress => throw ArgumentError.value(sliderId),
  };
}

const _allSliderCapabilities = ReaderSettingsCapabilities(
  profile: ReaderSettingsProfile.readiumReflowable,
  appearance: ReaderAppearanceCapabilities(theme: true),
  typography: ReaderTypographyCapabilities(fontSize: true, fontWeight: true),
  spacing: ReaderSpacingCapabilities(
    lineHeight: true,
    textMargins: true,
    pageGap: true,
  ),
);

final class _MenuProgressOrigin implements ReaderProgressOrigin {
  const _MenuProgressOrigin();
  @override
  int get readingOrderIndex => 1;
  @override
  double get resourceProgression => .375;
  @override
  double get totalProgression => .2;
  @override
  int get logicalPosition => 42;
}

import 'dart:async';

import 'package:bibliolife/features/reader/domain/models/reader_capabilities.dart';
import 'package:bibliolife/features/reader/domain/models/reader_kind.dart';
import 'package:bibliolife/features/reader/domain/models/reader_settings.dart';
import 'package:bibliolife/features/reader/presentation/models/local_reader_settings_adapters.dart';
import 'package:bibliolife/features/reader/presentation/models/reader_ui_controller.dart';
import 'package:bibliolife/features/reader/presentation/widgets/unified_reader_screen.dart';
import 'package:bibliolife/features/reader/presentation/widgets/reader_stable_components.dart';
import 'package:bibliolife/shared/presentation/widgets/biblio_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_reader_settings_repository.dart';

void main() {
  testWidgets('Settings uses one standardized responsive control system', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final host = _Host(ReaderSettingsCapabilities.readiumOriginal);
    final controller = _NoTextController(kind: ReaderKind.epub, settings: host);
    await _pump(tester, controller);

    expect(find.byType(ReaderMenuSection), findsNWidgets(5));
    expect(find.byType(ReaderSettingsChoiceField<ReaderTheme>), findsOneWidget);
    expect(find.byType(BiblioTabs<ReaderTheme>), findsOneWidget);
    expect(
      find.byType(ReaderSettingsDropdownField<ReaderFontFamily>),
      findsOneWidget,
    );
    expect(find.byType(ReaderSettingsFieldDivider), findsWidgets);
    expect(find.byType(ReaderSettingsSwitchRow), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('Readium composition exposes all implemented shared controls', (
    tester,
  ) async {
    final host = _Host(ReaderSettingsCapabilities.readiumGenerated);
    final controller = _NoTextController(kind: ReaderKind.epub, settings: host);
    await _pump(tester, controller);

    for (final label in [
      'Appearance',
      'Typography',
      'Font family',
      'Font size',
      'Font weight',
      'Spacing',
      'Line height',
      'Margins',
      'Text layout',
      'Paginated',
      'Scroll',
      'Columns',
    ]) {
      expect(
        find.textContaining(label, skipOffstage: false),
        findsOneWidget,
        reason: label,
      );
    }
    expect(find.text('Publisher styles'), findsNothing);
    controller.dispose();
  });

  testWidgets('Publisher Styles follows original EPUB source capability', (
    tester,
  ) async {
    final host = _Host(ReaderSettingsCapabilities.readiumOriginal);
    final controller = _NoTextController(kind: ReaderKind.epub, settings: host);
    await _pump(tester, controller);

    expect(find.text('Advanced'), findsOneWidget);
    expect(find.text('Publisher styles'), findsOneWidget);
    controller.dispose();
  });

  testWidgets(
    'Readium text overrides turn Publisher Styles off before preview',
    (tester) async {
      final host = _Host(ReaderSettingsCapabilities.readiumOriginal);
      final controller = _NoTextController(
        kind: ReaderKind.epub,
        settings: host,
      );
      await _pump(tester, controller);

      await tester.ensureVisible(find.text('Justify'));
      await tester.tap(find.text('Justify'));
      await tester.pumpAndSettle();

      expect(host.state.textLayout!.alignment, ReaderTextAlignment.justify);
      expect(host.state.sourceSpecific!.publisherStyles, isFalse);

      await tester.ensureVisible(find.text('Line height'));
      final lineHeightField = find.ancestor(
        of: find.text('Line height'),
        matching: find.byType(ReaderStableSettingSlider),
      );
      final lineHeightSlider = tester.widget<Slider>(
        find.descendant(of: lineHeightField, matching: find.byType(Slider)),
      );
      lineHeightSlider.onChangeEnd!(1.9);
      await tester.pumpAndSettle();
      expect(host.state.spacing!.lineHeight, 1.9);
      controller.dispose();
    },
  );

  testWidgets('shared footer previews then restores on Cancel', (tester) async {
    final host = _Host(ReaderSettingsCapabilities.readiumGenerated);
    final controller = _NoTextController(kind: ReaderKind.epub, settings: host);
    await _pump(tester, controller);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(host.previewCount, 1);
    expect(host.state.appearance!.theme, ReaderTheme.light);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(host.restoreCount, 1);
    expect(host.state, ReaderSettingsState.readiumDefaults);
    controller.dispose();
  });

  testWidgets('rapid previews are serialized and the newest draft wins', (
    tester,
  ) async {
    final host = _DelayedHost(ReaderSettingsCapabilities.readiumGenerated);
    final controller = _NoTextController(kind: ReaderKind.epub, settings: host);
    await _pump(tester, controller);

    await tester.tap(find.text('Light'));
    await tester.tap(find.text('Sepia'));
    await tester.pumpAndSettle();

    expect(host.state.appearance!.theme, ReaderTheme.sepia);
    expect(host.previewedThemes.last, ReaderTheme.sepia);
    controller.dispose();
  });

  testWidgets('Cancel submits restore while a preview is still pending', (
    tester,
  ) async {
    final host = _PendingHost(ReaderSettingsCapabilities.readiumGenerated);
    final controller = _NoTextController(kind: ReaderKind.epub, settings: host);
    await tester.pumpWidget(_menuHost(controller));
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Light'));
    await tester.pump();
    expect(host.previewStarted, isTrue);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(ReaderSettingsSheet), findsNothing);
    // This host cannot supersede previews. Let the late preview apply before
    // checking that rollback restores the initial settings.
    expect(host.restoreCount, 0);
    host.previewCompleter.complete();
    await tester.pumpAndSettle();

    expect(host.previewCount, 1);
    expect(host.restoreCount, 1);
    expect(host.commitCount, 0);
    expect(host.state, ReaderSettingsState.readiumDefaults);
    expect(find.text('Could not apply this setting.'), findsNothing);
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('dismiss without Apply restores the committed renderer state', (
    tester,
  ) async {
    final host = _Host(ReaderSettingsCapabilities.readiumGenerated);
    final controller = _NoTextController(kind: ReaderKind.epub, settings: host);
    await tester.pumpWidget(_menuHost(controller));
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(host.state.appearance!.theme, ReaderTheme.light);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(host.restoreCount, 1);
    expect(host.state, ReaderSettingsState.readiumDefaults);
    controller.dispose();
  });

  testWidgets('Apply commits the previewed theme, alignment and columns', (
    tester,
  ) async {
    final host = _Host(ReaderSettingsCapabilities.readiumGenerated);
    final controller = _NoTextController(kind: ReaderKind.epub, settings: host);
    await tester.pumpWidget(_menuHost(controller));
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();

    final twoColumns = find.descendant(
      of: find.byType(BiblioTabs<ReaderColumnCount>),
      matching: find.text('2'),
    );
    for (final option in [
      find.text('Sepia'),
      find.text('Justify'),
      twoColumns,
    ]) {
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pumpAndSettle();
    }
    expect(host.commitCount, 0);
    expect(host.state.appearance!.theme, ReaderTheme.sepia);
    expect(host.state.textLayout!.alignment, ReaderTextAlignment.justify);
    expect(host.state.textLayout!.columns, ReaderColumnCount.two);

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(host.commitCount, 1);
    expect(host.restoreCount, 0);
    expect(host.state.appearance!.theme, ReaderTheme.sepia);
    expect(host.state.textLayout!.alignment, ReaderTextAlignment.justify);
    expect(host.state.textLayout!.columns, ReaderColumnCount.two);
    expect(find.text('Open settings'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('columns are disabled while Readium is in scroll mode', (
    tester,
  ) async {
    final host = _Host(ReaderSettingsCapabilities.readiumGenerated);
    final controller = _NoTextController(kind: ReaderKind.epub, settings: host);
    await _pump(tester, controller);

    await tester.ensureVisible(find.text('Scroll'));
    await tester.tap(find.text('Scroll'));
    await tester.pumpAndSettle();
    final columnTabs = find.byType(BiblioTabs<ReaderColumnCount>);
    final columns = tester.widget<BiblioTabs<ReaderColumnCount>>(columnTabs);
    expect(columns.onSelected, isNull);
    final twoColumns = find.descendant(
      of: columnTabs,
      matching: find.text('2'),
    );
    await tester.ensureVisible(twoColumns);
    await tester.tapAt(tester.getCenter(twoColumns));
    await tester.pumpAndSettle();
    expect(host.state.textLayout!.readingMode, ReaderReadingMode.continuous);
    expect(host.state.textLayout!.columns, ReaderColumnCount.auto);
    controller.dispose();
  });

  testWidgets('columns are disabled on compact paginated viewports', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final host = _Host(ReaderSettingsCapabilities.readiumGenerated);
    final controller = _NoTextController(kind: ReaderKind.epub, settings: host);
    await _pump(tester, controller);

    await tester.ensureVisible(find.text('Columns (wide screens)'));
    final columns = tester.widget<BiblioTabs<ReaderColumnCount>>(
      find.byType(BiblioTabs<ReaderColumnCount>),
    );
    expect(columns.onSelected, isNull);
    expect(host.state.textLayout!.readingMode, ReaderReadingMode.paginated);
    controller.dispose();
  });

  testWidgets('PDF Settings never accesses a text typography controller', (
    tester,
  ) async {
    final adapter = PdfReaderSettingsAdapter(FakeReaderSettingsRepository());
    final controller = _NoTextController(
      kind: ReaderKind.pdf,
      settings: adapter,
    );
    await _pump(tester, controller);

    expect(find.text('Page'), findsOneWidget);
    expect(
      find.textContaining('Page gap', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Typography'), findsNothing);
    expect(find.text('Fit page'), findsNothing);
    expect(find.text('Two page'), findsNothing);
    expect(tester.takeException(), isNull);
    controller.dispose();
    adapter.dispose();
  });

  testWidgets('Comic Settings uses image controls and no text controls', (
    tester,
  ) async {
    final adapter = ComicReaderSettingsAdapter(FakeReaderSettingsRepository());
    final controller = _NoTextController(
      kind: ReaderKind.comic,
      settings: adapter,
    );
    await _pump(tester, controller);

    expect(find.text('Layout'), findsOneWidget);
    expect(find.text('Image fitting'), findsOneWidget);
    expect(find.text('Fit page'), findsOneWidget);
    expect(find.text('Fit width'), findsOneWidget);
    expect(find.text('RTL Manga'), findsOneWidget);
    expect(find.text('Scroll'), findsOneWidget);
    expect(find.text('Typography'), findsNothing);
    expect(find.text('Publisher styles'), findsNothing);
    expect(find.byType(BiblioTabs<ReaderImageFit>), findsOneWidget);
    await tester.ensureVisible(find.text('RTL Manga'));
    await tester.tap(find.text('RTL Manga'));
    await tester.pumpAndSettle();
    expect(
      adapter.state.page!.readingDirection,
      ReaderReadingDirection.rightToLeft,
    );
    expect(tester.takeException(), isNull);
    controller.dispose();
    adapter.dispose();
  });

  testWidgets('Comic direction is disabled while continuous mode is active', (
    tester,
  ) async {
    final adapter = ComicReaderSettingsAdapter(FakeReaderSettingsRepository());
    final controller = _NoTextController(
      kind: ReaderKind.comic,
      settings: adapter,
    );
    await _pump(tester, controller);

    await tester.ensureVisible(find.text('Scroll'));
    await tester.tap(find.text('Scroll'));
    await tester.pumpAndSettle();
    final direction = tester.widget<BiblioTabs<ReaderReadingDirection>>(
      find.byType(BiblioTabs<ReaderReadingDirection>),
    );
    expect(direction.onSelected, isNull);
    final rtl = find.text('RTL Manga');
    await tester.ensureVisible(rtl);
    await tester.tapAt(tester.getCenter(rtl));
    await tester.pumpAndSettle();
    expect(
      adapter.state.page!.readingDirection,
      ReaderReadingDirection.leftToRight,
    );
    controller.dispose();
    adapter.dispose();
  });
}

Widget _menuHost(ReaderUiController controller) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showReaderMenu<void>(
          context: context,
          title: 'Reader settings',
          child: ReaderSettingsSheet(controller: controller),
        ),
        child: const Text('Open settings'),
      ),
    ),
  ),
);

Future<void> _pump(WidgetTester tester, ReaderUiController controller) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReaderSettingsSheet(controller: controller)),
      ),
    );

class _NoTextController extends ReaderUiController {
  _NoTextController({
    required ReaderKind kind,
    required ReaderSettingsHost settings,
  }) : super(
         capabilities: ReaderCapabilities.forKind(kind),
         settings: settings,
       );

  @override
  ReaderTextSettingsController? get textSettings =>
      throw StateError('text settings must not be requested');
}

class _Host implements ReaderSettingsHost {
  _Host(this.settingsCapabilities);

  @override
  final ReaderSettingsCapabilities settingsCapabilities;
  ReaderSettingsState _state = ReaderSettingsState.readiumDefaults;
  int previewCount = 0;
  int commitCount = 0;
  int restoreCount = 0;

  @override
  ReaderSettingsState get state => _state;

  @override
  Future<void> previewSettings(ReaderSettingsState settings) async {
    previewCount++;
    _state = settings;
  }

  @override
  Future<void> commitSettings(ReaderSettingsState settings) async {
    commitCount++;
    _state = settings;
  }

  @override
  Future<void> restoreSettings(ReaderSettingsState settings) async {
    restoreCount++;
    _state = settings;
  }
}

class _DelayedHost extends _Host {
  _DelayedHost(super.settingsCapabilities);

  final List<ReaderTheme> previewedThemes = [];

  @override
  Future<void> previewSettings(ReaderSettingsState settings) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await super.previewSettings(settings);
    previewedThemes.add(settings.appearance!.theme);
  }
}

class _PendingHost extends _Host {
  _PendingHost(super.settingsCapabilities);

  final Completer<void> previewCompleter = Completer<void>();
  var previewStarted = false;

  @override
  Future<void> previewSettings(ReaderSettingsState settings) async {
    previewStarted = true;
    await previewCompleter.future;
    await super.previewSettings(settings);
  }
}

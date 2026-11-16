import 'dart:async';

import 'package:bibliolife/features/connectivity/application/app_connectivity_mode_provider.dart';
import 'package:bibliolife/features/connectivity/data/app_connectivity_mode_repository.dart';
import 'package:bibliolife/features/connectivity/domain/app_connectivity_mode.dart';
import 'package:bibliolife/features/settings/presentation/screens/settings_screen.dart';
import 'package:bibliolife/shared/presentation/widgets/biblio_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Offline Online Offline Online remains enabled and persists once',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = _Repository();
      await tester.pumpWidget(_app(repository));
      await _settleLoad(tester);
      expect(_state(tester).mode, AppConnectivityMode.offline);

      await _select(tester, 'Online');
      await tester.tap(find.widgetWithText(FilledButton, 'Enable Online'));
      await tester.pump();
      _expectMode(tester, repository, AppConnectivityMode.online, 1);

      await _select(tester, 'Offline');
      _expectMode(tester, repository, AppConnectivityMode.offline, 2);

      await _select(tester, 'Online');
      _expectMode(tester, repository, AppConnectivityMode.online, 3);
      semantics.dispose();
    },
  );

  testWidgets('acknowledgement Cancel clears pending and retry succeeds', (
    tester,
  ) async {
    final repository = _Repository();
    await tester.pumpWidget(_app(repository));
    await _settleLoad(tester);

    await _select(tester, 'Online');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pump();
    _expectMode(tester, repository, AppConnectivityMode.offline, 0);

    await _select(tester, 'Online');
    await tester.tap(find.widgetWithText(FilledButton, 'Enable Online'));
    await tester.pump();
    _expectMode(tester, repository, AppConnectivityMode.online, 1);
  });

  testWidgets('persistence failure clears pending and permits retry', (
    tester,
  ) async {
    final repository = _Repository()..failNextSave = true;
    await tester.pumpWidget(_app(repository));
    await _settleLoad(tester);

    await _select(tester, 'Online');
    await tester.tap(find.widgetWithText(FilledButton, 'Enable Online'));
    await tester.pump();
    _expectMode(tester, repository, AppConnectivityMode.offline, 1);
    expect(_state(tester).error, isNotNull);

    await _select(tester, 'Online');
    await tester.tap(find.widgetWithText(FilledButton, 'Enable Online'));
    await tester.pump();
    _expectMode(tester, repository, AppConnectivityMode.online, 2);
    expect(_state(tester).error, isNull);
  });

  testWidgets('duplicate activation while persistence is pending saves once', (
    tester,
  ) async {
    final repository = _Repository()..pendingSave = Completer<void>();
    await tester.pumpWidget(_app(repository));
    await _settleLoad(tester);

    await _select(tester, 'Online');
    await tester.tap(find.widgetWithText(FilledButton, 'Enable Online'));
    await tester.pump();
    expect(repository.saveCalls, 1);
    expect(_state(tester).isPersisting, isTrue);

    // The inline selector is disabled while its first save is in flight, so a
    // second UI activation cannot schedule another persistence operation.
    expect(
      tester
          .widget<BiblioTabs<AppConnectivityMode>>(
            find.byType(BiblioTabs<AppConnectivityMode>),
          )
          .onSelected,
      isNull,
    );
    await tester.tap(find.byKey(const Key('application-mode-option-online')));
    await tester.pump();
    expect(repository.saveCalls, 1);
    repository.pendingSave!.complete();
    await tester.pump();
    expect(_state(tester).isPersisting, isFalse);
    _expectSelectorEnabled(tester);
  });

  testWidgets('navigation away and back leaves selector enabled', (
    tester,
  ) async {
    final repository = _Repository();
    await tester.pumpWidget(_navigationApp(repository));
    await tester.tap(find.text('Open appearance'));
    await tester.pumpAndSettle();
    await _settleLoad(tester);

    await _select(tester, 'Online');
    await tester.tap(find.widgetWithText(FilledButton, 'Enable Online'));
    await tester.pump();
    _expectMode(tester, repository, AppConnectivityMode.online, 1);

    Navigator.of(
      tester.element(find.byType(ApplicationModeSettingsPanel)),
    ).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open appearance'));
    await tester.pumpAndSettle();

    _expectMode(tester, repository, AppConnectivityMode.online, 1);
  });
}

Widget _app(_Repository repository) => ProviderScope(
  overrides: [
    appConnectivityModeRepositoryProvider.overrideWithValue(repository),
  ],
  child: const MaterialApp(
    home: Scaffold(body: ApplicationModeSettingsPanel()),
  ),
);

Widget _navigationApp(_Repository repository) => ProviderScope(
  overrides: [
    appConnectivityModeRepositoryProvider.overrideWithValue(repository),
  ],
  child: MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) =>
                  const Scaffold(body: ApplicationModeSettingsPanel()),
            ),
          ),
          child: const Text('Open appearance'),
        ),
      ),
    ),
  ),
);

Future<void> _settleLoad(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<void> _select(WidgetTester tester, String label) async {
  final option = find.byKey(
    Key('application-mode-option-${label.toLowerCase()}'),
  );
  expect(option, findsOneWidget);
  await tester.tap(option);
  await tester.pump();
}

AppConnectivityState _state(WidgetTester tester) {
  final scope = ProviderScope.containerOf(
    tester.element(find.byType(ApplicationModeSettingsPanel)),
  );
  return scope.read(appConnectivityModeProvider);
}

void _expectMode(
  WidgetTester tester,
  _Repository repository,
  AppConnectivityMode mode,
  int saveCalls,
) {
  final state = _state(tester);
  expect(state.mode, mode);
  expect(state.isPersisting, isFalse);
  expect(repository.persisted.mode, mode);
  expect(repository.saveCalls, saveCalls);
  _expectSelectorEnabled(tester);
}

void _expectSelectorEnabled(WidgetTester tester) {
  expect(
    find.byKey(const Key('application-mode-settings-row')),
    findsOneWidget,
  );
  expect(
    tester
        .widget<BiblioTabs<AppConnectivityMode>>(
          find.byType(BiblioTabs<AppConnectivityMode>),
        )
        .onSelected,
    isNotNull,
  );
}

class _Repository implements AppConnectivityModeRepository {
  AppConnectivityState persisted = const AppConnectivityState(
    mode: AppConnectivityMode.offline,
    hasAcknowledgedOnline: false,
    isLoaded: true,
  );
  int saveCalls = 0;
  bool failNextSave = false;
  Completer<void>? pendingSave;

  @override
  Future<AppConnectivityState> load() async => persisted;

  @override
  Future<void> save(AppConnectivityState state) async {
    saveCalls++;
    if (failNextSave) {
      failNextSave = false;
      throw StateError('controlled failure');
    }
    if (pendingSave case final pending?) await pending.future;
    persisted = state.copyWith(isLoaded: true, isPersisting: false);
  }
}

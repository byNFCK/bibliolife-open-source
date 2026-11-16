import 'package:bibliolife/app/localization/app_strings.dart';
import 'package:bibliolife/features/app_logs/presentation/screens/app_log_screen.dart';
import 'package:bibliolife/shared/application/logging/app_log_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders existing logs and updates when new entries arrive', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(appLogProvider.notifier)
        .info(category: 'Test', message: 'existing event');

    await tester.pumpWidget(_app(container));
    await tester.pump();
    expect(find.textContaining('[INFO] [Test] existing event'), findsOneWidget);
    expect(find.textContaining('[INFO] [App] LOG page opened'), findsOneWidget);

    container
        .read(appLogProvider.notifier)
        .warning(category: 'Import', message: 'arrived while open');
    await tester.pump();
    expect(find.textContaining('arrived while open'), findsOneWidget);
  });

  testWidgets('shows the empty state when the buffer is cleared', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container));
    container.read(appLogProvider.notifier).clear();
    await tester.pump();

    expect(find.text(AppStrings.noLogsYet), findsOneWidget);
    expect(find.byKey(const Key('app-log-list')), findsNothing);
  });

  testWidgets('copies the full current snapshot including COPY invocation', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final service = container.read(appLogProvider.notifier);
    service.info(category: 'Reader', message: 'first copy line');
    service.error(category: 'Database', message: 'second copy line');
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(_app(container));
    await tester.tap(find.byKey(const Key('app-log-copy')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(copiedText, isNotNull);
    expect(copiedText, contains('[INFO] [Reader] first copy line'));
    expect(copiedText, contains('[ERROR] [Database] second copy line'));
    expect(copiedText, contains('[INFO] [App] COPY invoked'));
    expect(
      copiedText!.indexOf('first copy line'),
      lessThan(copiedText!.indexOf('second copy line')),
    );
    expect(find.text(AppStrings.logsCopied), findsOneWidget);
  });

  testWidgets('wraps long messages without overflowing the page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(appLogProvider.notifier)
        .info(category: 'Test', message: 'very-long-line-' * 80);

    await tester.pumpWidget(_app(container));
    expect(tester.takeException(), isNull);
    expect(find.byType(SelectableText), findsWidgets);
  });

  testWidgets('renders a large bounded list lazily and remains scrollable', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final service = container.read(appLogProvider.notifier)..clear();
    for (var index = 0; index < AppLogService.maxEntries; index++) {
      service.info(category: 'Test', message: 'entry $index');
    }

    await tester.pumpWidget(_app(container));
    expect(find.textContaining('entry 999'), findsNothing);
    final scrollable = find.descendant(
      of: find.byKey(const Key('app-log-list')),
      matching: find.byType(Scrollable),
    );
    final state = tester.state<ScrollableState>(scrollable.first);
    state.position.jumpTo(state.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.textContaining('entry 999'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: const MaterialApp(home: AppLogScreen()),
);

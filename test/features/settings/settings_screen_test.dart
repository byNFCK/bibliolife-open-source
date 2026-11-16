import 'package:bibliolife/features/settings/presentation/screens/settings_screen.dart';
import 'package:bibliolife/app/router/app_routes.dart';
import 'package:bibliolife/features/app_logs/presentation/screens/app_log_screen.dart';
import 'package:bibliolife/features/profile/presentation/screens/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('/settings uses the shared body and exposes Application mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Profile'), findsNothing);
    expect(find.byType(SettingsBody), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.byKey(const Key('settings-heading-Online')), findsOneWidget);
    expect(find.text('Storage', skipOffstage: false), findsOneWidget);
    expect(find.text('Application mode'), findsOneWidget);
    expect(find.text('Default carousel in Home'), findsOneWidget);
    expect(find.byType(SegmentedButton), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
  });

  testWidgets('LOG entry opens its page and back returns to Settings', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: AppRoutes.profilePath,
      routes: [
        GoRoute(
          path: AppRoutes.profilePath,
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: AppRoutes.logsPath,
          builder: (context, state) => const AppLogScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -1400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('logs-settings-row')), findsOneWidget);
    await tester.tap(find.byKey(const Key('logs-settings-row')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app-log-copy')), findsOneWidget);
    expect(find.textContaining('[INFO] [App] LOG page opened'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 1400));
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -1400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('logs-settings-row')), findsOneWidget);
  });
}

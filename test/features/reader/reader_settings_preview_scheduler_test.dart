import 'package:bibliolife/features/reader/presentation/models/reader_settings_preview_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('raw samples share one 120 ms cadence tick', (tester) async {
    var ticks = 0;
    var elapsed = Duration.zero;
    final scheduler = ReaderSettingsPreviewScheduler(
      onCadence: () => ticks++,
      elapsed: () => elapsed,
    );
    scheduler.schedule();
    await tester.pump(const Duration(milliseconds: 30));
    scheduler.schedule();
    scheduler.schedule();
    await tester.pump(const Duration(milliseconds: 89));
    expect(ticks, 0);
    elapsed = const Duration(milliseconds: 120);
    await tester.pump(const Duration(milliseconds: 1));
    expect(ticks, 1);
    scheduler.dispose();
  });

  testWidgets('dispatch starts are paced and yield a render opportunity', (
    tester,
  ) async {
    var ticks = 0;
    var elapsed = Duration.zero;
    void Function()? render;
    final scheduler = ReaderSettingsPreviewScheduler(
      onCadence: () => ticks++,
      elapsed: () => elapsed,
      requestRenderOpportunity: (onFrame) => render = onFrame,
    );

    scheduler.schedule();
    elapsed = const Duration(milliseconds: 120);
    await tester.pump(const Duration(milliseconds: 120));
    expect(ticks, 1);
    scheduler.recordDispatchStarted();
    scheduler.recordCommitCompleted();
    scheduler.schedule();
    elapsed = const Duration(milliseconds: 239);
    await tester.pump(const Duration(milliseconds: 119));
    expect(ticks, 1);
    elapsed = const Duration(milliseconds: 240);
    await tester.pump(const Duration(milliseconds: 1));
    expect(ticks, 1);
    expect(render, isNotNull);
    render!();
    expect(ticks, 2);
    scheduler.dispose();
  });

  testWidgets('urgent flush bypasses cadence and invalidates a queued frame', (
    tester,
  ) async {
    var ticks = 0;
    void Function()? render;
    final scheduler = ReaderSettingsPreviewScheduler(
      onCadence: () => ticks++,
      requestRenderOpportunity: (onFrame) => render = onFrame,
    );
    scheduler.recordCommitCompleted();
    scheduler.schedule();
    await tester.pump(const Duration(milliseconds: 120));
    expect(render, isNotNull);
    scheduler.flush();
    expect(ticks, 1);
    render!();
    expect(ticks, 1);
    expect(scheduler.consumeUrgentTick(), isTrue);
    scheduler.dispose();
  });

  testWidgets('held ordinary samples collapse until the active request ends', (
    tester,
  ) async {
    var ticks = 0;
    var elapsed = Duration.zero;
    final scheduler = ReaderSettingsPreviewScheduler(
      onCadence: () => ticks++,
      elapsed: () => elapsed,
    );
    scheduler.recordDispatchStarted();
    scheduler.holdUntilActiveCompletes();
    scheduler.schedule();
    elapsed = const Duration(seconds: 1);
    await tester.pump(const Duration(seconds: 1));
    expect(ticks, 0);
    elapsed = const Duration(seconds: 1);
    scheduler.resume();
    await tester.pump(const Duration(milliseconds: 1));
    expect(ticks, 1);
    scheduler.dispose();
  });

  testWidgets('cancel and dispose discard scheduled callbacks', (tester) async {
    var ticks = 0;
    final scheduler = ReaderSettingsPreviewScheduler(onCadence: () => ticks++);
    scheduler.schedule();
    scheduler.cancel();
    scheduler.schedule();
    scheduler.dispose();
    await tester.pump(const Duration(milliseconds: 120));
    expect(ticks, 0);
  });
}

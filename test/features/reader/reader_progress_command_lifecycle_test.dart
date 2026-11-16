import 'dart:async';
import 'package:bibliolife/features/reader/presentation/models/reader_progress_scrub_coordinator.dart';
import 'package:bibliolife/features/reader/presentation/models/reader_ui_controller.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'final survives ended gesture and new gesture with no navigation target',
    () async {
      final h = _Host();
      final c = ReaderProgressScrubCoordinator(host: h, uiSessionId: 4);
      c.sliderStart(.1);
      final done = c.finish(.8123456789);
      final id = c.activeCommandId;
      await tick();
      c.sliderStart(.8);
      expect(c.activeCommandId, id);
      expect(c.isCommandCurrent(id), true);
      expect(h.invalidated, isEmpty);
      expect(h.openCount, 1);
      h.calls.single.release.complete();
      await done;
      expect(c.isCommandCommitted(id), true);
      final end = h.logs.firstWhere(
        (e) => e['kind'] == 'progress_gesture_terminal',
      );
      expect(end['result'], 'ended');
      expect(end['commandStillAuthoritative'], true);
      c.detachUi();
    },
  );

  test(
    'Go survives UI close while UI callback is fenced independently',
    () async {
      final h = _Host();
      final c = ReaderProgressScrubCoordinator(host: h);
      final done = c.goToPosition(.9);
      final id = c.activeCommandId;
      c.detachUi();
      await tick();
      expect(h.invalidated, isEmpty);
      h.calls.single.release.complete();
      await done;
      await tick();
      expect(c.isCommandCommitted(id), true);
      final fence = h.logs.singleWhere(
        (e) => e['kind'] == 'progress_ui_callback_fence',
      );
      expect(fence['commandStillAuthoritative'], true);
      expect(fence['uiSessionOpen'], false);
    },
  );

  test(
    'Cancel supersedes executing Go and returns exactly captured origin after drain',
    () async {
      final h = _Host();
      final origin = h.currentOrigin;
      final c = ReaderProgressScrubCoordinator(host: h);
      final go = c.goToPosition(.9);
      await tick();
      final oldId = c.activeCommandId;
      h.currentOrigin = const _Origin(.9);
      final rollback = c.cancel();
      expect(c.isOpen, false);
      expect(h.calls, hasLength(1));
      expect(h.invalidated, [1]);
      h.calls.first.release.complete();
      await tick();
      expect(h.calls.map((e) => e.type), ['go_to_position', 'cancel_rollback']);
      expect(identical(h.calls.last.origin, origin), true);
      expect(h.calls.last.target, .125);
      h.calls.last.release.complete();
      await rollback;
      await go;
      expect(h.maximumActive, 1);
      expect(h.originCaptures, 1);
      expect(
        h.logs
            .where(
              (e) =>
                  e['kind'] == 'progress_navigation_command' &&
                  e['commandId'] == oldId &&
                  e['result'] != 'created',
            )
            .map((e) => e['result']),
        ['superseded'],
      );
    },
  );

  test(
    'pending Go is replaced by Cancel without intermediate Go dispatch',
    () async {
      final h = _Host();
      final c = ReaderProgressScrubCoordinator(host: h);
      c.preview(.3);
      await tick();
      c.preview(.6);
      final go = c.goToPosition(.8);
      final rollback = c.cancel();
      h.calls.first.release.complete();
      await tick();
      expect(h.calls.map((e) => e.type), ['preview', 'cancel_rollback']);
      h.calls.last.release.complete();
      await rollback;
      await go;
      expect(h.maximumActive, 1);
    },
  );

  test(
    'many completed previews roll back directly to once-captured origin',
    () async {
      final h = _Host();
      final c = ReaderProgressScrubCoordinator(host: h, cadence: Duration.zero);
      for (final target in [.3, .5, .8]) {
        c.sliderStart(target);
        c.preview(target);
        await tick();
        h.calls.last.release.complete();
        await tick();
        h.currentOrigin = _Origin(target);
      }
      final rollback = c.cancel();
      await tick();
      expect(h.calls.last.type, 'cancel_rollback');
      expect(h.calls.last.target, .125);
      expect(h.calls.where((e) => e.type == 'cancel_rollback'), hasLength(1));
      h.calls.last.release.complete();
      await rollback;
      expect(h.originCaptures, 1);
    },
  );

  test(
    'same modal supports repeated cross-resource gesture rollovers without reopen',
    () async {
      final h = _Host();
      final c = ReaderProgressScrubCoordinator(host: h, cadence: Duration.zero);
      for (var i = 0; i < 24; i++) {
        c.sliderStart(.1);
        final done = c.finish((i + 1) / 25);
        final id = c.activeCommandId;
        c.sliderStart(.2);
        await tick();
        expect(c.isCommandCurrent(id), true);
        h.calls.last.release.complete();
        await done;
        await tick();
        expect(c.isOpen, true);
      }
      expect(h.calls, hasLength(24));
      expect(h.originCaptures, 1);
      expect(h.maximumActive, 1);
      c.detachUi();
    },
  );

  test(
    'timeout terminal is unique and next final succeeds in same coordinator',
    () async {
      final h = _Host();
      final c = ReaderProgressScrubCoordinator(host: h);
      final failed = c.finish(.8);
      final expected = expectLater(failed, throwsStateError);
      await tick();
      h.calls.single.release.completeError(
        ReaderProgressCommandFailure('timeout', 'recovered_timeout'),
      );
      await expected;
      await tick();
      expect(
        h.logs.where(
          (e) =>
              e['kind'] == 'progress_navigation_command' &&
              e['result'] == 'recovered_timeout',
        ),
        hasLength(1),
      );
      final done = c.finish(.4);
      await tick();
      h.calls.last.release.complete();
      await done;
      expect(c.isCommandCommitted(c.activeCommandId), true);
      c.detachUi();
    },
  );

  test(
    'missing canonical origin fails instead of dispatching approximate rollback',
    () async {
      final h = _Host()..originAvailable = false;
      final c = ReaderProgressScrubCoordinator(host: h);
      await expectLater(c.cancel(), throwsStateError);
      expect(h.calls, isEmpty);
      expect(c.isOpen, false);
    },
  );
}

final class _Origin implements ReaderProgressOrigin {
  const _Origin(this.totalProgression);
  @override
  final double totalProgression;
  @override
  int get readingOrderIndex => 3;
  @override
  double get resourceProgression => .333;
  @override
  int get logicalPosition => 42;
}

final class _Call {
  _Call(this.target, this.type, [this.origin]);
  final double target;
  final String type;
  final ReaderProgressOrigin? origin;
  final release = Completer<void>();
}

final class _Host
    implements
        ReaderProgressScrubHost,
        ReaderProgressOriginHost,
        ReaderProgressDiagnosticHost {
  final logs = <Map<String, Object?>>[],
      calls = <_Call>[],
      invalidated = <int>[];
  var openCount = 0, originCaptures = 0, active = 0, maximumActive = 0;
  bool originAvailable = true;
  _Origin currentOrigin = const _Origin(.125);
  @override
  void progressDiagnostic(Map<String, Object?> fields) => logs.add(fields);
  @override
  ReaderProgressOrigin? captureProgressOrigin() {
    originCaptures++;
    return originAvailable ? currentOrigin : null;
  }

  @override
  Future<int> openProgressScrub({
    bool checkpointCurrentPosition = true,
    ReaderProgressCommandIdentity? command,
  }) async => ++openCount;
  @override
  bool isProgressScrubActive(int sessionId) =>
      sessionId == openCount && !invalidated.contains(sessionId);
  Future<void> run(_Call call) async {
    calls.add(call);
    active++;
    if (active > maximumActive) maximumActive = active;
    try {
      await call.release.future;
    } finally {
      active--;
    }
  }

  @override
  Future<void> previewProgressScrub({
    required int sessionId,
    required int requestId,
    required double target,
    ReaderProgressCommandIdentity? command,
  }) => run(_Call(target, 'preview'));
  @override
  Future<void> finishProgressScrub({
    required int sessionId,
    required int requestId,
    required double target,
    ReaderProgressCommandIdentity? command,
  }) => run(_Call(target, command?.commandType ?? 'slider_final'));
  @override
  Future<void> restoreProgressOrigin({
    required ReaderProgressOrigin origin,
    required int sessionId,
    required int requestId,
    required ReaderProgressCommandIdentity command,
  }) => run(_Call(origin.totalProgression!, 'cancel_rollback', origin));
  @override
  Future<void> restoreProgressScrub({
    required int sessionId,
    required int requestId,
    required double target,
  }) async => throw StateError('approximate rollback forbidden');
  @override
  Future<void> closeProgressScrub(int sessionId) async {}
  @override
  Future<void> invalidateProgressScrub(int sessionId) async {
    invalidated.add(sessionId);
  }
}

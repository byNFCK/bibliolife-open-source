import 'dart:async';

import 'package:bibliolife/features/reader/domain/models/epub_reader_settings.dart';
import 'package:bibliolife/features/reader/domain/models/reading_progress.dart';
import 'package:bibliolife/features/reader/domain/models/reader_kind.dart';
import 'package:bibliolife/features/reader/domain/models/reader_progress_state.dart';
import 'package:bibliolife/features/reader/domain/models/reader_search.dart';
import 'package:bibliolife/features/reader/domain/models/reader_settings.dart';
import 'package:bibliolife/features/reader/domain/repositories/epub_reader_settings_repository.dart';
import 'package:bibliolife/features/reader/domain/repositories/reading_progress_repository.dart';
import 'package:bibliolife/features/reader/presentation/models/readium_epub_reader_controller.dart';
import 'package:bibliolife/features/reader/presentation/models/reader_progress_scrub_coordinator.dart';
import 'package:bibliolife/features/reader/presentation/models/reader_ui_controller.dart';
import 'package:bibliolife/shared/application/logging/app_log_provider.dart';
import 'package:bibliolife/shared/models/book_format.dart';
import 'package:bibliolife/shared/models/library_book.dart';
import 'package:bibliolife_readium/bibliolife_readium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../support/fake_reader_settings_repository.dart';

void main() {
  test(
    'newer modal Go prevents older detached rollback from acquiring a later native lease',
    () async {
      final client = _FakeClient()..delayedOwnedNavigations = [];
      final progress = _ProgressRepository();
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        progressRepository: progress,
        settingsRepository: _SettingsRepository(),
        controllerBuilder: (v) =>
            ReadiumEpubController(configuration: v, client: client),
      );
      await adapter.initialize();
      final native = adapter.nativeController!;
      await native.start();
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 1,
          type: 'readerLifecycleChanged',
          payload: {'phase': 'ready'},
        ),
      );
      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 2,
          progression: .2,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final oldModal = ReaderProgressScrubCoordinator(host: adapter);
      oldModal.preview(.4);
      await Future<void>.delayed(Duration.zero);
      final oldPreviewRelease = client.delayedOwnedNavigations!.single;
      final rollback = oldModal.cancel();
      final newModal = ReaderProgressScrubCoordinator(host: adapter);
      final go = newModal.goToPosition(.9);
      await Future<void>.delayed(Duration.zero);
      final owner = client.progressScrubOwners.last;
      final goRelease = client.delayedOwnedNavigations!.last;
      expect(client.openedScrubSessions, hasLength(2));
      oldPreviewRelease.complete(const ReadiumNavigationResult('completed'));
      await rollback;
      await Future<void>.delayed(Duration.zero);
      expect(client.originRequests, isEmpty);
      expect(client.openedScrubSessions, hasLength(2));
      expect(newModal.isCommandCurrent(newModal.activeCommandId), true);
      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 3,
          progression: .9,
          owner: owner.toMap(),
        ),
      );
      goRelease.complete(const ReadiumNavigationResult('completed'));
      await go;
      expect(progress.saved.single.progression, .9);
      newModal.detachUi();
      await adapter.disposeAndWait();
    },
  );

  test(
    'Cancel restores exact modal-open canonical Locator only after verified publication; old start cannot revoke it',
    () async {
      const originJson =
          '{"href":"origin.xhtml","type":"application/xhtml+xml","locations":{"progression":0.375,"totalProgression":0.2,"position":42,"cssSelector":"p:nth-child(8)"},"text":{"before":"prefix","highlight":"anchor","after":"suffix"}}';
      final client = _FakeClient();
      final progress = _ProgressRepository();
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        progressRepository: progress,
        settingsRepository: _SettingsRepository(),
        controllerBuilder: (v) =>
            ReadiumEpubController(configuration: v, client: client),
      );
      await adapter.initialize();
      final native = adapter.nativeController!;
      await native.start();
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 1,
          type: 'readerLifecycleChanged',
          payload: {'phase': 'ready'},
        ),
      );
      Map<String, Object?> originPayload([Map<String, Object?>? owner]) => {
        'href': 'origin.xhtml',
        'locatorJson': originJson,
        'progression': .2,
        'totalProgression': .2,
        'resourceProgression': .375,
        'readingOrderIndex': 3,
        'position': 42,
        'progressOwner': owner,
      };
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 2,
          type: 'positionChanged',
          payload: originPayload(),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final c = ReaderProgressScrubCoordinator(host: adapter, uiSessionId: 10);
      c.sliderStart(.2);
      c.sliderStart(.2);
      expect(client.openedScrubSessions, isEmpty);
      expect(c.origin!.logicalPosition, 42);
      expect(c.origin!.readingOrderIndex, 3);
      c.preview(.8);
      await Future<void>.delayed(Duration.zero);
      final previewOwner = client.progressScrubOwners.last;
      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 3,
          progression: .8,
          owner: previewOwner.toMap(),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(progress.saved, isEmpty);
      final rollback = c.cancel();
      await Future<void>.delayed(Duration.zero);
      final request = client.originRequests.single;
      expect(request.locatorJson, originJson);
      expect(request.readingOrderIndex, 3);
      expect(request.progression, .2);
      expect(progress.saved, isEmpty);
      // This event was emitted by the older native request and arrived late.
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 4,
          type: 'readerLifecycleChanged',
          payload: {
            'phase': 'navigationStarted',
            'command': 'progression',
            'progressOwner': previewOwner.toMap(),
          },
        ),
      );
      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 5,
          progression: .8,
          owner: previewOwner.toMap(),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(adapter.isProgressScrubActive(request.owner.sessionId), true);
      expect(progress.saved, isEmpty);
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 6,
          type: 'positionChanged',
          payload: originPayload(request.owner.toMap()),
        ),
      );
      await rollback;
      expect(progress.saved, hasLength(1));
      expect(progress.saved.single.progression, .2);
      expect(progress.saved.single.locatorJson, originJson);
      await adapter.disposeAndWait();
    },
  );

  test(
    'independent Go commits and persists after its originating modal closes',
    () async {
      final client = _FakeClient();
      final progress = _ProgressRepository();
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        progressRepository: progress,
        settingsRepository: _SettingsRepository(),
        controllerBuilder: (v) =>
            ReadiumEpubController(configuration: v, client: client),
      );
      await adapter.initialize();
      final native = adapter.nativeController!;
      await native.start();
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 1,
          type: 'readerLifecycleChanged',
          payload: {'phase': 'ready'},
        ),
      );
      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 2,
          progression: .1,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final c = ReaderProgressScrubCoordinator(host: adapter);
      final go = c.goToPosition(.9);
      c.detachUi();
      await Future<void>.delayed(Duration.zero);
      final owner = client.progressScrubOwners.last;
      expect(adapter.isProgressScrubActive(owner.sessionId), true);
      expect(progress.saved, isEmpty);
      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 3,
          progression: .9,
          owner: owner.toMap(),
        ),
      );
      await go;
      expect(progress.saved.single.progression, .9);
      expect(c.isCommandCommitted(c.activeCommandId), true);
      expect(client.originRequests, isEmpty);
      await adapter.disposeAndWait();
    },
  );

  for (final failure in ['failed', 'recoveredTimeout', 'publication']) {
    test(
      'rollback $failure cannot persist origin before verified commit',
      () async {
        final client = _FakeClient();
        final progress = _ProgressRepository();
        final adapter = ReadiumEpubReaderController(
          book: _book(),
          progressRepository: progress,
          settingsRepository: _SettingsRepository(),
          controllerBuilder: (v) =>
              ReadiumEpubController(configuration: v, client: client),
        );
        await adapter.initialize();
        final native = adapter.nativeController!;
        await native.start();
        client.emit(
          _event(
            instanceId: native.instanceId,
            sequence: 1,
            type: 'readerLifecycleChanged',
            payload: {'phase': 'ready'},
          ),
        );
        client.emit(
          _positionEvent(
            instanceId: native.instanceId,
            sequence: 2,
            progression: .2,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        final c = ReaderProgressScrubCoordinator(host: adapter);
        client.ownedNavigationStatus = failure == 'publication'
            ? 'completed'
            : failure;
        client.ownedPublicationFailed = failure == 'publication';
        await expectLater(c.cancel(), throwsStateError);
        expect(client.originRequests, hasLength(1));
        expect(progress.saved, isEmpty);
        expect(c.isOpen, false);
        await adapter.disposeAndWait();
      },
    );
  }

  test(
    'Cancel fences old final publication and persistence before new session commit',
    () async {
      final progress = _ProgressRepository();
      final client = _FakeClient()..delayedOwnedNavigations = [];
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        progressRepository: progress,
        settingsRepository: _SettingsRepository(),
        controllerBuilder: (value) =>
            ReadiumEpubController(configuration: value, client: client),
      );
      await adapter.initialize();
      final native = adapter.nativeController!;
      await native.start();
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 1,
          type: 'readerLifecycleChanged',
          payload: {'phase': 'ready'},
        ),
      );
      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 2,
          progression: .1,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final old = await adapter.openProgressScrub();
      progress.saved.clear();
      final oldFinal = adapter.finishProgressScrub(
        sessionId: old,
        requestId: 1,
        target: .4,
      );
      final oldExpectation = expectLater(oldFinal, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      final release = client.delayedOwnedNavigations!.single;
      await adapter.invalidateProgressScrub(old);
      expect(adapter.isProgressScrubActive(old), false);
      final current = await adapter.openProgressScrub();
      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 3,
          progression: .4,
          owner: {'sessionId': old, 'requestId': 1, 'phase': 'final'},
        ),
      );
      release.complete(const ReadiumNavigationResult('completed'));
      await oldExpectation;
      expect(progress.saved, isEmpty);
      expect(adapter.isProgressScrubActive(current), true);
      client.delayedOwnedNavigations = null;
      final newFinal = adapter.finishProgressScrub(
        sessionId: current,
        requestId: 1,
        target: .9,
      );
      await Future<void>.delayed(Duration.zero);
      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 4,
          progression: .9,
          owner: {'sessionId': current, 'requestId': 1, 'phase': 'final'},
        ),
      );
      await newFinal;
      expect(progress.saved, hasLength(1));
      expect(progress.saved.single.progression, .9);
      await adapter.disposeAndWait();
    },
  );

  test(
    'recovered final never persists and a new gesture can navigate',
    () async {
      final progress = _ProgressRepository();
      final client = _FakeClient()..ownedNavigationStatus = 'recoveredTimeout';
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        progressRepository: progress,
        settingsRepository: _SettingsRepository(),
        controllerBuilder: (value) =>
            ReadiumEpubController(configuration: value, client: client),
      );
      await adapter.initialize();
      final native = adapter.nativeController!;
      await native.start();
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 1,
          type: 'readerLifecycleChanged',
          payload: {'phase': 'ready'},
        ),
      );
      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 2,
          progression: .1,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final oldSession = await adapter.openProgressScrub();
      progress.saved.clear();
      await expectLater(
        adapter.finishProgressScrub(
          sessionId: oldSession,
          requestId: 4,
          target: .8123456789,
        ),
        throwsStateError,
      );
      expect(adapter.isProgressScrubActive(oldSession), false);
      expect(progress.saved, isEmpty);
      client.ownedNavigationStatus = 'completed';
      final newSession = await adapter.openProgressScrub();
      expect(newSession, greaterThan(oldSession));
      await adapter.previewProgressScrub(
        sessionId: newSession,
        requestId: 1,
        target: .9,
      );
      expect(client.progressScrubOwners.last.sessionId, newSession);
      expect(progress.saved, isEmpty);
      adapter.dispose();
    },
  );

  for (final failure in ['publication', 'persistence']) {
    test('verified final navigation keeps $failure failure separate', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final log = container.read(appLogProvider.notifier);
      final client = _FakeClient();
      final progress = _ProgressRepository();
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        appLogService: log,
        progressRepository: progress,
        settingsRepository: _SettingsRepository(),
        controllerBuilder: (value) =>
            ReadiumEpubController(configuration: value, client: client),
      );
      await adapter.initialize();
      final native = adapter.nativeController!;
      await native.start();
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 1,
          type: 'readerLifecycleChanged',
          payload: {'phase': 'ready'},
        ),
      );
      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 2,
          progression: .1,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final sessionId = await adapter.openProgressScrub();
      progress.saved
          .clear(); // Opening may checkpoint the pre-gesture position.
      if (failure == 'publication') client.ownedPublicationFailed = true;
      if (failure == 'persistence') progress.failSave = true;
      final finalizing = adapter.finishProgressScrub(
        sessionId: sessionId,
        requestId: 1,
        target: .7,
      );
      final expectation = expectLater(finalizing, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      if (failure == 'persistence') {
        client.emit(
          _positionEvent(
            instanceId: native.instanceId,
            sequence: 3,
            progression: .7,
            owner: {'sessionId': sessionId, 'requestId': 1, 'phase': 'final'},
          ),
        );
      }
      await expectation;
      final expectedKind = failure == 'publication'
          ? 'progress_position_publication'
          : 'progress_persistence';
      expect(log.formattedText, contains('kind=$expectedKind'));
      expect(
        log.formattedText,
        contains('${failure}_failed_after_verified_navigation'),
      );
      expect(log.formattedText, isNot(contains('reason=final_not_committed')));
      expect(log.formattedText, isNot(contains('result=written')));
      expect(progress.saved, isEmpty);
      adapter.dispose();
    });
  }

  test(
    'native progress diagnostics reach dedicated AppLog category without book text',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final log = container.read(appLogProvider.notifier);
      final client = _FakeClient();
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        progressRepository: _ProgressRepository(),
        settingsRepository: _SettingsRepository(),
        appLogService: log,
        controllerBuilder: (value) =>
            ReadiumEpubController(configuration: value, client: client),
      );
      await adapter.initialize();
      final native = adapter.nativeController!;
      await native.start();
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 1,
          type: 'readerDiagnostic',
          payload: {
            'category': 'Reader.Progress',
            'kind': 'progress_target_resolved',
            'gestureId': 7,
            'previewId': 2,
            'navigationGeneration': 11,
            'targetResourceHref': 'OPS/chapter-2.xhtml',
            'isFinal': true,
            'targetLocatorAvailable': true,
            'targetPosition': 196,
            'text': 'PRIVATE CONTENT',
            'locatorJson': 'PRIVATE CONTENT',
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final entry = log.state.singleWhere(
        (e) => e.category == 'Reader.Progress',
      );
      expect(entry.message, contains('gestureId=7'));
      expect(entry.message, contains('previewId=2'));
      expect(entry.message, contains('navigationGeneration=11'));
      expect(entry.message, contains('targetResourceHref=OPS/chapter-2.xhtml'));
      expect(entry.message, contains('isFinal=true'));
      expect(entry.message, isNot(contains('PRIVATE CONTENT')));
      adapter.dispose();
      await adapter.disposeAndWait();
    },
  );

  test(
    'settings diagnostic context reaches AppLog with normalized apply data',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final log = container.read(appLogProvider.notifier);
      final client = _FakeClient()..baselineCapture = Completer<void>();
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        progressRepository: _ProgressRepository(),
        settingsRepository: _SettingsRepository(),
        appLogService: log,
        controllerBuilder: (value) =>
            ReadiumEpubController(configuration: value, client: client),
      );
      await adapter.initialize();
      final native = adapter.nativeController!;
      await native.start();
      final nativeDiagnostics = <ReadiumDiagnosticEvent>[];
      final diagnosticsSubscription = native.diagnostics.listen(
        nativeDiagnostics.add,
      );
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 1,
          type: 'readerLifecycleChanged',
          payload: <String, Object?>{'phase': 'ready'},
        ),
      );
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 2,
          type: 'readerDiagnostic',
          payload: <String, Object?>{
            'level': 'debug',
            'kind': 'measurement_applied',
            'gestureId': 91,
            'applyId': 4,
            'slider': 'fontSize',
            'preferenceGeneration': 8,
            'layoutGeneration': 12,
            'resourceGeneration': 27,
            'readingOrderIndex': 6,
            'oldHeightPx': 830,
            'newHeightPx': 914,
            'bookText': 'must be discarded by the parser',
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(nativeDiagnostics, hasLength(1));
      expect(nativeDiagnostics.single.fields['kind'], 'measurement_applied');
      final gesture = adapter.beginSettingsDiagnostic(
        ReaderSliderId.fontWeight,
        1.13,
      );
      final preview = adapter.previewSettingsWithDiagnostics(
        ReaderSettingsState.readiumDefaults.copyWith(
          typography: const ReaderTypographySettings(fontWeight: 1.17),
        ),
        gesture: gesture,
      );
      await Future<void>.delayed(Duration.zero);
      expect(client.diagnosticContexts, isEmpty);
      expect(client.gestureActions, ['begin']);
      client.baselineCapture!.complete();
      await preview;
      adapter.endSettingsDiagnostic(gesture, 1.17);
      await adapter.finishSettingsGestureBaseline(gesture);
      expect(client.gestureActions, ['begin', 'end']);

      expect(client.diagnosticContexts, hasLength(1));
      expect(client.diagnosticContexts.single.slider, 'fontWeight');
      expect(client.diagnosticContexts.single.gestureId, gesture.id);
      expect(client.diagnosticContexts.single.normalizedValue, 1.17);
      final messages = log.state.map((entry) => entry.message).join('\n');
      expect(messages, contains('kind=slider_start gestureId=${gesture.id}'));
      expect(
        messages,
        contains('kind=adapter_apply_start gestureId=${gesture.id}'),
      );
      expect(messages, contains('slider=fontWeight'));
      expect(messages, contains('kind=adapter_apply_done'));
      expect(messages, contains('kind=slider_end gestureId=${gesture.id}'));
      expect(messages, contains('kind=measurement_applied'));
      expect(messages, contains('layoutGeneration=12'));
      expect(messages, isNot(contains('bookText')));
      expect(log.formattedText, contains('kind=measurement_applied'));
      expect(log.formattedText, contains('resourceGeneration=27'));
      expect(log.formattedText, isNot(contains('must be discarded')));
      // Closing Settings must fence a pending start without waiting for its
      // DOM callback. A late completion cannot resurrect that gesture.
      client.baselineCapture = Completer<void>();
      final cancelledGesture = adapter.beginSettingsDiagnostic(
        ReaderSliderId.fontSize,
        1.0,
      );
      await adapter.finishSettingsGestureBaseline(
        cancelledGesture,
        cancelled: true,
      );
      expect(client.gestureActions, ['begin', 'end', 'begin', 'cancel']);
      expect(client.baselineCapture!.isCompleted, false);
      client.baselineCapture!.complete();
      await diagnosticsSubscription.cancel();
      adapter.dispose();
    },
  );

  test(
    'verified scrub release checkpoints once and ordinary publication resumes before close',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final log = container.read(appLogProvider.notifier);
      final progress = _ProgressRepository();
      final client = _FakeClient();
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        appLogService: log,
        progressRepository: progress,
        settingsRepository: _SettingsRepository(),
        controllerBuilder: (value) =>
            ReadiumEpubController(configuration: value, client: client),
      );
      await adapter.initialize();
      final native = adapter.nativeController!;
      await native.start();
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 1,
          type: 'readerLifecycleChanged',
          payload: <String, Object?>{'phase': 'ready'},
        ),
      );
      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 2,
          progression: .1,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(progress.saved.map((entry) => entry.progression), <double>[.1]);

      final sessionId = await adapter.openProgressScrub();
      await adapter.previewProgressScrub(
        sessionId: sessionId,
        requestId: 1,
        target: .4,
      );
      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 3,
          progression: .4,
          owner: <String, Object?>{
            'sessionId': sessionId,
            'requestId': 1,
            'phase': 'preview',
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(progress.saved.map((entry) => entry.progression), <double>[.1]);

      expect(log.formattedText, contains('result=skipped_preview'));
      expect(log.formattedText, isNot(contains('result=written')));
      final finalizing = adapter.finishProgressScrub(
        sessionId: sessionId,
        requestId: 2,
        target: .7,
      );
      await Future<void>.delayed(Duration.zero);
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 4,
          type: 'readerLifecycleChanged',
          payload: <String, Object?>{
            'phase': 'navigationStarted',
            'command': 'progression',
            'progressOwner': <String, Object?>{
              'sessionId': sessionId,
              'requestId': 2,
              'phase': 'final',
            },
          },
        ),
      );
      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 5,
          progression: .63,
        ),
      );
      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 6,
          progression: .95,
          owner: <String, Object?>{
            'sessionId': sessionId,
            'requestId': 3,
            'phase': 'preview',
          },
        ),
      );
      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 7,
          progression: .7,
          owner: <String, Object?>{
            'sessionId': sessionId,
            'requestId': 2,
            'phase': 'final',
          },
        ),
      );
      await finalizing;
      expect(log.formattedText, contains('Reader.Progress'));
      expect(log.formattedText, contains('kind=progress_persistence'));
      expect(log.formattedText, contains('isFinal=true result=written'));
      expect(log.formattedText, isNot(contains('locatorJson=')));
      expect(adapter.isProgressScrubActive(sessionId), isFalse);
      expect(progress.saved.map((entry) => entry.progression), <double>[
        .1,
        .7,
      ]);

      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 8,
          progression: .4,
          owner: <String, Object?>{
            'sessionId': sessionId,
            'requestId': 1,
            'phase': 'preview',
          },
        ),
      );
      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 9,
          progression: .7,
          owner: <String, Object?>{
            'sessionId': sessionId,
            'requestId': 2,
            'phase': 'final',
          },
        ),
      );
      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 10,
          progression: .9,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(adapter.progress.progression, .9);
      expect(progress.saved.map((entry) => entry.progression), <double>[
        .1,
        .7,
        .9,
      ]);
      final secondSession = await adapter.openProgressScrub();
      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 11,
          progression: .35,
          owner: <String, Object?>{
            'sessionId': sessionId,
            'requestId': 1,
            'phase': 'preview',
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(adapter.progress.progression, .9);
      expect(progress.saved.map((entry) => entry.progression), <double>[
        .1,
        .7,
        .9,
      ]);
      await adapter.invalidateProgressScrub(secondSession);
      await adapter.disposeAndWait();
    },
  );

  test(
    'ordinary navigation invalidates scrub ownership and rejects late preview',
    () async {
      final progress = _ProgressRepository();
      final client = _FakeClient();
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        progressRepository: progress,
        settingsRepository: _SettingsRepository(),
        controllerBuilder: (value) =>
            ReadiumEpubController(configuration: value, client: client),
      );
      await adapter.initialize();
      final native = adapter.nativeController!;
      await native.start();
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 1,
          type: 'readerLifecycleChanged',
          payload: <String, Object?>{'phase': 'ready'},
        ),
      );
      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 2,
          progression: .2,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final initialSaves = progress.saved.length;

      final sessionId = await adapter.openProgressScrub();
      await adapter.previewProgressScrub(
        sessionId: sessionId,
        requestId: 1,
        target: .6,
      );
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 3,
          type: 'readerLifecycleChanged',
          payload: <String, Object?>{
            'phase': 'navigationStarted',
            'command': 'toc',
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(adapter.isProgressScrubActive(sessionId), isFalse);
      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 4,
          progression: .6,
          owner: <String, Object?>{
            'sessionId': sessionId,
            'requestId': 1,
            'phase': 'preview',
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(progress.saved, hasLength(initialSaves));
      expect(progress.saved.last.progression, .2);
      await adapter.disposeAndWait();
    },
  );

  test(
    'failed final never checkpoints and disposal invalidates active lease',
    () async {
      final progress = _ProgressRepository();
      final client = _FakeClient();
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        progressRepository: progress,
        settingsRepository: _SettingsRepository(),
        controllerBuilder: (value) =>
            ReadiumEpubController(configuration: value, client: client),
      );
      await adapter.initialize();
      final native = adapter.nativeController!;
      await native.start();
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 1,
          type: 'readerLifecycleChanged',
          payload: <String, Object?>{'phase': 'ready'},
        ),
      );
      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 2,
          progression: .2,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));

      final failedSession = await adapter.openProgressScrub();
      client.ownedNavigationStatus = 'interrupted';
      await expectLater(
        adapter.finishProgressScrub(
          sessionId: failedSession,
          requestId: 1,
          target: .8,
        ),
        throwsStateError,
      );
      expect(adapter.isProgressScrubActive(failedSession), isFalse);
      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 3,
          progression: .8,
          owner: <String, Object?>{
            'sessionId': failedSession,
            'requestId': 1,
            'phase': 'final',
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(progress.saved.map((entry) => entry.progression), <double>[.2]);
      expect(adapter.progress.progression, .2);

      client.ownedNavigationStatus = 'completed';
      final restoring = adapter.restoreProgressScrub(
        sessionId: failedSession,
        requestId: 2,
        target: .2,
      );
      await Future<void>.delayed(Duration.zero);
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 4,
          type: 'readerLifecycleChanged',
          payload: <String, Object?>{
            'phase': 'navigationStarted',
            'command': 'progression',
            'progressOwner': <String, Object?>{
              'sessionId': failedSession + 1,
              'requestId': 2,
              'phase': 'final',
            },
          },
        ),
      );
      client.emit(
        _positionEvent(
          instanceId: native.instanceId,
          sequence: 5,
          progression: .2,
          owner: <String, Object?>{
            'sessionId': failedSession + 1,
            'requestId': 2,
            'phase': 'final',
          },
        ),
      );
      await restoring;
      expect(adapter.isProgressScrubActive(failedSession + 1), isFalse);
      expect(progress.saved.map((entry) => entry.progression), <double>[.2]);

      final disposedSession = await adapter.openProgressScrub();
      await adapter.disposeAndWait();
      expect(client.invalidatedScrubSessions, contains(disposedSession));
    },
  );

  test('equal native rendered positions are structurally deduplicated', () {
    const first = ReadiumPosition(
      locatorJson: '{"href":"chapter.xhtml"}',
      href: 'chapter.xhtml',
      progression: .5,
      fragments: <String>['fragment'],
      presentation: ReadiumPaginatedPresentation(
        pageIndex: 3,
        pageCount: 10,
        progression: .3,
        layoutGeneration: 4,
        publicationScoped: true,
      ),
    );
    const equal = ReadiumPosition(
      locatorJson: '{"href":"chapter.xhtml"}',
      href: 'chapter.xhtml',
      progression: .5,
      fragments: <String>['fragment'],
      presentation: ReadiumPaginatedPresentation(
        pageIndex: 3,
        pageCount: 10,
        progression: .3,
        layoutGeneration: 4,
        publicationScoped: true,
      ),
    );
    const changedPage = ReadiumPosition(
      locatorJson: '{"href":"chapter.xhtml"}',
      href: 'chapter.xhtml',
      progression: .5,
      fragments: <String>['fragment'],
      presentation: ReadiumPaginatedPresentation(
        pageIndex: 4,
        pageCount: 10,
        progression: .4,
        layoutGeneration: 4,
        publicationScoped: true,
      ),
    );

    expect(sameReadiumPositionForPerformance(first, equal), isTrue);
    expect(sameReadiumPositionForPerformance(first, changedPage), isFalse);
  });

  test(
    'live manual position updates UI but remains outside progress persistence',
    () async {
      final progress = _ProgressRepository();
      final client = _FakeClient();
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        progressRepository: progress,
        settingsRepository: _SettingsRepository(),
        controllerBuilder: (value) =>
            ReadiumEpubController(configuration: value, client: client),
      );
      await adapter.initialize();
      final native = adapter.nativeController!;
      await native.start();
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 1,
          type: 'readerLifecycleChanged',
          payload: <String, Object?>{'phase': 'ready'},
        ),
      );
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 2,
          type: 'positionChanged',
          payload: <String, Object?>{
            'href': 'chapter.xhtml',
            'locatorJson':
                '{"href":"chapter.xhtml","locations":{"progression":0.1}}',
            'progression': .1,
          },
        ),
      );
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 3,
          type: 'manualScrollActivityChanged',
          payload: <String, Object?>{'active': true},
        ),
      );
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 4,
          type: 'positionChanged',
          payload: <String, Object?>{
            'href': 'chapter.xhtml',
            'locatorJson':
                '{"href":"chapter.xhtml","locations":{"progression":0.8}}',
            'progression': .8,
            'liveManual': true,
          },
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(adapter.progress.progression, .8);
      expect(progress.saved, isEmpty);

      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 5,
          type: 'manualScrollActivityChanged',
          payload: <String, Object?>{'active': false},
        ),
      );
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 6,
          type: 'positionChanged',
          payload: <String, Object?>{
            'href': 'chapter.xhtml',
            'locatorJson':
                '{"href":"chapter.xhtml","locations":{"progression":0.8}}',
            'progression': .8,
          },
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(progress.saved, hasLength(1));
      expect(progress.saved.single.progression, .8);
      await adapter.disposeAndWait();
    },
  );

  test(
    'manual paginated snap-back persists final locator equal to prior checkpoint',
    () async {
      final progress = _ProgressRepository();
      final client = _FakeClient();
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        progressRepository: progress,
        settingsRepository: _SettingsRepository(),
        controllerBuilder: (value) =>
            ReadiumEpubController(configuration: value, client: client),
      );
      await adapter.initialize();
      final native = adapter.nativeController!;
      await native.start();
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 1,
          type: 'readerLifecycleChanged',
          payload: <String, Object?>{'phase': 'ready'},
        ),
      );
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 2,
          type: 'positionChanged',
          payload: <String, Object?>{
            'href': 'chapter.xhtml',
            'locatorJson':
                '{"href":"chapter.xhtml","locations":{"progression":0.1}}',
            'progression': .1,
          },
        ),
      );
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 3,
          type: 'manualScrollActivityChanged',
          payload: <String, Object?>{'active': true},
        ),
      );
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 4,
          type: 'positionChanged',
          payload: <String, Object?>{
            'href': 'chapter.xhtml',
            'locatorJson':
                '{"href":"chapter.xhtml","locations":{"progression":0.9}}',
            'progression': .9,
            'liveManual': true,
          },
        ),
      );
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 5,
          type: 'manualScrollActivityChanged',
          payload: <String, Object?>{'active': false},
        ),
      );
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 6,
          type: 'positionChanged',
          payload: <String, Object?>{
            'href': 'chapter.xhtml',
            'locatorJson':
                '{"href":"chapter.xhtml","locations":{"progression":0.1}}',
            'progression': .1,
          },
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(adapter.progress.progression, .1);
      expect(progress.saved, hasLength(1));
      expect(progress.saved.single.progression, .1);
      await adapter.disposeAndWait();
    },
  );

  test(
    'dispose during manual scrolling flushes only last authoritative checkpoint',
    () async {
      final progress = _ProgressRepository();
      final client = _FakeClient();
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        progressRepository: progress,
        settingsRepository: _SettingsRepository(),
        controllerBuilder: (value) =>
            ReadiumEpubController(configuration: value, client: client),
      );
      await adapter.initialize();
      final native = adapter.nativeController!;
      await native.start();
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 1,
          type: 'readerLifecycleChanged',
          payload: <String, Object?>{'phase': 'ready'},
        ),
      );
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 2,
          type: 'positionChanged',
          payload: <String, Object?>{
            'href': 'chapter.xhtml',
            'locatorJson':
                '{"href":"chapter.xhtml","locations":{"progression":0.1}}',
            'progression': .1,
          },
        ),
      );
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 3,
          type: 'manualScrollActivityChanged',
          payload: <String, Object?>{'active': true},
        ),
      );
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 4,
          type: 'positionChanged',
          payload: <String, Object?>{
            'href': 'chapter.xhtml',
            'locatorJson':
                '{"href":"chapter.xhtml","locations":{"progression":0.8}}',
            'progression': .8,
            'liveManual': true,
          },
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await adapter.disposeAndWait();
      expect(progress.saved, hasLength(1));
      expect(progress.saved.single.progression, .1);
    },
  );

  test(
    'uses one configuration locator and disposes one native controller',
    () async {
      final progress = _ProgressRepository()
        ..value = ReadingProgress(
          bookId: 'book',
          locatorJson: '{"href":"saved.xhtml"}',
          progression: .25,
          currentChapterTitle: 'Saved',
          currentPage: 7,
          totalPages: 10,
          updatedAt: DateTime(2026),
        );
      final client = _FakeClient();
      ReadiumEpubOpenConfiguration? configuration;
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        localFilePath: r'C:\cache\converted.epub',
        progressRepository: progress,
        settingsRepository: _SettingsRepository(),
        controllerBuilder: (value) {
          configuration = value;
          return ReadiumEpubController(configuration: value, client: client);
        },
      );

      await adapter.initialize();
      expect(configuration?.initialLocatorJson, '{"href":"saved.xhtml"}');
      expect(configuration?.localFilePath, r'C:\cache\converted.epub');
      expect(adapter.nativeController, isNotNull);
      await adapter.nativeController!.start();
      expect(client.goToLocatorCalls, 0);

      adapter.dispose();
      adapter.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(client.disposeCalls, 1);
    },
  );

  test(
    'explicit locator wins and native position is authoritative EPUB progress',
    () async {
      final progress = _ProgressRepository();
      final client = _FakeClient();
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        initialLocatorJson: '{"href":"explicit.xhtml"}',
        progressRepository: progress,
        settingsRepository: _SettingsRepository(),
        controllerBuilder: (value) =>
            ReadiumEpubController(configuration: value, client: client),
      );

      await adapter.initialize();
      final native = adapter.nativeController!;
      await native.start();
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 1,
          type: 'readerLifecycleChanged',
          payload: <String, Object?>{
            'phase': 'ready',
            'publication': <String, Object?>{
              'bookId': 'book',
              'title': 'Title',
            },
          },
        ),
      );
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 2,
          type: 'positionChanged',
          payload: <String, Object?>{
            'href': 'chapter.xhtml',
            'locatorJson': '{"href":"chapter.xhtml"}',
            'progression': .75,
            'totalProgression': .75,
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(adapter.progress.progression, .75);
      expect(adapter.progress.total, 0);
      expect(adapter.progress.label, 'Progress 75%');
      await adapter.progressRestore!();
      expect(client.goToLocatorCalls, 1);
      await adapter.flushProgress();
      expect(progress.saved.single.locatorJson, '{"href":"chapter.xhtml"}');
      expect(progress.saved.single.currentPage, isNull);
      expect(progress.saved.single.totalPages, isNull);
      adapter.dispose();
    },
  );

  test(
    'native content tap toggles shared controls once per interaction',
    () async {
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        progressRepository: _ProgressRepository(),
        settingsRepository: _SettingsRepository(),
      );
      adapter.setReady();
      final event = ReadiumContentTapEvent(
        metadata: const ReadiumEventMetadata(1, 'id', 1, 'contentTap'),
        interactionId: 42,
      );
      adapter.handleContentTap(event);
      adapter.handleContentTap(event);
      expect(adapter.controlsVisible, isFalse);
      adapter.dispose();
    },
  );

  test(
    'Readium shows a logical Position without calling it a screen page',
    () async {
      final client = _FakeClient();
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        progressRepository: _ProgressRepository(),
        settingsRepository: _SettingsRepository(),
        controllerBuilder: (value) =>
            ReadiumEpubController(configuration: value, client: client),
      );
      await adapter.initialize();
      final native = adapter.nativeController!;
      await native.start();
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 1,
          type: 'readerLifecycleChanged',
          payload: <String, Object?>{'phase': 'ready'},
        ),
      );
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 2,
          type: 'positionChanged',
          payload: <String, Object?>{
            'href': 'chapter.xhtml',
            'totalProgression': .4,
            'position': 42,
            'totalLogicalPositions': 120,
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(adapter.progress.label, 'Progress 40%');
      expect(adapter.progress.total, 0);
      expect(adapter.progress.progression, .4);
      expect(adapter.progress.metric, ReaderProgressMetric.progression);
      adapter.dispose();
    },
  );

  test(
    'TXT displays native rendered pages instead of logical positions',
    () async {
      final client = _FakeClient();
      final adapter = ReadiumEpubReaderController(
        book: _book(format: BookFormat.txt, filePath: r'C:\books\book.txt'),
        localFilePath: r'C:\cache\book.epub',
        progressRepository: _ProgressRepository(),
        settingsRepository: _SettingsRepository(),
        controllerBuilder: (value) =>
            ReadiumEpubController(configuration: value, client: client),
      );
      await adapter.initialize();
      final native = adapter.nativeController!;
      await native.start();
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 1,
          type: 'readerLifecycleChanged',
          payload: <String, Object?>{'phase': 'ready'},
        ),
      );
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 2,
          type: 'positionChanged',
          payload: <String, Object?>{
            'href': 'text/content.xhtml',
            'progression': .25,
            'position': 3,
            'totalLogicalPositions': 12,
            'presentation': <String, Object?>{
              'mode': 'paginated',
              'pageIndex': 2,
              'pageCount': 7,
              'progression': 1 / 3,
              'layoutGeneration': 0,
              'publicationScoped': true,
            },
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(adapter.progress.label, 'Page 3 of 7');
      expect(adapter.progress.current, 2);
      expect(adapter.progress.total, 7);
      expect(adapter.progress.progression, closeTo(1 / 3, .0001));
      expect(adapter.progress.metric, ReaderProgressMetric.renderedPage);
      adapter.dispose();
    },
  );

  test(
    'TXT remains seekable when native session supplies effective progression',
    () async {
      final client = _FakeClient();
      final adapter = ReadiumEpubReaderController(
        book: _book(format: BookFormat.txt, filePath: r'C:\books\book.txt'),
        localFilePath: r'C:\cache\book.epub',
        progressRepository: _ProgressRepository(),
        settingsRepository: _SettingsRepository(),
        controllerBuilder: (value) =>
            ReadiumEpubController(configuration: value, client: client),
      );
      await adapter.initialize();
      final native = adapter.nativeController!;
      await native.start();
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 1,
          type: 'readerLifecycleChanged',
          payload: <String, Object?>{'phase': 'ready'},
        ),
      );
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 2,
          type: 'positionChanged',
          payload: <String, Object?>{
            'href': 'text/content.xhtml',
            'progression': .35,
            'resourceProgression': .35,
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(adapter.progress.progression, .35);
      expect(adapter.progress.canSeek, isTrue);
      expect(adapter.progress.label, 'Progress 35%');
      adapter.dispose();
    },
  );

  test(
    'single-resource effective progression outranks coarse locator total',
    () async {
      final client = _FakeClient();
      final adapter = ReadiumEpubReaderController(
        book: _book(format: BookFormat.txt, filePath: r'C:\books\book.txt'),
        localFilePath: r'C:\cache\book.epub',
        progressRepository: _ProgressRepository(),
        settingsRepository: _SettingsRepository(),
        controllerBuilder: (value) =>
            ReadiumEpubController(configuration: value, client: client),
      );
      await adapter.initialize();
      final native = adapter.nativeController!;
      await native.start();
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 1,
          type: 'readerLifecycleChanged',
          payload: <String, Object?>{'phase': 'ready'},
        ),
      );
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 2,
          type: 'positionChanged',
          payload: <String, Object?>{
            'href': 'text/content.xhtml',
            'progression': .76,
            'resourceProgression': .76,
            'totalProgression': .5,
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(adapter.progress.progression, .76);
      adapter.dispose();
    },
  );

  test(
    'native content tap rejects stale viewport generations and disposal',
    () async {
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        progressRepository: _ProgressRepository(),
        settingsRepository: _SettingsRepository(),
      );
      adapter.setReady();
      adapter.handleContentTap(
        ReadiumContentTapEvent(
          metadata: const ReadiumEventMetadata(1, 'id', 1, 'contentTap'),
          interactionId: 1,
          viewportGeneration: 1,
        ),
      );
      expect(adapter.controlsVisible, isTrue);

      adapter.handleContentTap(
        ReadiumContentTapEvent(
          metadata: const ReadiumEventMetadata(1, 'id', 2, 'contentTap'),
          interactionId: 2,
          viewportGeneration: 0,
        ),
      );
      expect(adapter.controlsVisible, isFalse);

      adapter.dispose();
      adapter.handleContentTap(
        ReadiumContentTapEvent(
          metadata: const ReadiumEventMetadata(1, 'id', 3, 'contentTap'),
          interactionId: 3,
          viewportGeneration: 0,
        ),
      );
      expect(adapter.controlsVisible, isFalse);
    },
  );

  test(
    'native selection suppresses reader chrome until the session ends',
    () async {
      final client = _FakeClient();
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        progressRepository: _ProgressRepository(),
        settingsRepository: _SettingsRepository(),
        controllerBuilder: (value) =>
            ReadiumEpubController(configuration: value, client: client),
      );
      await adapter.initialize();
      final native = adapter.nativeController!;
      await native.start();

      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 1,
          type: 'selectionChanged',
          payload: <String, Object?>{
            'status': 'pending',
            'sessionId': 1,
            'nativeSessionId': 1,
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(adapter.readerChromeSuppressed, isTrue);
      expect(adapter.controlsVisible, isTrue);

      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 2,
          type: 'selectionChanged',
          payload: <String, Object?>{'status': 'inactive'},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(adapter.readerChromeSuppressed, isFalse);
      expect(adapter.controlsVisible, isTrue);
      adapter.dispose();
    },
  );

  test(
    'maps native search state and navigates by the stable result ID',
    () async {
      final client = _FakeClient();
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        progressRepository: _ProgressRepository(),
        settingsRepository: _SettingsRepository(),
        controllerBuilder: (value) =>
            ReadiumEpubController(configuration: value, client: client),
      );
      await adapter.initialize();
      final native = adapter.nativeController!;
      await native.start();
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 1,
          type: 'readerLifecycleChanged',
          payload: <String, Object?>{
            'phase': 'ready',
            'publication': <String, Object?>{
              'bookId': 'book',
              'title': 'Title',
            },
          },
        ),
      );
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 2,
          type: 'searchChanged',
          payload: <String, Object?>{
            'status': 'ready',
            'query': 'Привіт',
            'generation': 3,
            'hasMore': false,
            'loadingMore': false,
            'results': [
              <String, Object?>{
                'id': 'result-1',
                'href': 'chapter.xhtml',
                'title': 'Chapter 1',
                'before': 'Перед ',
                'highlight': 'Привіт',
                'after': ' після',
                'position': 4,
                'progression': .25,
              },
            ],
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final state = adapter.searchState as ReaderSearchReady;
      expect(state.query, 'Привіт');
      expect(state.results.single.id, 'result-1');
      expect(state.results.single.match, 'Привіт');
      expect((await adapter.goToSearchResult('result-1')).isSuccess, isTrue);
      expect(client.searchResultIds, ['result-1']);
      expect(
        (await adapter.goToSearchResult('stale')).status,
        ReaderSearchCommandStatus.stale,
      );
      adapter.dispose();
    },
  );

  test('settings preview is transient until explicit apply', () async {
    final client = _FakeClient();
    final settings = _SettingsRepository();
    final adapter = ReadiumEpubReaderController(
      book: _book(),
      progressRepository: _ProgressRepository(),
      settingsRepository: settings,
      controllerBuilder: (value) =>
          ReadiumEpubController(configuration: value, client: client),
    );
    await adapter.initialize();
    final native = adapter.nativeController!;
    await native.start();
    client.emit(
      _event(
        instanceId: native.instanceId,
        sequence: 1,
        type: 'readerLifecycleChanged',
        payload: <String, Object?>{'phase': 'ready'},
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final preview = ReaderTextSettings(
      fontSize: 1.5,
      lineHeight: 1.5,
      pageMargins: 1,
      publisherStyles: true,
    );
    await adapter.preview(preview);
    expect(settings.value, EpubReaderSettings.defaults);
    expect(client.preferenceApplyCalls, 1);

    await adapter.commit(preview);
    expect(settings.value.fontSize, 1.5);
    expect(client.preferenceApplyCalls, 1);

    await adapter.restore(
      const ReaderTextSettings(
        fontSize: 1,
        lineHeight: 1.5,
        pageMargins: 1,
        publisherStyles: true,
      ),
    );
    expect(settings.value.fontSize, 1.5);
    expect(client.preferenceApplyCalls, 2);
    adapter.dispose();
  });

  test(
    'expanded Readium preview is in-place and persists only on Apply',
    () async {
      final client = _FakeClient();
      final expanded = FakeReaderSettingsRepository();
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        progressRepository: _ProgressRepository(),
        settingsRepository: _SettingsRepository(),
        readerSettingsRepository: expanded,
        controllerBuilder: (value) =>
            ReadiumEpubController(configuration: value, client: client),
      );
      await adapter.initialize();
      final native = adapter.nativeController!;
      await native.start();
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 1,
          type: 'readerLifecycleChanged',
          payload: <String, Object?>{'phase': 'ready'},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 2,
          type: 'positionChanged',
          payload: <String, Object?>{
            'href': 'chapter.xhtml',
            'locatorJson':
                '{"href":"chapter.xhtml","locations":{"position":9}}',
            'progression': .32,
            'position': 9,
            'totalLogicalPositions': 40,
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final locatorBeforeReflow = adapter.locatorJson;
      final progressionBeforeReflow = adapter.normalizedProgression;
      final changed = adapter.state.copyWith(
        appearance: const ReaderAppearanceSettings(theme: ReaderTheme.sepia),
        typography: const ReaderTypographySettings(
          fontFamily: ReaderFontFamily.sansSerif,
          fontSize: 1.4,
          fontWeight: 1.2,
        ),
        spacing: const ReaderSpacingSettings(lineHeight: 1.8, textMargins: 2),
        textLayout: const ReaderTextLayoutSettings(
          alignment: ReaderTextAlignment.justify,
          readingMode: ReaderReadingMode.continuous,
          columns: ReaderColumnCount.two,
        ),
      );

      await adapter.previewSettings(changed);
      expect(adapter.nativeController, same(native));
      expect(expanded.saveCount, 0);
      expect(client.lastPreferences?.fontFamily, 'sansSerif');
      expect(client.lastPreferences?.fontWeight, 1.2);
      expect(client.lastPreferences?.textAlignment, 'justify');
      expect(client.lastPreferences?.scroll, isTrue);
      expect(client.lastPreferences?.columns, 'two');
      expect(adapter.locatorJson, locatorBeforeReflow);
      expect(adapter.normalizedProgression, progressionBeforeReflow);

      await adapter.commitSettings(changed);
      expect(client.preferenceApplyCalls, 1);
      expect(expanded.saveCount, 1);
      expect(adapter.locatorJson, locatorBeforeReflow);
      expect(adapter.normalizedProgression, progressionBeforeReflow);
      adapter.dispose();
    },
  );

  test('restore supersedes pending preview state publication', () async {
    final client = _FakeClient()..delayedPreferenceResults = [];
    final adapter = ReadiumEpubReaderController(
      book: _book(),
      progressRepository: _ProgressRepository(),
      settingsRepository: _SettingsRepository(),
      controllerBuilder: (value) =>
          ReadiumEpubController(configuration: value, client: client),
    );
    await adapter.initialize();
    final native = adapter.nativeController!;
    await native.start();
    client.emit(
      _event(
        instanceId: native.instanceId,
        sequence: 1,
        type: 'readerLifecycleChanged',
        payload: <String, Object?>{'phase': 'ready'},
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final initial = adapter.state;
    final changed = initial.copyWith(
      typography: const ReaderTypographySettings(fontSize: 1.4),
    );
    final preview = adapter.previewSettings(changed);
    await Future<void>.delayed(Duration.zero);
    expect(client.preferenceApplyCalls, 1);

    final restore = adapter.restoreSettings(initial);
    await Future<void>.delayed(Duration.zero);
    expect(client.preferenceApplyCalls, 2);

    client.delayedPreferenceResults![0].complete(
      const ReadiumPreferenceResult('cancelled'),
    );
    await Future<void>.delayed(Duration.zero);
    client.delayedPreferenceResults![1].complete(
      const ReadiumPreferenceResult('applied'),
    );
    await Future.wait([preview, restore]);
    expect(adapter.state, initial);
    adapter.dispose();
  });

  test(
    'committed Scroll and Paginated changes request a replacement after preview',
    () async {
      for (final (before, after) in <(ReaderReadingMode, ReaderReadingMode)>[
        (ReaderReadingMode.continuous, ReaderReadingMode.paginated),
        (ReaderReadingMode.paginated, ReaderReadingMode.continuous),
      ]) {
        final expanded = FakeReaderSettingsRepository(
          initial: {
            ReaderSettingsProfile.readiumReflowable: ReaderSettingsState
                .readiumDefaults
                .copyWith(
                  textLayout: ReaderTextLayoutSettings(readingMode: before),
                ),
          },
        );
        final client = _FakeClient();
        final replacements = <String?>[];
        final adapter = ReadiumEpubReaderController(
          book: _book(),
          progressRepository: _ProgressRepository(),
          settingsRepository: _SettingsRepository(),
          readerSettingsRepository: expanded,
          controllerBuilder: (configuration) => ReadiumEpubController(
            configuration: configuration,
            client: client,
          ),
          onReadingModeCommitted: (locator) async => replacements.add(locator),
        );
        await adapter.initialize();
        final native = adapter.nativeController!;
        await native.start();
        client.emit(
          _event(
            instanceId: native.instanceId,
            sequence: 1,
            type: 'readerLifecycleChanged',
            payload: <String, Object?>{'phase': 'ready'},
          ),
        );
        await Future<void>.delayed(Duration.zero);
        final changed = adapter.state.copyWith(
          textLayout: adapter.state.textLayout!.copyWith(readingMode: after),
        );

        await adapter.previewSettings(changed);
        expect(adapter.nativeController, same(native));
        expect(replacements, isEmpty);
        await adapter.commitSettings(changed);

        expect(replacements, <String?>[null]);
        expect(
          expanded
              .values[ReaderSettingsProfile.readiumReflowable]!
              .textLayout!
              .readingMode,
          after,
        );
        expect(client.preferenceApplyCalls, 1);
        await adapter.disposeAndWait();
      }
    },
  );

  test('non-backend commit does not request a session replacement', () async {
    final replacements = <String?>[];
    final expanded = FakeReaderSettingsRepository();
    final client = _FakeClient();
    final adapter = ReadiumEpubReaderController(
      book: _book(),
      progressRepository: _ProgressRepository(),
      settingsRepository: _SettingsRepository(),
      readerSettingsRepository: expanded,
      controllerBuilder: (configuration) =>
          ReadiumEpubController(configuration: configuration, client: client),
      onReadingModeCommitted: (locator) async => replacements.add(locator),
    );
    await adapter.initialize();
    final native = adapter.nativeController!;
    await native.start();
    client.emit(
      _event(
        instanceId: native.instanceId,
        sequence: 1,
        type: 'readerLifecycleChanged',
        payload: <String, Object?>{'phase': 'ready'},
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final changed = adapter.state.copyWith(
      typography: adapter.state.typography!.copyWith(fontSize: 1.4),
    );

    await adapter.previewSettings(changed);
    await adapter.commitSettings(changed);

    expect(adapter.nativeController, same(native));
    expect(replacements, isEmpty);
    expect(expanded.saveCount, 1);
    await adapter.disposeAndWait();
  });

  test(
    'stale viewport errors cannot change a disposed session authority',
    () async {
      final client = _FakeClient();
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        progressRepository: _ProgressRepository(),
        settingsRepository: _SettingsRepository(),
        controllerBuilder: (configuration) =>
            ReadiumEpubController(configuration: configuration, client: client),
      );
      await adapter.initialize();
      final oldControllerId = adapter.controllerInstanceId;
      await adapter.disposeAndWait();

      adapter.handleViewportError(
        const ReadiumBridgeError(code: 'stale_session_error'),
        controllerId: oldControllerId,
      );

      expect(adapter.error, isNull);
    },
  );

  test(
    'generated FB2 hides Publisher Styles and enables user text overrides',
    () {
      final adapter = ReadiumEpubReaderController(
        book: _book(format: BookFormat.fb2, filePath: r'C:\books\book.fb2'),
        localFilePath: r'C:\cache\book.epub',
        progressRepository: _ProgressRepository(),
        settingsRepository: _SettingsRepository(),
      );
      expect(
        adapter.settingsCapabilities.sourceSpecific.publisherStyles,
        isFalse,
      );
      expect(adapter.state.sourceSpecific!.publisherStyles, isFalse);
      adapter.dispose();
    },
  );

  test(
    'route reopen merges Drift-owned and JSON-owned Readium fields',
    () async {
      final legacy = _SettingsRepository()
        ..value = const EpubReaderSettings(
          theme: EpubReaderTheme.dark,
          fontSize: 1.7,
          lineHeight: 2.1,
          pageMargins: 2.5,
          publisherStyles: false,
        );
      final expanded = FakeReaderSettingsRepository(
        initial: {
          ReaderSettingsProfile.readiumReflowable: ReaderSettingsState
              .readiumDefaults
              .copyWith(
                appearance: const ReaderAppearanceSettings(
                  theme: ReaderTheme.sepia,
                ),
                typography: const ReaderTypographySettings(
                  fontFamily: ReaderFontFamily.monospace,
                  fontSize: .6,
                  fontWeight: 1.6,
                ),
                spacing: const ReaderSpacingSettings(
                  lineHeight: 1.1,
                  textMargins: .5,
                ),
                textLayout: const ReaderTextLayoutSettings(
                  alignment: ReaderTextAlignment.justify,
                  readingMode: ReaderReadingMode.continuous,
                  columns: ReaderColumnCount.two,
                ),
                sourceSpecific: const ReaderSourceSpecificSettings(
                  publisherStyles: true,
                ),
              ),
        },
      );
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        progressRepository: _ProgressRepository(),
        settingsRepository: legacy,
        readerSettingsRepository: expanded,
      );

      await adapter.initialize();

      expect(adapter.state.appearance!.theme, ReaderTheme.dark);
      expect(adapter.state.typography!.fontSize, 1.7);
      expect(adapter.state.spacing!.lineHeight, 2.1);
      expect(adapter.state.spacing!.textMargins, 2.5);
      expect(adapter.state.sourceSpecific!.publisherStyles, isFalse);
      expect(adapter.state.typography!.fontFamily, ReaderFontFamily.monospace);
      expect(adapter.state.typography!.fontWeight, 1.6);
      expect(adapter.state.textLayout!.alignment, ReaderTextAlignment.justify);
      expect(
        adapter.state.textLayout!.readingMode,
        ReaderReadingMode.continuous,
      );
      expect(adapter.state.textLayout!.columns, ReaderColumnCount.two);
      adapter.dispose();
    },
  );

  test(
    'generated settings do not overwrite the EPUB publisher preference',
    () async {
      final client = _FakeClient();
      final legacy = _SettingsRepository()
        ..value = const EpubReaderSettings(publisherStyles: true);
      final expanded = FakeReaderSettingsRepository(
        initial: {
          ReaderSettingsProfile.readiumReflowable: ReaderSettingsState
              .readiumDefaults
              .copyWith(
                sourceSpecific: const ReaderSourceSpecificSettings(
                  publisherStyles: true,
                ),
              ),
        },
      );
      final adapter = ReadiumEpubReaderController(
        book: _book(format: BookFormat.txt, filePath: r'C:\books\book.txt'),
        localFilePath: r'C:\cache\book.epub',
        progressRepository: _ProgressRepository(),
        settingsRepository: legacy,
        readerSettingsRepository: expanded,
        controllerBuilder: (value) =>
            ReadiumEpubController(configuration: value, client: client),
      );
      await adapter.initialize();
      final native = adapter.nativeController!;
      await native.start();
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 1,
          type: 'readerLifecycleChanged',
          payload: <String, Object?>{'phase': 'ready'},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final changed = adapter.state.copyWith(
        typography: adapter.state.typography!.copyWith(fontSize: 1.4),
        spacing: adapter.state.spacing!.copyWith(lineHeight: 1.9),
        textLayout: adapter.state.textLayout!.copyWith(
          alignment: ReaderTextAlignment.justify,
        ),
      );

      await adapter.commitSettings(changed);
      expect(client.lastPreferences?.publisherStyles, isFalse);
      expect(client.lastPreferences?.lineHeight, 1.9);
      expect(client.lastPreferences?.textAlignment, 'justify');
      expect(legacy.value.publisherStyles, isTrue);
      expect(
        expanded
            .values[ReaderSettingsProfile.readiumReflowable]!
            .sourceSpecific!
            .publisherStyles,
        isTrue,
      );
      adapter.dispose();
    },
  );

  test('native preference failure is never persisted', () async {
    final client = _FakeClient()..preferenceResult = 'failed';
    final expanded = FakeReaderSettingsRepository();
    final adapter = ReadiumEpubReaderController(
      book: _book(),
      progressRepository: _ProgressRepository(),
      settingsRepository: _SettingsRepository(),
      readerSettingsRepository: expanded,
      controllerBuilder: (value) =>
          ReadiumEpubController(configuration: value, client: client),
    );
    await adapter.initialize();
    final native = adapter.nativeController!;
    await native.start();
    client.emit(
      _event(
        instanceId: native.instanceId,
        sequence: 1,
        type: 'readerLifecycleChanged',
        payload: <String, Object?>{'phase': 'ready'},
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final changed = adapter.state.copyWith(
      typography: adapter.state.typography!.copyWith(fontSize: 1.8),
    );

    await expectLater(adapter.commitSettings(changed), throwsStateError);
    expect(expanded.saveCount, 0);
    expect(adapter.state.typography!.fontSize, 1);
    final failedApplyCount = client.preferenceApplyCalls;
    client.preferenceResult = 'applied';
    await adapter.restoreSettings(adapter.state);
    expect(client.preferenceApplyCalls, failedApplyCount + 1);
    expect(client.lastPreferences?.fontSize, 1);
    adapter.dispose();
  });

  test(
    'persistence failure rolls preview back to committed Readium state',
    () async {
      final client = _FakeClient();
      final legacy = _SettingsRepository();
      final adapter = ReadiumEpubReaderController(
        book: _book(),
        progressRepository: _ProgressRepository(),
        settingsRepository: legacy,
        readerSettingsRepository: _FailingReaderSettingsRepository(),
        controllerBuilder: (value) =>
            ReadiumEpubController(configuration: value, client: client),
      );
      await adapter.initialize();
      final native = adapter.nativeController!;
      await native.start();
      client.emit(
        _event(
          instanceId: native.instanceId,
          sequence: 1,
          type: 'readerLifecycleChanged',
          payload: <String, Object?>{'phase': 'ready'},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final changed = adapter.state.copyWith(
        typography: adapter.state.typography!.copyWith(fontSize: 1.8),
      );

      await adapter.previewSettings(changed);
      await expectLater(adapter.commitSettings(changed), throwsStateError);

      expect(adapter.state.typography!.fontSize, 1);
      expect(client.lastPreferences?.fontSize, 1);
      expect(legacy.value, EpubReaderSettings.defaults);
      adapter.dispose();
    },
  );

  test('migrates a legacy FB2 block position to a Readium locator', () async {
    final progress = _ProgressRepository()
      ..value = ReadingProgress(
        bookId: 'book',
        locatorJson: '{"type":"reflowable","block":12}',
        progression: .2,
        currentChapterTitle: null,
        currentPage: 13,
        totalPages: 60,
        updatedAt: DateTime(2026),
      );
    ReadiumEpubOpenConfiguration? configuration;
    final adapter = ReadiumEpubReaderController(
      book: _book(format: BookFormat.fb2, filePath: r'C:\books\book.fb2'),
      localFilePath: r'C:\cache\converted.epub',
      progressRepository: progress,
      settingsRepository: _SettingsRepository(),
      controllerBuilder: (value) {
        configuration = value;
        return ReadiumEpubController(
          configuration: value,
          client: _FakeClient(),
        );
      },
    );

    await adapter.initialize();
    expect(
      configuration?.initialLocatorJson,
      '{"href":"text/content.xhtml","type":"application/xhtml+xml",'
      '"locations":{"cssSelector":"#block-12"}}',
    );
    adapter.dispose();
  });

  test('format resolver routes every reflowable book through Readium', () {
    expect(
      readerPresentationFor(BookFormat.epub),
      ReaderPresentation.readiumFlutter,
    );
    expect(
      readerPresentationFor(BookFormat.pdf),
      ReaderPresentation.flutterPdf,
    );
    expect(
      readerPresentationFor(BookFormat.fb2),
      ReaderPresentation.readiumReflowable,
    );
    expect(
      readerPresentationFor(BookFormat.txt),
      ReaderPresentation.readiumReflowable,
    );
    expect(
      readerPresentationFor(BookFormat.cbz),
      ReaderPresentation.flutterComic,
    );
    expect(
      readerPresentationFor(BookFormat.cbr),
      ReaderPresentation.flutterComic,
    );
  });
}

ReadiumReaderEvent _event({
  required String instanceId,
  required int sequence,
  required String type,
  required Map<String, Object?> payload,
}) => ReadiumReaderEvent.parse(<String, Object?>{
  'protocolVersion': 1,
  'instanceId': instanceId,
  'sequence': sequence,
  'type': type,
  'payload': payload,
});

ReadiumReaderEvent _positionEvent({
  required String instanceId,
  required int sequence,
  required double progression,
  Map<String, Object?>? owner,
}) => _event(
  instanceId: instanceId,
  sequence: sequence,
  type: 'positionChanged',
  payload: <String, Object?>{
    'href': 'chapter.xhtml',
    'locatorJson':
        '{"href":"chapter.xhtml","locations":{"progression":$progression}}',
    'progression': progression,
    'progressOwner': owner,
  },
);

LibraryBook _book({
  BookFormat format = BookFormat.epub,
  String filePath = r'C:\books\book.epub',
}) => LibraryBook(
  id: 'book',
  title: 'Book',
  sortTitle: null,
  author: null,
  description: null,
  filePath: filePath,
  fileName: 'book.${format.normalizedExtension}',
  fileExtension: format.normalizedExtension,
  format: format,
  mediaType: null,
  coverPath: null,
  language: null,
  publisher: null,
  publishedDate: null,
  isbn: null,
  pageCount: null,
  fileSizeBytes: 1,
  dateAdded: DateTime(2026),
  lastOpenedAt: null,
  isFavorite: false,
);

class _ProgressRepository implements ReadingProgressRepository {
  bool failSave = false;
  ReadingProgress? value;
  final saved = <ReadingProgress>[];
  @override
  Future<ReadingProgress?> getForBook(String bookId) async => value;
  @override
  Future<void> save(ReadingProgress progress) async {
    if (failSave) throw StateError('Storage unavailable');
    saved.add(progress);
  }

  @override
  Future<void> deleteForBook(String bookId) async {}
  @override
  Stream<List<ReadingProgress>> watchAll() => Stream.value(const []);
  @override
  Stream<ReadingProgress?> watchForBook(String bookId) => Stream.value(value);
}

class _SettingsRepository implements EpubReaderSettingsRepository {
  EpubReaderSettings value = EpubReaderSettings.defaults;
  @override
  Future<EpubReaderSettings> load() async => value;
  @override
  Future<void> save(EpubReaderSettings settings) async => value = settings;
  @override
  Future<void> reset() async => value = EpubReaderSettings.defaults;
}

class _FailingReaderSettingsRepository extends FakeReaderSettingsRepository {
  @override
  Future<void> save(ReaderSettingsState settings) async {
    saveCount++;
    throw StateError('injected_settings_write_failure');
  }
}

class _FakeClient
    implements
        ReadiumBridgeClient,
        ReadiumProgressScrubClient,
        ReadiumProgressLocatorClient,
        ReadiumReflowDiagnosticClient,
        ReadiumReflowGestureClient {
  Completer<void>? baselineCapture;
  final gestureActions = <String>[];

  @override
  Future<void> settingsReflowGesture(
    int gestureId,
    String slider,
    String action,
    double value,
  ) async {
    gestureActions.add(action);
    if (action == 'begin') await baselineCapture?.future;
  }

  final _events = StreamController<ReadiumReaderEvent>.broadcast();
  int goToLocatorCalls = 0;
  int disposeCalls = 0;
  int preferenceApplyCalls = 0;
  ReadiumEpubPreferences? lastPreferences;
  final diagnosticContexts = <ReadiumReflowDiagnosticContext>[];
  String preferenceResult = 'applied';
  String ownedNavigationStatus = 'completed';
  List<Completer<ReadiumNavigationResult>>? delayedOwnedNavigations;
  bool ownedPublicationFailed = false;
  final progressScrubOwners = <ReadiumProgressNavigationOwner>[];
  final invalidatedScrubSessions = <int>[];
  List<Completer<ReadiumPreferenceResult>>? delayedPreferenceResults;
  final searchResultIds = <String>[];
  @override
  Stream<ReadiumReaderEvent> get events => _events.stream;
  @override
  Future<void> attachToPlatform() async {}
  @override
  Future<void> dispose() async {
    disposeCalls++;
    await _events.close();
  }

  void emit(ReadiumReaderEvent event) => _events.add(event);
  @override
  Future<ReadiumPreferenceResult> applyPreferencesWithDiagnostics(
    ReadiumEpubPreferences preferences,
    ReadiumReflowDiagnosticContext context,
  ) async {
    preferenceApplyCalls++;
    lastPreferences = preferences;
    diagnosticContexts.add(context);
    return ReadiumPreferenceResult(preferenceResult);
  }

  final openedScrubSessions = <int>[];
  final originRequests =
      <
        ({
          String locatorJson,
          double progression,
          int? readingOrderIndex,
          ReadiumProgressNavigationOwner owner,
        })
      >[];
  @override
  Future<ReadiumNavigationResult> goToProgressLocatorOwned({
    required double progression,
    required String locatorJson,
    int? readingOrderIndex,
    required ReadiumProgressNavigationOwner progressOwner,
  }) {
    originRequests.add((
      locatorJson: locatorJson,
      progression: progression,
      readingOrderIndex: readingOrderIndex,
      owner: progressOwner,
    ));
    return goToProgressionOwned(progression, progressOwner: progressOwner);
  }

  @override
  Future<void> openProgressScrubSession(int sessionId) async {
    openedScrubSessions.add(sessionId);
  }

  @override
  Future<void> invalidateProgressScrubSession(int sessionId) async =>
      invalidatedScrubSessions.add(sessionId);
  @override
  Future<void> reserveProgressScrubFinal(
    ReadiumProgressNavigationOwner progressOwner,
  ) async => progressScrubOwners.add(progressOwner);
  @override
  Future<ReadiumNavigationResult> goToProgressionOwned(
    double progression, {
    bool animated = false,
    required ReadiumProgressNavigationOwner progressOwner,
  }) async {
    progressScrubOwners.add(progressOwner);
    final delayed = delayedOwnedNavigations;
    if (delayed != null) {
      final completion = Completer<ReadiumNavigationResult>();
      delayed.add(completion);
      return completion.future;
    }
    return ReadiumNavigationResult(
      ownedNavigationStatus,
      details: ownedPublicationFailed
          ? {'positionPublication': 'failed'}
          : null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #goToLocatorJson) goToLocatorCalls++;
    if (invocation.memberName == #goToSearchResult) {
      final arguments = invocation.positionalArguments;
      if (arguments.isNotEmpty) searchResultIds.add(arguments.first as String);
      return Future.value(const ReadiumSearchCommandResult('completed'));
    }
    if (invocation.memberName == #applyPreferences) {
      preferenceApplyCalls++;
      lastPreferences =
          invocation.positionalArguments.first as ReadiumEpubPreferences;
      final delayed = delayedPreferenceResults;
      if (delayed != null) {
        final completer = Completer<ReadiumPreferenceResult>();
        delayed.add(completer);
        return completer.future;
      }
      return Future.value(ReadiumPreferenceResult(preferenceResult));
    }
    if (invocation.memberName == #search ||
        invocation.memberName == #cancelSearch ||
        invocation.memberName == #clearSearch) {
      return Future.value(const ReadiumSearchCommandResult('started'));
    }
    return Future.value(const ReadiumNavigationResult('completed'));
  }
}

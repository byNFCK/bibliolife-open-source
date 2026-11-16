import 'dart:async';

import 'package:bibliolife/features/reader/application/services/readium_epub_annotation_coordinator.dart';
import 'package:bibliolife/features/reader/domain/models/reader_annotation.dart';
import 'package:bibliolife/features/reader/domain/repositories/reader_annotation_repository.dart';
import 'package:bibliolife_readium/bibliolife_readium.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'persists one native selection request and acknowledges it once',
    () async {
      final client = _FakeClient();
      final controller = ReadiumEpubController(
        configuration: const ReadiumEpubOpenConfiguration(
          instanceId: 'reader-1',
          bookId: 'book-a',
          localFilePath: 'book.epub',
        ),
        client: client,
      );
      await controller.start();
      final repository = _FakeRepository();
      final coordinator = ReadiumEpubAnnotationCoordinator(
        bookId: 'book-a',
        controller: controller,
        repository: repository,
      );
      unawaited(coordinator.start());
      await Future<void>.value();
      client.emit(_readySnapshotEvent());

      final event = ReadiumSelectionActionRequestedEvent(
        metadata: const ReadiumEventMetadata(
          1,
          'reader-1',
          2,
          'selectionActionRequested',
        ),
        request: const ReadiumSelectionActionRequest(
          requestId: 4,
          instanceId: 'reader-1',
          selectionSessionId: 9,
          action: ReadiumSelectionAction.highlight,
          locatorJson:
              '{"href":"chapter.xhtml","locations":{"fragments":["t"]}}',
          selectedText: 'selected',
        ),
      );
      client.emit(event);
      client.emit(event);
      for (
        var index = 0;
        index < 20 &&
            (repository.upsertCalls == 0 ||
                client.setDecorationCalls == 0 ||
                client.clearSelectionCalls == 0 ||
                client.resolutions.isEmpty);
        index++
      ) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(repository.upsertCalls, 1);
      expect(client.setDecorationCalls, 1);
      expect(client.clearSelectionCalls, 1);
      expect(client.resolutions, hasLength(1));
      expect(
        client.resolutions.single.outcome,
        ReadiumSelectionActionOutcome.committed,
      );
      await coordinator.dispose();
      await controller.dispose();
    },
  );

  test(
    'selection highlight creation never presents the existing editor',
    () async {
      final harness = await _Harness.start();
      await harness.emitHighlight(color: 'yellow');

      expect(harness.repository.upsertCalls, 1);
      expect(harness.client.resolutions, hasLength(1));

      await harness.dispose();
    },
  );

  for (final color in const ['green', 'blue', 'pink']) {
    test(
      '$color highlight creation never presents the existing editor',
      () async {
        final harness = await _Harness.start();
        await harness.emitHighlight(color: color);

        expect(harness.repository.upsertCalls, 1);
        await harness.dispose();
      },
    );
  }

  test(
    'decoration application and acknowledgement never present the editor',
    () async {
      final harness = await _Harness.start();
      await harness.emitHighlight(color: 'yellow');
      harness.client.emit(
        ReadiumDecorationEvent(
          metadata: const ReadiumEventMetadata(
            1,
            'reader-1',
            3,
            'decorationStateChanged',
          ),
          decoration: const ReadiumDecorationGroupState(
            group: ReadiumDecorationGroup.persistentHighlights,
            requestedCount: 1,
            appliedCount: 1,
            generation: 1,
            isApplying: false,
            isReady: true,
            selectionProtected: false,
            hasApplied: true,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(harness.client.resolutions.single.annotationId, isNotNull);
      await harness.dispose();
    },
  );

  test('direct persistent activation is not a Flutter editor route', () async {
    final existing = _annotation('existing');
    final harness = await _Harness.start(existing: existing);
    await Future<void>.delayed(Duration.zero);
    harness.client.emit(
      ReadiumDecorationActivatedReaderEvent(
        metadata: const ReadiumEventMetadata(
          1,
          'reader-1',
          3,
          'decorationActivated',
        ),
        activation: const ReadiumDecorationActivatedEvent(
          interactionId: 1,
          instanceId: 'reader-1',
          group: 'PERSISTENT_HIGHLIGHTS',
          decorationId: 'annotation:existing',
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(harness.repository.deleteCalls, 0);
    expect(harness.repository.recolorCalls, 0);
    await harness.dispose();
  });

  test(
    'search decoration activation never presents the annotation editor',
    () async {
      final existing = _annotation('existing');
      final harness = await _Harness.start(existing: existing);
      harness.client.emit(
        ReadiumDecorationActivatedReaderEvent(
          metadata: const ReadiumEventMetadata(
            1,
            'reader-1',
            4,
            'decorationActivated',
          ),
          activation: const ReadiumDecorationActivatedEvent(
            interactionId: 2,
            instanceId: 'reader-1',
            group: 'SEARCH_RESULT',
            decorationId: 'annotation:existing',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(harness.repository.deleteCalls, 0);
      await harness.dispose();
    },
  );

  test(
    'native existing delete request deletes once and acknowledges',
    () async {
      final harness = await _Harness.start(existing: _annotation('existing'));
      harness.emitAnnotationAction(
        action: ReadiumAnnotationAction.delete,
        annotationId: 'existing',
      );
      await _eventually(() => harness.client.annotationResolutions.isNotEmpty);

      expect(harness.repository.deleteCalls, 1);
      expect(harness.repository.recolorCalls, 0);
      expect(
        harness.client.annotationResolutions.single.outcome,
        ReadiumSelectionActionOutcome.committed,
      );
      await harness.dispose();
    },
  );

  test(
    'native existing recolor updates same id once and acknowledges',
    () async {
      final harness = await _Harness.start(existing: _annotation('existing'));
      harness.emitAnnotationAction(
        action: ReadiumAnnotationAction.recolor,
        annotationId: 'existing',
        color: 'blue',
      );
      await _eventually(() => harness.client.annotationResolutions.isNotEmpty);

      expect(harness.repository.recolorCalls, 1);
      expect(harness.repository.lastUpdatedId, 'existing');
      expect(harness.repository.lastColor, ReaderAnnotationColor.blue);
      expect(harness.repository.deleteCalls, 0);
      expect(
        harness.client.annotationResolutions.single.outcome,
        ReadiumSelectionActionOutcome.committed,
      );
      await harness.dispose();
    },
  );
}

class _Harness {
  _Harness._(this.client, this.controller, this.repository, this.coordinator);

  final _FakeClient client;
  final ReadiumEpubController controller;
  final _FakeRepository repository;
  final ReadiumEpubAnnotationCoordinator coordinator;

  static Future<_Harness> start({ReaderAnnotation? existing}) async {
    final client = _FakeClient();
    final controller = ReadiumEpubController(
      configuration: const ReadiumEpubOpenConfiguration(
        instanceId: 'reader-1',
        bookId: 'book-a',
        localFilePath: 'book.epub',
      ),
      client: client,
    );
    await controller.start();
    final repository = _FakeRepository(existing: existing);
    final coordinator = ReadiumEpubAnnotationCoordinator(
      bookId: 'book-a',
      controller: controller,
      repository: repository,
    );
    final harness = _Harness._(client, controller, repository, coordinator);
    unawaited(coordinator.start());
    await Future<void>.value();
    client.emit(_readySnapshotEvent());
    return harness;
  }

  void emitAnnotationAction({
    required ReadiumAnnotationAction action,
    required String annotationId,
    String? color,
  }) {
    client.emit(
      ReadiumAnnotationActionRequestedEvent(
        metadata: const ReadiumEventMetadata(
          1,
          'reader-1',
          5,
          'annotationActionRequested',
        ),
        request: ReadiumAnnotationActionRequest(
          requestId: 7,
          instanceId: 'reader-1',
          annotationId: annotationId,
          action: action,
          color: color,
        ),
      ),
    );
  }

  Future<void> emitHighlight({required String color}) async {
    client.emit(
      ReadiumSelectionActionRequestedEvent(
        metadata: const ReadiumEventMetadata(
          1,
          'reader-1',
          2,
          'selectionActionRequested',
        ),
        request: ReadiumSelectionActionRequest(
          requestId: 4,
          instanceId: 'reader-1',
          selectionSessionId: 9,
          action: ReadiumSelectionAction.highlight,
          locatorJson:
              '{"href":"chapter.xhtml","locations":{"fragments":["t"]}}',
          selectedText: 'selected',
          color: color,
        ),
      ),
    );
    await _eventually(() => repository.upsertCalls == 1);
  }

  Future<void> dispose() async {
    await coordinator.dispose();
    await controller.dispose();
  }
}

Future<void> _eventually(bool Function() condition) async {
  for (var index = 0; index < 20 && !condition(); index++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

class _FakeClient
    implements
        ReadiumBridgeClient,
        ReadiumSelectionActionResolver,
        ReadiumAnnotationActionResolver {
  final _events = StreamController<ReadiumReaderEvent>.broadcast(sync: true);
  final resolutions = <ReadiumSelectionActionResolution>[];
  final annotationResolutions = <ReadiumAnnotationActionResolution>[];
  int setDecorationCalls = 0;
  int clearSelectionCalls = 0;

  @override
  Stream<ReadiumReaderEvent> get events => _events.stream;
  @override
  Future<void> attachToPlatform() async {}
  @override
  Future<ReadiumSelectionActionResolution> resolveSelectionAction(
    ReadiumSelectionActionResolution resolution,
  ) async {
    resolutions.add(resolution);
    return resolution;
  }

  @override
  Future<ReadiumAnnotationActionResolution> resolveAnnotationAction(
    ReadiumAnnotationActionResolution resolution,
  ) async {
    annotationResolutions.add(resolution);
    return resolution;
  }

  void emit(ReadiumReaderEvent event) => _events.add(event);
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #dispose) return _events.close();
    if (invocation.memberName == #clearSelection) {
      clearSelectionCalls++;
      return Future.value(const ReadiumSelectionResult('cleared'));
    }
    if (invocation.memberName == #setDecorations) {
      setDecorationCalls++;
      return Future.value(const ReadiumDecorationResult('applied'));
    }
    return Future.value(const ReadiumNavigationResult('completed'));
  }
}

class _FakeRepository implements ReaderAnnotationRepository {
  _FakeRepository({this.existing}) : _rows = [?existing] {
    _changes = StreamController<List<ReaderAnnotation>>.broadcast(
      sync: true,
      onListen: () => _changes.add(List.unmodifiable(_rows)),
    );
  }

  late final StreamController<List<ReaderAnnotation>> _changes;
  final List<ReaderAnnotation> _rows;
  final ReaderAnnotation? existing;
  int upsertCalls = 0;
  int deleteCalls = 0;
  int recolorCalls = 0;
  String? lastUpdatedId;
  ReaderAnnotationColor? lastColor;

  @override
  Stream<List<ReaderAnnotation>> watchForBook(String bookId) => _changes.stream;
  @override
  Future<ReaderAnnotation> upsert(ReaderAnnotation annotation) async {
    upsertCalls++;
    _rows.removeWhere((value) => value.id == annotation.id);
    _rows.add(annotation);
    _changes.add(List.unmodifiable(_rows));
    return annotation;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #listForBook) {
      return Future.value(List<ReaderAnnotation>.unmodifiable(_rows));
    }
    if (invocation.memberName == #getById) {
      final id = invocation.positionalArguments.single as String;
      return Future.value(_rows.where((row) => row.id == id).firstOrNull);
    }
    if (invocation.memberName == #deleteById) {
      deleteCalls++;
      final id = invocation.positionalArguments.single as String;
      final oldLength = _rows.length;
      _rows.removeWhere((row) => row.id == id);
      _changes.add(List.unmodifiable(_rows));
      return Future.value(oldLength != _rows.length);
    }
    if (invocation.memberName == #updateStyleAndColor) {
      recolorCalls++;
      lastUpdatedId = invocation.namedArguments[#id] as String;
      lastColor = invocation.namedArguments[#color] as ReaderAnnotationColor;
      final index = _rows.indexWhere((row) => row.id == lastUpdatedId);
      final current = _rows[index];
      final updated = ReaderAnnotation(
        id: current.id,
        bookId: current.bookId,
        locatorJson: current.locatorJson,
        locationKey: current.locationKey,
        selectedText: current.selectedText,
        textBefore: current.textBefore,
        textAfter: current.textAfter,
        note: current.note,
        style:
            invocation.namedArguments[#style] as ReaderAnnotationStyle? ??
            current.style,
        color: lastColor ?? current.color,
        href: current.href,
        progression: current.progression,
        totalProgression: current.totalProgression,
        createdAt: current.createdAt,
        updatedAt: invocation.namedArguments[#updatedAt] as DateTime,
      );
      _rows[index] = updated;
      _changes.add(List.unmodifiable(_rows));
      return Future<ReaderAnnotation>.value(updated);
    }
    return super.noSuchMethod(invocation);
  }
}

ReaderAnnotation _annotation(String id) => ReaderAnnotation(
  id: id,
  bookId: 'book-a',
  locatorJson: '{"href":"chapter.xhtml"}',
  locationKey: 'chapter.xhtml#existing',
  selectedText: 'selected',
  href: 'chapter.xhtml',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

ReadiumSnapshotEvent _readySnapshotEvent() => ReadiumSnapshotEvent(
  metadata: const ReadiumEventMetadata(1, 'reader-1', 1, 'snapshot'),
  snapshot: const ReadiumReaderSnapshot(
    lifecycle: ReadiumReaderLifecycle(phase: 'navigatorReady'),
    position: ReadiumPosition(href: 'chapter.xhtml', progression: 0.5),
    chapter: ReadiumChapter(title: 'Chapter'),
    preferences: ReadiumPreferencesState(
      applied: ReadiumEpubPreferences.defaults,
    ),
    toc: ReadiumTocState(status: ReadiumTocStatus.ready),
    search: ReadiumSearchState(status: ReadiumSearchStatus.idle),
    selection: ReadiumSelectionState(status: 'inactive'),
    decorations: <ReadiumDecorationGroup, ReadiumDecorationGroupState>{},
  ),
);

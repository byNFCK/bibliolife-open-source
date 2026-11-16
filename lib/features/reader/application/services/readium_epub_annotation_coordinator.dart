import 'dart:async';
import 'dart:convert';

import 'package:bibliolife/features/reader/application/services/reader_annotation_draft_factory.dart';
import 'package:bibliolife/features/reader/domain/models/reader_annotation.dart';
import 'package:bibliolife/features/reader/domain/repositories/reader_annotation_repository.dart';
import 'package:bibliolife_readium/bibliolife_readium.dart';
import 'package:flutter/foundation.dart';

/// Reader-owned view of the one annotation repository subscription.
class ReaderAnnotationMenuState {
  const ReaderAnnotationMenuState({
    this.annotations = const <ReaderAnnotation>[],
    this.isLoading = true,
    this.error,
  });

  final List<ReaderAnnotation> annotations;
  final bool isLoading;
  final Object? error;
}

abstract interface class ReaderAnnotationMenuController implements Listenable {
  ReaderAnnotationMenuState get annotationMenuState;
  Future<bool> openAnnotation(ReaderAnnotation annotation);
  Future<bool> deleteAnnotation(String id);
  Future<void> updateAnnotation({
    required String id,
    required String? note,
    required ReaderAnnotationStyle style,
    required ReaderAnnotationColor color,
  });
}

/// Flutter-owned annotation boundary for one PlatformView instance.
///
/// Native code only presents selection and decorations. This coordinator validates the
/// view/session identity, writes Drift, then restores one authoritative decoration snapshot
/// before acknowledging the native request.
final class ReadiumEpubAnnotationCoordinator
    implements ReaderAnnotationMenuController {
  ReadiumEpubAnnotationCoordinator({
    required this.bookId,
    required this.controller,
    required this.repository,
    ReaderAnnotationDraftFactory? draftFactory,
  }) : _draftFactory = draftFactory ?? ReaderAnnotationDraftFactory();

  final String bookId;
  final ReadiumEpubController controller;
  final ReaderAnnotationRepository repository;
  final ReaderAnnotationDraftFactory _draftFactory;

  StreamSubscription<ReadiumSelectionActionRequest>? _actionSubscription;
  StreamSubscription<ReadiumAnnotationActionRequest>?
  _annotationActionSubscription;
  StreamSubscription<List<ReaderAnnotation>>? _repositorySubscription;
  StreamSubscription<ReadiumEpubControllerState>? _controllerStateSubscription;
  final _handledRequests = <String>{};
  final _handledAnnotationActions = <String>{};
  final ValueNotifier<ReaderAnnotationMenuState> _menuNotifier = ValueNotifier(
    const ReaderAnnotationMenuState(),
  );
  Future<void> _serial = Future.value();
  String? _snapshotFingerprint;
  bool _disposed = false;
  bool _started = false;
  ReaderAnnotationMenuState _menuState = const ReaderAnnotationMenuState();

  @override
  ReaderAnnotationMenuState get annotationMenuState => _menuState;

  @override
  void addListener(VoidCallback listener) =>
      _menuNotifier.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _menuNotifier.removeListener(listener);

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _actionSubscription = controller.selectionActionRequests.listen(
      (request) => unawaited(_handleAction(request)),
    );
    _annotationActionSubscription = controller.annotationActionRequests.listen(
      (request) => unawaited(_handleAnnotationAction(request)),
    );
    _controllerStateSubscription = controller.stateChanges.listen((state) {
      if (state.isReady) unawaited(_syncCurrentSnapshot());
    });
    final first = Completer<void>();
    _repositorySubscription = repository
        .watchForBook(bookId)
        .listen(
          (annotations) => _replaceAnnotations(annotations, first),
          onError: (Object error, StackTrace stackTrace) {
            _setMenuState(
              ReaderAnnotationMenuState(
                annotations: _menuState.annotations,
                isLoading: false,
                error: error,
              ),
            );
            if (!first.isCompleted) first.completeError(error, stackTrace);
          },
        );
    await first.future;
  }

  Future<void> _handleAction(ReadiumSelectionActionRequest request) async {
    final key = '${controller.instanceId}:${request.requestId}';
    if (_disposed || !_rememberBounded(_handledRequests, key)) return;
    final validIdentity =
        request.instanceId == controller.instanceId &&
        controller.configuration.bookId == bookId &&
        request.locatorJson.trim().isNotEmpty &&
        request.selectedText.trim().isNotEmpty;
    if (!validIdentity) {
      await _ack(
        request,
        ReadiumSelectionActionOutcome.failed,
        errorCode: 'stale_selection',
      );
      return;
    }
    try {
      final color =
          ReaderAnnotationColor.tryParse(request.color ?? '') ??
          ReaderAnnotationColor.yellow;
      final selection = ReaderSelectionPlatformEvent(
        locatorJson: request.locatorJson,
        selectedText: request.selectedText,
        href: _hrefFromLocator(request.locatorJson),
      );
      final annotation = await repository.upsert(
        _draftFactory.create(
          bookId: bookId,
          selection: selection,
          style:
              ReaderAnnotationStyle.tryParse(request.style ?? '') ??
              ReaderAnnotationStyle.highlight,
          color: color,
        ),
      );
      await _syncCurrentSnapshot();
      if (_disposed) return;
      // Native clears/finishes the selection only after this acknowledgement.
      await controller.resolveSelectionAction(
        ReadiumSelectionActionResolution(
          requestId: request.requestId,
          selectionSessionId: request.selectionSessionId,
          outcome: ReadiumSelectionActionOutcome.committed,
          annotationId: annotation.id,
        ),
      );
      await controller.clearSelection();
    } catch (error) {
      if (_disposed) return;
      await _ack(
        request,
        ReadiumSelectionActionOutcome.failed,
        errorCode: _errorCode(error),
      );
    }
  }

  Future<void> _ack(
    ReadiumSelectionActionRequest request,
    ReadiumSelectionActionOutcome outcome, {
    String? errorCode,
  }) async {
    await controller.resolveSelectionAction(
      ReadiumSelectionActionResolution(
        requestId: request.requestId,
        selectionSessionId: request.selectionSessionId,
        outcome: outcome,
        errorCode: errorCode,
      ),
    );
  }

  Future<void> _handleAnnotationAction(
    ReadiumAnnotationActionRequest request,
  ) async {
    if (_disposed ||
        request.instanceId != controller.instanceId ||
        !_rememberBounded(
          _handledAnnotationActions,
          '${request.instanceId}:${request.requestId}',
        )) {
      return;
    }
    try {
      final annotation = await repository.getById(request.annotationId);
      if (_disposed || annotation?.bookId != bookId) {
        throw StateError('annotation_not_found');
      }
      switch (request.action) {
        case ReadiumAnnotationAction.delete:
          if (!await repository.deleteById(annotation!.id)) {
            throw StateError('annotation_not_found');
          }
        case ReadiumAnnotationAction.recolor:
          final color = ReaderAnnotationColor.tryParse(request.color ?? '');
          if (color == null) throw const FormatException('invalid_color');
          await repository.updateStyleAndColor(
            id: annotation!.id,
            style: annotation.style,
            color: color,
            updatedAt: DateTime.now(),
          );
      }
      await _syncCurrentSnapshot();
      if (_disposed) return;
      await controller.resolveAnnotationAction(
        ReadiumAnnotationActionResolution(
          requestId: request.requestId,
          outcome: ReadiumSelectionActionOutcome.committed,
        ),
      );
    } catch (error) {
      if (_disposed) return;
      await controller.resolveAnnotationAction(
        ReadiumAnnotationActionResolution(
          requestId: request.requestId,
          outcome: ReadiumSelectionActionOutcome.failed,
          errorCode: _errorCode(error),
        ),
      );
    }
  }

  void _replaceAnnotations(
    List<ReaderAnnotation> annotations,
    Completer<void> first,
  ) {
    _setMenuState(
      ReaderAnnotationMenuState(
        annotations: List<ReaderAnnotation>.unmodifiable(annotations),
        isLoading: false,
      ),
    );
    _serial = _serial.then((_) async {
      if (_disposed) return;
      try {
        await _applySnapshot(annotations);
        if (!first.isCompleted) first.complete();
      } catch (error, stackTrace) {
        if (!first.isCompleted) first.completeError(error, stackTrace);
      }
    });
  }

  Future<void> _syncCurrentSnapshot() async {
    final annotations = await repository.listForBook(bookId);
    await _applySnapshot(annotations);
  }

  @override
  Future<bool> openAnnotation(ReaderAnnotation annotation) async {
    if (_disposed ||
        annotation.bookId != bookId ||
        _validLocator(annotation.locatorJson) == null) {
      return false;
    }
    return (await controller.goToLocatorJson(annotation.locatorJson)).isSuccess;
  }

  @override
  Future<bool> deleteAnnotation(String id) async {
    if (_disposed || id.trim().isEmpty) return false;
    final deleted = await repository.deleteById(id);
    if (deleted) await _syncCurrentSnapshot();
    return deleted;
  }

  @override
  Future<void> updateAnnotation({
    required String id,
    required String? note,
    required ReaderAnnotationStyle style,
    required ReaderAnnotationColor color,
  }) async {
    if (_disposed) throw StateError('annotation_coordinator_disposed');
    final updatedAt = DateTime.now();
    await repository.updateNote(id: id, note: note, updatedAt: updatedAt);
    await repository.updateStyleAndColor(
      id: id,
      style: style,
      color: color,
      updatedAt: updatedAt,
    );
    await _syncCurrentSnapshot();
  }

  Future<void> _applySnapshot(List<ReaderAnnotation> annotations) async {
    final decorations = <ReadiumDecorationSpec>[];
    for (final annotation in annotations) {
      final locator = _validLocator(annotation.locatorJson);
      if (locator == null) continue;
      decorations.add(
        ReadiumDecorationSpec(
          id: 'annotation:${annotation.id}',
          locatorJson: annotation.locatorJson,
          style: ReadiumDecorationStyle(
            type: annotation.style == ReaderAnnotationStyle.underline
                ? ReadiumDecorationStyleType.underline
                : ReadiumDecorationStyleType.highlight,
            tint: _tint(annotation.color),
          ),
        ),
      );
    }
    decorations.sort((a, b) => a.id.compareTo(b.id));
    final fingerprint = decorations
        .map(
          (item) =>
              '${item.id}|${item.locatorJson}|${item.style.type.name}|${item.style.tint}',
        )
        .join('\n');
    if (fingerprint == _snapshotFingerprint || !controller.isReady) return;
    await controller.setDecorations(
      ReadiumDecorationGroup.persistentHighlights,
      decorations,
    );
    _snapshotFingerprint = fingerprint;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _actionSubscription?.cancel();
    await _annotationActionSubscription?.cancel();
    await _controllerStateSubscription?.cancel();
    await _repositorySubscription?.cancel();
    await _serial;
    _menuNotifier.dispose();
  }

  void _setMenuState(ReaderAnnotationMenuState value) {
    if (_disposed) return;
    _menuState = value;
    _menuNotifier.value = value;
  }
}

bool _rememberBounded(Set<String> values, String value) {
  if (!values.add(value)) return false;
  const limit = 128;
  while (values.length > limit) {
    values.remove(values.first);
  }
  return true;
}

Map<String, Object?>? _validLocator(String value) {
  try {
    final decoded = jsonDecode(value);
    return decoded is Map ? Map<String, Object?>.from(decoded) : null;
  } on FormatException {
    return null;
  }
}

String _hrefFromLocator(String value) {
  final decoded = _validLocator(value);
  final href = decoded?['href'];
  if (href is String && href.trim().isNotEmpty) return href;
  throw const FormatException('invalid_selection_locator');
}

int _tint(ReaderAnnotationColor color) => switch (color) {
  ReaderAnnotationColor.yellow => 0x66FDD835,
  ReaderAnnotationColor.green => 0x6643A047,
  ReaderAnnotationColor.blue => 0x6642A5F5,
  ReaderAnnotationColor.pink => 0x66EC407A,
  ReaderAnnotationColor.purple => 0x667E57C2,
};

String _errorCode(Object error) => error is FormatException
    ? 'invalid_annotation'
    : 'annotation_persistence_failed';

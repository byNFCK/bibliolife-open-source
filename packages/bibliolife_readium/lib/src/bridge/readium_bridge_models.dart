import 'package:flutter/foundation.dart';

import 'readium_bridge_constants.dart';
import '../readium_models.dart';

final class ReadiumBridgeError {
  const ReadiumBridgeError({
    required this.code,
    this.messageKey,
    this.details,
    this.fatal = false,
    this.retryable = false,
    this.operation,
  });

  final String code;
  final String? messageKey;
  final Object? details;
  final bool fatal;
  final bool retryable;
  final String? operation;

  Map<String, Object?>? get openFailure {
    final value = details;
    if (value is! Map || value['category'] != 'Reader.Open') return null;
    return ReadiumDiagnosticEvent._safeOpenFields(value);
  }

  factory ReadiumBridgeError.fromMap(Object? value) {
    final map = _asMap(value, 'error');
    return ReadiumBridgeError(
      code: _requiredString(map, ReadiumBridgeConstants.code),
      messageKey: _nullableString(map, ReadiumBridgeConstants.messageKey),
      details: _codecValue(map[ReadiumBridgeConstants.details]),
      fatal: _optionalBool(map, ReadiumBridgeConstants.fatal) ?? false,
      retryable: _optionalBool(map, ReadiumBridgeConstants.retryable) ?? false,
      operation: _nullableString(map, ReadiumBridgeConstants.operation),
    );
  }

  Map<String, Object?> toMap() => {
    'code': code,
    if (messageKey != null) 'messageKey': messageKey,
    if (details != null) 'details': details,
    'fatal': fatal,
    'retryable': retryable,
    if (operation != null) 'operation': operation,
  };

  @override
  bool operator ==(Object other) =>
      other is ReadiumBridgeError &&
      other.code == code &&
      other.messageKey == messageKey &&
      mapEquals(_asOptionalMap(details), _asOptionalMap(other.details)) &&
      other.fatal == fatal &&
      other.retryable == retryable &&
      other.operation == operation;

  @override
  int get hashCode => Object.hash(
    code,
    messageKey,
    details is Map ? Object.hashAll((details! as Map).entries) : details,
    fatal,
    retryable,
    operation,
  );
}

final class ReadiumBridgeException implements Exception {
  const ReadiumBridgeException(this.error);

  final ReadiumBridgeError error;

  String get code => error.code;

  @override
  String toString() => 'Readium bridge error: ${error.code}';
}

final class ReadiumBridgeFormatException extends ReadiumBridgeException {
  ReadiumBridgeFormatException(String message)
    : super(
        ReadiumBridgeError(
          code: 'malformed_native_payload',
          messageKey: message,
        ),
      );
}

final class ReadiumBridgeInfo {
  const ReadiumBridgeInfo({
    required this.protocolVersion,
    required this.instanceId,
    this.features = const <String>[],
  });

  final int protocolVersion;
  final String instanceId;
  final List<String> features;

  factory ReadiumBridgeInfo.fromMap(Object? value) {
    final map = _asMap(value, 'bridge info');
    final rawFeatures = map['features'];
    return ReadiumBridgeInfo(
      protocolVersion: _requiredInt(map, 'protocolVersion'),
      instanceId: _requiredNonBlankString(map, 'instanceId'),
      features: List.unmodifiable(
        rawFeatures is List
            ? rawFeatures.whereType<String>().toList(growable: false)
            : const <String>[],
      ),
    );
  }
}

final class ReadiumEpubOpenConfiguration {
  const ReadiumEpubOpenConfiguration({
    this.instanceId,
    required this.bookId,
    required this.localFilePath,
    this.initialLocatorJson,
    this.initialPreferences = ReadiumEpubPreferences.defaults,
    this.initialPreferencesAreAuthoritative = false,
    this.isNightMode = false,
    this.protocolVersion = ReadiumBridgeConstants.protocolVersion,
    this.openAttemptId,
    this.initialLocatorSource,
  });

  final String? instanceId;
  final String bookId;
  final String localFilePath;
  final String? initialLocatorJson;
  final ReadiumEpubPreferences initialPreferences;
  final bool initialPreferencesAreAuthoritative;
  final bool isNightMode;
  final int protocolVersion;
  final int? openAttemptId;
  final String? initialLocatorSource;

  ReadiumEpubOpenConfiguration withInstanceId(String value) =>
      ReadiumEpubOpenConfiguration(
        instanceId: value,
        bookId: bookId,
        localFilePath: localFilePath,
        initialLocatorJson: initialLocatorJson,
        initialPreferences: initialPreferences,
        initialPreferencesAreAuthoritative: initialPreferencesAreAuthoritative,
        isNightMode: isNightMode,
        protocolVersion: protocolVersion,
        openAttemptId: openAttemptId,
        initialLocatorSource: initialLocatorSource,
      );

  Map<String, Object?> toMap({String? resolvedInstanceId}) {
    final effectiveId = (resolvedInstanceId ?? instanceId)?.trim();
    if (effectiveId == null || effectiveId.isEmpty) {
      throw const FormatException('invalid_instance_id');
    }
    if (effectiveId.length > 512) {
      throw const FormatException('instance_id_too_long');
    }
    final normalizedBookId = bookId.trim();
    if (normalizedBookId.isEmpty) {
      throw const FormatException('missing_book_id');
    }
    final path = localFilePath.trim();
    if (path.isEmpty) {
      throw const FormatException('missing_file_path');
    }
    if (protocolVersion != ReadiumBridgeConstants.protocolVersion) {
      throw const FormatException('unsupported_protocol');
    }
    final locator = initialLocatorJson?.trim();
    if (locator != null && locator.isEmpty) {
      throw const FormatException('invalid_locator');
    }
    return <String, Object?>{
      'instanceId': effectiveId,
      'bookId': normalizedBookId,
      'localFilePath': path,
      'initialLocatorJson': locator,
      'initialPreferences': initialPreferences.toMap(),
      'initialPreferencesAreAuthoritative': initialPreferencesAreAuthoritative,
      'isNightMode': isNightMode,
      'bridgeProtocolVersion': protocolVersion,
      if (openAttemptId != null) 'openAttemptId': openAttemptId,
      if (initialLocatorSource != null)
        'initialLocatorSource': initialLocatorSource,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ReadiumEpubOpenConfiguration &&
      other.instanceId == instanceId &&
      other.bookId == bookId &&
      other.localFilePath == localFilePath &&
      other.initialLocatorJson == initialLocatorJson &&
      other.initialPreferences == initialPreferences &&
      other.initialPreferencesAreAuthoritative ==
          initialPreferencesAreAuthoritative &&
      other.isNightMode == isNightMode &&
      other.protocolVersion == protocolVersion &&
      other.openAttemptId == openAttemptId &&
      other.initialLocatorSource == initialLocatorSource;

  @override
  int get hashCode => Object.hash(
    instanceId,
    bookId,
    localFilePath,
    initialLocatorJson,
    initialPreferences,
    initialPreferencesAreAuthoritative,
    isNightMode,
    protocolVersion,
    openAttemptId,
    initialLocatorSource,
  );
}

enum ReadiumControllerLifecycle {
  notCreated,
  creating,
  initializing,
  ready,
  failed,
  disposed,
}

final class ReadiumReaderLifecycle {
  const ReadiumReaderLifecycle({
    required this.phase,
    this.bookId,
    this.title,
    this.reusedRestoredFragment,
    this.navigated,
    this.command,
    this.generation,
    this.progressOwner,
  });

  final String phase;
  final String? bookId;
  final String? title;
  final bool? reusedRestoredFragment;
  final bool? navigated;
  final String? command;
  final int? generation;
  final ReadiumProgressNavigationOwner? progressOwner;

  factory ReadiumReaderLifecycle.fromMap(Object? value) {
    final map = _asMap(value, 'lifecycle');
    final publication = map['publication'];
    final publicationMap = publication is Map
        ? publication
        : const <Object?, Object?>{};
    return ReadiumReaderLifecycle(
      phase: _requiredString(map, 'phase'),
      bookId: _nullableString(publicationMap, 'bookId'),
      title: _nullableString(publicationMap, 'title'),
      reusedRestoredFragment: _optionalBool(map, 'reusedRestoredFragment'),
      navigated: _optionalBool(map, 'navigated'),
      command: _nullableString(map, 'command'),
      generation: _optionalInt(map, 'generation'),
      progressOwner: _asOptionalMap(map['progressOwner']) == null
          ? null
          : ReadiumProgressNavigationOwner.fromMap(map['progressOwner']),
    );
  }
}

final class ReadiumPosition {
  const ReadiumPosition({
    this.locatorJson,
    required this.href,
    this.progression,
    this.resourceProgression,
    this.readingOrderIndex,
    this.totalProgression,
    this.position,
    this.totalLogicalPositions,
    this.fragments = const <String>[],
    this.presentation = const ReadiumUnknownPresentation(),
  });

  final String? locatorJson;
  final String href;
  final double? progression;
  final double? resourceProgression;
  final int? readingOrderIndex;
  final double? totalProgression;
  final int? position;
  final int? totalLogicalPositions;
  final List<String> fragments;
  final ReadiumPresentation presentation;

  factory ReadiumPosition.fromMap(Object? value) {
    final map = _asMap(value, 'position');
    return ReadiumPosition(
      locatorJson: _nullableString(map, 'locatorJson'),
      href: _requiredString(map, 'href'),
      progression: _optionalFiniteDouble(map, 'progression'),
      resourceProgression: _optionalFiniteDouble(map, 'resourceProgression'),
      readingOrderIndex: _optionalInt(map, 'readingOrderIndex'),
      totalProgression: _optionalFiniteDouble(map, 'totalProgression'),
      position: _optionalInt(map, 'position'),
      totalLogicalPositions: _optionalInt(map, 'totalLogicalPositions'),
      fragments: _stringList(map['fragments']),
      presentation: ReadiumPresentation.fromMap(map['presentation']),
    );
  }
}

sealed class ReadiumPresentation {
  const ReadiumPresentation();

  factory ReadiumPresentation.fromMap(Object? value) {
    if (value == null) return const ReadiumUnknownPresentation();
    final map = _asMap(value, 'presentation');
    return switch (_nullableString(map, 'mode')) {
      'scrolling' => const ReadiumScrollingPresentation(),
      'paginated' => ReadiumPaginatedPresentation(
        pageIndex: _requiredInt(map, 'pageIndex'),
        pageCount: _requiredInt(map, 'pageCount'),
        progression: _requiredFiniteDouble(map, 'progression'),
        layoutGeneration: _requiredInt(map, 'layoutGeneration'),
        publicationScoped: _requiredBool(map, 'publicationScoped'),
      ),
      _ => const ReadiumUnknownPresentation(),
    };
  }
}

final class ReadiumUnknownPresentation extends ReadiumPresentation {
  const ReadiumUnknownPresentation();
}

final class ReadiumScrollingPresentation extends ReadiumPresentation {
  const ReadiumScrollingPresentation();
}

final class ReadiumPaginatedPresentation extends ReadiumPresentation {
  const ReadiumPaginatedPresentation({
    required this.pageIndex,
    required this.pageCount,
    required this.progression,
    required this.layoutGeneration,
    required this.publicationScoped,
  });

  final int pageIndex;
  final int pageCount;
  final double progression;
  final int layoutGeneration;
  final bool publicationScoped;
}

final class ReadiumChapter {
  const ReadiumChapter({this.entryId, this.title, this.href});

  final String? entryId;
  final String? title;
  final String? href;

  factory ReadiumChapter.fromMap(Object? value) {
    final map = _asMap(value, 'chapter');
    return ReadiumChapter(
      entryId: _nullableString(map, 'entryId'),
      title: _nullableString(map, 'title'),
      href: _nullableString(map, 'href'),
    );
  }
}

final class ReadiumPreferencesState {
  const ReadiumPreferencesState({
    this.requested,
    this.applied,
    this.generation = 0,
    this.isApplying = false,
    this.initial = false,
    this.error,
  });

  final ReadiumEpubPreferences? requested;
  final ReadiumEpubPreferences? applied;
  final int generation;
  final bool isApplying;
  final bool initial;
  final ReadiumBridgeError? error;

  factory ReadiumPreferencesState.fromMap(Object? value) {
    final map = _asMap(value, 'preferences state');
    final requested = map['requested'];
    final applied = map['applied'];
    return ReadiumPreferencesState(
      requested: requested == null ? null : _parsePreferences(requested),
      applied: applied == null ? null : _parsePreferences(applied),
      generation: _optionalInt(map, 'generation') ?? 0,
      isApplying: _optionalBool(map, 'isApplying') ?? false,
      initial: _optionalBool(map, 'initial') ?? false,
      error: map['error'] == null
          ? null
          : ReadiumBridgeError.fromMap(map['error']),
    );
  }
}

enum ReadiumTocStatus { notLoaded, loading, ready, empty, failed, unknown }

final class ReadiumReaderTocEntry {
  const ReadiumReaderTocEntry({
    required this.id,
    required this.title,
    required this.href,
    this.fragment,
    this.level,
    this.children = const <ReadiumReaderTocEntry>[],
  });

  final String id;
  final String title;
  final String href;
  final String? fragment;
  final int? level;
  final List<ReadiumReaderTocEntry> children;

  factory ReadiumReaderTocEntry.fromMap(Object? value) {
    final map = _asMap(value, 'TOC entry');
    return ReadiumReaderTocEntry(
      id: _requiredNonBlankString(map, 'id'),
      title: _requiredString(map, 'title'),
      href: _requiredString(map, 'href'),
      fragment: _nullableString(map, 'fragment'),
      level: _optionalInt(map, 'level'),
      children: List.unmodifiable(
        _requiredList(map, 'children').map(ReadiumReaderTocEntry.fromMap),
      ),
    );
  }
}

final class ReadiumTocState {
  const ReadiumTocState({
    required this.status,
    this.entries = const <ReadiumReaderTocEntry>[],
    this.errorCode,
  });

  final ReadiumTocStatus status;
  final List<ReadiumReaderTocEntry> entries;
  final String? errorCode;

  factory ReadiumTocState.fromMap(Object? value) {
    final map = _asMap(value, 'TOC');
    return ReadiumTocState(
      status: _tocStatus(_requiredString(map, 'status')),
      entries: List.unmodifiable(
        ((map['entries'] as List?) ?? const <Object?>[]).map(
          ReadiumReaderTocEntry.fromMap,
        ),
      ),
      errorCode: _nullableString(map, 'errorCode'),
    );
  }
}

enum ReadiumSearchStatus { idle, loading, ready, empty, failed, unknown }

final class ReadiumSearchResult {
  const ReadiumSearchResult({
    required this.id,
    required this.href,
    required this.title,
    this.before,
    this.highlight,
    this.after,
    this.position,
    this.progression,
  });

  final String id;
  final String href;
  final String title;
  final String? before;
  final String? highlight;
  final String? after;
  final int? position;
  final double? progression;

  factory ReadiumSearchResult.fromMap(Object? value) {
    final map = _asMap(value, 'search result');
    return ReadiumSearchResult(
      id: _requiredNonBlankString(map, 'id'),
      href: _requiredString(map, 'href'),
      title: _requiredString(map, 'title'),
      before: _nullableString(map, 'before'),
      highlight: _nullableString(map, 'highlight'),
      after: _nullableString(map, 'after'),
      position: _optionalInt(map, 'position'),
      progression: _optionalFiniteDouble(map, 'progression'),
    );
  }
}

final class ReadiumSearchState {
  const ReadiumSearchState({
    required this.status,
    this.query,
    this.generation,
    this.loadingMore = false,
    this.hasMore = false,
    this.results = const <ReadiumSearchResult>[],
    this.errorCode,
  });

  final ReadiumSearchStatus status;
  final String? query;
  final int? generation;
  final bool loadingMore;
  final bool hasMore;
  final List<ReadiumSearchResult> results;
  final String? errorCode;

  factory ReadiumSearchState.fromMap(Object? value) {
    final map = _asMap(value, 'search');
    return ReadiumSearchState(
      status: _searchStatus(_requiredString(map, 'status')),
      query: _nullableString(map, 'query'),
      generation: _optionalInt(map, 'generation'),
      loadingMore: _optionalBool(map, 'loadingMore') ?? false,
      hasMore: _optionalBool(map, 'hasMore') ?? false,
      results: List.unmodifiable(
        ((map['results'] as List?) ?? const <Object?>[]).map(
          ReadiumSearchResult.fromMap,
        ),
      ),
      errorCode: _nullableString(map, 'errorCode'),
    );
  }
}

final class ReadiumSelectionRect {
  const ReadiumSelectionRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  factory ReadiumSelectionRect.fromMap(Object? value) {
    final map = _asMap(value, 'selection rectangle');
    return ReadiumSelectionRect(
      left: _requiredFiniteDouble(map, 'left'),
      top: _requiredFiniteDouble(map, 'top'),
      right: _requiredFiniteDouble(map, 'right'),
      bottom: _requiredFiniteDouble(map, 'bottom'),
    );
  }
}

final class ReadiumSelectionValue {
  const ReadiumSelectionValue({
    this.locatorJson,
    this.selectedText,
    this.textBefore,
    this.textAfter,
    this.href,
    this.progression,
    this.totalProgression,
    this.rect,
  });

  final String? locatorJson;
  final String? selectedText;
  final String? textBefore;
  final String? textAfter;
  final String? href;
  final double? progression;
  final double? totalProgression;
  final ReadiumSelectionRect? rect;

  factory ReadiumSelectionValue.fromMap(Object? value) {
    final map = _asMap(value, 'selection value');
    return ReadiumSelectionValue(
      locatorJson: _nullableString(map, 'locatorJson'),
      selectedText: _nullableString(map, 'selectedText'),
      textBefore: _nullableString(map, 'textBefore'),
      textAfter: _nullableString(map, 'textAfter'),
      href: _nullableString(map, 'href'),
      progression: _optionalFiniteDouble(map, 'progression'),
      totalProgression: _optionalFiniteDouble(map, 'totalProgression'),
      rect: map['rect'] == null
          ? null
          : ReadiumSelectionRect.fromMap(map['rect']),
    );
  }
}

final class ReadiumSelectionState {
  const ReadiumSelectionState({
    required this.status,
    this.sessionId,
    this.nativeSessionId,
    this.generation = 0,
    this.viewportEpoch = 0,
    this.retrievalInFlight = false,
    this.selection,
    this.errorCode,
  });

  final String status;
  final int? sessionId;
  final int? nativeSessionId;
  final int generation;
  final int viewportEpoch;
  final bool retrievalInFlight;
  final ReadiumSelectionValue? selection;
  final String? errorCode;

  bool get sessionActive => switch (status) {
    'pending' || 'active' || 'clearing' || 'retrieval_failed' => true,
    _ => false,
  };

  factory ReadiumSelectionState.fromMap(Object? value) {
    final map = _asMap(value, 'selection');
    return ReadiumSelectionState(
      status: _requiredString(map, 'status'),
      sessionId: _optionalInt(map, 'sessionId'),
      nativeSessionId: _optionalInt(map, 'nativeSessionId'),
      generation: _optionalInt(map, 'generation') ?? 0,
      viewportEpoch: _optionalInt(map, 'viewportEpoch') ?? 0,
      retrievalInFlight: _optionalBool(map, 'retrievalInFlight') ?? false,
      selection: map['selection'] == null
          ? null
          : ReadiumSelectionValue.fromMap(map['selection']),
      errorCode: _nullableString(map, 'errorCode'),
    );
  }
}

enum ReadiumSelectionAction {
  highlight('highlight'),
  note('note'),
  highlightAndNote('highlightAndNote');

  const ReadiumSelectionAction(this.wireValue);
  final String wireValue;

  static ReadiumSelectionAction fromWire(Object? value) {
    final raw = value is String ? value : '';
    return values.firstWhere(
      (item) => item.wireValue == raw,
      orElse: () =>
          throw ReadiumBridgeFormatException('invalid_selection_action'),
    );
  }
}

enum ReadiumSelectionActionOutcome {
  committed('committed'),
  failed('failed'),
  cancelled('cancelled');

  const ReadiumSelectionActionOutcome(this.wireValue);
  final String wireValue;
}

final class ReadiumSelectionActionRequest {
  const ReadiumSelectionActionRequest({
    required this.requestId,
    required this.instanceId,
    required this.selectionSessionId,
    required this.action,
    required this.locatorJson,
    required this.selectedText,
    this.style,
    this.color,
  });

  final int requestId;
  final String instanceId;
  final int selectionSessionId;
  final ReadiumSelectionAction action;
  final String locatorJson;
  final String selectedText;
  final String? style;
  final String? color;

  factory ReadiumSelectionActionRequest.fromMap(Object? value) {
    final map = _asMap(value, 'selection action request');
    final requestId = _requiredPositiveInt(map, 'requestId');
    final sessionId = _requiredPositiveInt(map, 'selectionSessionId');
    final instanceId = _requiredNonBlankString(map, 'instanceId');
    final locatorJson = _requiredNonBlankString(map, 'locatorJson');
    final selectedText = _requiredNonBlankString(map, 'selectedText');
    return ReadiumSelectionActionRequest(
      requestId: requestId,
      instanceId: instanceId,
      selectionSessionId: sessionId,
      action: ReadiumSelectionAction.fromWire(map['action']),
      locatorJson: locatorJson,
      selectedText: selectedText,
      style: _nullableString(map, 'style'),
      color: _nullableString(map, 'color'),
    );
  }
}

final class ReadiumSelectionActionResolution {
  const ReadiumSelectionActionResolution({
    required this.requestId,
    required this.selectionSessionId,
    required this.outcome,
    this.annotationId,
    this.errorCode,
  });

  final int requestId;
  final int selectionSessionId;
  final ReadiumSelectionActionOutcome outcome;
  final String? annotationId;
  final String? errorCode;

  Map<String, Object?> toMap() => {
    'requestId': requestId,
    'selectionSessionId': selectionSessionId,
    'outcome': outcome.wireValue,
    if (annotationId != null) 'annotationId': annotationId,
    if (errorCode != null) 'errorCode': errorCode,
  };
}

enum ReadiumAnnotationAction {
  delete('delete'),
  recolor('recolor');

  const ReadiumAnnotationAction(this.wireValue);
  final String wireValue;

  static ReadiumAnnotationAction fromWire(Object? value) {
    final raw = value is String ? value : '';
    return values.firstWhere(
      (item) => item.wireValue == raw,
      orElse: () =>
          throw ReadiumBridgeFormatException('invalid_annotation_action'),
    );
  }
}

final class ReadiumAnnotationActionRequest {
  const ReadiumAnnotationActionRequest({
    required this.requestId,
    required this.instanceId,
    required this.annotationId,
    required this.action,
    this.color,
  });

  final int requestId;
  final String instanceId;
  final String annotationId;
  final ReadiumAnnotationAction action;
  final String? color;

  factory ReadiumAnnotationActionRequest.fromMap(Object? value) {
    final map = _asMap(value, 'annotation action request');
    return ReadiumAnnotationActionRequest(
      requestId: _requiredPositiveInt(map, 'requestId'),
      instanceId: _requiredNonBlankString(map, 'instanceId'),
      annotationId: _requiredNonBlankString(map, 'annotationId'),
      action: ReadiumAnnotationAction.fromWire(map['action']),
      color: _nullableString(map, 'color'),
    );
  }
}

final class ReadiumAnnotationActionResolution {
  const ReadiumAnnotationActionResolution({
    required this.requestId,
    required this.outcome,
    this.errorCode,
  });

  final int requestId;
  final ReadiumSelectionActionOutcome outcome;
  final String? errorCode;

  Map<String, Object?> toMap() => {
    'requestId': requestId,
    'outcome': outcome.wireValue,
    if (errorCode != null) 'errorCode': errorCode,
  };
}

final class ReadiumDecorationActivatedEvent {
  const ReadiumDecorationActivatedEvent({
    required this.interactionId,
    required this.instanceId,
    required this.group,
    required this.decorationId,
  });

  final int interactionId;
  final String instanceId;
  final String group;
  final String decorationId;

  factory ReadiumDecorationActivatedEvent.fromMap(Object? value) {
    final map = _asMap(value, 'decoration activation');
    return ReadiumDecorationActivatedEvent(
      interactionId: _requiredPositiveInt(map, 'interactionId'),
      instanceId: _requiredNonBlankString(map, 'instanceId'),
      group: _requiredNonBlankString(map, 'group'),
      decorationId: _requiredNonBlankString(map, 'decorationId'),
    );
  }
}

enum ReadiumDecorationGroup {
  persistentHighlights('PERSISTENT_HIGHLIGHTS'),
  searchResult('SEARCH_RESULT');

  const ReadiumDecorationGroup(this.wireValue);
  final String wireValue;

  static ReadiumDecorationGroup fromWire(Object? value) {
    final raw = value is String ? value : '';
    return values.firstWhere(
      (group) => group.wireValue == raw,
      orElse: () =>
          throw ReadiumBridgeFormatException('invalid_decoration_group'),
    );
  }
}

enum ReadiumDecorationStyleType { highlight, underline }

final class ReadiumDecorationStyle {
  const ReadiumDecorationStyle({
    required this.type,
    required this.tint,
    this.active = false,
  });

  final ReadiumDecorationStyleType type;
  final int tint;
  final bool active;

  Map<String, Object> toMap() => {
    'type': type.name,
    'tint': tint,
    'active': active,
  };

  factory ReadiumDecorationStyle.fromMap(Object? value) {
    final map = _asMap(value, 'decoration style');
    final type = _requiredString(map, 'type');
    final style = switch (type) {
      'highlight' => ReadiumDecorationStyleType.highlight,
      'underline' => ReadiumDecorationStyleType.underline,
      _ => throw ReadiumBridgeFormatException('invalid_decoration_style'),
    };
    return ReadiumDecorationStyle(
      type: style,
      tint: _requiredInt(map, 'tint'),
      active: _optionalBool(map, 'active') ?? false,
    );
  }
}

final class ReadiumDecorationSpec {
  const ReadiumDecorationSpec({
    required this.id,
    required this.locatorJson,
    required this.style,
  });

  final String id;
  final String locatorJson;
  final ReadiumDecorationStyle style;

  Map<String, Object> toMap() => {
    'id': id,
    'locatorJson': locatorJson,
    'style': style.toMap(),
  };
}

final class ReadiumDecorationGroupState {
  const ReadiumDecorationGroupState({
    required this.group,
    required this.requestedCount,
    required this.appliedCount,
    required this.generation,
    required this.isApplying,
    required this.isReady,
    required this.selectionProtected,
    required this.hasApplied,
  });

  final ReadiumDecorationGroup group;
  final int requestedCount;
  final int appliedCount;
  final int generation;
  final bool isApplying;
  final bool isReady;
  final bool selectionProtected;
  final bool hasApplied;

  factory ReadiumDecorationGroupState.fromMap(Object? value) {
    final map = _asMap(value, 'decoration state');
    return ReadiumDecorationGroupState(
      group: ReadiumDecorationGroup.fromWire(map['group']),
      requestedCount: _requiredInt(map, 'requestedCount'),
      appliedCount: _requiredInt(map, 'appliedCount'),
      generation: _requiredInt(map, 'generation'),
      isApplying: _requiredBool(map, 'isApplying'),
      isReady: _requiredBool(map, 'isReady'),
      selectionProtected: _requiredBool(map, 'selectionProtected'),
      hasApplied: _requiredBool(map, 'hasApplied'),
    );
  }
}

final class ReadiumReaderSnapshot {
  const ReadiumReaderSnapshot({
    required this.lifecycle,
    required this.position,
    required this.chapter,
    required this.preferences,
    required this.toc,
    required this.search,
    required this.selection,
    required this.decorations,
    this.latestError,
  });

  final ReadiumReaderLifecycle lifecycle;
  final ReadiumPosition? position;
  final ReadiumChapter chapter;
  final ReadiumPreferencesState preferences;
  final ReadiumTocState toc;
  final ReadiumSearchState search;
  final ReadiumSelectionState selection;
  final Map<ReadiumDecorationGroup, ReadiumDecorationGroupState> decorations;
  final ReadiumBridgeError? latestError;

  factory ReadiumReaderSnapshot.fromMap(Object? value) {
    final map = _asMap(value, 'snapshot');
    final decorations = <ReadiumDecorationGroup, ReadiumDecorationGroupState>{};
    final rawDecorations = map['decorations'];
    if (rawDecorations is Map) {
      for (final entry in rawDecorations.entries) {
        final state = ReadiumDecorationGroupState.fromMap(entry.value);
        decorations[state.group] = state;
      }
    }
    for (final group in ReadiumDecorationGroup.values) {
      decorations.putIfAbsent(
        group,
        () => ReadiumDecorationGroupState(
          group: group,
          requestedCount: 0,
          appliedCount: 0,
          generation: 0,
          isApplying: false,
          isReady: false,
          selectionProtected: false,
          hasApplied: false,
        ),
      );
    }
    final bridge = _asMap(map['bridge'], 'snapshot.bridge');
    return ReadiumReaderSnapshot(
      lifecycle: ReadiumReaderLifecycle.fromMap(map['lifecycle']),
      position: map['position'] == null
          ? null
          : ReadiumPosition.fromMap(map['position']),
      chapter: ReadiumChapter.fromMap(map['chapter']),
      preferences: ReadiumPreferencesState.fromMap(map['preferences']),
      toc: ReadiumTocState.fromMap(map['toc']),
      search: ReadiumSearchState.fromMap(map['search']),
      selection: ReadiumSelectionState.fromMap(map['selection']),
      decorations: Map.unmodifiable(decorations),
      latestError: map['error'] == null
          ? null
          : ReadiumBridgeError.fromMap(map['error']),
    )..assertBridge(bridge);
  }

  ReadiumReaderSnapshot assertBridge(Map<Object?, Object?> bridge) {
    final protocol = _requiredInt(bridge, 'protocolVersion');
    if (protocol != ReadiumBridgeConstants.protocolVersion) {
      throw ReadiumBridgeFormatException('protocol_mismatch');
    }
    return this;
  }
}

sealed class ReadiumReaderEvent {
  const ReadiumReaderEvent({
    required this.protocolVersion,
    required this.instanceId,
    required this.sequence,
    required this.type,
  });

  final int protocolVersion;
  final String instanceId;
  final int sequence;
  final String type;

  static ReadiumReaderEvent parse(Object? value) {
    final map = _asMap(value, 'reader event');
    final protocol = _requiredInt(map, 'protocolVersion');
    if (protocol != ReadiumBridgeConstants.protocolVersion) {
      throw ReadiumBridgeFormatException('protocol_mismatch');
    }
    final instanceId = _requiredNonBlankString(map, 'instanceId');
    final sequence = _requiredInt(map, 'sequence');
    if (sequence < 1) throw ReadiumBridgeFormatException('invalid_sequence');
    final type = _requiredString(map, 'type');
    final payload = map['payload'];
    final metadata = ReadiumEventMetadata(protocol, instanceId, sequence, type);
    return switch (type) {
      ReadiumBridgeConstants.snapshot => ReadiumSnapshotEvent(
        metadata: metadata,
        snapshot: ReadiumReaderSnapshot.fromMap(payload),
      ),
      ReadiumBridgeConstants.readerLifecycleChanged => ReadiumLifecycleEvent(
        metadata: metadata,
        lifecycle: ReadiumReaderLifecycle.fromMap(payload),
      ),
      ReadiumBridgeConstants.positionChanged => ReadiumPositionEvent(
        metadata: metadata,
        position: ReadiumPosition.fromMap(payload),
        liveManual:
            _optionalBool(_asMap(payload, 'position'), 'liveManual') ?? false,
        progressOwner:
            _asOptionalMap(_asMap(payload, 'position')['progressOwner']) == null
            ? null
            : ReadiumProgressNavigationOwner.fromMap(
                _asMap(payload, 'position')['progressOwner'],
              ),
      ),
      ReadiumBridgeConstants.manualScrollActivityChanged =>
        ReadiumManualScrollActivityEvent(
          metadata: metadata,
          active: _requiredBool(
            _asMap(payload, 'manual scroll activity'),
            'active',
          ),
        ),
      ReadiumBridgeConstants.chapterChanged => ReadiumChapterEvent(
        metadata: metadata,
        chapter: ReadiumChapter.fromMap(payload),
      ),
      ReadiumBridgeConstants.preferencesChanged => ReadiumPreferencesEvent(
        metadata: metadata,
        preferences: ReadiumPreferencesState.fromMap(payload),
      ),
      ReadiumBridgeConstants.readerDiagnostic => ReadiumDiagnosticEvent(
        metadata: metadata,
        fields: ReadiumDiagnosticEvent._safeFields(payload),
      ),
      ReadiumBridgeConstants.tocChanged => ReadiumTocEvent(
        metadata: metadata,
        toc: ReadiumTocState.fromMap(payload),
      ),
      ReadiumBridgeConstants.searchChanged => ReadiumSearchEvent(
        metadata: metadata,
        search: ReadiumSearchState.fromMap(payload),
      ),
      ReadiumBridgeConstants.selectionChanged => ReadiumSelectionEvent(
        metadata: metadata,
        selection: ReadiumSelectionState.fromMap(payload),
      ),
      ReadiumBridgeConstants.decorationStateChanged => ReadiumDecorationEvent(
        metadata: metadata,
        decoration: ReadiumDecorationGroupState.fromMap(payload),
      ),
      ReadiumBridgeConstants.contentTap => ReadiumContentTapEvent(
        metadata: metadata,
        interactionId: _requiredPositiveInt(
          _asMap(payload, 'content tap'),
          ReadiumBridgeConstants.interactionId,
        ),
        viewportGeneration: _optionalNonNegativeInt(
          _asMap(payload, 'content tap'),
          ReadiumBridgeConstants.viewportGeneration,
        ),
        region: _contentTapRegion(_asMap(payload, 'content tap')),
      ),
      ReadiumBridgeConstants.selectionActionRequested =>
        ReadiumSelectionActionRequestedEvent(
          metadata: metadata,
          request: ReadiumSelectionActionRequest.fromMap(payload),
        ),
      ReadiumBridgeConstants.decorationActivated =>
        ReadiumDecorationActivatedReaderEvent(
          metadata: metadata,
          activation: ReadiumDecorationActivatedEvent.fromMap(payload),
        ),
      ReadiumBridgeConstants.annotationActionRequested =>
        ReadiumAnnotationActionRequestedEvent(
          metadata: metadata,
          request: ReadiumAnnotationActionRequest.fromMap(payload),
        ),
      ReadiumBridgeConstants.readerError => ReadiumErrorEvent(
        metadata: metadata,
        error: ReadiumBridgeError.fromMap(payload),
      ),
      ReadiumBridgeConstants.disposed => ReadiumDisposedEvent(
        metadata: metadata,
      ),
      _ => ReadiumUnknownEvent(metadata: metadata),
    };
  }
}

/// Optional request metadata used only to correlate reader diagnostics.
/// It is deliberately kept beside, never inside, [ReadiumEpubPreferences].
final class ReadiumReflowDiagnosticContext {
  const ReadiumReflowDiagnosticContext({
    required this.gestureId,
    required this.slider,
    required this.applyId,
    required this.normalizedValue,
  });

  final int gestureId;
  final String slider;
  final int applyId;
  final double normalizedValue;

  Map<String, Object?> toMap() => {
    'gestureId': gestureId,
    'slider': slider,
    'applyId': applyId,
    'normalizedValue': normalizedValue,
  };
}

/// Whitelisted, structured native diagnostics. The parser intentionally
/// ignores arbitrary payload values so book content cannot enter AppLog.
final class ReadiumDiagnosticEvent extends ReadiumReaderEvent {
  ReadiumDiagnosticEvent({
    required ReadiumEventMetadata metadata,
    required this.fields,
  }) : super(
         protocolVersion: metadata.protocolVersion,
         instanceId: metadata.instanceId,
         sequence: metadata.sequence,
         type: metadata.type,
       );

  final Map<String, Object?> fields;

  static Map<String, Object?> _safeFields(Object? payload) {
    if (payload is! Map) return const <String, Object?>{};
    if (payload['category'] == 'Reader.Open') return _safeOpenFields(payload);
    const integerFields = <String>{
      'timeoutMs',
      'previousGestureId',
      'newGestureId',
      'nextPendingPreviewId',
      'nextPreviewId',
      'oldPreviewId',
      'previewId',
      'navigationGeneration',
      'currentNavigationGeneration',
      'targetReadingOrderIndex',
      'requestedReadingOrderIndex',
      'targetPosition',
      'firstVisibleResourceIndex',
      'navigationElapsedMs',

      'cssGeneration',
      'fromPreferenceGeneration',
      'toPreferenceGeneration',
      'activeCssPreferenceGeneration',
      'activeCssLayoutGeneration',
      'committedGeometryPreferenceGeneration',
      'committedGeometryLayoutGeneration',
      'resourceIndex',
      'anchorCharacterOffset',
      'gestureId',
      'applyId',
      'preferenceGeneration',
      'transactionGeneration',
      'layoutGeneration',
      'resourceGeneration',
      'measurementGeneration',
      'readingOrderIndex',
      'measurementCount',
      'anchorBeforeIndex',
      'scrollAnchorIndex',
      'logicalPosition',
      'viewportFirstVisibleIndex',
      'viewportHeightPx',
      'viewportPaddingTopPx',
      'viewportPaddingBottomPx',
      'viewportAnchorIndex',
      'webViewIdentity',
      'predecessorMeasurementCount',
      'observedReadingOrderIndex',
      'viewportFirstVisibleIndexBefore',
      'viewportFirstVisibleIndexAfter',
    };
    const numberFields = <String>{
      'requestedResourceProgression',
      'requestedTotalProgression',
      'observedResourceProgression',
      'observedTotalProgression',
      'normalizedProgress',
      'targetProgression',
      'targetTotalProgression',
      'resourceProgression',
      'totalProgression',
      'locatorProgression',
      'requestedNormalizedProgress',
      'observedNormalizedProgress',
      'progressError',
      'requestedProgress',
      'observedProgress',
      'requestedProgression',
      'resourceProgressError',
      'firstVisibleTopPx',

      'declaredFaceCount',
      'letterSpacingDeltaPx',
      'anchorCharacterOffset',
      'fontSizePx',
      'lineHeightPx',
      'letterSpacingPx',
      'rangeLeftPx',
      'rangeTopPx',
      'rangeRightPx',
      'rangeBottomPx',
      'rangeWidthPx',
      'rangeHeightPx',
      'clientRectCount',
      'firstRectTopPx',
      'firstRectHeightPx',
      'elementTopPx',
      'elementBottomPx',
      'elementHeightPx',
      'devicePixelRatio',
      'scrollYCssPx',
      'visualViewportScale',
      'resourceHeightCssPx',
      'loadingEventCount',
      'rangeTopDeltaPx',
      'rangeHeightDeltaPx',
      'rangeLeftDeltaPx',
      'rangeWidthDeltaPx',
      'elementTopDeltaPx',
      'elementHeightDeltaPx',
      'lineHeightDeltaPx',
      'fontSizeDeltaPx',
      'resourceHeightCssDeltaPx',
      'heightPx',
      'committedHeightPx',
      'webViewHeightPx',
      'parentResourceHeightPx',
      'originalTargetViewportYPx',
      'actualBeforeReflowViewportYPx',
      'actualFinalViewportYPx',
      'errorFromOriginalBaselinePx',
      'cumulativeDriftFromGestureStartPx',
      'beforeViewportY',
      'resolvedBeforeCorrectionViewportY',
      'finalViewportY',
      'finalDeltaPx',
      'pointToTargetOffsetPx',
      'anchorCaptureViewportY',
      'anchorResolvedViewportYBeforeCorrection',
      'anchorTargetViewportY',
      'anchorFinalViewportY',
      'elapsedMs',
      'uiValue',
      'normalizedValue',
      'oldHeightPx',
      'newHeightPx',
      'anchorBeforeOffsetPx',
      'scrollAnchorOffsetPx',
      'anchorY',
      'anchorBeforeY',
      'anchorAfterY',
      'positionProgression',
      'intervalSincePreviousMs',
      'anchorProgression',
      'anchorBeforeLocalYPx',
      'anchorBeforeViewportYPx',
      'anchorPointDocumentYPx',
      'anchorPointViewportYPx',
      'anchorViewportDeltaPx',
      'anchorViewportTolerancePx',
      'requestedCorrectionOffsetPx',
      'requestedViewportDeltaPx',
      'predecessorHeightDeltaPx',
      'batchHeightDeltaPx',
      'targetViewportYPx',
      'actualViewportYPx',
      'observedProgression',
      'semanticProgressionDelta',
      'viewportFirstVisibleTopBeforePx',
      'viewportFirstVisibleTopAfterPx',
      'viewportFirstVisibleTopDeltaPx',
      'viewportFirstVisibleTopPx',
      'viewportAnchorTopPx',
      'viewportAnchorBottomPx',
    };
    const stringFields = <String>{
      'terminalResult',
      'sideEffectsScope',
      'fromState',
      'toState',
      'validationDomain',
      'validationResult',
      'category',
      'stage',
      'snapshotSource',
      'viewportVerification',
      'positioningOutcome',
      'verificationSource',
      'a11State',

      'measurementResult',
      'identityType',
      'anchorIdentityType',
      'anchorIdentityId',
      'semanticAnchorQuality',
      'kind',
      'slider',
      'result',
      'source',
      'backend',
      'level',
      'reason',
      'snapshotStage',
      'viewportSampleStage',
      'anchorPointSampleStage',
      'anchorPointUnavailableReason',
      'viewportSnapshotUnavailableReason',
      'webViewIdentityUnavailableReason',
      'dispatchStage',
      'anchorBeforeYCoordinateSpace',
      'anchorResourceHrefUnavailableReason',
      'viewportScrollReason',
    };
    const booleanFields = <String>{
      'activeSlotCleared',
      'activeOwnerMatches',
      'nextPendingIsFinal',
      'nextIsFinal',
      'previousGestureEnded',
      'previousNavigationStillActive',
      'viewportAlreadyVerified',
      'viewportVerified',
      'terminalMutationAttempted',
      'isFinal',
      'targetLocatorAvailable',
      'activeNavigation',
      'sameRequestedResource',
      'targetRangeAtReadingAnchor',
      'authorityStillCurrent',
      'sideEffectsApplied',

      'declaredFacesTruncated',
      'variableWeightDeclared',
      'forced_layout_sample',
      'fallbackChainPresent',
      'fontFamilyChanged',
      'geometryMutation',
      'scrollRequested',
      'postRestoreLayoutPass',
      'fullGeometryBatchApplied',
      'cssHeightMeasurementKnown',
      'coherent',
      'sameResource',
      'sameDomIdentity',
      'sameCharacterOffset',
      'semanticAnchorResolved',
      'semanticAnchorExact',
      'fallbackUsed',
      'anchorPointAvailable',
      'anchorSemanticMatch',
      'scrollRequestIssued',
      'commitLockHeld',
      'activeApply',
      'pendingLatest',
    };
    final safe = <String, Object?>{};
    final validatedValue = payload['valueBeingValidated'];
    if (validatedValue is num && validatedValue.isFinite ||
        validatedValue is String &&
            RegExp(r'^[A-Za-z0-9_.-]{1,64}$').hasMatch(validatedValue)) {
      safe['valueBeingValidated'] = validatedValue;
    }
    for (final key in integerFields) {
      final value = payload[key];
      if (value is int && value >= 0) safe[key] = value;
    }
    for (final key in numberFields) {
      final value = payload[key];
      if (value is num && value.isFinite) safe[key] = value.toDouble();
    }
    for (final key in stringFields) {
      final value = payload[key];
      if (value is String &&
          RegExp(r'^[A-Za-z0-9_.-]{1,48}$').hasMatch(value)) {
        safe[key] = value;
      }
    }
    for (final key in booleanFields) {
      final value = payload[key];
      if (value is bool) safe[key] = value;
    }
    const textRenderFontFields = <String>{
      'lineHeight',
      'letterSpacing',
      'declaredFaceStatuses',
      'rangeMode',
      'fontFamily',
      'declaredPrimaryFamily',
      'fontWeight',
      'requestedWeight',
      'fontStyle',
      'fontStretch',
      'fontVariationSettings',
      'fontFeatureSettings',
      'fontSynthesis',
      'declaredWeights',
      'fontSetStatus',
      'elementTag',
      'fontLoadingEvents',
      'fontWeightBefore',
      'fontWeightAfter',
      'fontSetStatusBefore',
      'fontSetStatusAfter',
    };
    for (final key in textRenderFontFields) {
      final value = payload[key];
      if (value is String &&
          value.isNotEmpty &&
          value.length <= 160 &&
          !RegExp(r'[\x00-\x1f\x7f<>]').hasMatch(value)) {
        safe[key] = value;
      }
    }
    for (final key in <String>{
      'syntheticWeightLikely',
      'activeFontCheck',
      'activeFontCheckBefore',
      'activeFontCheckAfter',
    }) {
      final value = payload[key];
      if (value is bool || value == 'unknown') {
        safe[key] = value;
      }
    }
    for (final hrefKey in const [
      'anchorResourceHref',
      'resourceHref',
      'targetResourceHref',
    ]) {
      final relativeHref = payload[hrefKey];
      if (relativeHref is String &&
          relativeHref.length <= 160 &&
          !relativeHref.startsWith('/') &&
          !RegExp(r'%(?![0-9A-Fa-f]{2})').hasMatch(relativeHref) &&
          RegExp(r'^[A-Za-z0-9_./%\-]+$').hasMatch(relativeHref)) {
        safe[hrefKey] = relativeHref;
      }
    }
    return Map.unmodifiable(safe);
  }

  // The native producer supplies only whitelisted error phrases and numbers.
  // Do not copy generic reader diagnostic fields into an opening event.
  static Map<String, Object?> _safeOpenFields(
    Map<Object?, Object?> payload, {
    bool includeRestoration = true,
  }) {
    final safe = <String, Object?>{'category': 'Reader.Open'};
    for (final key in const [
      'stage',
      'result',
      'component',
      'errorCode',
      'exceptionType',
      'readiumErrorCategory',
      'readiumCauseType',
      'restorationStage',
      'locatorSource',
      'viewportVerification',
      'positioningOutcome',
      'failureReason',
      'skipReason',
    ]) {
      final value = payload[key];
      if (value is String && RegExp(r'^[a-zA-Z0-9_]{1,64}$').hasMatch(value)) {
        safe[key] = value;
      }
    }
    for (final key in const [
      'fileSizeBytes',
      'osErrorCode',
      'openAttemptId',
      'elapsedMs',
      'requestedReadingOrderIndex',
      'resolvedReadingOrderIndex',
      'actualReadingOrderIndex',
      'viewportAnchorIndex',
    ]) {
      final value = payload[key];
      if (value is int && value >= 0) safe[key] = value;
    }
    for (final key in const [
      'fileExists',
      'readable',
      'pathIsRegularFile',
      'fileAccessChecked',
      'nativeSessionCreated',
      'readiumInitializationReached',
      'requestedHrefMatchesPublication',
    ]) {
      final value = payload[key];
      if (value is bool) safe[key] = value;
    }
    for (final key in const [
      'requestedResourceProgression',
      'actualResourceProgression',
    ]) {
      final value = payload[key];
      if (value is num && value.isFinite) safe[key] = value;
    }
    if (payload['kind'] == 'initial_locator_restoration') {
      safe['kind'] = 'initial_locator_restoration';
      final geometry = payload['initialLocatorGeometry'];
      if (geometry is Map) {
        safe['initialLocatorGeometry'] = _safeInitialLocatorGeometry(geometry);
      }
      for (final key in const [
        'requestedReadingOrderIndex',
        'requestedResourceProgression',
        'requestedHrefMatchesPublication',
        'resolvedReadingOrderIndex',
        'actualReadingOrderIndex',
        'actualResourceProgression',
        'viewportAnchorIndex',
        'viewportVerification',
      ]) {
        if (payload.containsKey(key) && payload[key] == null) safe[key] = null;
      }
    }
    final restoration = payload['initialLocatorRestoration'];
    if (includeRestoration &&
        restoration is Map &&
        restoration['kind'] == 'initial_locator_restoration') {
      safe['initialLocatorRestoration'] = _safeOpenFields(
        restoration,
        includeRestoration: false,
      );
    }
    final message = payload['message'];
    if (message is String &&
        message.length <= 240 &&
        RegExp(r"^[a-zA-Z0-9_ ';.-]+$").hasMatch(message)) {
      safe['message'] = message;
    }
    return Map.unmodifiable(safe);
  }

  static Map<String, Object?> _safeInitialLocatorGeometry(
    Map<Object?, Object?> payload,
  ) {
    final safe = <String, Object?>{};
    final offset = payload['targetDocumentOffsetLayoutPx'];
    if (offset is num && offset.isFinite) {
      safe['targetDocumentOffsetLayoutPx'] = offset;
    }
    for (final key in const [
      'sameResource',
      'selectorEqual',
      'quoteEqual',
      'domEquivalence',
    ]) {
      if (payload[key] is bool) safe[key] = payload[key];
    }
    final range = payload['rangeEvidence'];
    if (range is Map) {
      safe['rangeEvidence'] = <String, Object?>{
        for (final key in const [
          'matches',
          'rangeResolved',
          'semanticRangeResolved',
          'finiteInputs',
          'rangeCollapsed',
        ])
          if (range[key] is bool) key: range[key],
        for (final key in const [
          'rangeTopCssPx',
          'rangeHeightCssPx',
          'anchorCssPx',
          'maxDistanceCssPx',
          'distanceCssPx',
          'windowScrollYCssPx',
        ])
          if (range[key] is num && (range[key] as num).isFinite)
            key: range[key],
      };
    }
    for (final key in const [
      'offsetBeforeRecoveryPx',
      'offsetAfterRecoveryPx',
    ]) {
      final value = payload[key];
      if (value is num && value.isFinite) safe[key] = value;
    }
    final recoveryCheck = payload['recoveryOffsetCheck'];
    if (const {
      'unstable_geometry',
      'current_point_aligned',
      'boundary_proof_required',
      'target_offset_mismatch',
    }.contains(recoveryCheck)) {
      safe['recoveryOffsetCheck'] = recoveryCheck;
    }
    final requestedOffset = payload['requestedItemOffsetPx'];
    if (requestedOffset is int) safe['requestedItemOffsetPx'] = requestedOffset;
    final check = payload['verificationCheck'];
    if (const {
      'semantic_identity',
      'meaningful_block',
      'resource_no_longer_live',
      'requested_range_not_eligible',
      'geometry_not_ready_before_range',
      'anchor_unavailable',
      'anchor_target_mismatch',
      'requested_range_at_anchor',
      'requested_range_at_start_boundary',
      'top_boundary_clamp_verified',
      'range_not_visible',
      'geometry_not_ready_after_range',
      'anchor_changed_during_range',
      'start_boundary_changed_during_range',
      'requested_range_not_at_anchor',
      'requested_range_not_at_start_boundary',
      'requested_range_verification_failed',
      'viewport_locator_unavailable',
    }.contains(check)) {
      safe['verificationCheck'] = check;
    }
    for (final key in const [
      'requestedLocatorFields',
      'observedLocatorFields',
    ]) {
      final flags = payload[key];
      if (flags is! Map) continue;
      safe[key] = Map<String, Object?>.unmodifiable({
        for (final flag in const [
          'hasSelector',
          'hasFragment',
          'hasCfi',
          'hasQuote',
          'hasPosition',
          'hasTotalProgression',
        ])
          if (flags[flag] is bool) flag: flags[flag],
      });
    }
    for (final stage in const [
      'beforePositioning',
      'afterPositioningLayout',
      'afterVerification',
      'beforeRecovery',
      'afterRecovery',
    ]) {
      final sample = payload[stage];
      if (sample is! Map) continue;
      final fields = <String, Object?>{};
      for (final key in const [
        'layoutGeneration',
        'resourceGeneration',
        'reportedMeasurementGeneration',
        'measurementEpoch',
        'layoutPass',
        'resourceTopPx',
        'resourceHeightPx',
        'committedResourceHeightPx',
        'viewportHeightPx',
        'viewportPaddingTopPx',
      ]) {
        final value = sample[key];
        if (value is int) fields[key] = value;
      }
      for (final key in const [
        'viewportAnchorYPx',
        'anchorLocalYPx',
        'density',
      ]) {
        final value = sample[key];
        if (value is num && value.isFinite) fields[key] = value;
      }
      for (final key in const ['geometryReady', 'canScrollTowardStart']) {
        final value = sample[key];
        if (value is bool) fields[key] = value;
      }
      safe[stage] = Map.unmodifiable(fields);
    }
    return Map.unmodifiable(safe);
  }
}

final class ReadiumEventMetadata {
  const ReadiumEventMetadata(
    this.protocolVersion,
    this.instanceId,
    this.sequence,
    this.type,
  );
  final int protocolVersion;
  final String instanceId;
  final int sequence;
  final String type;
}

final class ReadiumSnapshotEvent extends ReadiumReaderEvent {
  ReadiumSnapshotEvent({
    required ReadiumEventMetadata metadata,
    required this.snapshot,
  }) : super(
         protocolVersion: metadata.protocolVersion,
         instanceId: metadata.instanceId,
         sequence: metadata.sequence,
         type: metadata.type,
       );
  final ReadiumReaderSnapshot snapshot;
}

final class ReadiumLifecycleEvent extends ReadiumReaderEvent {
  ReadiumLifecycleEvent({
    required ReadiumEventMetadata metadata,
    required this.lifecycle,
  }) : super(
         protocolVersion: metadata.protocolVersion,
         instanceId: metadata.instanceId,
         sequence: metadata.sequence,
         type: metadata.type,
       );
  final ReadiumReaderLifecycle lifecycle;
}

final class ReadiumProgressNavigationOwner {
  const ReadiumProgressNavigationOwner({
    required this.sessionId,
    required this.requestId,
    required this.phase,
  });

  final int sessionId;
  final int requestId;
  final String phase;

  factory ReadiumProgressNavigationOwner.fromMap(Object? value) {
    final map = _asMap(value, 'progress owner');
    final sessionId = _requiredInt(map, 'sessionId');
    final requestId = _requiredInt(map, 'requestId');
    final phase = _requiredString(map, 'phase');
    if (sessionId <= 0 ||
        requestId <= 0 ||
        !const {'preview', 'final'}.contains(phase)) {
      throw ReadiumBridgeFormatException('invalid_progress_owner');
    }
    return ReadiumProgressNavigationOwner(
      sessionId: sessionId,
      requestId: requestId,
      phase: phase,
    );
  }

  Map<String, Object?> toMap() => {
    'sessionId': sessionId,
    'requestId': requestId,
    'phase': phase,
  };
}

final class ReadiumPositionEvent extends ReadiumReaderEvent {
  ReadiumPositionEvent({
    required ReadiumEventMetadata metadata,
    required this.position,
    this.liveManual = false,
    this.progressOwner,
  }) : super(
         protocolVersion: metadata.protocolVersion,
         instanceId: metadata.instanceId,
         sequence: metadata.sequence,
         type: metadata.type,
       );
  final ReadiumPosition position;
  final bool liveManual;
  final ReadiumProgressNavigationOwner? progressOwner;
}

final class ReadiumManualScrollActivityEvent extends ReadiumReaderEvent {
  ReadiumManualScrollActivityEvent({
    required ReadiumEventMetadata metadata,
    required this.active,
  }) : super(
         protocolVersion: metadata.protocolVersion,
         instanceId: metadata.instanceId,
         sequence: metadata.sequence,
         type: metadata.type,
       );
  final bool active;
}

final class ReadiumChapterEvent extends ReadiumReaderEvent {
  ReadiumChapterEvent({
    required ReadiumEventMetadata metadata,
    required this.chapter,
  }) : super(
         protocolVersion: metadata.protocolVersion,
         instanceId: metadata.instanceId,
         sequence: metadata.sequence,
         type: metadata.type,
       );
  final ReadiumChapter chapter;
}

final class ReadiumPreferencesEvent extends ReadiumReaderEvent {
  ReadiumPreferencesEvent({
    required ReadiumEventMetadata metadata,
    required this.preferences,
  }) : super(
         protocolVersion: metadata.protocolVersion,
         instanceId: metadata.instanceId,
         sequence: metadata.sequence,
         type: metadata.type,
       );
  final ReadiumPreferencesState preferences;
}

final class ReadiumTocEvent extends ReadiumReaderEvent {
  ReadiumTocEvent({required ReadiumEventMetadata metadata, required this.toc})
    : super(
        protocolVersion: metadata.protocolVersion,
        instanceId: metadata.instanceId,
        sequence: metadata.sequence,
        type: metadata.type,
      );
  final ReadiumTocState toc;
}

final class ReadiumSearchEvent extends ReadiumReaderEvent {
  ReadiumSearchEvent({
    required ReadiumEventMetadata metadata,
    required this.search,
  }) : super(
         protocolVersion: metadata.protocolVersion,
         instanceId: metadata.instanceId,
         sequence: metadata.sequence,
         type: metadata.type,
       );
  final ReadiumSearchState search;
}

final class ReadiumSelectionEvent extends ReadiumReaderEvent {
  ReadiumSelectionEvent({
    required ReadiumEventMetadata metadata,
    required this.selection,
  }) : super(
         protocolVersion: metadata.protocolVersion,
         instanceId: metadata.instanceId,
         sequence: metadata.sequence,
         type: metadata.type,
       );
  final ReadiumSelectionState selection;
}

final class ReadiumDecorationEvent extends ReadiumReaderEvent {
  ReadiumDecorationEvent({
    required ReadiumEventMetadata metadata,
    required this.decoration,
  }) : super(
         protocolVersion: metadata.protocolVersion,
         instanceId: metadata.instanceId,
         sequence: metadata.sequence,
         type: metadata.type,
       );
  final ReadiumDecorationGroupState decoration;
}

enum ReadiumContentTapRegion { center, leading, trailing }

sealed class ReadiumReaderInteractionEvent {
  const ReadiumReaderInteractionEvent({
    required this.protocolVersion,
    required this.instanceId,
    required this.sequence,
  });

  final int protocolVersion;
  final String instanceId;
  final int sequence;
}

final class ReadiumContentTapEvent extends ReadiumReaderEvent
    implements ReadiumReaderInteractionEvent {
  ReadiumContentTapEvent({
    required ReadiumEventMetadata metadata,
    required this.interactionId,
    this.viewportGeneration,
    this.region,
  }) : super(
         protocolVersion: metadata.protocolVersion,
         instanceId: metadata.instanceId,
         sequence: metadata.sequence,
         type: metadata.type,
       );

  final int interactionId;
  final int? viewportGeneration;
  final ReadiumContentTapRegion? region;
}

final class ReadiumSelectionActionRequestedEvent extends ReadiumReaderEvent
    implements ReadiumReaderInteractionEvent {
  ReadiumSelectionActionRequestedEvent({
    required ReadiumEventMetadata metadata,
    required this.request,
  }) : super(
         protocolVersion: metadata.protocolVersion,
         instanceId: metadata.instanceId,
         sequence: metadata.sequence,
         type: metadata.type,
       );

  final ReadiumSelectionActionRequest request;
}

final class ReadiumDecorationActivatedReaderEvent extends ReadiumReaderEvent
    implements ReadiumReaderInteractionEvent {
  ReadiumDecorationActivatedReaderEvent({
    required ReadiumEventMetadata metadata,
    required this.activation,
  }) : super(
         protocolVersion: metadata.protocolVersion,
         instanceId: metadata.instanceId,
         sequence: metadata.sequence,
         type: metadata.type,
       );

  final ReadiumDecorationActivatedEvent activation;
}

final class ReadiumAnnotationActionRequestedEvent extends ReadiumReaderEvent
    implements ReadiumReaderInteractionEvent {
  ReadiumAnnotationActionRequestedEvent({
    required ReadiumEventMetadata metadata,
    required this.request,
  }) : super(
         protocolVersion: metadata.protocolVersion,
         instanceId: metadata.instanceId,
         sequence: metadata.sequence,
         type: metadata.type,
       );

  final ReadiumAnnotationActionRequest request;
}

final class ReadiumErrorEvent extends ReadiumReaderEvent {
  ReadiumErrorEvent({
    required ReadiumEventMetadata metadata,
    required this.error,
  }) : super(
         protocolVersion: metadata.protocolVersion,
         instanceId: metadata.instanceId,
         sequence: metadata.sequence,
         type: metadata.type,
       );
  final ReadiumBridgeError error;
}

final class ReadiumDisposedEvent extends ReadiumReaderEvent {
  ReadiumDisposedEvent({required ReadiumEventMetadata metadata})
    : super(
        protocolVersion: metadata.protocolVersion,
        instanceId: metadata.instanceId,
        sequence: metadata.sequence,
        type: metadata.type,
      );
}

final class ReadiumUnknownEvent extends ReadiumReaderEvent {
  ReadiumUnknownEvent({required ReadiumEventMetadata metadata})
    : super(
        protocolVersion: metadata.protocolVersion,
        instanceId: metadata.instanceId,
        sequence: metadata.sequence,
        type: metadata.type,
      );
}

final class ReadiumReaderCommandResult {
  const ReadiumReaderCommandResult(this.status, {this.details});
  final String status;
  final Object? details;
  bool get isDisposed => status == 'disposed';
  bool get isSuccess => const {
    'completed',
    'applied',
    'started',
    'cleared',
    'cancelled',
    'updated',
    'empty',
    'queued',
    'unchanged',
    'boundaryReached',
  }.contains(status);
}

final class ReadiumNavigationResult extends ReadiumReaderCommandResult {
  const ReadiumNavigationResult(super.status, {super.details});
  bool get isCompleted => status == 'completed';
  bool get positionPublicationFailed =>
      details is Map && (details as Map)['positionPublication'] == 'failed';
}

final class ReadiumPreferenceResult extends ReadiumReaderCommandResult {
  const ReadiumPreferenceResult(super.status, {super.details});
}

final class ReadiumSearchCommandResult extends ReadiumReaderCommandResult {
  const ReadiumSearchCommandResult(super.status, {super.details});
}

final class ReadiumDecorationResult extends ReadiumReaderCommandResult {
  const ReadiumDecorationResult(super.status, {super.details});
}

final class ReadiumSelectionResult extends ReadiumReaderCommandResult {
  const ReadiumSelectionResult(super.status, {super.details});
}

final class ReadiumEpubControllerState {
  const ReadiumEpubControllerState({
    required this.lifecycle,
    required this.instanceId,
    this.snapshot,
    this.position,
    this.chapter = const ReadiumChapter(),
    this.preferences = const ReadiumPreferencesState(),
    this.toc = const ReadiumTocState(status: ReadiumTocStatus.notLoaded),
    this.search = const ReadiumSearchState(status: ReadiumSearchStatus.idle),
    this.selection = const ReadiumSelectionState(status: 'inactive'),
    this.decorations =
        const <ReadiumDecorationGroup, ReadiumDecorationGroupState>{},
    this.latestError,
    this.lastSequence = 0,
    this.manualScrollActive = false,
    this.positionLiveManual = false,
    this.progressOwner,
    this.lastNavigationStartedSequence = 0,
    this.lastNavigationCommand,
    this.lastNavigationProgressOwner,
  });

  final ReadiumControllerLifecycle lifecycle;
  final String instanceId;
  final ReadiumReaderSnapshot? snapshot;
  final ReadiumPosition? position;
  final ReadiumChapter chapter;
  final ReadiumPreferencesState preferences;
  final ReadiumTocState toc;
  final ReadiumSearchState search;
  final ReadiumSelectionState selection;
  final Map<ReadiumDecorationGroup, ReadiumDecorationGroupState> decorations;
  final ReadiumBridgeError? latestError;
  final int lastSequence;
  final bool manualScrollActive;
  final bool positionLiveManual;
  final ReadiumProgressNavigationOwner? progressOwner;
  final int lastNavigationStartedSequence;
  final String? lastNavigationCommand;
  final ReadiumProgressNavigationOwner? lastNavigationProgressOwner;

  bool get isReady => lifecycle == ReadiumControllerLifecycle.ready;
  bool get isDisposed => lifecycle == ReadiumControllerLifecycle.disposed;
  bool get hasFatalError => latestError?.fatal == true;
  double? get progression => position?.progression;
}

Map<Object?, Object?> _asMap(Object? value, String context) {
  if (value is! Map) throw ReadiumBridgeFormatException('invalid_$context');
  return Map<Object?, Object?>.from(value);
}

List<Object?> _requiredList(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is! List) throw ReadiumBridgeFormatException('invalid_$key');
  return List<Object?>.from(value);
}

String _requiredString(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is! String) throw ReadiumBridgeFormatException('missing_$key');
  return value;
}

String _requiredNonBlankString(Map<Object?, Object?> map, String key) {
  final value = _requiredString(map, key);
  if (value.trim().isEmpty) throw ReadiumBridgeFormatException('missing_$key');
  return value;
}

String? _nullableString(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value == null || value is String) return value as String?;
  throw ReadiumBridgeFormatException('invalid_$key');
}

bool _requiredBool(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is! bool) throw ReadiumBridgeFormatException('missing_$key');
  return value;
}

bool? _optionalBool(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value == null || value is bool) return value as bool?;
  throw ReadiumBridgeFormatException('invalid_$key');
}

int _requiredInt(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is! num || !value.isFinite || value.truncateToDouble() != value) {
    throw ReadiumBridgeFormatException('invalid_$key');
  }
  return value.toInt();
}

int? _optionalInt(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is! num || !value.isFinite || value.truncateToDouble() != value) {
    throw ReadiumBridgeFormatException('invalid_$key');
  }
  return value.toInt();
}

int _requiredPositiveInt(Map<Object?, Object?> map, String key) {
  final value = _requiredInt(map, key);
  if (value < 1) throw ReadiumBridgeFormatException('invalid_$key');
  return value;
}

int? _optionalNonNegativeInt(Map<Object?, Object?> map, String key) {
  final value = _optionalInt(map, key);
  if (value != null && value < 0) {
    throw ReadiumBridgeFormatException('invalid_$key');
  }
  return value;
}

ReadiumContentTapRegion? _contentTapRegion(Map<Object?, Object?> map) {
  final value = map[ReadiumBridgeConstants.region];
  if (value == null) return null;
  if (value is! String) {
    throw ReadiumBridgeFormatException('invalid_region');
  }
  return switch (value) {
    'center' => ReadiumContentTapRegion.center,
    'leading' => ReadiumContentTapRegion.leading,
    'trailing' => ReadiumContentTapRegion.trailing,
    _ => null,
  };
}

double _requiredFiniteDouble(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is! num || !value.isFinite) {
    throw ReadiumBridgeFormatException('invalid_$key');
  }
  return value.toDouble();
}

double? _optionalFiniteDouble(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is! num || !value.isFinite) {
    throw ReadiumBridgeFormatException('invalid_$key');
  }
  return value.toDouble();
}

List<String> _stringList(Object? value) {
  if (value == null) return const <String>[];
  if (value is! List || value.any((entry) => entry is! String)) {
    throw ReadiumBridgeFormatException('invalid_fragments');
  }
  return List.unmodifiable(value.cast<String>());
}

Object? _codecValue(Object? value) {
  if (value == null || value is bool || value is String || value is num) {
    return value;
  }
  if (value is List) return List.unmodifiable(value.map(_codecValue));
  if (value is Map) {
    return Map.unmodifiable(
      value.map((key, entry) => MapEntry(key.toString(), _codecValue(entry))),
    );
  }
  return null;
}

Map<Object?, Object?>? _asOptionalMap(Object? value) =>
    value is Map ? Map<Object?, Object?>.from(value) : null;

ReadiumEpubPreferences _parsePreferences(Object? value) {
  final parsed = ReadiumEpubPreferences.fromMap(value);
  if (parsed == null) {
    throw ReadiumBridgeFormatException('invalid_preferences');
  }
  return parsed;
}

ReadiumTocStatus _tocStatus(String value) => switch (value) {
  'notLoaded' => ReadiumTocStatus.notLoaded,
  'loading' => ReadiumTocStatus.loading,
  'ready' => ReadiumTocStatus.ready,
  'empty' => ReadiumTocStatus.empty,
  'failed' => ReadiumTocStatus.failed,
  _ => ReadiumTocStatus.unknown,
};

ReadiumSearchStatus _searchStatus(String value) => switch (value) {
  'idle' => ReadiumSearchStatus.idle,
  'loading' => ReadiumSearchStatus.loading,
  'ready' => ReadiumSearchStatus.ready,
  'empty' => ReadiumSearchStatus.empty,
  'failed' => ReadiumSearchStatus.failed,
  _ => ReadiumSearchStatus.unknown,
};

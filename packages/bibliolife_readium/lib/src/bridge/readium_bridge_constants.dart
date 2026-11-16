import 'dart:convert';

abstract final class ReadiumBridgeConstants {
  static const protocolVersion = 1;
  static const viewType = 'app.bibliolife.reader.readium/reader_host';
  static const namespace = 'app.bibliolife.reader.readium';
  static const commandSuffix = 'commands';
  static const eventSuffix = 'events';

  static const getBridgeInfo = 'getBridgeInfo';
  static const getSnapshot = 'getSnapshot';
  static const next = 'next';
  static const previous = 'previous';
  static const goToProgression = 'goToProgression';
  static const openProgressScrubSession = 'openProgressScrubSession';
  static const invalidateProgressScrubSession =
      'invalidateProgressScrubSession';
  static const reserveProgressScrubFinal = 'reserveProgressScrubFinal';
  static const goToLocator = 'goToLocator';
  static const applyPreferences = 'applyPreferences';
  static const supersedeSettingsPreviews = 'supersedeSettingsPreviews';
  static const settingsReflowGesture = 'settingsReflowGesture';
  static const goToTocEntry = 'goToTocEntry';
  static const search = 'search';
  static const cancelSearch = 'cancelSearch';
  static const clearSearch = 'clearSearch';
  static const goToSearchResult = 'goToSearchResult';
  static const setDecorations = 'setDecorations';
  static const upsertDecoration = 'upsertDecoration';
  static const removeDecoration = 'removeDecoration';
  static const clearDecorations = 'clearDecorations';
  static const requestCurrentSelection = 'requestCurrentSelection';
  static const clearSelection = 'clearSelection';
  static const resolveSelectionAction = 'resolveSelectionAction';
  static const resolveAnnotationAction = 'resolveAnnotationAction';

  static const snapshot = 'snapshot';
  static const readerLifecycleChanged = 'readerLifecycleChanged';
  static const positionChanged = 'positionChanged';
  static const manualScrollActivityChanged = 'manualScrollActivityChanged';
  static const chapterChanged = 'chapterChanged';
  static const preferencesChanged = 'preferencesChanged';
  static const readerDiagnostic = 'readerDiagnostic';
  static const tocChanged = 'tocChanged';
  static const searchChanged = 'searchChanged';
  static const selectionChanged = 'selectionChanged';
  static const decorationStateChanged = 'decorationStateChanged';
  static const contentTap = 'contentTap';
  static const selectionActionRequested = 'selectionActionRequested';
  static const decorationActivated = 'decorationActivated';
  static const annotationActionRequested = 'annotationActionRequested';
  static const readerError = 'readerError';
  static const disposed = 'disposed';

  static const ok = 'ok';
  static const value = 'value';
  static const error = 'error';
  static const code = 'code';
  static const messageKey = 'messageKey';
  static const details = 'details';
  static const fatal = 'fatal';
  static const retryable = 'retryable';
  static const operation = 'operation';

  static const instanceId = 'instanceId';
  static const bookId = 'bookId';
  static const localFilePath = 'localFilePath';
  static const initialLocatorJson = 'initialLocatorJson';
  static const initialPreferences = 'initialPreferences';
  static const initialPreferencesAreAuthoritative =
      'initialPreferencesAreAuthoritative';
  static const isNightMode = 'isNightMode';
  static const bridgeProtocolVersion = 'bridgeProtocolVersion';
  static const interactionId = 'interactionId';
  static const viewportGeneration = 'viewportGeneration';
  static const region = 'region';

  static String encodedInstanceId(String instanceId) {
    final logical = instanceId.trim();
    if (logical.isEmpty) {
      throw const FormatException('invalid_instance_id');
    }
    if (logical.length > 512) {
      throw const FormatException('instance_id_too_long');
    }
    return base64Url.encode(utf8.encode(logical)).replaceAll('=', '');
  }

  static ReadiumBridgeChannelNames channelNames(String instanceId) {
    final encoded = encodedInstanceId(instanceId);
    return ReadiumBridgeChannelNames(
      command: '$namespace/reader/$encoded/$commandSuffix',
      events: '$namespace/reader/$encoded/$eventSuffix',
      encodedInstanceId: encoded,
    );
  }
}

final class ReadiumBridgeChannelNames {
  const ReadiumBridgeChannelNames({
    required this.command,
    required this.events,
    required this.encodedInstanceId,
  });

  final String command;
  final String events;
  final String encodedInstanceId;

  @override
  bool operator ==(Object other) =>
      other is ReadiumBridgeChannelNames &&
      other.command == command &&
      other.events == events &&
      other.encodedInstanceId == encodedInstanceId;

  @override
  int get hashCode => Object.hash(command, events, encodedInstanceId);
}

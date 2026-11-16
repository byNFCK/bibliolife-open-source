import 'dart:async';

import 'package:bibliolife/features/reader/domain/models/reader_capabilities.dart';
import 'package:bibliolife/features/reader/domain/models/reader_bookmark.dart';
import 'package:bibliolife/features/reader/domain/models/reader_bookmark_target.dart';
import 'package:bibliolife/features/reader/domain/models/reader_progress_state.dart';
import 'package:bibliolife/features/reader/domain/models/reader_search.dart';
import 'package:bibliolife/features/reader/domain/models/reader_settings.dart';
import 'package:bibliolife/features/reader/application/services/reader_bookmark_coordinator.dart';
import 'package:bibliolife/features/reader/application/services/readium_epub_annotation_coordinator.dart';
import 'package:bibliolife/features/bookmarks/domain/models/library_bookmark.dart';
import 'package:bibliolife/features/reader/performance/reader_performance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

typedef ReaderProgressSeek = Future<void> Function(double progression);
typedef ReaderProgressRestore = Future<void> Function();

abstract interface class ReaderProgressDiagnosticHost {
  void progressDiagnostic(Map<String, Object?> fields);
}

/// Identity of actual navigation work, independent of the finger and modal lifetimes.
final class ReaderProgressCommandIdentity {
  const ReaderProgressCommandIdentity({
    required this.commandId,
    required this.uiSessionId,
    required this.gestureId,
    required this.commandType,
  });
  final int commandId;
  final int? uiSessionId;
  final int? gestureId;
  final String commandType;
}

/// An engine's immutable canonical position, captured once when the menu opens.
abstract interface class ReaderProgressOrigin {
  int? get readingOrderIndex;
  double? get resourceProgression;
  double? get totalProgression;
  int? get logicalPosition;
}

/// The reader rejects older detached commands when a newer modal accepted work.
abstract interface class ReaderProgressCommandAuthorityHost {
  bool acceptProgressCommand(ReaderProgressCommandIdentity command);
  bool isProgressCommandCurrent(ReaderProgressCommandIdentity command);
}

abstract interface class ReaderProgressOriginHost {
  ReaderProgressOrigin? captureProgressOrigin();
  Future<void> restoreProgressOrigin({
    required ReaderProgressOrigin origin,
    required int sessionId,
    required int requestId,
    required ReaderProgressCommandIdentity command,
  });
}

class ReaderProgressCommandFailure extends StateError {
  ReaderProgressCommandFailure(super.message, this.terminalResult);
  final String terminalResult;
}

abstract interface class ReaderProgressScrubHost {
  Future<int> openProgressScrub({
    bool checkpointCurrentPosition = true,
    ReaderProgressCommandIdentity? command,
  });
  Future<void> previewProgressScrub({
    required int sessionId,
    required int requestId,
    required double target,
    ReaderProgressCommandIdentity? command,
  });
  Future<void> finishProgressScrub({
    required int sessionId,
    required int requestId,
    required double target,
    ReaderProgressCommandIdentity? command,
  });
  Future<void> restoreProgressScrub({
    required int sessionId,
    required int requestId,
    required double target,
  });
  Future<void> closeProgressScrub(int sessionId);
  Future<void> invalidateProgressScrub(int sessionId);
  bool isProgressScrubActive(int sessionId);
}

enum ReaderSliderId {
  progress,
  fontSize,
  fontWeight,
  lineHeight,
  margins,
  pageSpacing,
}

class ReaderTextSettings {
  const ReaderTextSettings({
    this.theme = 'system',
    required this.fontSize,
    required this.lineHeight,
    required this.pageMargins,
    required this.publisherStyles,
  });

  final String theme;
  final double fontSize;
  final double lineHeight;
  final double pageMargins;
  final bool publisherStyles;

  @override
  bool operator ==(Object other) =>
      other is ReaderTextSettings &&
      other.theme == theme &&
      other.fontSize == fontSize &&
      other.lineHeight == lineHeight &&
      other.pageMargins == pageMargins &&
      other.publisherStyles == publisherStyles;

  @override
  int get hashCode =>
      Object.hash(theme, fontSize, lineHeight, pageMargins, publisherStyles);
}

abstract interface class ReaderTextSettingsController {
  ReaderTextSettings get settings;
  Future<void> update(ReaderTextSettings settings);
}

/// A settings interaction whose visual preview is deliberately separate from
/// durable storage. It mirrors the stable reader's explicit Apply/Cancel flow.
abstract interface class ReaderTextSettingsSessionController
    implements ReaderTextSettingsController {
  Future<void> preview(ReaderTextSettings settings);
  Future<void> commit(ReaderTextSettings settings);
  Future<void> restore(ReaderTextSettings settings);
}

abstract interface class ReaderSettingsHost {
  ReaderSettingsCapabilities get settingsCapabilities;
  ReaderSettingsState get state;
  Future<void> previewSettings(ReaderSettingsState settings);
  Future<void> commitSettings(ReaderSettingsState settings);
  Future<void> restoreSettings(ReaderSettingsState settings);
}

/// Correlation hooks for the reflowable reader's five settings sliders.
abstract interface class ReaderSettingsDiagnosticHost {
  ReaderSettingsDiagnosticGesture? beginSettingsDiagnostic(
    ReaderSliderId sliderId,
    double uiValue,
  );
  void endSettingsDiagnostic(
    ReaderSettingsDiagnosticGesture gesture,
    double uiValue,
  );
  Future<void> previewSettingsWithDiagnostics(
    ReaderSettingsState settings, {
    required ReaderSettingsDiagnosticGesture? gesture,
  });
  void logSettingsDiagnosticAction(String action);
}

/// Optional latest-preview delivery contract for settings hosts that can
/// interrupt a superseded native preview without starting another apply.
abstract interface class ReaderSettingsPreviewRequestHost {
  int allocateSettingsPreviewRequestId();
  Future<void> supersedeSettingsPreviewsBefore(int requestId);
  Future<void> previewSettingsWithRequestId(
    ReaderSettingsState settings, {
    required int requestId,
    required ReaderSettingsDiagnosticGesture? gesture,
  });
}

/// Explicit semantic-baseline lifetime, independent of slider focus and logs.
abstract interface class ReaderSettingsGestureBaselineHost {
  Future<void> finishSettingsGestureBaseline(
    ReaderSettingsDiagnosticGesture gesture, {
    bool cancelled = false,
  });
  Future<void> cancelSettingsGestureBaselines();
}

final class ReaderSettingsDiagnosticGesture {
  const ReaderSettingsDiagnosticGesture({
    required this.id,
    required this.sliderId,
    required this.uiStartValue,
  });

  final int id;
  final ReaderSliderId sliderId;
  final double uiStartValue;
}

class ReaderTocEntry {
  const ReaderTocEntry({
    required this.id,
    required this.title,
    this.children = const <ReaderTocEntry>[],
  });

  final String id;
  final String title;
  final List<ReaderTocEntry> children;
}

abstract interface class ReaderTocController {
  List<ReaderTocEntry> get entries;
  bool get isReady;
  Future<void> goTo(String entryId);
}

class ReaderUiController extends ChangeNotifier {
  ReaderUiController({required this.capabilities, ReaderSettingsHost? settings})
    : _readerSettings = settings {
    _listenToSettings(settings);
  }

  final ReaderCapabilities capabilities;
  final StreamController<ReaderSearchState> _searchStateEvents =
      StreamController<ReaderSearchState>.broadcast();
  ReaderSearchState _searchState = const ReaderSearchIdle();
  var _searchDisposed = false;

  ReaderSearchState get searchState => _searchState;
  Stream<ReaderSearchState> get searchStates => _searchStateEvents.stream;

  void setSearchState(ReaderSearchState state) {
    if (_searchDisposed) return;
    _searchState = state;
    _searchStateEvents.add(state);
    notifyListeners();
  }

  Future<ReaderSearchCommandResult> search(String query) async =>
      const ReaderSearchCommandResult.unsupported();

  Future<ReaderSearchCommandResult> cancelSearch() async =>
      const ReaderSearchCommandResult.unsupported();

  Future<ReaderSearchCommandResult> clearSearch() async =>
      const ReaderSearchCommandResult.unsupported();

  Future<ReaderSearchCommandResult> goToSearchResult(String resultId) async =>
      const ReaderSearchCommandResult.unsupported();

  Future<void> clearSelectionForSearch() async {}
  ReaderTextSettingsController? get textSettings => null;
  ReaderProgressScrubHost? get progressScrubHost => null;
  ReaderSettingsHost? _readerSettings;
  ReaderSettingsHost? get readerSettings => _readerSettings;

  void attachReaderSettings(ReaderSettingsHost settings) {
    final previous = _readerSettings;
    if (identical(previous, settings)) return;
    if (previous case final Listenable listenable) {
      listenable.removeListener(_notifySettingsChanged);
    }
    _readerSettings = settings;
    _listenToSettings(settings);
    notifyListeners();
  }

  void _listenToSettings(ReaderSettingsHost? settings) {
    if (settings case final Listenable listenable) {
      listenable.addListener(_notifySettingsChanged);
    }
  }

  void _notifySettingsChanged() => notifyListeners();
  ReaderTocController? get tocController => null;
  ReaderBookmarkCoordinator? get bookmarkCoordinator => null;
  ReaderAnnotationMenuController? get annotationMenuController => null;
  ReaderBookmarkState get bookmarkState =>
      bookmarkCoordinator?.state ?? const ReaderBookmarkState(isLoading: false);
  ReaderBookmarkTarget? get currentBookmarkTarget =>
      bookmarkCoordinator?.currentBookmarkTarget;
  bool get isCurrentPositionBookmarked =>
      bookmarkState.isCurrentPositionBookmarked;

  Future<ReaderBookmarkCommandResult> addBookmark() async =>
      bookmarkCoordinator == null
      ? const ReaderBookmarkCommandResult.unsupported()
      : bookmarkCoordinator!.addBookmark();

  Future<ReaderBookmarkCommandResult> removeCurrentBookmark() async =>
      bookmarkCoordinator == null
      ? const ReaderBookmarkCommandResult.unsupported()
      : bookmarkCoordinator!.removeCurrentBookmark();

  Future<ReaderBookmarkCommandResult> goToBookmark(
    LibraryBookmark bookmark,
  ) async => bookmarkCoordinator == null
      ? const ReaderBookmarkCommandResult.unsupported()
      : bookmarkCoordinator!.goToBookmark(bookmark);

  Future<ReaderBookmarkCommandResult> deleteBookmark(
    LibraryBookmark bookmark,
  ) async => bookmarkCoordinator == null
      ? const ReaderBookmarkCommandResult.unsupported()
      : bookmarkCoordinator!.deleteBookmark(bookmark);
  ReaderProgressState _progress = const ReaderProgressState.unknown();
  ReaderProgressState get progress => _progress;
  ReaderProgressSeek? _seek;
  ReaderProgressRestore? _progressRestore;
  ReaderProgressRestore? get progressRestore => _progressRestore;
  Future<void>? _activeSeek;
  Object? _error;
  Object? get error => _error;
  var _isLoading = true;
  bool get isLoading => _isLoading;
  var _controlsVisible = true;
  bool get controlsVisible => _controlsVisible;
  bool get readerChromeSuppressed => false;
  var _isSeeking = false;
  bool get isSeeking => _isSeeking;
  ReaderSliderId? _activeSliderId;
  Object? _activeSliderToken;
  var _sliderNotificationPending = false;
  ReaderSliderId? get activeSliderId => _activeSliderId;
  bool get isSliderInteractionActive => _activeSliderId != null;

  Object? beginSliderInteraction(ReaderSliderId sliderId) {
    if (_searchDisposed) return null;
    final changed = _activeSliderId != sliderId || _activeSliderId == null;
    final token = Object();
    _activeSliderId = sliderId;
    _activeSliderToken = token;
    if (changed) _notifySliderInteractionChanged();
    return token;
  }

  void endSliderInteraction(ReaderSliderId sliderId, Object? token) {
    if (_searchDisposed ||
        token == null ||
        _activeSliderId != sliderId ||
        !identical(_activeSliderToken, token)) {
      return;
    }
    _activeSliderId = null;
    _activeSliderToken = null;
    _notifySliderInteractionChanged();
  }

  void _notifySliderInteractionChanged() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_sliderNotificationPending) return;
      _sliderNotificationPending = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _sliderNotificationPending = false;
        if (!_searchDisposed) notifyListeners();
      });
      return;
    }
    notifyListeners();
  }

  @override
  void notifyListeners() {
    ReaderPerformance.recordControllerNotification();
    super.notifyListeners();
  }

  void setProgress(
    ReaderProgressState progress, {
    ReaderProgressSeek? seek,
    ReaderProgressRestore? restore,
  }) {
    final changed = _progress != progress || _isLoading || _error != null;
    _progress = progress;
    _seek = seek ?? _seek;
    _progressRestore = restore ?? _progressRestore;
    _isLoading = false;
    _error = null;
    if (changed) notifyListeners();
  }

  void setReady({ReaderProgressSeek? seek}) {
    final changed = _isLoading || _error != null;
    _seek = seek ?? _seek;
    _isLoading = false;
    _error = null;
    if (changed) notifyListeners();
  }

  void setError(Object error) {
    if (!_isLoading && identical(_error, error)) return;
    _error = error;
    _isLoading = false;
    notifyListeners();
  }

  void toggleControls() {
    _controlsVisible = !_controlsVisible;
    notifyListeners();
  }

  void showControls() {
    if (_controlsVisible) return;
    _controlsVisible = true;
    notifyListeners();
  }

  Future<void> seek(double progression) async {
    final action = _seek;
    if (action == null || !_progress.canSeek) return;
    final activeSeek = _activeSeek;
    if (activeSeek != null) {
      // Page-menu previews can still be in flight when Cancel is selected.
      // Queue the rollback instead of silently dropping it, so cancellation
      // always restores the locator captured when the menu opened.
      await activeSeek;
      return seek(progression);
    }
    _isSeeking = true;
    notifyListeners();
    Future<void>? operation;
    try {
      operation = action(progression.clamp(0.0, 1.0));
      _activeSeek = operation;
      await operation;
    } finally {
      if (identical(_activeSeek, operation)) {
        _activeSeek = null;
      }
      _isSeeking = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    final settings = _readerSettings;
    if (settings case final Listenable listenable) {
      listenable.removeListener(_notifySettingsChanged);
    }
    _searchDisposed = true;
    _activeSliderId = null;
    _activeSliderToken = null;
    unawaited(_searchStateEvents.close());
    super.dispose();
  }
}

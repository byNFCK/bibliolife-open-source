import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/scheduler.dart';

const libraryCoverDiagnosticsEnabled = bool.fromEnvironment(
  'BIBLIOLIFE_LIBRARY_COVER_LOGS',
  defaultValue: false,
);

const libraryFrameDiagnosticsEnabled = bool.fromEnvironment(
  'BIBLIOLIFE_LIBRARY_FRAME_LOGS',
  defaultValue: false,
);

/// Short-lived, opt-in diagnostics for local and remote cover failures.
///
/// Normal builds do not inspect files, allocate failure maps, or emit logs.
abstract final class LibraryCoverDiagnostics {
  static const _maxTrackedSources = 128;
  static final Map<String, int> _attempts = <String, int>{};
  static final Set<String> _reported = <String>{};
  static final Map<String, Timer> _pendingReports = <String, Timer>{};

  static void recordFileFailure({
    required String sourceType,
    required String sourceId,
    required File file,
    required String profile,
    required int decodeWidth,
    required int? decodeHeight,
    Object? error,
    Uri? uri,
  }) {
    if (!libraryCoverDiagnosticsEnabled) return;
    final key = [
      sourceType,
      file.path,
      profile,
      decodeWidth,
      decodeHeight ?? 'native',
    ].join('|');
    final attempt = (_attempts[key] ?? 0) + 1;
    _rememberAttempt(key, attempt);
    if (_reported.contains(key)) return;
    _pendingReports[key]?.cancel();
    _pendingReports[key] = Timer(const Duration(milliseconds: 200), () {
      _pendingReports.remove(key);
      if (_reported.contains(key)) return;
      _reported.add(key);
      unawaited(
        _describeFile(
          sourceType: sourceType,
          sourceId: sourceId,
          file: file,
          profile: profile,
          decodeWidth: decodeWidth,
          decodeHeight: decodeHeight,
          attempt: _attempts[key] ?? attempt,
          error: error,
          uri: uri,
        ).then(_emit),
      );
    });
  }

  static void recordRemoteFailure({
    required String sourceId,
    required Uri uri,
    required String profile,
    required int decodeWidth,
    required int? decodeHeight,
    Object? error,
  }) {
    if (!libraryCoverDiagnosticsEnabled) return;
    final key = [
      'remote',
      uri.toString(),
      profile,
      decodeWidth,
      decodeHeight ?? 'native',
    ].join('|');
    final attempt = (_attempts[key] ?? 0) + 1;
    _rememberAttempt(key, attempt);
    if (_reported.add(key)) {
      _emit(
        'LIBRARY_COVER_DECODE_FAILURE '
        'sourceType=remote sourceId=$sourceId '
        'uri=${_safeUri(uri)} extension=${_extension(uri.path)} '
        'expectedMime=${_expectedMime(uri.path)} '
        'profile=$profile decode=${_decodeLabel(decodeWidth, decodeHeight)} '
        'attempt=$attempt error=${error.runtimeType}',
      );
    }
  }

  static void _rememberAttempt(String key, int attempt) {
    _attempts[key] = attempt;
    if (_attempts.length <= _maxTrackedSources) return;
    final oldest = _attempts.keys.first;
    _attempts.remove(oldest);
    _reported.remove(oldest);
    _pendingReports.remove(oldest)?.cancel();
  }

  static Future<String> _describeFile({
    required String sourceType,
    required String sourceId,
    required File file,
    required String profile,
    required int decodeWidth,
    required int? decodeHeight,
    required int attempt,
    Object? error,
    Uri? uri,
  }) async {
    var exists = false;
    var length = 0;
    var signature = 'missing';
    try {
      exists = await file.exists();
      if (exists) {
        length = await file.length();
        final header = await _readHeader(file);
        signature = _signature(header);
      }
    } on FileSystemException {
      signature = 'filesystem-error';
    }
    return 'LIBRARY_COVER_DECODE_FAILURE '
        'sourceType=$sourceType sourceId=$sourceId '
        'path=${_safePath(file.path)} '
        'extension=${_extension(file.path)} '
        'expectedMime=${_expectedMime(file.path)} '
        'exists=$exists bytes=$length signature=$signature '
        'profile=$profile decode=${_decodeLabel(decodeWidth, decodeHeight)} '
        'attempt=$attempt${uri == null ? '' : ' uri=${_safeUri(uri)}'} '
        'error=${error?.runtimeType ?? 'unknown'}';
  }

  static Future<List<int>> _readHeader(File file) async {
    final bytes = <int>[];
    await for (final chunk in file.openRead(0, 16)) {
      bytes.addAll(chunk);
      if (bytes.length >= 16) break;
    }
    return bytes;
  }

  static String _signature(List<int> bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a) {
      return 'png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'jpeg';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38 &&
        (bytes[4] == 0x37 || bytes[4] == 0x39) &&
        bytes[5] == 0x61) {
      return 'gif';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'webp';
    }
    return bytes.isEmpty ? 'empty' : 'unknown';
  }

  static String _safePath(String value) {
    final normalized = value.replaceAll('\\', '/');
    final parts = normalized.split('/').where((part) => part.isNotEmpty);
    final list = parts.toList(growable: false);
    if (list.length <= 2) return list.join('/');
    return '${list[list.length - 2]}/${list.last}';
  }

  static String _safeUri(Uri uri) =>
      '${uri.scheme}://${uri.host}${uri.path.isEmpty ? '' : uri.path}';

  static String _extension(String value) {
    final normalized = value.replaceAll('\\', '/');
    final name = normalized.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? 'none' : name.substring(dot + 1).toLowerCase();
  }

  static String _expectedMime(String value) => switch (_extension(value)) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    _ => 'unknown',
  };

  static String _decodeLabel(int width, int? height) =>
      '${width}x${height ?? 'native'}';

  static void _emit(String message) {
    if (!libraryCoverDiagnosticsEnabled) return;
    // Profile runs forward print reliably; normal builds never reach this.
    // ignore: avoid_print
    print(message);
    developer.log(message, name: 'BIBLIOLIFE_LIBRARY_COVER');
  }
}

final class LibraryFrameTimingObserver {
  final List<FrameTiming> _timings = <FrameTiming>[];
  String _transition = 'unknown';
  var _started = false;

  bool get isRunning => _started;

  void start(String transition) {
    if (!libraryFrameDiagnosticsEnabled) return;
    if (_started) {
      _transition = transition;
      return;
    }
    _transition = transition;
    _timings.clear();
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void setTransition(String transition) {
    if (_started) _transition = transition;
  }

  void _onTimings(List<FrameTiming> values) => _timings.addAll(values);

  LibraryFrameTimingSummary? stop() {
    if (!_started) return null;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _started = false;
    final summary = LibraryFrameTimingSummary.from(
      transition: _transition,
      timings: List<FrameTiming>.unmodifiable(_timings),
    );
    _timings.clear();
    if (libraryFrameDiagnosticsEnabled) {
      // ignore: avoid_print
      print('LIBRARY_FRAME_REPORT ${summary.fields}');
    }
    return summary;
  }

  void dispose() {
    stop();
  }
}

final class LibraryFrameTimingSummary {
  const LibraryFrameTimingSummary({
    required this.transition,
    required this.frames,
    required this.over16,
    required this.over33,
    required this.worstBuildMicros,
    required this.worstRasterMicros,
    required this.averageBuildMicros,
    required this.averageRasterMicros,
  });

  factory LibraryFrameTimingSummary.from({
    required String transition,
    required List<FrameTiming> timings,
  }) {
    var worstBuild = 0;
    var worstRaster = 0;
    var buildTotal = 0;
    var rasterTotal = 0;
    for (final timing in timings) {
      final build = timing.buildDuration.inMicroseconds;
      final raster = timing.rasterDuration.inMicroseconds;
      if (build > worstBuild) worstBuild = build;
      if (raster > worstRaster) worstRaster = raster;
      buildTotal += build;
      rasterTotal += raster;
    }
    return LibraryFrameTimingSummary(
      transition: transition,
      frames: timings.length,
      over16: timings
          .where((timing) => timing.totalSpan.inMicroseconds > 16667)
          .length,
      over33: timings
          .where((timing) => timing.totalSpan.inMicroseconds > 33333)
          .length,
      worstBuildMicros: worstBuild,
      worstRasterMicros: worstRaster,
      averageBuildMicros: timings.isEmpty ? 0 : buildTotal ~/ timings.length,
      averageRasterMicros: timings.isEmpty ? 0 : rasterTotal ~/ timings.length,
    );
  }

  final String transition;
  final int frames;
  final int over16;
  final int over33;
  final int worstBuildMicros;
  final int worstRasterMicros;
  final int averageBuildMicros;
  final int averageRasterMicros;

  String get classification {
    final buildBound = worstBuildMicros > 16667;
    final rasterBound = worstRasterMicros > 16667;
    if (buildBound && rasterBound) return 'both';
    if (buildBound) return 'build-bound';
    if (rasterBound) return 'raster-bound';
    return 'neither';
  }

  String get fields =>
      'transition=$transition frames=$frames over_16_67ms=$over16 '
      'over_33_3ms=$over33 worst_build_ms=${worstBuildMicros / 1000} '
      'worst_raster_ms=${worstRasterMicros / 1000} '
      'average_build_ms=${averageBuildMicros / 1000} '
      'average_raster_ms=${averageRasterMicros / 1000} '
      'classification=$classification';
}

String libraryTransitionName(int from, int to) {
  const names = ['collection', 'follow', 'all_books'];
  if (from < 0 || from >= names.length || to < 0 || to >= names.length) {
    return 'unknown_to_unknown';
  }
  return '${names[from]}_to_${names[to]}';
}

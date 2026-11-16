import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_log_entry.dart';

final appLogProvider = NotifierProvider<AppLogService, List<AppLogEntry>>(
  AppLogService.new,
);

class AppLogService extends Notifier<List<AppLogEntry>> {
  static const maxEntries = 1000;

  @override
  List<AppLogEntry> build() => List.unmodifiable([
    AppLogEntry(
      timestamp: DateTime.now().toUtc(),
      level: AppLogLevel.info,
      category: 'App',
      message: 'Application log service initialized',
    ),
  ]);

  void debug({required String category, required String message}) =>
      _append(AppLogLevel.debug, category, message);

  void info({required String category, required String message}) =>
      _append(AppLogLevel.info, category, message);

  void warning({required String category, required String message}) =>
      _append(AppLogLevel.warning, category, message);

  void error({required String category, required String message}) =>
      _append(AppLogLevel.error, category, message);

  // Opening diagnostics can be emitted during a widget build or disposal.
  void appendDeferred({
    required AppLogLevel level,
    required String category,
    required String message,
  }) {
    final logRef = ref;
    scheduleMicrotask(() {
      if (logRef.mounted) _append(level, category, message);
    });
  }

  String get formattedText =>
      state.map((entry) => entry.toLogLine()).join('\n');

  void clear() => state = const [];

  void _append(AppLogLevel level, String category, String message) {
    final entries = [
      ...state,
      AppLogEntry(
        timestamp: DateTime.now().toUtc(),
        level: level,
        category: category,
        message: message,
      ),
    ];
    if (entries.length > maxEntries) {
      entries.removeRange(0, entries.length - maxEntries);
    }
    state = List.unmodifiable(entries);
  }
}

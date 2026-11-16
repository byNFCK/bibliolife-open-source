enum AppLogLevel { debug, info, warning, error }

class AppLogEntry {
  const AppLogEntry({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
  });

  final DateTime timestamp;
  final AppLogLevel level;
  final String category;
  final String message;

  String toLogLine() =>
      '${timestamp.toUtc().toIso8601String()} '
      '[${level.name.toUpperCase()}] [$category] $message';
}

import 'dart:convert';
import 'dart:io';

import 'package:bibliolife/shared/application/logging/app_log_entry.dart';
import 'package:bibliolife/shared/application/logging/app_log_provider.dart';
import 'package:bibliolife_readium/bibliolife_readium.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// One opening lifecycle, owned by a route and handed off to one controller.
final class ReaderOpenAttempt {
  ReaderOpenAttempt(
    this._log, {
    required String bookId,
    required String source,
    String format = 'EPUB',
    DateTime? startedAt,
    Stopwatch? elapsed,
  }) : _originalFormat = format,
       _elapsed = elapsed ?? (Stopwatch()..start()),
       id = ++_nextId {
    _write({
      'kind': 'book_open_start',
      'bookId': bookId,
      'format': format,
      'source': const {'library', 'book_details'}.contains(source)
          ? source
          : 'other',
      'timestamp': (startedAt ?? DateTime.now()).toUtc().toIso8601String(),
    });
  }

  static int _nextId = 0;
  final AppLogService _log;
  final String _originalFormat;
  final Stopwatch _elapsed;
  final int id;
  bool _finished = false;
  bool _restorationTerminalLogged = false;
  bool get isFinished => _finished;

  String _stage = 'book_lookup';
  String _component = 'library_repository';
  final Map<String, Object?> _facts = {
    'readiumInitializationReached': false,
    'nativeSessionCreated': false,
    'fileResolved': false,
    'fileAccessChecked': false,
  };

  void stage(
    String stage,
    String result,
    String component, [
    Map<String, Object?> facts = const {},
  ]) {
    if (_finished) return;
    _stage = stage;
    _component = component;
    _facts.addAll(facts);
    _write({
      'kind': 'book_open_stage',
      'stage': stage,
      'result': result,
      'component': component,
      ...facts,
    });
  }

  void resolveFile(String reference) {
    final path = reference.trim();
    final type = switch (path) {
      '' => 'missing',
      _ when path.startsWith('content://') => 'content_uri',
      _ when path.startsWith('file:') => 'file_uri',
      _ when RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(path) =>
        'other_uri',
      _ when File(path).isAbsolute => 'local_path',
      _ => 'relative_path',
    };
    final storage = switch (path) {
      _ when type == 'content_uri' => 'content_uri',
      _ when path.startsWith('/data/') => 'internal',
      _ when path.startsWith('/storage/') || path.startsWith('/sdcard/') =>
        'external',
      _ => 'unknown',
    };
    stage('file_resolution', 'started', 'stored_file_reference');
    stage(
      'file_resolution',
      path.isEmpty ? 'failed' : 'success',
      'stored_file_reference',
      {
        'fileReferencePresent': path.isNotEmpty,
        'fileResolved': type == 'local_path' || type == 'relative_path',
        'resolvedPathType': type,
        'storageKind': storage,
        'fileNameExtension':
            const ['epub', 'txt', 'fb2']
                .where((ext) => path.toLowerCase().endsWith('.$ext'))
                .firstOrNull ??
            'other_or_missing',
      },
    );
  }

  void onNativeDiagnostic(ReadiumDiagnosticEvent event) {
    if (_finished) return;
    final fields = event.fields;
    if (!_belongsToAttempt(fields)) return;
    if (fields['kind'] == 'initial_locator_restoration') {
      if (fields['openAttemptId'] == id) _writeRestoration(fields);
      return;
    }
    final stageName = fields['stage'];
    final result = fields['result'];
    final component = fields['component'];
    if (stageName is! String || result is! String || component is! String) {
      return;
    }
    final facts = Map<String, Object?>.of(fields)
      ..remove('category')
      ..remove('openAttemptId')
      ..remove('stage')
      ..remove('result')
      ..remove('component');
    if (result == 'failed') {
      final code = facts.remove('errorCode') as String?;
      final type = facts.remove('exceptionType') as String?;
      final message = facts.remove('message') as String?;
      fail(
        facts: facts,
        stageName: stageName,
        component: component,
        code: code,
        exceptionType: type,
        message: message,
      );
      return;
    }
    stage(stageName, result, component, facts);
    if (stageName == 'reader_ready' && result == 'success') {
      _terminal('ready');
    }
  }

  void fail({
    Object? error,
    String? stageName,
    String? component,
    String? code,
    String? exceptionType,
    String? message,
    Map<String, Object?> facts = const {},
  }) {
    if (_finished) return;
    final bridgeError = switch (error) {
      ReadiumBridgeException(:final error) => error,
      ReadiumBridgeError() => error,
      _ => null,
    };
    final nativeFailure = bridgeError?.openFailure;
    if (nativeFailure != null && _belongsToAttempt(nativeFailure)) {
      stageName ??= nativeFailure['stage'] as String?;
      component ??= nativeFailure['component'] as String?;
      exceptionType ??= nativeFailure['exceptionType'] as String?;
      message ??= nativeFailure['message'] as String?;
      facts = {...nativeFailure, ...facts}
        ..remove('category')
        ..remove('stage')
        ..remove('result')
        ..remove('component')
        ..remove('errorCode')
        ..remove('exceptionType')
        ..remove('message')
        ..remove('openAttemptId');
    }
    final restoration = facts['initialLocatorRestoration'];
    if (restoration is Map<String, Object?> &&
        restoration['openAttemptId'] == id) {
      _writeRestoration(restoration);
    } else if (restoration != null) {
      facts = Map.of(facts)..remove('initialLocatorRestoration');
    }
    final nativeCreationMessage = error is PlatformException
        ? _safeDartMessage(error, null)
        : null;
    final platformCode = error is PlatformException
        ? (nativeCreationMessage?.contains('_') == true
              ? nativeCreationMessage
              : _safeCode(error.code))
        : null;
    if (platformCode == 'missing_file_path') {
      stageName = 'file_resolution';
      component = 'stored_file_reference';
    }
    final resolvedCode =
        code ??
        _safeCode(bridgeError?.code) ??
        platformCode ??
        '${stageName ?? _stage}_failed';
    final fileError = error is FileSystemException ? error.osError : null;
    final safeMessage =
        message ??
        _safeDartMessage(error, fileError) ??
        resolvedCode.replaceAll('_', ' ');
    stage(stageName ?? _stage, 'failed', component ?? _component, {
      ...facts,
      if (platformCode == 'host_binding_unavailable')
        'nativeSessionCreated': true,
    });
    _terminal('failed', {
      'failedStage': _stage,
      'component': _component,
      'errorCode': resolvedCode,
      'exceptionType':
          exceptionType ??
          (error is PlatformException
              ? _nativeExceptionType(error.message)
              : null) ??
          error?.runtimeType.toString() ??
          'none',
      'message': safeMessage,
      if (fileError != null) 'osErrorCode': fileError.errorCode,
      ..._facts,
    });
  }

  void cancel() {
    if (!_finished) _terminal('cancelled', {'lastStage': _stage});
  }

  bool _belongsToAttempt(Map<String, Object?> fields) {
    final attemptId = fields['openAttemptId'];
    return attemptId == null || attemptId == id;
  }

  void _writeRestoration(Map<String, Object?> fields) {
    if (fields['stage'] == 'restoration_terminal') {
      if (_restorationTerminalLogged) return;
      _restorationTerminalLogged = true;
    }
    _write(Map.of(fields)..remove('category'));
  }

  static String? _safeCode(String? code) =>
      code != null && RegExp(r'^[a-zA-Z0-9_.-]{1,64}$').hasMatch(code)
      ? code
      : null;

  static String? _nativeExceptionType(String? message) => message == null
      ? null
      : RegExp(
          r'^(?:[a-zA-Z_][a-zA-Z0-9_]*\.)*([A-Z][A-Za-z0-9_]{0,64}(?:Exception|Error)):',
        ).firstMatch(message)?.group(1);

  // Database, parser and platform exceptions can embed book content, paths or
  // channel arguments. Keep only recognized diagnostic phrases and codes.
  static String? _safeDartMessage(Object? error, OSError? fileError) {
    final raw = switch (error) {
      PlatformException(:final message) => message,
      FileSystemException(:final message) => fileError?.message ?? message,
      StateError(:final message) => message.toString(),
      FormatException(:final message) => message,
      _ => null,
    };
    if (raw == null) return null;
    final known = RegExp(
      r'permission denied|access is denied|operation not permitted|no such file or directory|the system cannot find the file specified|file not found|database is locked|database is closed|database disk image is malformed|invalid initial locator|readium reader (?:failed|disposed)|activity_unavailable|invalid_open_configuration|missing_file_path|missing_book_id|invalid_instance_id|invalid_channel_identity|unsupported_protocol|invalid_protocol|host_binding_unavailable|transport_unavailable|bridge_listener_unavailable',
      caseSensitive: false,
    ).firstMatch(raw)?.group(0);
    return known ??
        (fileError == null ? null : 'OS error ${fileError.errorCode}');
  }

  void _terminal(String result, [Map<String, Object?> fields = const {}]) {
    _finished = true;
    _elapsed.stop();
    _write({
      'kind': 'book_open_terminal',
      'result': result,
      'elapsedMs': _elapsed.elapsedMilliseconds,
      ..._facts,
      ...fields,
    }, level: result == 'failed' ? AppLogLevel.error : AppLogLevel.info);
  }

  void _write(
    Map<String, Object?> fields, {
    AppLogLevel level = AppLogLevel.info,
  }) {
    final message = jsonEncode({
      'originalFormat': _originalFormat,
      'readerFormat': 'EPUB',
      ...fields,
      'openAttemptId': id,
    });
    _log.appendDeferred(
      level: level,
      category: 'Reader.Open',
      message: message,
    );
    // Mirror the same sanitized event for read-only physical collection.
    // App LOG remains the existing owner and there is no second lifecycle.
    try {
      const chunkSize = 800;
      if (message.length <= chunkSize) {
        debugPrint('Reader.Open $message');
      } else {
        final count = (message.length + chunkSize - 1) ~/ chunkSize;
        for (var part = 0; part < count; part++) {
          final start = part * chunkSize;
          final end = start + chunkSize < message.length
              ? start + chunkSize
              : message.length;
          debugPrint(
            'Reader.Open.chunk $id $part/$count ${message.substring(start, end)}',
          );
        }
      }
    } on Object {
      // A diagnostic sink cannot change opening behavior.
    }
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:bibliolife/features/reader/domain/models/reader_settings.dart';
import 'package:bibliolife/features/reader/domain/repositories/reader_settings_repository.dart';
import 'package:path/path.dart' as path;

typedef ReaderSettingsDirectoryProvider = Future<Directory> Function();
typedef ReaderSettingsFileReplacer =
    Future<void> Function(File temporary, File destination);

/// Stores global renderer defaults without changing the existing Drift schema.
/// The profile key leaves room for future per-publication overrides while A1
/// deliberately preserves the application's current global settings scope.
class FileReaderSettingsRepository implements ReaderSettingsRepository {
  FileReaderSettingsRepository(
    this._directory, {
    ReaderSettingsFileReplacer? replaceFile,
  }) : _replaceFile = replaceFile ?? _replaceFileSafely;

  final ReaderSettingsDirectoryProvider _directory;
  final ReaderSettingsFileReplacer _replaceFile;
  Future<void> _writeTail = Future<void>.value();
  var _temporarySequence = 0;

  @override
  Future<ReaderSettingsState?> load(ReaderSettingsProfile profile) async {
    await _waitForWrites();
    final file = await _file();
    await _recoverInterruptedReplace(file);
    if (!await file.exists()) return null;
    try {
      final root = jsonDecode(await file.readAsString());
      if (root is! Map) return null;
      if (root['version'] != 1) return null;
      final profiles = root['profiles'];
      if (profiles is! Map) return null;
      final value = profiles[profile.name];
      if (value is! Map) return null;
      final state = ReaderSettingsState.fromJson(value.cast<String, Object?>());
      return state.profile == profile ? state : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(ReaderSettingsState settings) {
    final operation = _writeTail.then((_) => _saveNow(settings));
    _writeTail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _saveNow(ReaderSettingsState settings) async {
    final file = await _file();
    await _recoverInterruptedReplace(file);
    final profiles = <String, Object?>{};
    if (await file.exists()) {
      try {
        final root = jsonDecode(await file.readAsString());
        if (root is Map && root['version'] == 1 && root['profiles'] is Map) {
          profiles.addAll((root['profiles'] as Map).cast<String, Object?>());
        } else if (root is Map &&
            root['version'] is num &&
            root['version'] != 1) {
          throw UnsupportedError('unsupported_reader_settings_version');
        }
      } on Object {
        // A corrupt optional preferences file is replaced by valid settings,
        // but a future schema is preserved rather than destructively guessed.
        final root = await _decodedRoot(file);
        if (root?['version'] is num && root!['version'] != 1) rethrow;
      }
    }
    profiles[settings.profile.name] = _profileJson(settings);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp-${_temporarySequence++}');
    try {
      await temporary.writeAsString(
        jsonEncode(<String, Object?>{'version': 1, 'profiles': profiles}),
        encoding: utf8,
        flush: true,
      );
      await _replaceFile(temporary, file);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  /// Drift remains authoritative for the five legacy EPUB fields. The sidecar
  /// owns only the extended Readium values, so the two stores cannot disagree
  /// about theme, font size, line height, page margins, or publisher styles.
  Map<String, Object?> _profileJson(ReaderSettingsState settings) {
    if (settings.profile != ReaderSettingsProfile.readiumReflowable) {
      return settings.toJson();
    }
    return <String, Object?>{
      'profile': settings.profile.name,
      if (settings.typography case final typography?)
        'typography': <String, Object>{
          'fontFamily': typography.fontFamily.name,
          'fontWeight': typography.fontWeight,
        },
      if (settings.textLayout case final textLayout?)
        'textLayout': textLayout.toJson(),
    };
  }

  Future<void> _waitForWrites() async {
    try {
      await _writeTail;
    } on Object {
      // Individual save callers receive the error. A later read still returns
      // the last valid file.
    }
  }

  Future<Map<Object?, Object?>?> _decodedRoot(File file) async {
    try {
      final value = jsonDecode(await file.readAsString(encoding: utf8));
      return value is Map ? value : null;
    } on Object {
      return null;
    }
  }

  static Future<void> _replaceFileSafely(
    File temporary,
    File destination,
  ) async {
    final backup = File('${destination.path}.bak');
    if (await backup.exists()) await backup.delete();
    final hadDestination = await destination.exists();
    if (hadDestination) await destination.rename(backup.path);
    try {
      await temporary.rename(destination.path);
    } on Object {
      if (hadDestination && await backup.exists()) {
        await backup.rename(destination.path);
      }
      rethrow;
    }
    try {
      if (await backup.exists()) await backup.delete();
    } on FileSystemException {
      // The new live file is already committed. A leftover backup is harmless
      // and is cleaned on the next repository access.
    }
  }

  Future<void> _recoverInterruptedReplace(File file) async {
    final backup = File('${file.path}.bak');
    if (await file.exists()) {
      try {
        if (await backup.exists()) await backup.delete();
      } on FileSystemException {
        // A valid live file always wins over a stale cleanup artifact.
      }
      return;
    }
    if (await backup.exists()) await backup.rename(file.path);
  }

  Future<File> _file() async =>
      File(path.join((await _directory()).path, 'reader-settings-v1.json'));
}

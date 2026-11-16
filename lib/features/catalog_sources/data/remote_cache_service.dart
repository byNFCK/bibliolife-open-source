import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:bibliolife/core/performance/online_pipeline_performance.dart';
import 'package:bibliolife/features/catalog_sources/domain/remote_cache_budget.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

const remoteCacheFreeSpaceReserveBytes = 256 * 1024 * 1024;
const _cacheStorageChannel = MethodChannel('bibliolife/cache-storage');

class RemoteCacheSnapshot {
  const RemoteCacheSnapshot({
    required this.bytes,
    required this.entryCount,
    required this.maximumBytes,
  });

  final int bytes;
  final int entryCount;
  final int maximumBytes;
}

class RemoteMetadataCacheEntry {
  const RemoteMetadataCacheEntry({
    required this.bodyBytes,
    required this.expiresAt,
    this.etag,
    this.lastModified,
  });

  final Uint8List bodyBytes;
  final DateTime expiresAt;
  final String? etag;
  final String? lastModified;
}

typedef RemoteCoverFetcher = Future<Uint8List?> Function(Uri uri);

/// The single persistent cache for anonymous online Search data. It grows on
/// demand, stores only hashed keys, and is intentionally separate from local
/// imported books and their covers.
class RemoteCacheService {
  RemoteCacheService({
    Future<Directory> Function()? cacheDirectory,
    RemoteCoverFetcher? coverFetcher,
    Future<int?> Function()? availableBytes,
    DateTime Function()? now,
    bool? validateFetchedCovers,
    int? maximumBytes,
    int? coverMaximumBytes,
    int? metadataMaximumBytes,
    this.initialBudget,
  }) : _cacheDirectory = cacheDirectory ?? getApplicationCacheDirectory,
       _coverFetcher = coverFetcher ?? _downloadCover,
       _validateFetchedCovers = validateFetchedCovers ?? true,
       _availableBytes = availableBytes ?? _platformAvailableBytes,
       _now = now ?? DateTime.now,
       _budget = _customBudget(
         maximumBytes,
         coverMaximumBytes,
         metadataMaximumBytes,
       );

  final Future<Directory> Function() _cacheDirectory;
  final RemoteCoverFetcher _coverFetcher;
  final bool _validateFetchedCovers;
  final Future<int?> Function() _availableBytes;
  final DateTime Function() _now;
  RemoteCacheBudget _budget;
  final Future<RemoteCacheBudget>? initialBudget;
  final Map<String, Future<File?>> _coverRequests = {};
  Future<void>? _initialization;
  Future<void>? _trimLoop;
  bool _trimRequested = false;

  int get maximumBytes => _budget.maximumBytes;
  int get coverMaximumBytes => _budget.coverMaximumBytes;
  int get metadataMaximumBytes => _budget.metadataMaximumBytes;

  Future<void> updateBudget(RemoteCacheBudget budget) async {
    await _ensureInitialized();
    if (_budget == budget) return;
    _budget = budget;
    await _scheduleTrim();
  }

  Future<RemoteMetadataCacheEntry?> readMetadata(String key) async {
    await _ensureInitialized();
    final file = File(
      path.join((await _metadataDirectory()).path, '$key.json'),
    );
    try {
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (decoded['schema'] != 1) throw const FormatException();
      final body = decoded['body'] as String?;
      final expires = DateTime.tryParse(decoded['expiresAt'] as String? ?? '');
      if (body == null || expires == null) throw const FormatException();
      await file.setLastModified(_now());
      return RemoteMetadataCacheEntry(
        bodyBytes: Uint8List.fromList(base64Decode(body)),
        expiresAt: expires,
        etag: decoded['etag'] as String?,
        lastModified: decoded['lastModified'] as String?,
      );
    } on FileSystemException {
      return null;
    } on Object {
      await _deleteQuietly(file);
      return null;
    }
  }

  Future<void> writeMetadata(String key, RemoteMetadataCacheEntry entry) async {
    await _ensureInitialized();
    final body = entry.bodyBytes;
    if (body.length > 2 * 1024 * 1024) return;
    final directory = await _metadataDirectory();
    final file = File(path.join(directory.path, '$key.json'));
    final temporary = File('${file.path}.${_now().microsecondsSinceEpoch}.tmp');
    final encoded = jsonEncode({
      'schema': 1,
      'expiresAt': entry.expiresAt.toIso8601String(),
      'etag': entry.etag,
      'lastModified': entry.lastModified,
      'body': base64Encode(body),
    });
    try {
      if (!await _mayGrowBy(utf8.encode(encoded).length)) return;
      await temporary.writeAsString(encoded, flush: true);
      await _replaceAtomically(temporary, file);
      await _scheduleTrim();
    } catch (_) {
      await _deleteQuietly(temporary);
    }
  }

  Future<File?> cover(
    Uri uri, {
    OnlineSearchPerformanceSession? performanceSession,
  }) async {
    await _ensureInitialized();
    if (!_isSafeUri(uri)) return Future.value();
    final key = _key(uri.toString());
    final inFlight = _coverRequests[key];
    if (inFlight != null) {
      performanceSession?.recordCoverCache(state: 'miss', coalesced: true);
      return inFlight;
    }
    final request = Future<File?>.microtask(() async {
      try {
        final directory = await _coverDirectory();
        final file = File(path.join(directory.path, '$key.cover'));
        if (await file.exists()) {
          if (_validateFetchedCovers && !await _hasKnownImageFile(file)) {
            await _deleteQuietly(file);
          } else {
            await file.setLastModified(_now());
            performanceSession?.recordCoverCache(state: 'disk');
            return file;
          }
        }
        performanceSession?.recordCoverCache(state: 'miss');
        final bytes = await _coverFetcher(uri);
        if (bytes == null || bytes.isEmpty || bytes.length > 12 * 1024 * 1024) {
          return null;
        }
        if (_validateFetchedCovers && !_hasKnownImageBytes(bytes)) return null;
        if (!await _mayGrowBy(bytes.length)) return null;
        final temporary = File(
          '${file.path}.${_now().microsecondsSinceEpoch}.tmp',
        );
        try {
          await temporary.writeAsBytes(bytes, flush: true);
          await _replaceAtomically(temporary, file);
          await _trim();
          performanceSession?.recordCoverCache(state: 'disk', cacheWrite: true);
          return file;
        } catch (_) {
          await _deleteQuietly(temporary);
          return null;
        }
      } finally {
        _coverRequests.remove(key);
      }
    });
    _coverRequests[key] = request;
    return request;
  }

  /// Returns a ready disk-cache cover without starting a network request.
  ///
  /// Import uses this fast path so the foreground completion transition never
  /// waits for a cold remote image. A later background promotion can join
  /// [cover] when the image is not already present.
  Future<File?> cachedCover(Uri uri) async {
    await _ensureInitialized();
    if (!_isSafeUri(uri)) return null;
    final file = File(
      path.join(
        (await _coverDirectory()).path,
        '${_key(uri.toString())}.cover',
      ),
    );
    try {
      if (!await file.exists()) return null;
      if (_validateFetchedCovers && !await _hasKnownImageFile(file)) {
        await _deleteQuietly(file);
        return null;
      }
      await file.setLastModified(_now());
      return file;
    } on FileSystemException {
      return null;
    }
  }

  Future<RemoteCacheSnapshot> snapshot() async {
    await _ensureInitialized();
    final files = await _files();
    var bytes = 0;
    for (final file in files) {
      bytes += (await file.length());
    }
    return RemoteCacheSnapshot(
      bytes: bytes,
      entryCount: files.length,
      maximumBytes: maximumBytes,
    );
  }

  Future<void> clear() async {
    await _ensureInitialized();
    final root = await _rootDirectory();
    if (await root.exists()) await root.delete(recursive: true);
  }

  Future<Directory> _rootDirectory() async {
    final root = Directory(
      path.join((await _cacheDirectory()).path, 'remote_cache_v1'),
    );
    await root.create(recursive: true);
    return root;
  }

  Future<Directory> _metadataDirectory() async {
    final directory = Directory(
      path.join((await _rootDirectory()).path, 'metadata'),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> _coverDirectory() async {
    final directory = Directory(
      path.join((await _rootDirectory()).path, 'covers'),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> _trim() async {
    final files = await _files();
    final metadata = files
        .where((file) => file.path.endsWith('.json'))
        .toList();
    final covers = files.where((file) => file.path.endsWith('.cover')).toList();
    await _trimFiles(metadata, metadataMaximumBytes);
    await _trimFiles(covers, coverMaximumBytes);
    await _trimFiles(await _files(), maximumBytes);
  }

  Future<void> _ensureInitialized() => _initialization ??=
      (initialBudget ?? Future.value(_budget)).then((budget) async {
        _budget = budget;
        await _scheduleTrim();
      });

  /// One cleanup loop absorbs a burst of selector changes. Each pass reads the
  /// newest budget, so an older request can never trim against a stale value.
  Future<void> _scheduleTrim() {
    _trimRequested = true;
    final active = _trimLoop;
    if (active != null) return active;
    final loop = Future<void>(() async {
      do {
        _trimRequested = false;
        await _trim();
      } while (_trimRequested);
    });
    _trimLoop = loop;
    return loop.whenComplete(() => _trimLoop = null);
  }

  static RemoteCacheBudget _customBudget(
    int? maximumBytes,
    int? coverMaximumBytes,
    int? metadataMaximumBytes,
  ) {
    if (maximumBytes == null &&
        coverMaximumBytes == null &&
        metadataMaximumBytes == null) {
      return const RemoteCacheBudget.defaultValue();
    }
    final maximum =
        maximumBytes ?? (coverMaximumBytes ?? 0) + (metadataMaximumBytes ?? 0);
    // Test-only custom capacities retain the caller's total; production uses
    // the validated persisted policy above.
    return RemoteCacheBudget.forMaximumBytes(maximum);
  }

  Future<void> _trimFiles(List<File> files, int limit) async {
    final entries = <(File, FileStat)>[];
    var bytes = 0;
    for (final file in files) {
      final stat = await file.stat();
      entries.add((file, stat));
      bytes += stat.size;
    }
    entries.sort(
      (left, right) => left.$2.modified.compareTo(right.$2.modified),
    );
    for (final entry in entries) {
      if (bytes <= limit) break;
      bytes -= entry.$2.size;
      await _deleteQuietly(entry.$1);
    }
  }

  Future<List<File>> _files() async {
    final root = await _rootDirectory();
    if (!await root.exists()) return const [];
    return root
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File && !entity.path.endsWith('.tmp'))
        .cast<File>()
        .toList();
  }

  Future<bool> _mayGrowBy(int bytes) async {
    final available = await _availableBytes();
    // Disk growth is Android-only until another platform provides the same
    // free-space contract. Never risk a write without a reserve measurement.
    if (available == null) return false;
    if (available >= bytes + remoteCacheFreeSpaceReserveBytes) return true;
    await _trimFiles(await _files(), 0);
    final availableAfterTrim = await _availableBytes();
    return availableAfterTrim != null &&
        availableAfterTrim >= bytes + remoteCacheFreeSpaceReserveBytes;
  }

  static Future<void> _replaceAtomically(
    File temporary,
    File destination,
  ) async {
    if (await destination.exists()) await destination.delete();
    await temporary.rename(destination.path);
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // A concurrent cleanup can win the race.
    }
  }

  static bool _isSafeUri(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !uri.queryParameters.keys.any(_isSensitiveParameter);

  static bool _isSensitiveParameter(String name) {
    final normalized = name.toLowerCase();
    return normalized == 'key' ||
        normalized.contains('token') ||
        normalized.contains('signature') ||
        normalized == 'sig' ||
        normalized.startsWith('x-amz-');
  }

  static String _key(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  static Future<Uint8List?> _downloadCover(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.acceptHeader, 'image/*');
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final contentType = response.headers.contentType?.mimeType.toLowerCase();
      if (contentType != null && !contentType.startsWith('image/')) return null;
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        bytes.add(chunk);
        if (bytes.length > 12 * 1024 * 1024) return null;
      }
      final result = bytes.takeBytes();
      return _hasKnownImageBytes(result) ? result : null;
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<bool> _hasKnownImageFile(File file) async {
    try {
      final bytes = <int>[];
      await for (final chunk in file.openRead(0, 16)) {
        bytes.addAll(chunk);
        if (bytes.length >= 16) break;
      }
      return _hasKnownImageBytes(bytes);
    } on FileSystemException {
      return false;
    }
  }

  static bool _hasKnownImageBytes(List<int> bytes) {
    final png =
        bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a;
    final jpeg =
        bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff;
    final gif =
        bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38 &&
        (bytes[4] == 0x37 || bytes[4] == 0x39) &&
        bytes[5] == 0x61;
    final webp =
        bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    return png || jpeg || gif || webp;
  }

  static Future<int?> _platformAvailableBytes() async {
    try {
      return await _cacheStorageChannel.invokeMethod<int>('availableBytes');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

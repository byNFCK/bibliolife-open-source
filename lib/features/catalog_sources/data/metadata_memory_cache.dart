class MetadataMemoryCacheEntry<T> {
  const MetadataMemoryCacheEntry({
    required this.value,
    required this.expiresAt,
    required this.bytes,
    this.etag,
    this.lastModified,
  });
  final T value;
  final DateTime expiresAt;
  final int bytes;
  final String? etag;
  final String? lastModified;
}

/// Process-local LRU cache. Keys are supplied by the transport layer and must
/// already be credential-safe for diagnostics.
class MetadataMemoryCache {
  MetadataMemoryCache({
    this.maximumEntries = 128,
    this.maximumBytes = 16 * 1024 * 1024,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  final int maximumEntries;
  final int maximumBytes;
  final DateTime Function() _now;
  final _entries = <String, MetadataMemoryCacheEntry<Object>>{};
  var _bytes = 0;
  var evictionCount = 0;
  MetadataMemoryCacheEntry<T>? get<T>(String key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    _entries[key] = entry;
    return entry as MetadataMemoryCacheEntry<T>;
  }

  bool isFresh(MetadataMemoryCacheEntry<Object> entry) =>
      !_now().isAfter(entry.expiresAt);
  void put<T>(String key, MetadataMemoryCacheEntry<T> entry) {
    final old = _entries.remove(key);
    if (old != null) _bytes -= old.bytes;
    _entries[key] = entry as MetadataMemoryCacheEntry<Object>;
    _bytes += entry.bytes;
    while (_entries.length > maximumEntries || _bytes > maximumBytes) {
      final oldest = _entries.keys.first;
      _bytes -= _entries.remove(oldest)!.bytes;
      evictionCount++;
    }
  }

  int get cachedBytes => _bytes;
}

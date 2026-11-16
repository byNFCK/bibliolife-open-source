const remoteCacheMegabyteBytes = 1024 * 1024;
const remoteCacheDefaultMaximumBytes = 1280 * remoteCacheMegabyteBytes;
const remoteCacheMinimumMaximumBytes = 512 * remoteCacheMegabyteBytes;
const remoteCacheMaximumMaximumBytes = 2048 * remoteCacheMegabyteBytes;

/// Immutable, validated capacity and deterministic sub-budgets for the one
/// disk cache used by online catalog data.
class RemoteCacheBudget {
  const RemoteCacheBudget._(this.maximumBytes);

  factory RemoteCacheBudget.fromStored(int? maximumBytes) {
    switch (maximumBytes) {
      case remoteCacheMinimumMaximumBytes:
      case remoteCacheDefaultMaximumBytes:
      case remoteCacheMaximumMaximumBytes:
        return RemoteCacheBudget._(maximumBytes!);
      default:
        return const RemoteCacheBudget._(remoteCacheDefaultMaximumBytes);
    }
  }

  /// Used only by the cache's focused low-byte tests. Persisted values must
  /// always enter through [fromStored].
  factory RemoteCacheBudget.forMaximumBytes(int maximumBytes) =>
      RemoteCacheBudget._(maximumBytes);

  const RemoteCacheBudget.defaultValue()
    : maximumBytes = remoteCacheDefaultMaximumBytes;

  final int maximumBytes;

  /// Keeps the established 1100 / 1280 cover allocation proportion.
  int get coverMaximumBytes => maximumBytes * 1100 ~/ 1280;
  int get metadataMaximumBytes => maximumBytes - coverMaximumBytes;

  @override
  bool operator ==(Object other) =>
      other is RemoteCacheBudget && other.maximumBytes == maximumBytes;

  @override
  int get hashCode => maximumBytes.hashCode;
}

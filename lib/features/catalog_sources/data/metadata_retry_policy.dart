import 'dart:math';

/// Central retry decision for metadata transport. Parsing and cancellation are
/// deliberately excluded from retries.
class MetadataRetryPolicy {
  const MetadataRetryPolicy({
    this.maximumRetries = 2,
    this.baseDelay = const Duration(milliseconds: 350),
    this.maxDelay = const Duration(seconds: 4),
  });
  final int maximumRetries;
  final Duration baseDelay;
  final Duration maxDelay;

  bool shouldRetryStatus(int statusCode, int completedRetries) =>
      completedRetries < maximumRetries &&
      const {429, 502, 503, 504}.contains(statusCode);

  Duration delayFor(int retry, {Duration? retryAfter}) {
    if (retryAfter != null && retryAfter >= Duration.zero) return retryAfter;
    final milliseconds = min(
      maxDelay.inMilliseconds,
      baseDelay.inMilliseconds * (1 << retry),
    );
    return Duration(milliseconds: milliseconds);
  }
}

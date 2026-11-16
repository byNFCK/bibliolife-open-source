import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Enables concise, device-local online pipeline measurements.
///
/// This is deliberately a compile-time flag so normal builds do not allocate
/// sessions, stopwatches, request fingerprints, or log strings.
const biblioLifeNetPerfLogsEnabled = bool.fromEnvironment(
  'BIBLIOLIFE_NET_PERF_LOGS',
  defaultValue: false,
);

/// Enables lifecycle and per-request lines in addition to the aggregate search
/// summary. Verbose telemetry never enables output by itself.
const biblioLifeNetPerfVerboseLogsEnabled =
    biblioLifeNetPerfLogsEnabled &&
    bool.fromEnvironment(
      'BIBLIOLIFE_NET_PERF_VERBOSE_LOGS',
      defaultValue: false,
    );

/// Frame timings are collected only for opt-in profile runs. Keeping this
/// separate from the verbose flag makes the normal diagnostic build cheap.
const biblioLifeSearchFrameMetricsEnabled =
    biblioLifeNetPerfLogsEnabled &&
    bool.fromEnvironment(
      'BIBLIOLIFE_SEARCH_FRAME_METRICS',
      defaultValue: false,
    );

typedef OnlinePerformanceLog = void Function(String message);

/// Emits a profile-safe lifecycle checkpoint for the focused Search benchmark.
///
/// This intentionally uses [print] instead of [debugPrint]: profile runners
/// consistently forward it, and this function is unreachable in normal builds
/// unless the primary compile-time telemetry flag is enabled.
void searchPerformanceHealth(
  String event, {
  Map<String, Object?> fields = const {},
}) {
  if (!biblioLifeNetPerfLogsEnabled) return;
  final suffix = fields.entries
      .where((entry) => entry.value != null)
      .map((entry) => '${entry.key}=${entry.value}')
      .join(' ');
  final message =
      'SEARCH_PERF_HEALTH $event${suffix.isEmpty ? '' : ' $suffix'}';
  // Profile runner health check; this branch is compile-time disabled by default.
  // ignore: avoid_print
  print(message);
  developer.log(message, name: 'SEARCH_PERF');
}

/// Emits a credential-safe verbose lifecycle boundary for a focused profile run.
void onlinePerformanceMarker(
  String name, {
  Map<String, Object?> fields = const {},
}) {
  if (!biblioLifeNetPerfVerboseLogsEnabled) return;
  final suffix = fields.entries
      .where((entry) => entry.value != null)
      .map((entry) => '${entry.key}=${entry.value}')
      .join(' ');
  final message = 'SEARCH_PERF_MARKER $name${suffix.isEmpty ? '' : ' $suffix'}';
  debugPrint(message);
  developer.log(message, name: 'SEARCH_PERF');
  developer.Timeline.instantSync(name, arguments: fields);
}

/// A short-lived counter set for one submitted online search.
///
/// It is owned by [MultiCatalogSearchController] and is finished only when the
/// query is replaced or the controller is disposed. This allows cover loads
/// occurring after source responses to contribute to the same summary.
class OnlineSearchPerformanceSession {
  OnlineSearchPerformanceSession({required this.id, OnlinePerformanceLog? log})
    : _log = log ?? _profileLog,
      _elapsed = Stopwatch()..start() {
    if (biblioLifeSearchFrameMetricsEnabled) {
      _frameCollector = _SearchFrameTimingCollector(
        onRegistered: () =>
            searchPerformanceHealth('frame_callback_registered'),
        onFirstBatch: (frameCount) => searchPerformanceHealth(
          'first_frame_batch',
          fields: {'frames': frameCount},
        ),
      );
    }
  }

  final String id;
  final OnlinePerformanceLog _log;
  final Stopwatch _elapsed;
  final Map<String, Stopwatch> _sourceStopwatches = {};
  final Map<String, int> _sourceDurationsMs = {};
  final Map<String, int> _recentFingerprintsMs = {};
  _SearchFrameTimingCollector? _frameCollector;

  int participatingSourceCount = 0;
  int networkRequestCount = 0;
  int duplicateRequestCount = 0;
  int cancelledRequestCount = 0;
  int staleResponseCount = 0;
  int cacheHitCount = 0;
  int cacheMissCount = 0;
  int cacheRevalidationCount = 0;
  int cache304Count = 0;
  int cacheEvictionCount = 0;
  int cachedBytes = 0;
  int retryScheduledCount = 0;
  int requestsAvoidedByCache = 0;
  int retryCompletedCount = 0;
  int retryCancelledCount = 0;
  int retryAfterUsageCount = 0;
  int sourceRecordCount = 0;
  int canonicalResultCount = 0;
  int mergedRecordCount = 0;
  int rejectedMergeCount = 0;
  int canonicalComparisonCount = 0;
  int normalizationCallCount = 0;
  int isbnConversionCount = 0;
  int canonicalObjectCount = 0;
  int parserDurationMs = 0;
  int canonicalDurationMs = 0;
  int rankDurationMs = 0;
  int stateEmissionCount = 0;
  int wholeListReplacementCount = 0;
  int canonicalMaterializationCount = 0;
  int unifiedAssemblerExecutionCount = 0;
  int localIdentityIndexConstructionCount = 0;
  int appendedPaginationBatchCount = 0;
  int individualItemReplacementCount = 0;
  int visibleCardBuildCount = 0;
  int duplicatedPaginationRequestCount = 0;
  final Map<String, int> paginationRequestsBySource = {};
  int coverRequestCount = 0;
  int coverMemoryHitCount = 0;
  int coverDiskHitCount = 0;
  int coverMissCount = 0;
  int coalescedCoverSubscriberCount = 0;
  int duplicatePhysicalCoverDownloadCount = 0;
  int imageDecodeCount = 0;
  int cacheWriteCount = 0;
  int coverLoadSuccessCount = 0;
  int coverLoadFailureCount = 0;
  int coordinatorQueuedCount = 0;
  int coordinatorQueuedCancelledCount = 0;
  int coordinatorStartedCount = 0;
  int coordinatorCoalescedCallerCount = 0;
  int transportAbortedCount = 0;
  int timeoutCount = 0;
  int activeNetworkRequests = 0;
  int peakNetworkRequests = 0;
  int activeSourceSearches = 0;
  int peakSourceSearches = 0;
  int? _firstVisibleResultMs;
  var _finished = false;

  static void _profileLog(String message) {
    // Profile runner summary; this branch is compile-time disabled by default.
    // ignore: avoid_print
    print(message);
    developer.log(message, name: 'SEARCH_PERF');
  }

  void configureSources(int count) => participatingSourceCount = count;

  void sourceStarted(String sourceId) {
    if (_finished) return;
    _sourceStopwatches[sourceId] = Stopwatch()..start();
    activeSourceSearches++;
    if (activeSourceSearches > peakSourceSearches) {
      peakSourceSearches = activeSourceSearches;
    }
  }

  void sourceFinished(String sourceId, {required int recordCount}) {
    if (_finished) return;
    sourceRecordCount += recordCount;
    _finishSource(sourceId);
  }

  void sourceFailed(String sourceId) {
    if (_finished) return;
    _finishSource(sourceId);
  }

  void recordCancellationRequested() {
    if (!_finished) cancelledRequestCount++;
  }

  void recordStaleResponse() {
    if (!_finished) staleResponseCount++;
  }

  void recordStateEmission({bool wholeListReplacement = false}) {
    if (_finished) return;
    stateEmissionCount++;
    if (wholeListReplacement) wholeListReplacementCount++;
  }

  void recordFirstVisibleResultCandidate() {
    _firstVisibleResultMs ??= _elapsed.elapsedMilliseconds;
  }

  void recordCanonicalMaterialization() {
    if (!_finished) canonicalMaterializationCount++;
  }

  void recordUnifiedAssemblerExecution() {
    if (!_finished) unifiedAssemblerExecutionCount++;
  }

  void recordLocalIdentityIndexConstruction() {
    if (!_finished) localIdentityIndexConstructionCount++;
  }

  void recordPaginationRequest(String sourceId, {bool duplicate = false}) {
    if (_finished) return;
    paginationRequestsBySource.update(
      sourceId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    if (duplicate) duplicatedPaginationRequestCount++;
  }

  void recordPaginationBatchAppended() {
    if (!_finished) appendedPaginationBatchCount++;
  }

  void recordIndividualItemReplacement(int count) {
    if (!_finished) individualItemReplacementCount += count;
  }

  void recordVisibleCardBuild() {
    if (!_finished) visibleCardBuildCount++;
  }

  void recordCoverCache({
    required String state,
    bool coalesced = false,
    bool physicalDownload = false,
    bool cacheWrite = false,
  }) {
    if (_finished) return;
    switch (state) {
      case 'memory':
        coverMemoryHitCount++;
        break;
      case 'disk':
        coverDiskHitCount++;
        break;
      case 'miss':
        coverMissCount++;
        break;
    }
    if (coalesced) coalescedCoverSubscriberCount++;
    if (physicalDownload) duplicatePhysicalCoverDownloadCount++;
    if (cacheWrite) cacheWriteCount++;
  }

  void recordImageDecode() {
    if (!_finished) imageDecodeCount++;
  }

  void recordCoordinatorEvent(String event) {
    if (_finished) return;
    switch (event) {
      case 'queued':
        coordinatorQueuedCount++;
        break;
      case 'queuedCancelled':
        coordinatorQueuedCancelledCount++;
        break;
      case 'started':
        coordinatorStartedCount++;
        break;
      case 'coalesced':
        coordinatorCoalescedCallerCount++;
        break;
      case 'aborted':
        transportAbortedCount++;
        break;
      case 'timeout':
        timeoutCount++;
        break;
      case 'revalidation':
        cacheRevalidationCount++;
        break;
      case 'cache304':
        cache304Count++;
        break;
      case 'retry':
        retryScheduledCount++;
        break;
      case 'cacheAvoided':
        requestsAvoidedByCache++;
        break;
      case 'retryCompleted':
        retryCompletedCount++;
        break;
      case 'retryCancelled':
        retryCancelledCount++;
        break;
      case 'retryAfter':
        retryAfterUsageCount++;
        break;
      default:
        break;
    }
  }

  void recordCacheState({required int evictions, required int bytes}) {
    if (_finished) return;
    cacheEvictionCount = evictions;
    cachedBytes = bytes;
  }

  void recordParser({
    required String sourceId,
    required String parser,
    required int responseBytes,
    required int itemCount,
    required Duration decode,
    required Duration mapping,
    Duration parse = Duration.zero,
    Duration extract = Duration.zero,
    int skippedItemCount = 0,
    String execution = 'local',
  }) {
    if (_finished) return;
    final total = decode + parse + extract + mapping;
    parserDurationMs += total.inMilliseconds;
    if (biblioLifeNetPerfVerboseLogsEnabled) {
      _log(
        'PARSER_PERF session=$id source=$sourceId bytes=$responseBytes decodeMicros=${decode.inMicroseconds} parseMicros=${parse.inMicroseconds} extractMicros=${extract.inMicroseconds} mapMicros=${mapping.inMicroseconds} totalMicros=${total.inMicroseconds} itemCount=$itemCount skippedItemCount=$skippedItemCount',
      );
    }
  }

  void recordCanonical({
    required int inputRecordCount,
    required int resultCount,
    required int mergedCount,
    required int rejectedCount,
    required int comparisonCount,
    required int normalizationCalls,
    required int isbnConversions,
    required Duration mergeDuration,
  }) {
    if (_finished) return;
    canonicalResultCount = resultCount;
    mergedRecordCount += mergedCount;
    rejectedMergeCount += rejectedCount;
    canonicalComparisonCount += comparisonCount;
    normalizationCallCount += normalizationCalls;
    isbnConversionCount += isbnConversions;
    canonicalObjectCount += resultCount;
    canonicalDurationMs += mergeDuration.inMilliseconds;
    if (biblioLifeNetPerfVerboseLogsEnabled) {
      _log(
        'CANONICAL_PERF session=$id inputRecords=$inputRecordCount results=$resultCount comparisons=$comparisonCount merges=$mergedCount rejected=$rejectedCount durationMs=${mergeDuration.inMilliseconds}',
      );
    }
  }

  void recordRanking(Duration duration) {
    if (!_finished) rankDurationMs += duration.inMilliseconds;
  }

  OnlineNetworkRequestMetric networkStarted({
    required String sourceId,
    required String method,
    required Uri uri,
  }) {
    final fingerprint = sanitizedRequestFingerprint(
      sourceId: sourceId,
      method: method,
      uri: uri,
    );
    final now = _elapsed.elapsedMilliseconds;
    final previous = _recentFingerprintsMs[fingerprint];
    if (previous != null && now - previous <= 3000) duplicateRequestCount++;
    _recentFingerprintsMs[fingerprint] = now;
    networkRequestCount++;
    activeNetworkRequests++;
    if (activeNetworkRequests > peakNetworkRequests) {
      peakNetworkRequests = activeNetworkRequests;
    }
    if (biblioLifeNetPerfVerboseLogsEnabled) {
      _log(
        'NETWORK_PERF session=$id phase=start source=$sourceId active=$activeNetworkRequests',
      );
    }
    return OnlineNetworkRequestMetric._(this, sourceId, method, uri);
  }

  void recordCoverRequest({
    required String sourceId,
    required String remoteId,
    required Uri uri,
    required int? cacheWidth,
    required int? cacheHeight,
  }) {
    if (_finished) return;
    coverRequestCount++;
    if (biblioLifeNetPerfVerboseLogsEnabled) {
      _log(
        'COVER_PERF session=$id phase=request source=$sourceId cacheWidth=${cacheWidth ?? 'none'} cacheHeight=${cacheHeight ?? 'none'}',
      );
    }
  }

  void recordCoverCompleted({
    required String sourceId,
    required String remoteId,
    required Uri uri,
  }) {
    if (_finished) return;
    coverLoadSuccessCount++;
    if (biblioLifeNetPerfVerboseLogsEnabled) {
      _log('COVER_PERF session=$id phase=completed source=$sourceId');
    }
  }

  void recordCoverFailed({
    required String sourceId,
    required String remoteId,
    required Uri uri,
    required String reason,
  }) {
    if (_finished) return;
    coverLoadFailureCount++;
    if (biblioLifeNetPerfVerboseLogsEnabled) {
      _log(
        'COVER_PERF session=$id phase=failed source=$sourceId reason=$reason',
      );
    }
  }

  void finish({required String reason}) {
    if (_finished) return;
    _finished = true;
    final frameSummary = _frameCollector?.finish();
    for (final sourceId in _sourceStopwatches.keys.toList(growable: false)) {
      _finishSource(sourceId);
    }
    _elapsed.stop();
    final sourceDurations = _sourceDurationsMs.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .join(',');
    final paginationRequests = paginationRequestsBySource.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .join(',');
    _log(
      // Version 3 keeps one runner line below Android's truncation limit.
      // Groups are fixed-order aggregate counters: net=requests,duplicates,
      // cancellations,stale; cache=hits,misses,revalidations,304,evictions,
      // bytes,avoided; retry=scheduled,completed,cancelled,retryAfter;
      // res=records,canonical,merged,rejected,comparisons,normalizations,isbn;
      // state=emissions,wholeList,materializations,assemblers,identityIndexes,
      // appendedPages,itemReplacements,visibleCards; coord=queued,
      // queuedCancelled,started,coalesced,aborted,timeouts; cover=requests,
      // memory,disk,misses,coalesced,duplicateDownloads,decodes,writes,
      // success,failure. No user or publication data is included.
      'SEARCH_PERF_SUMMARY v=3 s=$id r=$reason src=$participatingSourceCount '
      'd=${_elapsed.elapsedMilliseconds} fvr=${_firstVisibleResultMs ?? 'none'} '
      'sd=${sourceDurations.isEmpty ? 'none' : sourceDurations} '
      'net=$networkRequestCount,$duplicateRequestCount,$cancelledRequestCount,$staleResponseCount '
      'cache=$cacheHitCount,$cacheMissCount,$cacheRevalidationCount,$cache304Count,$cacheEvictionCount,$cachedBytes,$requestsAvoidedByCache '
      'retry=$retryScheduledCount,$retryCompletedCount,$retryCancelledCount,$retryAfterUsageCount '
      'res=$sourceRecordCount,$canonicalResultCount,$mergedRecordCount,$rejectedMergeCount,$canonicalComparisonCount,$normalizationCallCount,$isbnConversionCount '
      'cpu=$parserDurationMs,$canonicalDurationMs,$rankDurationMs '
      'state=$stateEmissionCount,$wholeListReplacementCount,$canonicalMaterializationCount,$unifiedAssemblerExecutionCount,$localIdentityIndexConstructionCount,$appendedPaginationBatchCount,$individualItemReplacementCount,$visibleCardBuildCount '
      'page=${paginationRequests.isEmpty ? 'none' : paginationRequests},$duplicatedPaginationRequestCount '
      'coord=$coordinatorQueuedCount,$coordinatorQueuedCancelledCount,$coordinatorStartedCount,$coordinatorCoalescedCallerCount,$transportAbortedCount,$timeoutCount '
      'cover=$coverRequestCount,$coverMemoryHitCount,$coverDiskHitCount,$coverMissCount,$coalescedCoverSubscriberCount,$duplicatePhysicalCoverDownloadCount,$imageDecodeCount,$cacheWriteCount,$coverLoadSuccessCount,$coverLoadFailureCount '
      'peak=$peakNetworkRequests,$peakSourceSearches '
      '${frameSummary ?? 'frames=disabled'}',
    );
  }

  void _finishSource(String sourceId) {
    final stopwatch = _sourceStopwatches.remove(sourceId);
    if (stopwatch == null) return;
    stopwatch.stop();
    _sourceDurationsMs[sourceId] = stopwatch.elapsedMilliseconds;
    if (activeSourceSearches > 0) activeSourceSearches--;
  }
}

class _SearchFrameTimingCollector {
  _SearchFrameTimingCollector({
    required this.onRegistered,
    required this.onFirstBatch,
  }) {
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    onRegistered();
  }

  final void Function() onRegistered;
  final void Function(int frameCount) onFirstBatch;
  final List<int> _buildMicros = [];
  final List<int> _rasterMicros = [];
  final List<int> _totalMicros = [];
  var _receivedFirstBatch = false;

  void _onTimings(List<FrameTiming> timings) {
    if (!_receivedFirstBatch && timings.isNotEmpty) {
      _receivedFirstBatch = true;
      onFirstBatch(timings.length);
    }
    for (final timing in timings) {
      _buildMicros.add(timing.buildDuration.inMicroseconds);
      _rasterMicros.add(timing.rasterDuration.inMicroseconds);
      _totalMicros.add(timing.totalSpan.inMicroseconds);
    }
  }

  String finish() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    final total = List<int>.from(_totalMicros)..sort();
    final build = List<int>.from(_buildMicros)..sort();
    final raster = List<int>.from(_rasterMicros)..sort();
    final janky = total.where((value) => value > 16667).length;
    return 'frm=${total.length};b=${_percentile(build, 50)}/${_percentile(build, 90)}/${_percentile(build, 99)};r=${_percentile(raster, 50)}/${_percentile(raster, 90)}/${_percentile(raster, 99)};t=${_percentile(total, 50)}/${_percentile(total, 90)}/${_percentile(total, 99)};max=${_milliseconds(total.isEmpty ? 0 : total.last)};over=${total.where((value) => value > 16667).length}/${total.where((value) => value > 33333).length}/${total.where((value) => value > 100000).length};j=${total.isEmpty ? '0.0' : (janky * 100 / total.length).toStringAsFixed(1)}';
  }

  String _percentile(List<int> values, int percentile) {
    if (values.isEmpty) return 'none';
    final index = ((values.length - 1) * percentile / 100).ceil();
    return _milliseconds(values[index]);
  }

  String _milliseconds(int micros) => (micros / 1000).toStringAsFixed(2);
}

class OnlineNetworkRequestMetric {
  OnlineNetworkRequestMetric._(
    this._session,
    this.sourceId,
    this.method,
    this.uri,
  ) : _elapsed = Stopwatch()..start();

  final OnlineSearchPerformanceSession _session;
  final String sourceId;
  final String method;
  final Uri uri;
  final Stopwatch _elapsed;
  var _completed = false;

  void completed({required int statusCode, required int responseBytes}) {
    if (_completed) return;
    _completed = true;
    _elapsed.stop();
    if (_session.activeNetworkRequests > 0) {
      _session.activeNetworkRequests--;
    }
    if (biblioLifeNetPerfVerboseLogsEnabled) {
      _session._log(
        'NETWORK_PERF session=${_session.id} phase=complete source=$sourceId status=$statusCode bytes=$responseBytes durationMs=${_elapsed.elapsedMilliseconds} active=${_session.activeNetworkRequests}',
      );
    }
  }

  void failed(String failure) {
    if (_completed) return;
    _completed = true;
    _elapsed.stop();
    if (_session.activeNetworkRequests > 0) {
      _session.activeNetworkRequests--;
    }
    if (biblioLifeNetPerfVerboseLogsEnabled) {
      _session._log(
        'NETWORK_PERF session=${_session.id} phase=failed source=$sourceId failure=$failure durationMs=${_elapsed.elapsedMilliseconds} active=${_session.activeNetworkRequests}',
      );
    }
  }
}

/// Propagates a search session through the existing async transport without
/// changing any production method signatures.
class OnlinePerformanceScope {
  const OnlinePerformanceScope._();

  static final _sessionKey = Object();
  static final _sourceKey = Object();

  static OnlineSearchPerformanceSession? get session =>
      Zone.current[_sessionKey] as OnlineSearchPerformanceSession?;

  static String get sourceId => Zone.current[_sourceKey] as String? ?? 'none';

  static Future<T> run<T>(
    OnlineSearchPerformanceSession? performance,
    String sourceId,
    Future<T> Function() action,
  ) {
    if (performance == null) return action();
    return runZoned(
      action,
      zoneValues: {_sessionKey: performance, _sourceKey: sourceId},
    );
  }
}

String sanitizedUri(Uri uri) => '${uri.scheme}://${uri.host}${uri.path}';

String sanitizedRequestFingerprint({
  required String sourceId,
  required String method,
  required Uri uri,
}) {
  final entries = <String>[];
  for (final entry in uri.queryParametersAll.entries) {
    if (_isSensitiveParameter(entry.key)) continue;
    final values = [...entry.value]..sort();
    entries.add('${entry.key}=${values.join(',')}');
  }
  entries.sort();
  return '$sourceId|${method.toUpperCase()}|${uri.host.toLowerCase()}${uri.path}?${entries.join('&')}';
}

bool _isSensitiveParameter(String name) {
  final normalized = name.toLowerCase();
  return normalized == 'key' ||
      normalized.contains('token') ||
      normalized.contains('signature') ||
      normalized == 'sig' ||
      normalized.startsWith('x-amz-');
}

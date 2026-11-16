/// Format-agnostic reader search state. Native/readium types stop at the adapter.
sealed class ReaderSearchState {
  const ReaderSearchState();

  String get query;
}

final class ReaderSearchIdle extends ReaderSearchState {
  const ReaderSearchIdle();

  @override
  String get query => '';
}

final class ReaderSearchLoading extends ReaderSearchState {
  const ReaderSearchLoading({required this.query});

  @override
  final String query;
}

final class ReaderSearchReady extends ReaderSearchState {
  ReaderSearchReady({
    required this.query,
    required List<ReaderSearchResult> results,
    required this.isComplete,
  }) : results = List.unmodifiable(results);

  @override
  final String query;
  final List<ReaderSearchResult> results;
  final bool isComplete;
}

final class ReaderSearchEmpty extends ReaderSearchState {
  const ReaderSearchEmpty({required this.query});

  @override
  final String query;
}

final class ReaderSearchFailure extends ReaderSearchState {
  const ReaderSearchFailure({required this.query, required this.error});

  @override
  final String query;
  final ReaderSearchError error;
}

final class ReaderSearchResult {
  const ReaderSearchResult({
    required this.id,
    this.title,
    this.before,
    this.match,
    this.after,
    this.position,
    this.progression,
  });

  final String id;
  final String? title;
  final String? before;
  final String? match;
  final String? after;
  final int? position;
  final double? progression;
}

final class ReaderSearchError {
  const ReaderSearchError({required this.code, this.retryable = true});

  final String code;
  final bool retryable;
}

enum ReaderSearchCommandStatus {
  started,
  accepted,
  completed,
  cleared,
  cancelled,
  failed,
  unsupported,
  stale,
  disposed,
}

final class ReaderSearchCommandResult {
  const ReaderSearchCommandResult(this.status, {this.errorCode});

  const ReaderSearchCommandResult.started()
    : this(ReaderSearchCommandStatus.started);
  const ReaderSearchCommandResult.completed()
    : this(ReaderSearchCommandStatus.completed);
  const ReaderSearchCommandResult.unsupported()
    : this(ReaderSearchCommandStatus.unsupported);
  const ReaderSearchCommandResult.disposed()
    : this(ReaderSearchCommandStatus.disposed);
  const ReaderSearchCommandResult.stale()
    : this(ReaderSearchCommandStatus.stale);

  final ReaderSearchCommandStatus status;
  final String? errorCode;

  bool get isSuccess => const {
    ReaderSearchCommandStatus.started,
    ReaderSearchCommandStatus.accepted,
    ReaderSearchCommandStatus.completed,
    ReaderSearchCommandStatus.cleared,
    ReaderSearchCommandStatus.cancelled,
  }.contains(status);
}

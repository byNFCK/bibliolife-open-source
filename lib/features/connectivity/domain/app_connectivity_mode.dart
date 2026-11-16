enum AppConnectivityMode { offline, online }

class AppConnectivityState {
  const AppConnectivityState({
    required this.mode,
    required this.hasAcknowledgedOnline,
    this.isLoaded = false,
    this.isPersisting = false,
    this.error,
  });

  const AppConnectivityState.offline()
    : mode = AppConnectivityMode.offline,
      hasAcknowledgedOnline = false,
      isLoaded = false,
      isPersisting = false,
      error = null;

  final AppConnectivityMode mode;
  final bool hasAcknowledgedOnline;
  final bool isLoaded;
  final bool isPersisting;
  final Object? error;

  AppConnectivityState copyWith({
    AppConnectivityMode? mode,
    bool? hasAcknowledgedOnline,
    bool? isLoaded,
    bool? isPersisting,
    Object? error,
  }) => AppConnectivityState(
    mode: mode ?? this.mode,
    hasAcknowledgedOnline: hasAcknowledgedOnline ?? this.hasAcknowledgedOnline,
    isLoaded: isLoaded ?? this.isLoaded,
    isPersisting: isPersisting ?? this.isPersisting,
    error: error,
  );
}

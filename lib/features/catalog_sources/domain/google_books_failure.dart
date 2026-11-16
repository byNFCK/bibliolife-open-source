import 'package:bibliolife/features/catalog_sources/domain/remote_catalog_failure.dart';

enum GoogleBooksFailureCategory {
  apiKeyMissing,
  apiKeyInvalid,
  apiNotEnabled,
  apiKeyRestrictionRejected,
  rateLimitExceeded,
  dailyLimitExceeded,
  quotaExceeded,
  resourceExhausted,
  permissionDenied,
  requestConstructionFailed,
  malformedGoogleError,
}

class GoogleBooksRequestException extends RemoteCatalogException {
  GoogleBooksRequestException({
    required this.category,
    required this.statusCode,
    this.googleStatus,
    this.reason,
    this.retryAfter,
  }) : super(_failureFor(category), message: category.name);

  final GoogleBooksFailureCategory category;
  final int statusCode;
  final String? googleStatus;
  final String? reason;
  final Duration? retryAfter;

  bool get isTransient =>
      category == GoogleBooksFailureCategory.rateLimitExceeded ||
      category == GoogleBooksFailureCategory.resourceExhausted;

  String get userMessage => switch (category) {
    GoogleBooksFailureCategory.apiKeyMissing =>
      'Google Books is not configured in this build.',
    GoogleBooksFailureCategory.rateLimitExceeded ||
    GoogleBooksFailureCategory.resourceExhausted =>
      'Google Books is receiving too many requests. Try again shortly.',
    GoogleBooksFailureCategory.dailyLimitExceeded ||
    GoogleBooksFailureCategory.quotaExceeded =>
      'The Google Books request limit has been reached. Try again later.',
    GoogleBooksFailureCategory.apiKeyInvalid ||
    GoogleBooksFailureCategory.apiNotEnabled ||
    GoogleBooksFailureCategory.apiKeyRestrictionRejected ||
    GoogleBooksFailureCategory.permissionDenied =>
      'Google Books is currently unavailable because its API configuration is invalid.',
    GoogleBooksFailureCategory.malformedGoogleError =>
      'Google Books is currently unavailable. Try again later.',
    GoogleBooksFailureCategory.requestConstructionFailed =>
      'Google Books is currently unavailable. Try again later.',
  };

  static RemoteCatalogFailure _failureFor(
    GoogleBooksFailureCategory category,
  ) => switch (category) {
    GoogleBooksFailureCategory.apiKeyMissing =>
      RemoteCatalogFailure.googleBooksApiKeyMissing,
    GoogleBooksFailureCategory.apiKeyInvalid ||
    GoogleBooksFailureCategory.apiNotEnabled ||
    GoogleBooksFailureCategory.apiKeyRestrictionRejected ||
    GoogleBooksFailureCategory.permissionDenied =>
      RemoteCatalogFailure.googleBooksConfigurationInvalid,
    GoogleBooksFailureCategory.malformedGoogleError =>
      RemoteCatalogFailure.responseParsingFailed,
    GoogleBooksFailureCategory.requestConstructionFailed =>
      RemoteCatalogFailure.requestConstructionFailed,
    _ => RemoteCatalogFailure.googleApiError,
  };
}

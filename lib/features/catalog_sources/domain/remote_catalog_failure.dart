enum RemoteCatalogFailure {
  accessDenied,
  invalidSourceOrLocation,
  transport,
  timeout,
  httpStatus,
  emptyResponse,
  responseTooLarge,
  insecureRedirect,
  unsupportedCatalogFormat,
  malformedCatalogResponse,
  sourceNotFound,
  sourceDisabled,
  transportUnavailable,
  searchUnsupported,
  malformedSearchDescription,
  unsupportedSearchTemplate,
  googleBooksApiKeyMissing,
  googleBooksConfigurationInvalid,
  requestConstructionFailed,
  googleApiError,
  responseParsingFailed,
}

class RemoteCatalogException implements Exception {
  const RemoteCatalogException(this.failure, {this.message});

  const RemoteCatalogException.accessDenied([String? message])
    : this(RemoteCatalogFailure.accessDenied, message: message);

  const RemoteCatalogException.invalidSourceOrLocation([String? message])
    : this(RemoteCatalogFailure.invalidSourceOrLocation, message: message);

  const RemoteCatalogException.transport([String? message])
    : this(RemoteCatalogFailure.transport, message: message);

  const RemoteCatalogException.timeout([String? message])
    : this(RemoteCatalogFailure.timeout, message: message);

  const RemoteCatalogException.httpStatus([String? message])
    : this(RemoteCatalogFailure.httpStatus, message: message);

  const RemoteCatalogException.emptyResponse([String? message])
    : this(RemoteCatalogFailure.emptyResponse, message: message);

  const RemoteCatalogException.responseTooLarge([String? message])
    : this(RemoteCatalogFailure.responseTooLarge, message: message);

  const RemoteCatalogException.insecureRedirect([String? message])
    : this(RemoteCatalogFailure.insecureRedirect, message: message);

  const RemoteCatalogException.unsupportedCatalogFormat([String? message])
    : this(RemoteCatalogFailure.unsupportedCatalogFormat, message: message);

  const RemoteCatalogException.malformedCatalogResponse([String? message])
    : this(RemoteCatalogFailure.malformedCatalogResponse, message: message);

  const RemoteCatalogException.sourceNotFound([String? message])
    : this(RemoteCatalogFailure.sourceNotFound, message: message);

  const RemoteCatalogException.sourceDisabled([String? message])
    : this(RemoteCatalogFailure.sourceDisabled, message: message);

  const RemoteCatalogException.transportUnavailable([String? message])
    : this(RemoteCatalogFailure.transportUnavailable, message: message);

  const RemoteCatalogException.searchUnsupported([String? message])
    : this(RemoteCatalogFailure.searchUnsupported, message: message);

  const RemoteCatalogException.malformedSearchDescription([String? message])
    : this(RemoteCatalogFailure.malformedSearchDescription, message: message);

  const RemoteCatalogException.unsupportedSearchTemplate([String? message])
    : this(RemoteCatalogFailure.unsupportedSearchTemplate, message: message);

  final RemoteCatalogFailure failure;
  final String? message;

  @override
  String toString() =>
      'RemoteCatalogException(${failure.name}${message == null ? '' : ': $message'})';
}

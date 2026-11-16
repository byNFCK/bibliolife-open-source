enum CatalogSourceFailure {
  emptyName,
  emptyUrl,
  malformedUrl,
  unsupportedScheme,
  insecureHttp,
  missingHost,
  duplicateUrl,
  sourceNotFound,
  builtInImmutable,
  builtInCannotBeDeleted,
  persistenceFailure,
  operationAlreadyInProgress,
}

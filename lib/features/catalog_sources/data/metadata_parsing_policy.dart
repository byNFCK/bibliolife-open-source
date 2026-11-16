enum MetadataParserType {
  googleBooks,
  openLibrary,
  internetArchive,
  openSearch,
  opds,
}

/// Central, injectable decision boundary for main-isolate parsing.
class MetadataParsingPolicy {
  const MetadataParsingPolicy({
    this.googleBooksThresholdBytes = 128 * 1024,
    this.openLibraryThresholdBytes = 128 * 1024,
    this.internetArchiveThresholdBytes = 96 * 1024,
    this.opdsThresholdBytes = 96 * 1024,
    this.openSearchThresholdBytes = 256 * 1024,
  });

  final int googleBooksThresholdBytes;
  final int openLibraryThresholdBytes;
  final int internetArchiveThresholdBytes;
  final int opdsThresholdBytes;
  final int openSearchThresholdBytes;

  bool shouldUseBackground(MetadataParserType type, int bytes) =>
      bytes >=
      switch (type) {
        MetadataParserType.googleBooks => googleBooksThresholdBytes,
        MetadataParserType.openLibrary => openLibraryThresholdBytes,
        MetadataParserType.internetArchive => internetArchiveThresholdBytes,
        MetadataParserType.opds => opdsThresholdBytes,
        MetadataParserType.openSearch => openSearchThresholdBytes,
      };
}

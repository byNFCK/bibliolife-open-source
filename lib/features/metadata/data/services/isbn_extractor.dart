enum IsbnKind { isbn10, isbn13 }

enum IsbnSource { packageMetadata, frontMatter, backMatter }

class IsbnCandidate {
  const IsbnCandidate({
    required this.canonical,
    required this.kind,
    required this.source,
    required this.confidence,
  });

  final String canonical;
  final IsbnKind kind;
  final IsbnSource source;
  final int confidence;
}

/// Pure ISBN canonicalization and checksum validation for decoded text.
class IsbnExtractor {
  const IsbnExtractor._();

  static List<IsbnCandidate> extractCandidates(
    String text, {
    required IsbnSource source,
  }) {
    final candidates = <IsbnCandidate>[];
    final seen = <String>{};
    for (final match in _isbnText.allMatches(text)) {
      final canonical = canonicalize(match.group(0)!);
      if (canonical == null || !seen.add(canonical)) continue;
      candidates.add(
        IsbnCandidate(
          canonical: canonical,
          kind: canonical.length == 13 ? IsbnKind.isbn13 : IsbnKind.isbn10,
          source: source,
          confidence: match.group(0)!.toLowerCase().contains('isbn') ? 100 : 80,
        ),
      );
    }
    return candidates;
  }

  static String? canonicalize(String value) {
    final withoutLabel = value
        .replaceFirst(RegExp(r'^\s*urn:isbn:', caseSensitive: false), '')
        .replaceFirst(
          RegExp(r'^\s*isbn(?:-1[03]|1[03])?\s*:?\s*', caseSensitive: false),
          '',
        );
    final canonical = withoutLabel
        .replaceAll(RegExp(r'[\s\-\u2010-\u2015\u00a0\u202f]'), '')
        .toUpperCase();
    if (isValidIsbn13(canonical) || isValidIsbn10(canonical)) return canonical;
    return null;
  }

  static bool isValidIsbn13(String value) {
    if (!RegExp(r'^(?:978|979)\d{10}$').hasMatch(value)) return false;
    final sum = List.generate(
      12,
      (index) => int.parse(value[index]) * (index.isEven ? 1 : 3),
    ).reduce((a, b) => a + b);
    return (10 - sum % 10) % 10 == int.parse(value[12]);
  }

  static bool isValidIsbn10(String value) {
    if (!RegExp(r'^\d{9}[\dX]$').hasMatch(value)) return false;
    final sum = List.generate(
      10,
      (index) =>
          (value[index] == 'X' ? 10 : int.parse(value[index])) * (10 - index),
    ).reduce((a, b) => a + b);
    return sum % 11 == 0;
  }

  static String? selectBest(Iterable<IsbnCandidate> candidates) {
    final values = candidates.toList()
      ..sort((a, b) {
        final kind =
            (b.kind == IsbnKind.isbn13 ? 1 : 0) -
            (a.kind == IsbnKind.isbn13 ? 1 : 0);
        if (kind != 0) return kind;
        return b.confidence.compareTo(a.confidence);
      });
    return values.isEmpty ? null : values.first.canonical;
  }

  static final _isbnText = RegExp(
    r'(?:urn:isbn:|isbn(?:-1[03]|1[03])?\s*:?\s*)?[0-9Xx](?:[0-9Xx\s\-\u2010-\u2015\u00a0\u202f]){8,22}[0-9Xx]',
    caseSensitive: false,
  );
}

import 'package:bibliolife/features/book_details/presentation/models/book_classification_taxonomy.dart';

class BookClassification {
  const BookClassification({
    this.genres = const [],
    this.subgenresOrTags = const [],
  });

  final List<String> genres;
  final List<String> subgenresOrTags;

  bool get isEmpty => genres.isEmpty && subgenresOrTags.isEmpty;
}

typedef BookClassificationComputer =
    BookClassification Function(Iterable<String?> rawSubjects);

/// Synchronous, in-memory cache for the Book Details-only derived metadata.
///
/// Cache-key contract:
/// - each subject is normalized with [BookClassificationClassifier
///   .normalizeTaxonomyKey], so whitespace is collapsed and empty values drop;
/// - normalized subjects remain in their original order and are never sorted
///   or converted to a [Set];
/// - duplicate normalized subjects remain in the key, matching classifier
///   input semantics;
/// - different orders are different cache inputs because stable tag ordering is
///   source-sensitive.
///
/// The length-prefixed encoding is collision-safe even when a subject contains
/// punctuation or a previously used delimiter. Unrelated view state such as
/// reading progress, favorite state, covers, theme, or download state is not
/// part of the key.
class BookDetailsClassificationCache {
  BookDetailsClassificationCache({BookClassificationComputer? compute})
    : _compute = compute ?? _defaultCompute;

  final BookClassificationComputer _compute;
  final Map<String, BookClassification> _values = {};

  BookClassification resolve(Iterable<String?> rawSubjects) {
    final subjects = rawSubjects.toList(growable: false);
    final normalizedSubjects = subjects
        .whereType<String>()
        .map(BookClassificationClassifier.normalizeTaxonomyKey)
        .where((subject) => subject.isNotEmpty)
        .toList(growable: false);
    return _values.putIfAbsent(
      _encodeKey(normalizedSubjects),
      () => _compute(subjects),
    );
  }

  static String _encodeKey(Iterable<String> subjects) =>
      subjects.map((subject) => '${subject.length}:$subject').join();

  static BookClassification _defaultCompute(Iterable<String?> rawSubjects) =>
      const BookClassificationClassifier().classify(rawSubjects);
}

class BookClassificationRule {
  const BookClassificationRule({
    this.canonicalGenre,
    this.canonicalSubgenreOrTag,
    this.canonicalGenres = const [],
    this.canonicalSubgenresOrTags = const [],
    this.ignored = false,
  });

  final String? canonicalGenre;
  final String? canonicalSubgenreOrTag;
  final List<String> canonicalGenres;
  final List<String> canonicalSubgenresOrTags;
  final bool ignored;

  Iterable<String> get genres sync* {
    if (canonicalGenre case final value?) yield value;
    yield* canonicalGenres;
  }

  Iterable<String> get tags sync* {
    if (canonicalSubgenreOrTag case final value?) yield value;
    yield* canonicalSubgenresOrTags;
  }
}

class BookClassificationDictionary {
  const BookClassificationDictionary({this.rules = const {}});

  final Map<String, BookClassificationRule> rules;

  BookClassificationRule? ruleFor(String normalizedTerm) {
    final key = BookClassificationClassifier.normalizeTaxonomyKey(
      normalizedTerm,
    );
    for (final entry in rules.entries) {
      if (BookClassificationClassifier.normalizeTaxonomyKey(entry.key) == key) {
        return entry.value;
      }
    }
    return null;
  }
}

enum ResidualTagKind {
  canonicalTaxonomy,
  canonicalPlot,
  literaryForm,
  themeOrOccupation,
  person,
  place,
  historicalOrSocialContext,
  other,
}

final class _TagCandidate {
  const _TagCandidate(this.value, this.kind, this.sourceIndex);

  final String value;
  final ResidualTagKind kind;
  final int sourceIndex;
}

final class _TaxonomyLookups {
  _TaxonomyLookups._({
    required this.exact,
    required this.phrases,
    required this.genreOrder,
    required this.canonicalTagKeys,
    required this.plotTagKeys,
  });

  factory _TaxonomyLookups.production() {
    final rules = <String, BookClassificationRule>{};
    final genreOrder = <String, int>{};
    final canonicalTagKeys = <String>{};
    final plotTagKeys = <String>{};
    for (var index = 0; index < bookGenreTaxonomy.length; index++) {
      final entry = bookGenreTaxonomy[index];
      genreOrder[entry.canonical.toLowerCase()] = index;
      final rule = BookClassificationRule(canonicalGenre: entry.canonical);
      for (final phrase in [entry.canonical, ...entry.aliases]) {
        _mergeRule(rules, phrase, rule);
      }
    }
    for (final entry in bookTagTaxonomy) {
      canonicalTagKeys.add(
        BookClassificationClassifier.normalizeTaxonomyKey(entry.canonical),
      );
      final rule = BookClassificationRule(
        canonicalSubgenreOrTag: entry.canonical,
      );
      for (final phrase in [entry.canonical, ...entry.aliases]) {
        _mergeRule(rules, phrase, rule);
      }
    }
    for (final plotTag in bookPlotTags) {
      plotTagKeys.add(
        BookClassificationClassifier.normalizeTaxonomyKey(plotTag),
      );
      _mergeRule(
        rules,
        plotTag,
        BookClassificationRule(canonicalSubgenreOrTag: plotTag),
      );
    }
    for (final entry in bookCombinedGenreTaxonomy) {
      _mergeRule(
        rules,
        entry.phrase,
        BookClassificationRule(
          canonicalGenres: entry.genres,
          canonicalSubgenresOrTags: entry.tags,
        ),
      );
    }
    final phrases = rules.entries.toList(growable: false)
      ..sort((left, right) {
        final wordDifference = _wordCount(
          right.key,
        ).compareTo(_wordCount(left.key));
        return wordDifference != 0
            ? wordDifference
            : right.key.length.compareTo(left.key.length);
      });
    return _TaxonomyLookups._(
      exact: Map.unmodifiable(rules),
      phrases: List.unmodifiable(phrases),
      genreOrder: Map.unmodifiable(genreOrder),
      canonicalTagKeys: Set.unmodifiable(canonicalTagKeys),
      plotTagKeys: Set.unmodifiable(plotTagKeys),
    );
  }

  final Map<String, BookClassificationRule> exact;
  final List<MapEntry<String, BookClassificationRule>> phrases;
  final Map<String, int> genreOrder;
  final Set<String> canonicalTagKeys;
  final Set<String> plotTagKeys;

  static void _mergeRule(
    Map<String, BookClassificationRule> rules,
    String phrase,
    BookClassificationRule addition,
  ) {
    final key = BookClassificationClassifier.normalizeTaxonomyKey(phrase);
    final existing = rules[key];
    if (existing == null) {
      rules[key] = addition;
      return;
    }
    rules[key] = BookClassificationRule(
      canonicalGenres: {
        ...existing.genres,
        ...addition.genres,
      }.toList(growable: false),
      canonicalSubgenresOrTags: {
        ...existing.tags,
        ...addition.tags,
      }.toList(growable: false),
      ignored: existing.ignored || addition.ignored,
    );
  }

  static int _wordCount(String value) => value
      .split(RegExp(r'[^a-z0-9\u0400-\u04ff]+'))
      .where((e) => e.isNotEmpty)
      .length;
}

class BookClassificationClassifier {
  const BookClassificationClassifier({this.dictionary});

  static final _production = _TaxonomyLookups.production();
  static const _maxDisplayLength = 120;
  static const _metadataLabels = {
    'subject',
    'subjects',
    'genre',
    'genres',
    'topic',
    'topics',
  };
  static const _boilerplate = {'unknown', 'n/a', 'none', 'not specified'};
  static const _flattenedFormSuffixes = {'composers fiction': 'Composers'};
  static const _genericGenres = {'Fiction & Literature'};
  static const _knownNameRewrites = {
    'holmes sherlock': 'Sherlock Holmes',
    'dracula count': 'Count Dracula',
    'lescaut manon': 'Manon Lescaut',
    'twain mark': 'Mark Twain',
    'odysseus king of ithaca': 'Odysseus, King of Ithaca',
  };
  static const _nationalityFormNouns = {
    'authors',
    'fiction',
    'literature',
    'poetry',
    'short stories',
    'horror tales',
    'drama',
    'romances',
  };
  static const _removableSubdivisionQualifiers = {
    'fiction',
    'drama',
    'biography',
    'travel',
    'description and travel',
    'romances',
    'translations into english',
  };

  final BookClassificationDictionary? dictionary;

  static String normalizeTaxonomyKey(String input) => input
      .toLowerCase()
      .replaceAll(RegExp(r'[\u2018\u2019\u02bc\u0060]'), "'")
      .replaceAll(RegExp(r'[\u2010-\u2015\u2212]'), '-')
      .replaceAll(RegExp(r'\bsci[\s-]*fi\b'), 'science fiction')
      .replaceAll(RegExp(r'\s*,\s*'), ' ')
      .replaceAll(RegExp(r'\s*&\s*'), ' & ')
      .replaceAll(
        RegExp(r'[\s\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]+'),
        ' ',
      )
      .trim();

  BookClassification classify(Iterable<String?> rawSubjects) {
    final genres = <String>[];
    final seenGenres = <String>{};
    final tagCandidates = <_TagCandidate>[];
    final seenTags = <String>{};
    var sourceIndex = 0;
    for (final raw in rawSubjects) {
      for (final value in _cleanValues(raw)) {
        final normalized = normalizeTaxonomyKey(value);
        final exactRule = _exactRule(normalized);
        if (exactRule?.ignored == true) continue;
        final matchedRules = exactRule == null
            ? _completePhraseRules(normalized)
            : [exactRule];
        var recognizedTag = false;
        for (final rule in matchedRules) {
          for (final genre in rule.genres) {
            _addStable(genres, seenGenres, genre);
          }
          for (final tag in rule.tags) {
            recognizedTag = true;
            _addTagCandidate(
              tagCandidates,
              seenTags,
              tag,
              _canonicalTagKind(tag),
              sourceIndex,
            );
          }
        }
        if (exactRule == null && !recognizedTag) {
          _addTagCandidate(
            tagCandidates,
            seenTags,
            value,
            _residualTagKind(value),
            sourceIndex,
          );
        }
        sourceIndex++;
      }
    }

    if (genres.any((genre) => !_genericGenres.contains(genre))) {
      genres.removeWhere(_genericGenres.contains);
    }
    genres.sort((left, right) {
      final leftGeneric = _genericGenres.contains(left);
      final rightGeneric = _genericGenres.contains(right);
      if (leftGeneric != rightGeneric) return leftGeneric ? 1 : -1;
      return (_production.genreOrder[left.toLowerCase()] ?? 999).compareTo(
        _production.genreOrder[right.toLowerCase()] ?? 999,
      );
    });
    if (genres.length > 3) genres.removeRange(3, genres.length);
    final displayedGenres = genres.map((genre) => genre.toLowerCase()).toSet();
    final tags =
        tagCandidates
            .where((tag) => !displayedGenres.contains(tag.value.toLowerCase()))
            .where((tag) => !_isRedundantTag(tag, tagCandidates))
            .toList()
          ..sort((left, right) {
            final kindComparison = left.kind.index.compareTo(right.kind.index);
            return kindComparison != 0
                ? kindComparison
                : left.sourceIndex.compareTo(right.sourceIndex);
          });
    return BookClassification(
      genres: List.unmodifiable(genres),
      subgenresOrTags: List.unmodifiable(tags.map((tag) => tag.value)),
    );
  }

  ResidualTagKind _canonicalTagKind(String value) {
    final key = normalizeTaxonomyKey(value);
    if (_production.plotTagKeys.contains(key)) {
      return ResidualTagKind.canonicalPlot;
    }
    return ResidualTagKind.canonicalTaxonomy;
  }

  ResidualTagKind _residualTagKind(String value) {
    final lower = normalizeTaxonomyKey(value);
    if (RegExp(
      r'\b(?:fiction|poetry|stories|tales|romances|drama|opera)\b',
    ).hasMatch(lower)) {
      return ResidualTagKind.literaryForm;
    }
    if (RegExp(
      r'\b(?:authors|investigators|pilots|gentry|inheritance|youth|women|sisters|selection|classes|vendetta|conflict)\b',
    ).hasMatch(lower)) {
      return ResidualTagKind.themeOrOccupation;
    }
    if (_knownNameRewrites.containsValue(value) ||
        _knownNameRewrites.values.any(
          (name) => lower.startsWith('${name.toLowerCase()} '),
        ) ||
        const {
          'homer',
          'odysseus, king of ithaca',
          'juliet',
          'romeo',
        }.contains(lower)) {
      return ResidualTagKind.person;
    }
    if (lower.contains('social life and customs') ||
        RegExp(r'\b\d{1,2}(?:st|nd|rd|th) century\b').hasMatch(lower)) {
      return ResidualTagKind.historicalOrSocialContext;
    }
    if (RegExp(r'\([^)]*\)$').hasMatch(value) ||
        RegExp(
          r'^(?:england|london|verona|mars|martians|mississippi river(?: valley)?|united states)\b',
          caseSensitive: false,
        ).hasMatch(value)) {
      return ResidualTagKind.place;
    }
    return ResidualTagKind.other;
  }

  bool _isRedundantTag(_TagCandidate candidate, List<_TagCandidate> all) {
    return all.any((other) {
      if (identical(other, candidate)) return false;
      return other.value.startsWith('${candidate.value} — ') &&
          normalizeTaxonomyKey(other.value).contains('social life and customs');
    });
  }

  void _addTagCandidate(
    List<_TagCandidate> candidates,
    Set<String> seen,
    String value,
    ResidualTagKind kind,
    int sourceIndex,
  ) {
    final normalized = normalizeTaxonomyKey(
      value,
    ).replaceAll(RegExp(r'[\s,.:;!?—-]+'), ' ').trim();
    if (seen.add(normalized)) {
      candidates.add(_TagCandidate(value, kind, sourceIndex));
    }
  }

  BookClassificationRule? _exactRule(String normalized) {
    final custom = dictionary;
    if (custom != null) return custom.ruleFor(normalized);
    return _production.exact[normalized];
  }

  List<BookClassificationRule> _completePhraseRules(String normalized) {
    if (dictionary != null) return const [];
    final rules = <BookClassificationRule>[];
    final occupied = <(int, int)>[];
    for (final entry in _production.phrases) {
      final phrase = entry.key;
      final expression = RegExp(
        '(?<![a-z0-9\\u0400-\\u04ff])${RegExp.escape(phrase)}'
        '(?![a-z0-9\\u0400-\\u04ff])',
        unicode: true,
      );
      for (final match in expression.allMatches(normalized)) {
        if (occupied.any(
          (range) => match.start < range.$2 && match.end > range.$1,
        )) {
          continue;
        }
        occupied.add((match.start, match.end));
        rules.add(entry.value);
      }
    }
    return rules;
  }

  Iterable<String> _cleanValues(String? raw) sync* {
    if (raw == null) return;
    try {
      final decoded = _decodeEntities(raw);
      final withoutTags = decoded.replaceAll(RegExp(r'<[^>]*>'), ' ');
      for (final part in withoutTags.split(RegExp(r'[;|]+'))) {
        final value = _normalize(part);
        if (_isDisplayValue(value)) yield value;
      }
    } catch (_) {
      // Classification is display-only; malformed source metadata is ignored.
    }
  }

  String _normalize(String input) {
    var value = input
        .replaceAll(
          RegExp(
            r'[\s\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]+',
          ),
          ' ',
        )
        .trim();
    while (value.length >= 2 &&
        const {'"': '"', "'": "'", '(': ')', '[': ']', '{': '}'}[value[0]] ==
            value[value.length - 1]) {
      value = value.substring(1, value.length - 1).trim();
    }
    value = value.replaceAll(RegExp(r'[,;|]+'), ' ');
    value = value.replaceAllMapped(
      RegExp(r'([,.:!?])\1+'),
      (match) => match[1]!,
    );
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    value = value.replaceFirst(RegExp(r'[\s.,;:!?]+$'), '').trim();
    value = value.replaceAll(
      RegExp(
        r'\s*\((?:fictitious|legendary|mythological) character\)',
        caseSensitive: false,
      ),
      '',
    );
    final subdivisions = value
        .split(RegExp(r'\s+(?:--|—|–|-)\s+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (subdivisions.isNotEmpty) {
      final retained = <String>[_normalizePrimary(subdivisions.removeAt(0))];
      retained.addAll(
        subdivisions.where(
          (subdivision) => !_removableSubdivisionQualifiers.contains(
            normalizeTaxonomyKey(subdivision),
          ),
        ),
      );
      value = retained
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .join(' — ');
    }
    return _flattenedFormSuffixes[value.toLowerCase()] ?? value;
  }

  String _normalizePrimary(String value) {
    var normalized = value
        .replaceFirst(
          RegExp(r'\s+translations into english$', caseSensitive: false),
          '',
        )
        .replaceFirst(RegExp(r'\s+\d{3,4}\s*[-–—]\s*\d{3,4}$'), '')
        .trim();
    final key = normalizeTaxonomyKey(normalized);
    if (key == 'lady of the lake romances') return 'Lady of the Lake';
    normalized = _knownNameRewrites[key] ?? normalized;
    return _normalizeNationalityForm(normalized);
  }

  String _normalizeNationalityForm(String value) {
    final match = RegExp(
      r'^(.*)\s+(American|Greek)$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return value;
    final before = match[1]!.trim();
    if (!_nationalityFormNouns.any(
      (noun) =>
          before.toLowerCase() == noun ||
          before.toLowerCase().endsWith(' $noun'),
    )) {
      return value;
    }
    return '${match[2]!} ${before.toLowerCase()}';
  }

  bool _isDisplayValue(String value) {
    if (value.isEmpty || value.length > _maxDisplayLength) return false;
    final lower = value.toLowerCase();
    if (_metadataLabels.contains(lower) || _boilerplate.contains(lower)) {
      return false;
    }
    if (RegExp(
      r'^(?:language and literatures|language and literature|languages and literatures|romance literatures)\s*:',
      caseSensitive: false,
    ).hasMatch(value)) {
      return false;
    }
    if (lower == 'text' || lower == 'texts') return false;
    if (RegExp(r'^(https?://|www\.)', caseSensitive: false).hasMatch(value)) {
      return false;
    }
    if (RegExp(
      r'^(urn:|isbn(?:-1[03])?:|doi:|uuid:)',
      caseSensitive: false,
    ).hasMatch(value)) {
      return false;
    }
    return RegExp(r'[A-Za-z\u00c0-\uffff]').hasMatch(value);
  }

  void _addStable(List<String> values, Set<String> seen, String value) {
    final normalized = normalizeTaxonomyKey(
      value,
    ).replaceAll(RegExp(r'[\s,.:;!?—-]+'), ' ').trim();
    if (seen.add(normalized)) values.add(value);
  }

  String _decodeEntities(String input) => input.replaceAllMapped(
    RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos|nbsp);'),
    (match) {
      final entity = match[1]!;
      return switch (entity) {
        'amp' => '&',
        'lt' => '<',
        'gt' => '>',
        'quot' => '"',
        'apos' => "'",
        'nbsp' => ' ',
        _ => _numericEntity(entity) ?? match[0]!,
      };
    },
  );

  String? _numericEntity(String entity) {
    final radix = entity.startsWith('#x') ? 16 : 10;
    final digits = entity.substring(radix == 16 ? 2 : 1);
    final codePoint = int.tryParse(digits, radix: radix);
    if (codePoint == null || codePoint < 0 || codePoint > 0x10ffff) return null;
    return String.fromCharCode(codePoint);
  }
}

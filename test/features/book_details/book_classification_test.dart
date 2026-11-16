import 'package:bibliolife/features/book_details/presentation/models/book_classification.dart';
import 'package:bibliolife/features/book_details/presentation/models/book_classification_taxonomy.dart';
import 'package:bibliolife/features/book_details/presentation/models/book_details_view_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const classifier = BookClassificationClassifier();

  group('complete genre taxonomy', () {
    test('recognizes all 28 canonical genres', () {
      expect(bookGenreTaxonomy, hasLength(28));
      for (final entry in bookGenreTaxonomy) {
        expect(
          classifier.classify([entry.canonical]).genres,
          contains(entry.canonical),
          reason: entry.canonical,
        );
      }
    });

    test('recognizes every supplied genre alias', () {
      for (final entry in bookGenreTaxonomy) {
        expect(entry.aliases, isNotEmpty, reason: entry.canonical);
        for (final alias in entry.aliases) {
          expect(
            classifier.classify([alias]).genres,
            contains(entry.canonical),
            reason: '$alias -> ${entry.canonical}',
          );
        }
      }
    });

    test('recognizes combined and deprecated categories', () {
      for (final entry in bookCombinedGenreTaxonomy) {
        final result = classifier.classify([entry.phrase]);
        expect(result.genres, containsAll(entry.genres), reason: entry.phrase);
        expect(result.subgenresOrTags, containsAll(entry.tags));
      }
    });
  });

  group('complete tag taxonomy', () {
    test('recognizes all canonical tags', () {
      for (final entry in bookTagTaxonomy) {
        final result = classifier.classify([entry.canonical]);
        expect(
          [...result.genres, ...result.subgenresOrTags],
          contains(entry.canonical),
          reason: entry.canonical,
        );
      }
    });

    test('canonicalizes every supplied tag alias', () {
      for (final entry in bookTagTaxonomy) {
        for (final alias in entry.aliases) {
          final result = classifier.classify([alias]);
          expect(
            [...result.genres, ...result.subgenresOrTags],
            contains(entry.canonical),
            reason: '$alias -> ${entry.canonical}',
          );
        }
      }
    });

    test('recognizes every supplied plot tag', () {
      for (final tag in bookPlotTags) {
        expect(
          classifier.classify([tag]).subgenresOrTags,
          contains(tag),
          reason: tag,
        );
      }
    });
  });

  group('matching protections', () {
    test('uses longest complete phrases and resolves science fiction', () {
      final result = classifier.classify([
        'Science Fiction',
        'Science Fiction & Fantasy',
        'Popular Science',
      ]);
      expect(result.genres, ['Fantasy', 'Science', 'Science Fiction']);
      expect(result.genres, isNot(contains('Fiction & Literature')));
      expect(result.subgenresOrTags, contains('Popular Science'));
    });

    test('uses whole tokens for AI, YA and art', () {
      expect(classifier.classify(['AI']).subgenresOrTags, contains('AI'));
      expect(classifier.classify(['YA']).genres, ['Young Adult']);
      expect(classifier.classify(['chair']).genres, isEmpty);
      expect(classifier.classify(['daily']).subgenresOrTags, ['daily']);
      expect(classifier.classify(['art']).genres, ['Arts & Entertainment']);
    });

    test('does not confuse mysticism with mystery', () {
      final result = classifier.classify(['Mysticism']);
      expect(result.genres, ['Religion & Spirituality']);
      expect(result.genres, isNot(contains('Mystery & Thriller')));
      expect(result.subgenresOrTags, isEmpty);
    });

    test('rejects Romance literatures taxonomy noise', () {
      final result = classifier.classify([
        'Romance literatures: French Italian Spanish Portuguese',
      ]);
      expect(result, isA<BookClassification>());
      expect(result.isEmpty, isTrue);
    });

    test('deduplicates aliases after canonicalization', () {
      final result = classifier.classify([
        'sci-fi',
        'SCI FI',
        'Science Fiction',
        'вампіри',
        'Vampires',
      ]);
      expect(result.genres, ['Science Fiction']);
      expect(result.subgenresOrTags, ['Vampires']);
    });

    test('specific genre suppresses generic fiction', () {
      final result = classifier.classify([
        'Science Fiction',
        'fiction',
        'Fantasy novel',
      ]);
      expect(result.genres, ['Fantasy', 'Science Fiction']);
      expect(result.genres, isNot(contains('Fiction & Literature')));
    });

    test('keeps meaningful unknown cleaned subjects as residual tags', () {
      final result = classifier.classify(['  <b>Sea&nbsp;Stories</b>...  ']);
      expect(result.subgenresOrTags, ['Sea Stories']);
    });

    test('custom dictionary remains an immutable extension point', () {
      const configured = BookClassificationClassifier(
        dictionary: BookClassificationDictionary(
          rules: {
            'sci-fi': BookClassificationRule(
              canonicalGenre: 'Speculative fiction',
              canonicalSubgenreOrTag: 'Science fiction',
            ),
            'ignore-me': BookClassificationRule(ignored: true),
          },
        ),
      );
      final result = configured.classify([
        'Sci-Fi',
        'Ignore-me',
        'Unmapped term',
      ]);
      expect(result.genres, ['Speculative fiction']);
      expect(result.subgenresOrTags, ['Science fiction', 'Unmapped term']);
    });
  });

  group('Gutenberg cleanup fixtures', () {
    test('Dracula', () {
      final result = classifier.classify([
        'Horror tales',
        'Epistolary fiction',
        'Gothic fiction',
        'Vampires -- Fiction',
        'Dracula Count (Fictitious character) -- Fiction',
        'Transylvania (Romania) -- Fiction',
        'Whitby (England) -- Fiction',
        'Language and Literatures: English literature',
        'Text',
      ]);
      expect(result.genres, contains('Horror'));
      expect(result.subgenresOrTags, [
        'Vampires',
        'Horror tales',
        'Epistolary fiction',
        'Gothic fiction',
        'Count Dracula',
        'Transylvania (Romania)',
        'Whitby (England)',
      ]);
    });

    test('The Phantom of the Opera', () {
      final result = classifier.classify([
        'Horror tales',
        'Musical fiction',
        'Opera',
        'Paris (France) -- Fiction',
        'Composers Fiction',
        'Phantom of the Opera (Fictitious character) -- Fiction',
        'French fiction -- 20th century',
        'Romance literatures: French Italian Spanish Portuguese',
      ]);
      expect(result.genres, isNot(contains('Romance')));
      expect(result.subgenresOrTags, [
        'Horror tales',
        'Musical fiction',
        'Opera',
        'Phantom of the Opera',
        'French fiction — 20th century',
        'Paris (France)',
        'Composers',
      ]);
    });

    test('The Monk', () {
      final result = classifier.classify([
        'Horror tales',
        'Gothic fiction',
        'Monks -- Fiction',
        'Madrid (Spain) -- Fiction',
        'Language and Literatures: English literature',
        'Text',
      ]);
      expect(result.subgenresOrTags, [
        'Horror tales',
        'Gothic fiction',
        'Madrid (Spain)',
        'Monks',
      ]);
    });
  });

  group('residual subject normalization and ordering', () {
    test('joins internal line wraps without creating subject boundaries', () {
      final result = classifier.classify([
        'Adventure\nstories',
        'Mississippi\nRiver',
      ]);
      expect(result.genres, ['Adventure']);
      expect(result.subgenresOrTags, [
        'Adventure stories',
        'Mississippi River',
      ]);
    });

    test('normalizes LCSH qualifiers, names, nationality and chronology', () {
      final fixtures = <({List<String> input, List<String> output})>[
        (
          input: [
            'Homer Translations into English',
            'Epic poetry Greek - Translations into English',
            'Odysseus King of Ithaca',
          ],
          output: ['Greek epic poetry', 'Homer', 'Odysseus, King of Ithaca'],
        ),
        (
          input: [
            'Holmes Sherlock',
            'Private investigators - England',
            'Detective',
          ],
          output: [
            'Detective',
            'Private investigators — England',
            'Sherlock Holmes',
          ],
        ),
        (
          input: ['Arthurian romances', 'Lady of the Lake Romances'],
          output: ['Arthurian romances', 'Lady of the Lake'],
        ),
        (
          input: ['Martians', 'Mars (Planet)'],
          output: ['Martians', 'Mars (Planet)'],
        ),
        (
          input: [
            'Vendetta - Drama',
            'Youth -- Drama',
            'Verona (Italy) – Drama',
            'Juliet - Drama',
            'Romeo - Drama',
            'Conflict of generations - Drama',
          ],
          output: [
            'Vendetta',
            'Youth',
            'Conflict of generations',
            'Juliet',
            'Romeo',
            'Verona (Italy)',
          ],
        ),
        (
          input: [
            'Mississippi River - Description and travel',
            'Mississippi River Valley - Social life and customs - 19th century',
            'Authors American - 19th century - Biography',
            'Pilots and pilotage - Mississippi River',
            'Twain Mark 1835-1910 - Travel - Mississippi River',
          ],
          output: [
            'American authors — 19th century',
            'Pilots and pilotage — Mississippi River',
            'Mark Twain — Mississippi River',
            'Mississippi River',
            'Mississippi River Valley — Social life and customs — 19th century',
          ],
        ),
      ];
      for (final fixture in fixtures) {
        expect(
          classifier.classify(fixture.input).subgenresOrTags,
          fixture.output,
          reason: fixture.input.join('; '),
        );
      }
    });

    test('retains richer context and removes redundant standalone places', () {
      final result = classifier.classify([
        'England - Social life and customs - 19th century',
        'Inheritance and succession',
        'England',
        'Young women',
        'Love stories',
        'Sisters',
        'Domestic fiction',
        'Mate selection',
        'Social classes',
        'Gentry - England',
        'Regency fiction',
      ]);
      expect(result.subgenresOrTags, [
        'Love stories',
        'Domestic fiction',
        'Regency fiction',
        'Inheritance and succession',
        'Young women',
        'Sisters',
        'Mate selection',
        'Social classes',
        'Gentry — England',
        'England — Social life and customs — 19th century',
      ]);
      expect(result.subgenresOrTags, isNot(contains('England')));
    });

    test(
      'canonical tags suppress equivalent residuals and preserve source order',
      () {
        final result = classifier.classify([
          'Detective fiction',
          'Private investigators - England',
          'Private investigators - England',
        ]);
        expect(result.subgenresOrTags, [
          'Detective',
          'Private investigators — England',
        ]);
      },
    );
  });

  test('identical local and remote subject inputs classify equally', () {
    const localClassifier = BookClassificationClassifier();
    const remoteClassifier = BookClassificationClassifier();
    const subjects = ['Science Fiction', 'вампіри', 'Unknown regional topic'];
    final local = localClassifier.classify(subjects);
    final remote = remoteClassifier.classify(subjects);
    expect(remote.genres, local.genres);
    expect(remote.subgenresOrTags, local.subgenresOrTags);
  });

  test(
    'Book Details classification is lazy, memoized and subject-invalidated',
    () {
      var invocations = 0;
      final cache = BookDetailsClassificationCache(
        compute: (subjects) {
          invocations++;
          return const BookClassificationClassifier().classify(subjects);
        },
      );
      BookDetailsViewData data(List<String> subjects) => BookDetailsViewData(
        title: 'Book',
        authors: const [],
        subjects: subjects,
        classificationCache: cache,
      );

      final initial = data([' Science Fiction ', 'Vampires']);
      expect(invocations, 0);
      expect(initial.classification.genres, ['Science Fiction']);
      expect(invocations, 1);
      expect(initial.classification.subgenresOrTags, ['Vampires']);
      expect(invocations, 1);

      final rebuildWithUnrelatedChanges = data(['science fiction', 'vampires']);
      expect(rebuildWithUnrelatedChanges.classification.genres, [
        'Science Fiction',
      ]);
      expect(invocations, 1);

      final changedSubjects = data(['Fantasy', 'Vampires']);
      expect(changedSubjects.classification.genres, ['Fantasy']);
      expect(invocations, 2);
    },
  );

  test('ordered normalized subjects are the cache-key contract', () {
    var invocations = 0;
    final cache = BookDetailsClassificationCache(
      compute: (subjects) {
        invocations++;
        return BookClassification(
          subgenresOrTags: subjects.whereType<String>().toList(),
        );
      },
    );

    final first = cache.resolve([' Detective ', 'Sherlock   Holmes']);
    final equivalent = cache.resolve(['Detective', 'Sherlock Holmes']);
    expect(invocations, 1);
    expect(identical(first, equivalent), isTrue);

    final reordered = cache.resolve(['Sherlock Holmes', 'Detective']);
    expect(invocations, 2);
    expect(identical(first, reordered), isFalse);
  });

  test('length-prefixed subject keys cannot collide on content boundaries', () {
    var invocations = 0;
    final cache = BookDetailsClassificationCache(
      compute: (subjects) {
        invocations++;
        return BookClassification(
          subgenresOrTags: subjects.whereType<String>().toList(),
        );
      },
    );

    final first = cache.resolve(['a', 'b|c']);
    final second = cache.resolve(['a|b', 'c']);
    expect(invocations, 2);
    expect(first.subgenresOrTags, ['a', 'b|c']);
    expect(second.subgenresOrTags, ['a|b', 'c']);
  });

  test('empty values drop from cache keys but duplicates remain ordered', () {
    var invocations = 0;
    final cache = BookDetailsClassificationCache(
      compute: (subjects) {
        invocations++;
        return BookClassification(
          subgenresOrTags: subjects.whereType<String>().toList(),
        );
      },
    );

    final normalized = cache.resolve(['', '  ', 'Detective', 'Detective']);
    final equivalent = cache.resolve(['Detective', 'Detective']);
    final deduplicated = cache.resolve(['Detective']);
    expect(invocations, 2);
    expect(identical(normalized, equivalent), isTrue);
    expect(identical(normalized, deduplicated), isFalse);
  });
}

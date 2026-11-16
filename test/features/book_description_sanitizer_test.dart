import 'package:bibliolife/features/metadata/data/services/book_description_sanitizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BookDescriptionSanitizer', () {
    test('removes a generated-summary marker and its trailing block', () {
      const raw = '''Meaningful opening prose.

(This is an automatically generated summary.)
Reading level: Easy
Language: English
Subjects: Fiction
Rights: Public domain''';

      expect(
        BookDescriptionSanitizer.sanitize(raw),
        'Meaningful opening prose.',
      );
    });

    test('removes a trailing structured bibliographic block without marker', () {
      const raw = '''A careful description with two paragraphs.

It remains useful to a reader.

Language: English
Subjects: Fiction
LoC Class: PR
Rights: Public domain''';

      expect(
        BookDescriptionSanitizer.sanitize(raw),
        'A careful description with two paragraphs.\n\nIt remains useful to a reader.',
      );
    });

    test('supports label and value on separate lines', () {
      const raw = '''Useful prose.

Language
English
Subjects
Adventure
Rights
Public domain''';

      expect(BookDescriptionSanitizer.sanitize(raw), 'Useful prose.');
    });

    test('sanitizes HTML list tails and preserves paragraphs', () {
      const raw = '''<p>First paragraph.</p><p>Second paragraph.</p>
<ul><li>Language: English</li><li>Rights: Public domain</li></ul>''';

      expect(
        BookDescriptionSanitizer.sanitize(raw),
        'First paragraph.\nSecond paragraph.',
      );
    });

    test('preserves prose that merely uses metadata words', () {
      const raw =
          'The author explores language, rights and downloads throughout the novel.\nRights reserved.';

      expect(BookDescriptionSanitizer.sanitize(raw), raw);
    });

    test('returns null for boilerplate only and handles duplicate markers', () {
      expect(
        BookDescriptionSanitizer.sanitize(
          '(This is an automatically generated summary.)\nLanguage: English\nRights: Public domain',
        ),
        isNull,
      );
      expect(
        BookDescriptionSanitizer.sanitize(
          'Prose.\n(This is an automatically generated summary.)\n(This is an automatically generated summary.)\nLanguage: English',
        ),
        'Prose.',
      );
    });

    test('is deterministic, idempotent and normalizes line endings', () {
      const unix =
          'Український опис.\n\nLanguage: English\nRights: Public domain';
      const windows =
          'Український опис.\r\n\r\nLanguage: English\r\nRights: Public domain';
      final cleaned = BookDescriptionSanitizer.sanitize(unix);

      expect(cleaned, 'Український опис.');
      expect(BookDescriptionSanitizer.sanitize(windows), cleaned);
      expect(BookDescriptionSanitizer.sanitize(cleaned), cleaned);
    });

    test('preserves Unicode prose', () {
      const prose =
          '\u041e\u043f\u0438\u0441 \u043a\u043d\u0438\u0433\u0438 \u2014 \u0432\u0438\u043f\u0440\u043e\u0431\u0443\u0432\u0430\u043d\u043d\u044f.';

      expect(
        BookDescriptionSanitizer.sanitize(
          '$prose\nLanguage: English\nRights: Public domain',
        ),
        prose,
      );
    });

    test('removes bounded Gutenberg prefixes before genuine prose', () {
      const prose = 'A young hero crosses the lake and confronts old secrets.';
      final cases = [
        'Wikipedia: https://en.wikipedia.org/wiki/Example\n$prose',
        'https://example.org/catalog\nhttps://www.gutenberg.org/ebooks/1\n$prose',
        'Credits: Produced by A. Person\n$prose',
        'Credit: A. Person\n$prose',
        'Title: The Lady of the Lake\n$prose',
        'Note: Illustrated edition\n$prose',
        'The edition has images removed.\n$prose',
        'This edition has illustrations.\n$prose',
        'Illustrated edition with plates.\n$prose',
        'Transcribed by A. Person\n$prose',
      ];

      for (final raw in cases) {
        expect(BookDescriptionSanitizer.sanitize(raw), prose, reason: raw);
      }
    });

    test(
      'cleans HTML metadata tables and honors an explicit Summary marker',
      () {
        const prose = 'Actual descriptive prose.\nA second summary paragraph.';
        expect(
          BookDescriptionSanitizer.sanitize(
            '<table><tr><td>Title:</td><td>Book</td></tr>'
            '<tr><td>Credits:</td><td>Producer</td></tr></table>'
            '<p>Summary: Actual descriptive prose.</p>'
            '<p>A second summary paragraph.</p>',
          ),
          prose,
        );
      },
    );

    test('metadata-only prefixes become null', () {
      expect(
        BookDescriptionSanitizer.sanitize(
          'Title: A Book\nNote: Illustrated\nCredits: Producer\n'
          'https://www.gutenberg.org/ebooks/1',
        ),
        isNull,
      );
    });

    test('legitimate short and contextual-link prose remains unchanged', () {
      const credits =
          'The novel examines how credits shape the characters’ ambitions.';
      const contextual =
          'This biography discusses its Wikipedia reception at https://example.org/context.';
      const quoted = '“Run,” Alice says, beginning a brief adventure.';

      expect(BookDescriptionSanitizer.sanitize(credits), credits);
      expect(BookDescriptionSanitizer.sanitize(contextual), contextual);
      expect(BookDescriptionSanitizer.sanitize(quoted), quoted);
    });
  });
}

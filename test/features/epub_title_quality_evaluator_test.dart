import 'package:bibliolife/features/metadata/data/services/epub_title_quality_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EpubTitleQualityEvaluator', () {
    test(
      'preserves legitimate titles with digits, punctuation and Unicode',
      () {
        for (final title in [
          '1984',
          'Fahrenheit 451',
          'Catch-22',
          '1Q84',
          'HTML5',
          'C++ Primer',
          'Clean Code',
          'Dune',
          'Metro 2033',
          'S.T.A.L.K.E.R.',
          'The 7 Habits of Highly Effective People',
          'ISO 9001:2015',
          'G\u00f6del, Escher, Bach',
          '\u041b\u0456\u0441\u043e\u0432\u0430 \u043f\u0456\u0441\u043d\u044f',
          '\u0643\u062a\u0627\u0628',
          '\u4e09\u4f53',
          '\u0414\u044e\u043d\u0430: Dune',
          'X \u00c6 A-12',
          '2312',
          'Q',
          'R2-D2',
          'B612',
          'GEB',
          'e',
          'Node.js',
          'C# 12',
          'GPT-4',
          'Zyrrh\u00e6l',
          '\u4e66',
        ]) {
          final selection = EpubTitleQualityEvaluator.select(
            metadataTitle: title,
            filename: 'fallback title.epub',
          );
          expect(selection.title, title, reason: title);
          expect(selection.source, BookTitleSource.epubMetadata, reason: title);
        }
      },
    );

    test('selects a valid filename only for definitive broken metadata', () {
      final cases = <String, EpubTitleIssue>{
        '550e8400-e29b-41d4-a716-446655440000': EpubTitleIssue.uuidLike,
        '{550E8400-E29B-41D4-A716-446655440000}': EpubTitleIssue.uuidLike,
        'urn:uuid:550e8400-e29b-41d4-a716-446655440000':
            EpubTitleIssue.uuidLike,
        'f4c3b00c2b9f43e1a129ada1e7a315aa': EpubTitleIssue.hashLike,
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa':
            EpubTitleIssue.hashLike,
        'a8F3k91Lm02Px77Qw5Zr19': EpubTitleIssue.longAlphanumericToken,
        'com.vendor.export.928347': EpubTitleIssue.identifierLike,
        'unknown': EpubTitleIssue.placeholderTitle,
        'bad\uFFFDtitle': EpubTitleIssue.replacementCharacters,
        '': EpubTitleIssue.empty,
      };
      for (final entry in cases.entries) {
        final selection = EpubTitleQualityEvaluator.select(
          metadataTitle: entry.key,
          filename: 'Readable_Book_2026.epub',
        );
        expect(
          selection.metadata.quality,
          EpubTitleQuality.unusable,
          reason: entry.key,
        );
        expect(
          selection.metadata.issues,
          contains(entry.value),
          reason: entry.key,
        );
        expect(
          selection.metadata.confidence,
          greaterThanOrEqualTo(EpubTitleQualityEvaluator.unusableThreshold),
        );
        expect(selection.title, 'Readable Book 2026');
        expect(selection.source, BookTitleSource.filenameFallback);
      }
    });

    test('does not choose a filename that is itself unusable', () {
      final selection = EpubTitleQualityEvaluator.select(
        metadataTitle: 'unknown',
        filename: '550e8400-e29b-41d4-a716-446655440000.EPUB',
      );

      expect(selection.title, 'unknown');
      expect(selection.source, BookTitleSource.epubMetadata);
      expect(selection.filename.quality, EpubTitleQuality.unusable);
    });

    test('derives a clean Unicode filename title without title-casing', () {
      expect(
        EpubTitleQualityEvaluator.deriveTitleFromFilename('the_hobbit.epub'),
        'the hobbit',
      );
      expect(
        EpubTitleQualityEvaluator.deriveTitleFromFilename(
          '%D0%9B%D1%96%D0%BD%D0%B0_%D0%9A%D0%BE%D1%81%D1%82%D0%B5%D0%BD%D0%BA%D0%BE---%D0%9C%D0%B0%D1%80%D1%83%D1%81%D1%8F.EPUB',
        ),
        '\u041b\u0456\u043d\u0430 \u041a\u043e\u0441\u0442\u0435\u043d\u043a\u043e \u041c\u0430\u0440\u0443\u0441\u044f',
      );
      expect(
        EpubTitleQualityEvaluator.deriveTitleFromFilename(
          "my.book..export.epub",
        ),
        'my.book export',
      );
      expect(
        EpubTitleQualityEvaluator.deriveTitleFromFilename("O'Connor_1984.epub"),
        "O'Connor 1984",
      );
      expect(
        EpubTitleQualityEvaluator.deriveTitleFromFilename('.epub'),
        isNull,
      );
      expect(
        EpubTitleQualityEvaluator.deriveTitleFromFilename(
          '\u0413\u043b\u043e\u0440\u0456\u044f.epub',
        ),
        '\u0413\u043b\u043e\u0440\u0456\u044f',
      );
      expect(
        EpubTitleQualityEvaluator.deriveTitleFromFilename('%ZZ.epub'),
        '%ZZ',
      );
    });
  });
}

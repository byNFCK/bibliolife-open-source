import 'package:bibliolife/features/metadata/data/services/isbn_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonicalizes and validates ISBN-10 and Bookland ISBN-13', () {
    expect(IsbnExtractor.canonicalize('ISBN-10: 0-306-40615-2'), '0306406152');
    expect(IsbnExtractor.canonicalize('0 8044 2957 x'), '080442957X');
    expect(
      IsbnExtractor.canonicalize('ISBN 978-0-306-40615-7'),
      '9780306406157',
    );
    expect(IsbnExtractor.canonicalize('979 1234567896'), '9791234567896');
    expect(IsbnExtractor.canonicalize('4006381333931'), isNull);
    expect(IsbnExtractor.canonicalize('9780306406158'), isNull);
    expect(IsbnExtractor.canonicalize('030640615X'), isNull);
  });

  test(
    'extracts separator and label variants without accepting random digits',
    () {
      final candidates = IsbnExtractor.extractCandidates(
        'Edition. ISBN-13: 978\u2013030\u2013640\u2013615\u20137. Ref 1234567890123.',
        source: IsbnSource.frontMatter,
      );
      expect(IsbnExtractor.selectBest(candidates), '9780306406157');
    },
  );
}

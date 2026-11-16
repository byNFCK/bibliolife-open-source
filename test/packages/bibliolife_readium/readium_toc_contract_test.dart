import 'package:bibliolife_readium/bibliolife_readium.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nested TOC platform payload is typed and preserves order', () {
    final result = ReadiumTocExtractionResult.fromMap({
      'status': 'success',
      'entries': [
        {
          'title': 'One',
          'locatorJson':
              '{"href":"one.xhtml#first","type":"application/xhtml+xml","locations":{"fragments":["first"]}}',
          'children': [
            {
              'title': 'Child',
              'locatorJson':
                  '{"href":"child.xhtml#second","type":"application/xhtml+xml"}',
              'children': [],
            },
          ],
        },
        {
          'title': 'Two',
          'locatorJson': '{"href":"two.xhtml","type":"application/xhtml+xml"}',
          'children': [],
        },
      ],
    });
    expect(result, isA<ReadiumTocExtractionSuccess>());
    final entries = (result as ReadiumTocExtractionSuccess).entries;
    expect(entries.map((entry) => entry.title), ['One', 'Two']);
    expect(entries.first.children.single.title, 'Child');
    expect(entries.first.locatorJson, isNot(entries.last.locatorJson));
    expect(entries.first.children.single.locatorJson, contains('#second'));
  });

  test('empty and failure platform payloads stay distinct', () {
    expect(
      ReadiumTocExtractionResult.fromMap({'status': 'empty'}),
      isA<ReadiumTocExtractionEmpty>(),
    );
    final failure = ReadiumTocExtractionResult.fromMap({
      'status': 'failed',
      'failure': 'invalid_publication',
    });
    expect(
      (failure as ReadiumTocExtractionFailure).code,
      'invalid_publication',
    );
  });
}

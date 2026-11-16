import 'package:bibliolife/features/reader/presentation/models/annotation_location_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AnnotationLocationLabel? label(
    String locations, {
    String? verifiedPageLabel,
  }) => AnnotationLocationLabel.fromLocatorJson(
    '{"href":"chapter.xhtml","locations":$locations}',
    verifiedPageLabel: verifiedPageLabel,
  );

  test('verified numeric page label displays as Page 12', () {
    expect(label('{"position":42}', verifiedPageLabel: '12')?.text, 'Page 12');
  });

  test('verified Roman-numeral page label remains unchanged', () {
    expect(
      label('{"position":42}', verifiedPageLabel: 'xii')?.text,
      'Page xii',
    );
  });

  test('saved reflowable annotation prefers progression over position', () {
    final result = label('{"position":42,"totalProgression":0.8}');
    expect(result?.kind, AnnotationLocationLabelKind.progression);
    expect(result?.text, '80%');
  });

  test('verified page label takes priority over position', () {
    expect(
      label(
        '{"position":42,"totalProgression":0.8}',
        verifiedPageLabel: '12',
      )?.text,
      'Page 12',
    );
  });

  test('logical position is not exposed as a printed page substitute', () {
    expect(label('{"position":7,"totalProgression":0.74}')?.text, '74%');
    expect(label('{"position":7}'), isNull);
  });

  test('total progression uses nearest whole-percent rounding', () {
    expect(label('{"totalProgression":0.184}')?.text, '18%');
    expect(label('{"totalProgression":0.995}')?.text, '100%');
  });

  test('resource progression is the fallback when total is absent', () {
    expect(label('{"progression":0.74}')?.text, '74%');
  });

  test('progression boundaries display as 0% and 100%', () {
    expect(label('{"totalProgression":0.0}')?.text, '0%');
    expect(label('{"totalProgression":1.0}')?.text, '100%');
  });

  test('invalid position and progression are omitted safely', () {
    for (final locations in [
      '{"position":0}',
      '{"position":-1}',
      '{"totalProgression":-0.1}',
      '{"totalProgression":1.1}',
      '{"totalProgression":"NaN"}',
    ]) {
      expect(label(locations), isNull);
    }
  });

  test('missing locations and malformed locator are unavailable', () {
    expect(AnnotationLocationLabel.fromLocatorJson('{}'), isNull);
    expect(AnnotationLocationLabel.fromLocatorJson('{bad'), isNull);
    expect(
      AnnotationLocationLabel.fromLocatorJson('{"locations":"bad"}'),
      isNull,
    );
  });
}

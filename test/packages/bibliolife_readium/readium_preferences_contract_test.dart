import 'package:bibliolife_readium/bibliolife_readium.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preferences defaults, themes and numeric transport bounds', () {
    expect(ReadiumEpubPreferences.defaults.toMap(), {
      'theme': 'system',
      'fontFamily': 'original',
      'fontSize': 1.0,
      'fontWeight': 1.0,
      'lineHeight': 1.5,
      'pageMargins': 1.0,
      'textAlignment': 'start',
      'scroll': false,
      'columns': 'auto',
      'publisherStyles': true,
    });
    for (final theme in ['system', 'light', 'dark', 'sepia']) {
      final value = ReadiumEpubPreferences.fromMap({'theme': theme});
      expect(value!.theme, theme);
    }
    final value = ReadiumEpubPreferences.fromMap({
      'theme': 'bad',
      'fontSize': 9.0,
      'lineHeight': 0.0,
      'pageMargins': -1.0,
    });
    expect(
      value,
      const ReadiumEpubPreferences(fontSize: 3, lineHeight: 1, pageMargins: 0),
    );
  });
}

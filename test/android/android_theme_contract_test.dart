import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const lightStyles = 'android/app/src/main/res/values/styles.xml';
  const darkStyles = 'android/app/src/main/res/values-night/styles.xml';
  const manifest = 'android/app/src/main/AndroidManifest.xml';
  const activity =
      'android/app/src/main/kotlin/app/bibliolife/reader/MainActivity.kt';
  const readiumStyles =
      'packages/bibliolife_readium/android/src/main/res/values/styles.xml';
  const highlightPresenter =
      'packages/bibliolife_readium/android/src/main/kotlin/app/'
      'bibliolife/reader/readium/ReaderHighlightToolbarPresenter.kt';

  test('launch and normal themes never create an Android ActionBar', () {
    final light = File(lightStyles).readAsStringSync();
    final dark = File(darkStyles).readAsStringSync();

    for (final styles in [light, dark]) {
      expect(
        styles,
        contains('name="LaunchTheme" parent="@android:style/Theme.Material'),
      );
      expect(
        styles,
        contains('name="NormalTheme" parent="@android:style/Theme.Material'),
      );
      expect(styles, contains('NoActionBar'));
      expect(
        styles,
        contains('<item name="android:windowActionBar">false</item>'),
      );
      expect(
        styles,
        contains('<item name="android:windowNoTitle">true</item>'),
      );
    }
  });

  test(
    'MainActivity uses the NoActionBar theme chain without runtime hiding',
    () {
      final manifestSource = File(manifest).readAsStringSync();
      final activitySource = File(activity).readAsStringSync();

      expect(manifestSource, contains('android:theme="@style/LaunchTheme"'));
      expect(manifestSource, contains('android:resource="@style/NormalTheme"'));
      expect(activitySource, isNot(contains('actionBar?.hide()')));
      expect(activitySource, isNot(contains('supportActionBar')));
      expect(
        activitySource,
        contains('requestWindowFeature(Window.FEATURE_NO_TITLE)'),
      );
    },
  );

  test('Readium popup scopes Material 3 attributes without retheming Flutter', () {
    final styles = File(readiumStyles).readAsStringSync();
    final presenter = File(highlightPresenter).readAsStringSync();

    expect(
      styles,
      contains(
        'name="BiblioLifeReadiumPopupTheme" '
        'parent="Theme.Material3.DayNight.NoActionBar"',
      ),
    );
    expect(
      presenter,
      contains(
        'ContextThemeWrapper(context, R.style.BiblioLifeReadiumPopupTheme)',
      ),
    );
    expect(presenter, contains('MaterialButton(presentationContext)'));
    expect(presenter, isNot(contains('MaterialButton(context)')));
  });
}

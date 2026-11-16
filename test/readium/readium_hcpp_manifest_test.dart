import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

void main() {
  test('main manifest enables HCPP exactly once', () {
    final manifest = XmlDocument.parse(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
    );
    final entries = manifest
        .findAllElements('meta-data')
        .where(
          (element) =>
              element.getAttribute(
                'name',
                namespaceUri: 'http://schemas.android.com/apk/res/android',
              ) ==
              'io.flutter.embedding.android.EnableHcpp',
        )
        .toList();

    expect(entries, hasLength(1));
    expect(
      entries.single.getAttribute(
        'value',
        namespaceUri: 'http://schemas.android.com/apk/res/android',
      ),
      'true',
    );
  });
}

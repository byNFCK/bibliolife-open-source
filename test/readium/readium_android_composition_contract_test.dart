import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Readium selects HCPP with an exact legacy HC fallback', () {
    final viewport = File(
      '${_repositoryRoot().path}/packages/bibliolife_readium/lib/src/bridge/readium_epub_viewport.dart',
    ).readAsStringSync();

    expect(viewport, contains('HybridAndroidViewController.checkIfSupported'));
    expect(viewport, contains('PlatformViewsService.initHybridAndroidView('));
    expect(
      viewport,
      contains('PlatformViewsService.initExpensiveAndroidView('),
    );
    expect(
      viewport,
      isNot(contains('PlatformViewsService.initSurfaceAndroidView(')),
    );
    expect(viewport, isNot(contains('PlatformViewsService.initAndroidView(')));
    expect(viewport, contains('PlatformViewLink('));
    expect(viewport, contains('AndroidViewSurface('));
    expect('viewType: params.viewType'.allMatches(viewport), hasLength(2));
    expect(
      'creationParams: _effectiveConfiguration.toMap()'.allMatches(viewport),
      hasLength(2),
    );
    expect(
      'creationParamsCodec: const StandardMessageCodec()'.allMatches(viewport),
      hasLength(2),
    );
    expect(
      'onFocus: () => params.onFocusChanged(true)'.allMatches(viewport),
      hasLength(2),
    );
    expect(
      viewport,
      contains(
        'gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{}',
      ),
    );
    expect(
      viewport,
      contains('hitTestBehavior: PlatformViewHitTestBehavior.opaque'),
    );
  });
}

Directory _repositoryRoot() {
  var directory = Directory.current;
  while (directory.parent.path != directory.path) {
    if (File('${directory.path}/pubspec.yaml').existsSync() &&
        Directory('${directory.path}/packages').existsSync()) {
      return directory;
    }
    directory = directory.parent;
  }
  throw StateError('Could not locate the BiblioLife repository root');
}

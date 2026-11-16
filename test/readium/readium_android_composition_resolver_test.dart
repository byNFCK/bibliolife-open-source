import 'package:bibliolife_readium/bibliolife_readium.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('support true resolves HCPP and is memoized', () async {
    var probes = 0;
    final resolver = ReadiumAndroidCompositionResolver(
      supportProbe: () async {
        probes++;
        return true;
      },
    );

    final first = await resolver.resolve();
    final second = await resolver.resolve();

    expect(first.backend, ReadiumAndroidCompositionBackend.hcpp);
    expect(first.supportCheck, ReadiumHcppSupportCheck.supported);
    expect(identical(first, second), isTrue);
    expect(probes, 1);
  });

  test('support false resolves the legacy Hybrid Composition path', () async {
    final resolution = await ReadiumAndroidCompositionResolver(
      supportProbe: () async => false,
    ).resolve();

    expect(
      resolution.backend,
      ReadiumAndroidCompositionBackend.legacyHybridComposition,
    );
    expect(resolution.supportCheck, ReadiumHcppSupportCheck.unsupported);
    expect(resolution.controllerLabel, 'ExpensiveAndroidViewController');
  });

  test('support-check exception safely resolves the legacy path', () async {
    final resolution = await ReadiumAndroidCompositionResolver(
      supportProbe: () async => throw StateError('unavailable'),
    ).resolve();

    expect(
      resolution.backend,
      ReadiumAndroidCompositionBackend.legacyHybridComposition,
    );
    expect(resolution.supportCheck, ReadiumHcppSupportCheck.error);
    expect(resolution.supportCheckLabel, 'error');
  });
}

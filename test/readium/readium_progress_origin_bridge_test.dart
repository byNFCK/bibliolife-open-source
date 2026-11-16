import 'package:bibliolife_readium/bibliolife_readium.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'owned canonical origin crosses method channel intact with resource and global domains distinct',
    () async {
      const origin =
          '{"href":"chapter.xhtml","type":"application/xhtml+xml","locations":{"progression":0.375,"totalProgression":0.2,"position":42,"cssSelector":"p:nth-child(8)"},"text":{"highlight":"anchor"}}';
      const channel = MethodChannel('phase5-origin');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {
          'ok': true,
          'value': {'status': 'completed'},
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final client = MethodChannelReadiumBridgeClient(
        const ReadiumEpubOpenConfiguration(
          instanceId: 'phase5',
          bookId: 'book',
          localFilePath: '/book.epub',
        ),
        commandChannel: channel,
        eventChannel: const EventChannel('phase5-origin-events'),
      );
      await client.attachToPlatform();
      final result = await client.goToProgressLocatorOwned(
        progression: .2,
        locatorJson: origin,
        readingOrderIndex: 3,
        progressOwner: const ReadiumProgressNavigationOwner(
          sessionId: 7,
          requestId: 1,
          phase: 'final',
        ),
      );
      expect(result.isCompleted, true);
      expect(calls.single.method, ReadiumBridgeConstants.goToProgression);
      expect(calls.single.arguments, {
        'progression': .2,
        'animated': false,
        'originLocatorJson': origin,
        'originReadingOrderIndex': 3,
        'progressOwner': {'sessionId': 7, 'requestId': 1, 'phase': 'final'},
      });
      await client.dispose();
    },
  );
}

import 'dart:async';

import 'package:bibliolife_readium/bibliolife_readium.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('renders only the injected content view and starts once', (
    tester,
  ) async {
    final client = FakeViewportClient();
    final controller = ReadiumEpubController(
      configuration: const ReadiumEpubOpenConfiguration(
        instanceId: 'reader-1',
        bookId: 'book',
        localFilePath: '/book.epub',
      ),
      client: client,
    );
    var readyCalls = 0;
    var builderCalls = 0;
    var createdCalls = 0;

    Widget builder(
      BuildContext context,
      ReadiumEpubOpenConfiguration configuration,
      ValueChanged<int> onCreated,
    ) {
      builderCalls++;
      final createPlatformView = onCreated;
      onCreated = (id) {
        if (createdCalls == 0) createdCalls++;
        createPlatformView(id);
      };
      if (createdCalls == 0) onCreated(42);
      return const SizedBox(key: ValueKey<String>('epub-content'));
    }

    await tester.pumpWidget(
      ReadiumEpubViewport(
        configuration: const ReadiumEpubOpenConfiguration(
          instanceId: 'reader-1',
          bookId: 'book',
          localFilePath: '/book.epub',
        ),
        controller: controller,
        platformViewBuilder: builder,
        onControllerReady: (_) => readyCalls++,
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey<String>('epub-content')), findsOneWidget);
    expect(find.byType(Scaffold), findsNothing);
    expect(builderCalls, 1);
    expect(createdCalls, 1);
    expect(readyCalls, 1);
    expect(client.attachCalls, 1);

    await tester.pumpWidget(
      ReadiumEpubViewport(
        configuration: const ReadiumEpubOpenConfiguration(
          instanceId: 'reader-1',
          bookId: 'book',
          localFilePath: '/book.epub',
        ),
        controller: controller,
        platformViewBuilder: builder,
      ),
    );
    await tester.pump();

    expect(builderCalls, 2);
    expect(createdCalls, 1);
    expect(client.attachCalls, 1);
    await tester.pumpWidget(const SizedBox());
    expect(client.disposeCalls, 0);
    await tester.runAsync(controller.dispose);
  });

  testWidgets(
    'disposes an internally owned controller but not an external one',
    (tester) async {
      final disposed = Completer<void>();
      final client = FakeViewportClient(onDisposed: disposed.complete);
      await tester.pumpWidget(
        ReadiumEpubViewport(
          configuration: const ReadiumEpubOpenConfiguration(
            instanceId: 'reader-2',
            bookId: 'book',
            localFilePath: '/book.epub',
          ),
          clientFactory: (_) => client,
          platformViewBuilder: (context, configuration, onCreated) {
            onCreated(7);
            return const SizedBox();
          },
        ),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() => disposed.future);

      expect(client.disposeCalls, 1);
    },
  );

  testWidgets('rejects a duplicate active logical instance ID', (tester) async {
    final firstClient = FakeViewportClient();
    final secondClient = FakeViewportClient();
    Widget view(FakeViewportClient client) => ReadiumEpubViewport(
      configuration: const ReadiumEpubOpenConfiguration(
        instanceId: 'duplicate-reader',
        bookId: 'book',
        localFilePath: '/book.epub',
      ),
      clientFactory: (_) => client,
      platformViewBuilder: (context, configuration, onCreated) {
        onCreated(1);
        return const SizedBox(key: ValueKey<String>('native-content'));
      },
    );

    await tester.pumpWidget(
      Column(
        children: <Widget>[
          SizedBox(height: 250, child: view(firstClient)),
          SizedBox(height: 250, child: view(secondClient)),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(firstClient.attachCalls, 1);
    expect(secondClient.attachCalls, 0);
    expect(
      find.byKey(const ValueKey<String>('native-content')),
      findsOneWidget,
    );
  });

  testWidgets(
    'forwards native content taps and replaces callback without recreating view',
    (tester) async {
      final client = FakeViewportClient();
      final controller = ReadiumEpubController(
        configuration: const ReadiumEpubOpenConfiguration(
          instanceId: 'reader-tap',
          bookId: 'book',
          localFilePath: '/book.epub',
        ),
        client: client,
      );
      var createdCalls = 0;
      final first = <ReadiumContentTapEvent>[];
      final second = <ReadiumContentTapEvent>[];

      Widget view(ValueChanged<ReadiumContentTapEvent>? callback) =>
          ReadiumEpubViewport(
            configuration: const ReadiumEpubOpenConfiguration(
              instanceId: 'reader-tap',
              bookId: 'book',
              localFilePath: '/book.epub',
            ),
            controller: controller,
            onContentTap: callback,
            platformViewBuilder: (context, configuration, onCreated) {
              return Builder(
                builder: (context) {
                  if (createdCalls == 0) {
                    createdCalls++;
                    onCreated(11);
                  }
                  return const SizedBox(key: ValueKey<String>('tap-content'));
                },
              );
            },
          );

      await tester.pumpWidget(view(first.add));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      client.emit(_tapEvent(1, 1));
      await tester.pump();
      expect(first, hasLength(1));

      await tester.pumpWidget(view(second.add));
      await tester.pump();
      client.emit(_tapEvent(2, 2));
      await tester.pump();
      expect(first, hasLength(1));
      expect(second, hasLength(1));
      expect(createdCalls, 1);
      expect(find.byType(GestureDetector), findsNothing);
      expect(find.byType(Listener), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(client.disposeCalls, 0);
      await tester.runAsync(controller.dispose);
    },
  );

  testWidgets('route reopen creates a fresh viewport identity and controller', (
    tester,
  ) async {
    final clients = <FakeViewportClient>[];
    final instanceIds = <String>[];
    var nextId = 0;

    ReadiumEpubViewport viewport() => ReadiumEpubViewport(
      configuration: const ReadiumEpubOpenConfiguration(
        bookId: 'book',
        localFilePath: '/book.epub',
      ),
      instanceIdFactory: () => 'reopen-${++nextId}',
      clientFactory: (configuration) {
        instanceIds.add(configuration.instanceId!);
        final client = FakeViewportClient();
        clients.add(client);
        return client;
      },
      platformViewBuilder: (context, configuration, onCreated) {
        onCreated(nextId);
        return const SizedBox();
      },
    );

    await tester.pumpWidget(viewport());
    for (var index = 0; index < 6; index++) {
      await tester.pump();
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(viewport());
    for (var index = 0; index < 6; index++) {
      await tester.pump();
    }

    expect(instanceIds, ['reopen-1', 'reopen-2']);
    expect(clients, hasLength(2));
    expect(clients.first.attachCalls, 1);
    expect(clients.first.disposeCalls, 1);
    expect(clients.last.attachCalls, 1);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('does not create a platform view before backend resolution', (
    tester,
  ) async {
    final support = Completer<bool>();
    final resolver = ReadiumAndroidCompositionResolver(
      supportProbe: () => support.future,
    );
    var builderCalls = 0;

    await tester.pumpWidget(
      ReadiumEpubViewport(
        configuration: const ReadiumEpubOpenConfiguration(
          instanceId: 'pending-composition',
          bookId: 'book',
          localFilePath: '/book.epub',
        ),
        clientFactory: (_) => FakeViewportClient(),
        compositionResolver: resolver,
        platformViewBuilder: (context, configuration, onCreated) {
          builderCalls++;
          return const SizedBox(
            key: ValueKey<String>('resolved-platform-view'),
          );
        },
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('readium-composition-resolving')),
      findsOneWidget,
    );
    expect(builderCalls, 0);

    support.complete(true);
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('resolved-platform-view')),
      findsOneWidget,
    );
    expect(builderCalls, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ignores a support result that arrives after disposal', (
    tester,
  ) async {
    final support = Completer<bool>();
    var builderCalls = 0;

    await tester.pumpWidget(
      ReadiumEpubViewport(
        configuration: const ReadiumEpubOpenConfiguration(
          instanceId: 'disposed-before-resolution',
          bookId: 'book',
          localFilePath: '/book.epub',
        ),
        clientFactory: (_) => FakeViewportClient(),
        compositionResolver: ReadiumAndroidCompositionResolver(
          supportProbe: () => support.future,
        ),
        platformViewBuilder: (context, configuration, onCreated) {
          builderCalls++;
          return const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(const SizedBox());

    support.complete(true);
    await tester.pump();

    expect(builderCalls, 0);
  });

  testWidgets(
    'route reopen reuses capability but creates a view for each viewport',
    (tester) async {
      var probes = 0;
      var builderCalls = 0;
      final resolver = ReadiumAndroidCompositionResolver(
        supportProbe: () async {
          probes++;
          return true;
        },
      );

      ReadiumEpubViewport viewport(String instanceId) => ReadiumEpubViewport(
        configuration: ReadiumEpubOpenConfiguration(
          instanceId: instanceId,
          bookId: 'book',
          localFilePath: '/book.epub',
        ),
        clientFactory: (_) => FakeViewportClient(),
        compositionResolver: resolver,
        platformViewBuilder: (context, configuration, onCreated) {
          builderCalls++;
          return SizedBox(key: ValueKey<String>(configuration.instanceId!));
        },
      );

      await tester.pumpWidget(viewport('cached-capability-1'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(viewport('cached-capability-2'));
      await tester.pump();

      expect(probes, 1);
      expect(builderCalls, 2);
      expect(
        find.byKey(const ValueKey<String>('cached-capability-2')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('rapid reopen cannot attach the disposed pending viewport', (
    tester,
  ) async {
    final support = Completer<bool>();
    var probes = 0;
    final builds = <String>[];
    final resolver = ReadiumAndroidCompositionResolver(
      supportProbe: () {
        probes++;
        return support.future;
      },
    );

    ReadiumEpubViewport viewport(String instanceId) => ReadiumEpubViewport(
      configuration: ReadiumEpubOpenConfiguration(
        instanceId: instanceId,
        bookId: 'book',
        localFilePath: '/book.epub',
      ),
      clientFactory: (_) => FakeViewportClient(),
      compositionResolver: resolver,
      platformViewBuilder: (context, configuration, onCreated) {
        builds.add(configuration.instanceId!);
        return const SizedBox();
      },
    );

    await tester.pumpWidget(viewport('rapid-reopen-1'));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(viewport('rapid-reopen-2'));

    support.complete(true);
    await tester.pump();
    await tester.pump();

    expect(probes, 1);
    expect(builds, ['rapid-reopen-2']);
    await tester.pumpWidget(const SizedBox());
  });
}

final class FakeViewportClient implements ReadiumBridgeClient {
  FakeViewportClient({this.onDisposed});

  final void Function()? onDisposed;
  final StreamController<ReadiumReaderEvent> _events =
      StreamController<ReadiumReaderEvent>.broadcast();
  @override
  Stream<ReadiumReaderEvent> get events => _events.stream;
  int attachCalls = 0;
  int disposeCalls = 0;

  void emit(ReadiumReaderEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  Future<void> attachToPlatform() async => attachCalls++;

  @override
  Future<ReadiumBridgeInfo> getBridgeInfo() async =>
      const ReadiumBridgeInfo(protocolVersion: 1, instanceId: 'reader');

  @override
  Future<ReadiumReaderSnapshot> getSnapshot() async =>
      throw UnimplementedError();

  @override
  Future<ReadiumNavigationResult> next({bool animated = false}) =>
      Future.value(const ReadiumNavigationResult('completed'));

  @override
  Future<ReadiumNavigationResult> previous({bool animated = false}) =>
      Future.value(const ReadiumNavigationResult('completed'));

  @override
  Future<ReadiumNavigationResult> goToProgression(
    double progression, {
    bool animated = false,
  }) => Future.value(const ReadiumNavigationResult('completed'));

  @override
  Future<ReadiumNavigationResult> goToLocatorJson(
    String locatorJson, {
    bool animated = false,
  }) => Future.value(const ReadiumNavigationResult('completed'));

  @override
  Future<ReadiumPreferenceResult> applyPreferences(
    ReadiumEpubPreferences preferences,
  ) => Future.value(const ReadiumPreferenceResult('applied'));

  @override
  Future<ReadiumNavigationResult> goToTocEntry(
    String entryId, {
    bool animated = true,
  }) => Future.value(const ReadiumNavigationResult('completed'));

  @override
  Future<ReadiumSearchCommandResult> search(String query) =>
      Future.value(const ReadiumSearchCommandResult('started'));

  @override
  Future<ReadiumSearchCommandResult> cancelSearch() =>
      Future.value(const ReadiumSearchCommandResult('cancelled'));

  @override
  Future<ReadiumSearchCommandResult> clearSearch() =>
      Future.value(const ReadiumSearchCommandResult('cleared'));

  @override
  Future<ReadiumSearchCommandResult> goToSearchResult(
    String resultId, {
    bool animated = false,
  }) => Future.value(const ReadiumSearchCommandResult('completed'));

  @override
  Future<ReadiumDecorationResult> setDecorations(
    ReadiumDecorationGroup group,
    List<ReadiumDecorationSpec> decorations,
  ) => Future.value(const ReadiumDecorationResult('applied'));

  @override
  Future<ReadiumDecorationResult> upsertDecoration(
    ReadiumDecorationGroup group,
    ReadiumDecorationSpec decoration,
  ) => Future.value(const ReadiumDecorationResult('applied'));

  @override
  Future<ReadiumDecorationResult> removeDecoration(
    ReadiumDecorationGroup group,
    String id,
  ) => Future.value(const ReadiumDecorationResult('cleared'));

  @override
  Future<ReadiumDecorationResult> clearDecorations(
    ReadiumDecorationGroup group,
  ) => Future.value(const ReadiumDecorationResult('cleared'));

  @override
  Future<ReadiumSelectionResult> requestCurrentSelection() =>
      Future.value(const ReadiumSelectionResult('empty'));

  @override
  Future<ReadiumSelectionResult> clearSelection() =>
      Future.value(const ReadiumSelectionResult('cleared'));

  @override
  Future<void> dispose() async {
    disposeCalls++;
    onDisposed?.call();
    await _events.close();
  }
}

ReadiumContentTapEvent _tapEvent(int sequence, int interactionId) =>
    ReadiumContentTapEvent(
      metadata: ReadiumEventMetadata(
        1,
        'reader-tap',
        sequence,
        ReadiumBridgeConstants.contentTap,
      ),
      interactionId: interactionId,
      viewportGeneration: 0,
    );

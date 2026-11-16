import 'dart:async';

import 'package:bibliolife_readium/bibliolife_readium.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Readium bridge protocol', () {
    test('parses live manual position and scroll activity events', () {
      final livePosition =
          ReadiumReaderEvent.parse(<String, Object?>{
                'protocolVersion': 1,
                'instanceId': 'reader-1',
                'sequence': 1,
                'type': 'positionChanged',
                'payload': <String, Object?>{
                  'href': 'chapter.xhtml',
                  'progression': .44,
                  'liveManual': true,
                },
              })
              as ReadiumPositionEvent;
      final activity =
          ReadiumReaderEvent.parse(<String, Object?>{
                'protocolVersion': 1,
                'instanceId': 'reader-1',
                'sequence': 2,
                'type': 'manualScrollActivityChanged',
                'payload': <String, Object?>{'active': true},
              })
              as ReadiumManualScrollActivityEvent;

      expect(livePosition.liveManual, isTrue);
      expect(livePosition.position.progression, .44);
      expect(activity.active, isTrue);
    });

    test('position payload keeps logical count distinct from progression', () {
      final position = ReadiumPosition.fromMap(<String, Object?>{
        'href': 'chapter.xhtml',
        'position': 42,
        'totalLogicalPositions': 120,
        'progression': .41,
        'totalProgression': .4,
      });

      expect(position.position, 42);
      expect(position.totalLogicalPositions, 120);
      expect(position.progression, .41);
      expect(position.totalProgression, .4);
      expect(position.presentation, isA<ReadiumUnknownPresentation>());
    });

    test('parses typed ephemeral rendered pagination', () {
      final position = ReadiumPosition.fromMap(<String, Object?>{
        'href': 'chapter.xhtml',
        'progression': .5,
        'presentation': <String, Object?>{
          'mode': 'paginated',
          'pageIndex': 3,
          'pageCount': 7,
          'progression': .5,
          'layoutGeneration': 4,
          'publicationScoped': true,
        },
      });

      final rendered = position.presentation as ReadiumPaginatedPresentation;
      expect(rendered.pageIndex, 3);
      expect(rendered.pageCount, 7);
      expect(rendered.progression, .5);
      expect(rendered.layoutGeneration, 4);
      expect(rendered.publicationScoped, isTrue);
    });

    test('derives native channel names with URL-safe instance IDs', () {
      final names = ReadiumBridgeConstants.channelNames(' book/東京 ');

      expect(names.command, contains('/reader/'));
      expect(names.events, endsWith('/events'));
      expect(names.command, isNot(contains('=')));
      expect(names.command, isNot(contains('/reader/book/')));
      expect(names.command, startsWith('app.bibliolife.reader.readium/reader/'));
      expect(names.encodedInstanceId, isNot(contains('/')));
    });

    test('serializes the exact native creation contract', () {
      const configuration = ReadiumEpubOpenConfiguration(
        instanceId: 'reader-1',
        bookId: 'book-1',
        localFilePath: 'C:/books/book.epub',
        initialLocatorJson: '{"href":"chapter.xhtml"}',
        initialPreferences: ReadiumEpubPreferences(
          theme: 'dark',
          fontSize: 1.25,
        ),
        initialPreferencesAreAuthoritative: true,
        isNightMode: true,
      );

      expect(configuration.toMap(), <String, Object?>{
        'instanceId': 'reader-1',
        'bookId': 'book-1',
        'localFilePath': 'C:/books/book.epub',
        'initialLocatorJson': '{"href":"chapter.xhtml"}',
        'initialPreferences': <String, Object>{
          'theme': 'dark',
          'fontFamily': 'original',
          'fontSize': 1.25,
          'fontWeight': 1.0,
          'lineHeight': 1.5,
          'pageMargins': 1.0,
          'textAlignment': 'start',
          'scroll': false,
          'columns': 'auto',
          'publisherStyles': true,
        },
        'initialPreferencesAreAuthoritative': true,
        'isNightMode': true,
        'bridgeProtocolVersion': 1,
      });
    });

    test('rejects invalid creation identity and protocol', () {
      expect(
        () => const ReadiumEpubOpenConfiguration(
          bookId: 'book',
          localFilePath: '/book.epub',
        ).toMap(),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => const ReadiumEpubOpenConfiguration(
          instanceId: 'reader',
          bookId: 'book',
          localFilePath: '/book.epub',
          protocolVersion: 99,
        ).toMap(),
        throwsA(isA<FormatException>()),
      );
    });

    test('client sends exact native method names and arguments', () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final commandChannel = const MethodChannel('readium-test-commands');
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(commandChannel, (call) async {
        calls.add(call);
        return <String, Object?>{
          'ok': true,
          'value': <String, Object?>{'status': 'completed'},
        };
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(commandChannel, null),
      );

      final client = MethodChannelReadiumBridgeClient(
        const ReadiumEpubOpenConfiguration(
          instanceId: 'reader-1',
          bookId: 'book',
          localFilePath: '/book.epub',
        ),
        commandChannel: commandChannel,
        eventChannel: const EventChannel('readium-test-events'),
      );
      await client.attachToPlatform();
      final result = await client.next(animated: true);
      await client.goToProgression(.76);
      final search = await client.search('  query  ');
      await client.settingsReflowGesture(42, 'fontSize', 'begin', 1.0);
      await client.settingsReflowGesture(42, 'fontSize', 'end', 1.7);
      await client.dispose();

      expect(result.status, 'completed');
      expect(search.status, 'completed');
      expect(calls[0].method, ReadiumBridgeConstants.next);
      expect(calls[0].arguments, <String, Object?>{'animated': true});
      expect(calls[1].method, ReadiumBridgeConstants.goToProgression);
      expect(calls[1].arguments, <String, Object?>{
        'progression': .76,
        'animated': false,
      });
      expect(calls[2].method, ReadiumBridgeConstants.search);
      expect(calls[2].arguments, <String, Object?>{'query': 'query'});
      expect(calls[3].method, ReadiumBridgeConstants.settingsReflowGesture);
      expect(calls[3].arguments, <String, Object?>{
        'gestureId': 42,
        'slider': 'fontSize',
        'action': 'begin',
        'value': 1.0,
      });
      expect(calls[4].arguments, <String, Object?>{
        'gestureId': 42,
        'slider': 'fontSize',
        'action': 'end',
        'value': 1.7,
      });
    });

    test(
      'rejects out-of-contract preferences instead of clamping them',
      () async {
        final client = MethodChannelReadiumBridgeClient(
          const ReadiumEpubOpenConfiguration(
            instanceId: 'reader-1',
            bookId: 'book',
            localFilePath: '/book.epub',
          ),
          commandChannel: const MethodChannel('readium-pref-commands'),
          eventChannel: const EventChannel('readium-pref-events'),
        );
        await client.attachToPlatform();
        expect(
          () => client.applyPreferences(
            const ReadiumEpubPreferences(fontSize: 9),
          ),
          throwsA(isA<FormatException>()),
        );
        await client.dispose();
      },
    );

    test('parses event metadata and ignores unknown future event types', () {
      final event = ReadiumReaderEvent.parse(<String, Object?>{
        'protocolVersion': 1,
        'instanceId': 'reader-1',
        'sequence': 4,
        'type': 'future_event',
        'payload': <String, Object?>{},
      });

      expect(event, isA<ReadiumUnknownEvent>());
      expect(event.sequence, 4);
      expect(
        () => ReadiumReaderEvent.parse(<String, Object?>{
          'protocolVersion': 2,
          'instanceId': 'reader-1',
          'sequence': 1,
          'type': 'future_event',
        }),
        throwsA(isA<ReadiumBridgeFormatException>()),
      );
    });

    test('preserves opaque semantic anchor comparison without book text', () {
      final event =
          ReadiumReaderEvent.parse(<String, Object?>{
                'protocolVersion': 1,
                'instanceId': 'reader-1',
                'sequence': 4,
                'type': ReadiumBridgeConstants.readerDiagnostic,
                'payload': <String, Object?>{
                  'kind': 'semantic_anchor_compare',
                  'semanticAnchorQuality': 'EXACT_DOM_POINT',
                  'anchorIdentityType': 'exact_dom_point',
                  'anchorIdentityId': '7',
                  'anchorCharacterOffset': 12,
                  'sameResource': true,
                  'sameDomIdentity': true,
                  'sameCharacterOffset': true,
                  'semanticAnchorExact': true,
                  'fallbackUsed': false,
                  'finalDeltaPx': -0.15,
                  'pointToTargetOffsetPx': -9.0,
                  'originalTargetViewportYPx': 556.551,
                  'actualFinalViewportYPx': 556.14,
                  'cumulativeDriftFromGestureStartPx': -0.411,
                  'bookText': 'must be discarded',
                },
              })
              as ReadiumDiagnosticEvent;
      expect(event.fields['sameDomIdentity'], true);
      expect(event.fields['sameCharacterOffset'], true);
      expect(event.fields['anchorCharacterOffset'], 12);
      expect(event.fields['semanticAnchorQuality'], 'EXACT_DOM_POINT');
      expect(event.fields['fallbackUsed'], false);
      expect(event.fields['finalDeltaPx'], -0.15);
      expect(event.fields['pointToTargetOffsetPx'], -9.0);
      expect(event.fields['originalTargetViewportYPx'], 556.551);
      expect(event.fields['cumulativeDriftFromGestureStartPx'], -0.411);
      expect(event.fields.containsKey('bookText'), false);
    });

    test(
      'preserves no-op physical work diagnostics without content fields',
      () {
        final event =
            ReadiumReaderEvent.parse(<String, Object?>{
                  'protocolVersion': 1,
                  'instanceId': 'reader-1',
                  'sequence': 4,
                  'type': ReadiumBridgeConstants.readerDiagnostic,
                  'payload': <String, Object?>{
                    'kind': 'reflow_path',
                    'result': 'no_op',
                    'reason': 'same_height_anchor_stable',
                    'geometryMutation': false,
                    'scrollRequested': false,
                    'postRestoreLayoutPass': false,
                    'fullGeometryBatchApplied': false,
                    'coherent': true,
                    'bookText': 'discard',
                  },
                })
                as ReadiumDiagnosticEvent;
        expect(event.fields['result'], 'no_op');
        expect(event.fields['geometryMutation'], false);
        expect(event.fields['scrollRequested'], false);
        expect(event.fields['postRestoreLayoutPass'], false);
        expect(event.fields['fullGeometryBatchApplied'], false);
        expect(event.fields['coherent'], true);
        expect(event.fields.containsKey('bookText'), false);
      },
    );

    test(
      'preserves text render metrics and font state without book content',
      () {
        final event =
            ReadiumReaderEvent.parse(<String, Object?>{
                  'protocolVersion': 1,
                  'instanceId': 'reader-1',
                  'sequence': 4,
                  'type': ReadiumBridgeConstants.readerDiagnostic,
                  'payload': <String, Object?>{
                    'kind': 'webview_text_render_snapshot',
                    'snapshotStage': 'after_measurement',
                    'fontFamily': '"Example Font", serif',
                    'fontVariationSettings': '"wght" 650',
                    'rangeTopPx': 22.25,
                    'rangeHeightDeltaPx': -0.25,
                    'sameDomIdentity': true,
                    'forced_layout_sample': true,
                    'activeFontCheck': true,
                    'syntheticWeightLikely': 'unknown',
                    'bookText': 'SECRET',
                    'html': '<p>SECRET</p>',
                  },
                })
                as ReadiumDiagnosticEvent;
        expect(event.fields['fontFamily'], '"Example Font", serif');
        expect(event.fields['fontVariationSettings'], '"wght" 650');
        expect(event.fields['rangeTopPx'], 22.25);
        expect(event.fields['rangeHeightDeltaPx'], -0.25);
        expect(event.fields['activeFontCheck'], true);
        expect(event.fields['syntheticWeightLikely'], 'unknown');
        expect(event.fields['forced_layout_sample'], true);
        expect(event.fields.toString(), isNot(contains('SECRET')));
      },
    );

    test('preserves CSS generation consistency without content fields', () {
      final event =
          ReadiumReaderEvent.parse(<String, Object?>{
                'protocolVersion': 1,
                'instanceId': 'reader-1',
                'sequence': 4,
                'type': ReadiumBridgeConstants.readerDiagnostic,
                'payload': <String, Object?>{
                  'kind': 'reflow_consistency',
                  'cssGeneration': 91,
                  'activeCssPreferenceGeneration': 39,
                  'activeCssLayoutGeneration': 12,
                  'committedGeometryPreferenceGeneration': 39,
                  'committedGeometryLayoutGeneration': 12,
                  'cssHeightMeasurementKnown': true,
                  'coherent': true,
                  'webViewHeightPx': 700,
                  'parentResourceHeightPx': 700,
                  'measurementResult': 'same_height',
                  'body': 'discard',
                },
              })
              as ReadiumDiagnosticEvent;
      expect(event.fields['activeCssPreferenceGeneration'], 39);
      expect(event.fields['committedGeometryPreferenceGeneration'], 39);
      expect(event.fields['coherent'], true);
      expect(event.fields['measurementResult'], 'same_height');
      expect(event.fields.containsKey('body'), false);
    });

    test('parses reflow diagnostics with only the safe field whitelist', () {
      final event =
          ReadiumReaderEvent.parse(<String, Object?>{
                'protocolVersion': 1,
                'instanceId': 'reader-1',
                'sequence': 4,
                'type': ReadiumBridgeConstants.readerDiagnostic,
                'payload': <String, Object?>{
                  'kind': 'measurement_accepted',
                  'gestureId': 8,
                  'slider': 'fontSize',
                  'newHeightPx': 412.0,
                  'preferenceGeneration': 9,
                  'source': 'reflow_committed',
                  'readingOrderIndex': 6,
                  'logicalPosition': 143,
                  'positionProgression': 0.42,
                  'bookText': 'must not enter logs',
                  'fullPath': 'private/path.epub',
                  'unknown': <String, Object?>{'nested': 'ignored'},
                },
              })
              as ReadiumDiagnosticEvent;

      expect(event.fields, <String, Object?>{
        'gestureId': 8,
        'newHeightPx': 412.0,
        'kind': 'measurement_accepted',
        'slider': 'fontSize',
        'preferenceGeneration': 9,
        'source': 'reflow_committed',
        'readingOrderIndex': 6,
        'logicalPosition': 143,
        'positionProgression': 0.42,
      });
    });

    test('keeps bounded viewport snapshots and nullable dispatch timing', () {
      final snapshot =
          ReadiumReaderEvent.parse(<String, Object?>{
                'protocolVersion': 1,
                'instanceId': 'reader-1',
                'sequence': 5,
                'type': ReadiumBridgeConstants.readerDiagnostic,
                'payload': <String, Object?>{
                  'kind': 'viewport_snapshot',
                  'snapshotStage': 'after_anchor_verified',
                  'viewportFirstVisibleIndex': 6,
                  'viewportFirstVisibleTopPx': -18,
                  'webViewIdentity': 2468,
                  'anchorPointAvailable': true,
                  'anchorSemanticMatch': true,
                  'anchorViewportDeltaPx': 2.5,
                  'anchorPointUnavailableReason': 'none',
                  'anchorBeforeY': -8.0,
                  'anchorBeforeYCoordinateSpace': 'recycler_view_px',
                  'batchHeightDeltaPx': -12,
                  'anchorResourceHref': 'OEBPS/chapter-6.xhtml',
                  'anchorResourceHrefUnavailableReason': 'none',
                  'targetViewportYPx': 34.5,
                  'actualViewportYPx': 36.0,
                  'viewportFirstVisibleIndexBefore': 5,
                  'viewportFirstVisibleIndexAfter': 6,
                  'viewportScrollReason': 'anchor_restore',
                  'fullPath': 'private/book.epub',
                  'rawLocator': <String, Object?>{'text': 'private book text'},
                  'unsafeHref': 'OEBPS/chapter.xhtml?secret=token',
                },
              })
              as ReadiumDiagnosticEvent;
      expect(snapshot.fields, <String, Object?>{
        'kind': 'viewport_snapshot',
        'snapshotStage': 'after_anchor_verified',
        'viewportFirstVisibleIndex': 6,
        'viewportFirstVisibleTopPx': -18.0,
        'webViewIdentity': 2468,
        'anchorPointAvailable': true,
        'anchorSemanticMatch': true,
        'anchorViewportDeltaPx': 2.5,
        'anchorPointUnavailableReason': 'none',
        'anchorBeforeY': -8.0,
        'anchorBeforeYCoordinateSpace': 'recycler_view_px',
        'batchHeightDeltaPx': -12.0,
        'anchorResourceHref': 'OEBPS/chapter-6.xhtml',
        'anchorResourceHrefUnavailableReason': 'none',
        'targetViewportYPx': 34.5,
        'actualViewportYPx': 36.0,
        'viewportFirstVisibleIndexBefore': 5,
        'viewportFirstVisibleIndexAfter': 6,
        'viewportScrollReason': 'anchor_restore',
      });

      final firstDispatch =
          ReadiumReaderEvent.parse(<String, Object?>{
                'protocolVersion': 1,
                'instanceId': 'reader-1',
                'sequence': 6,
                'type': ReadiumBridgeConstants.readerDiagnostic,
                'payload': <String, Object?>{
                  'kind': 'preview_dispatch',
                  'dispatchStage': 'native_session_received',
                  'activeApply': true,
                  'pendingLatest': false,
                  'intervalSincePreviousMs': double.nan,
                },
              })
              as ReadiumDiagnosticEvent;
      expect(firstDispatch.fields, <String, Object?>{
        'kind': 'preview_dispatch',
        'dispatchStage': 'native_session_received',
        'activeApply': true,
        'pendingLatest': false,
      });

      final unsafeHref =
          ReadiumReaderEvent.parse(<String, Object?>{
                'protocolVersion': 1,
                'instanceId': 'reader-1',
                'sequence': 7,
                'type': ReadiumBridgeConstants.readerDiagnostic,
                'payload': <String, Object?>{
                  'kind': 'viewport_snapshot',
                  'anchorResourceHref': 'OEBPS/chapter.xhtml?user=secret',
                  'webViewIdentityUnavailableReason':
                      'resource_not_materialized',
                },
              })
              as ReadiumDiagnosticEvent;
      expect(unsafeHref.fields, <String, Object?>{
        'kind': 'viewport_snapshot',
        'webViewIdentityUnavailableReason': 'resource_not_materialized',
      });
    });

    test('parses a validated content tap with optional region', () {
      final event = ReadiumReaderEvent.parse(<String, Object?>{
        'protocolVersion': 1,
        'instanceId': 'reader-1',
        'sequence': 8,
        'type': ReadiumBridgeConstants.contentTap,
        'payload': <String, Object?>{
          'interactionId': 12,
          'viewportGeneration': 4,
          'region': 'center',
          'futureField': 'ignored',
        },
      });
      expect(event, isA<ReadiumContentTapEvent>());
      final tap = event as ReadiumContentTapEvent;
      expect(tap.interactionId, 12);
      expect(tap.viewportGeneration, 4);
      expect(tap.region, ReadiumContentTapRegion.center);
      expect(tap.sequence, 8);
    });

    test('content tap parser validates identity and payload safely', () {
      Map<String, Object?> event({
        String id = 'reader-1',
        Object? interaction = 1,
      }) => <String, Object?>{
        'protocolVersion': 1,
        'instanceId': id,
        'sequence': 1,
        'type': ReadiumBridgeConstants.contentTap,
        'payload': <String, Object?>{'interactionId': interaction},
      };

      expect(
        () => ReadiumReaderEvent.parse(event(interaction: 0)),
        throwsA(isA<ReadiumBridgeFormatException>()),
      );
      expect(
        () => ReadiumReaderEvent.parse(event(interaction: '1')),
        throwsA(isA<ReadiumBridgeFormatException>()),
      );
      expect(
        () => ReadiumReaderEvent.parse(event(interaction: -1)),
        throwsA(isA<ReadiumBridgeFormatException>()),
      );
      expect(
        () => ReadiumReaderEvent.parse(event(id: 'other')),
        returnsNormally,
      );
      final unknownPayload = event();
      unknownPayload['payload'] = <String, Object?>{
        'interactionId': 1,
        'region': 'future',
      };
      final unknownRegion =
          ReadiumReaderEvent.parse(unknownPayload) as ReadiumContentTapEvent;
      expect(unknownRegion.region, isNull);
    });
  });

  group('ReadiumEpubController', () {
    test(
      'diagnostic events do not notify state listeners but consume sequence',
      () async {
        final client = FakeReadiumBridgeClient();
        final controller = ReadiumEpubController(
          configuration: const ReadiumEpubOpenConfiguration(
            instanceId: 'reader-1',
            bookId: 'book',
            localFilePath: '/book.epub',
          ),
          client: client,
        );
        await controller.start();
        var stateNotifications = 0;
        controller.listenable.addListener(() => stateNotifications++);
        final received = <ReadiumDiagnosticEvent>[];
        final subscription = controller.diagnostics.listen(received.add);
        final sequence = controller.state.lastSequence;

        client.emit(
          ReadiumReaderEvent.parse(<String, Object?>{
            'protocolVersion': 1,
            'instanceId': 'reader-1',
            'sequence': sequence + 1,
            'type': ReadiumBridgeConstants.readerDiagnostic,
            'payload': <String, Object?>{'kind': 'preference_received'},
          }),
        );
        await Future<void>.value();
        expect(received, hasLength(1));
        expect(stateNotifications, 0);
        expect(controller.state.lastSequence, sequence);

        client.emit(
          ReadiumReaderEvent.parse(<String, Object?>{
            'protocolVersion': 1,
            'instanceId': 'reader-1',
            'sequence': sequence + 2,
            'type': ReadiumBridgeConstants.readerLifecycleChanged,
            'payload': <String, Object?>{'phase': 'navigatorReady'},
          }),
        );
        await Future<void>.value();
        expect(controller.state.lastSequence, sequence + 2);
        expect(stateNotifications, 1);
        await subscription.cancel();
        await controller.dispose();
      },
    );

    test(
      'drops live positions outside manual activity but consumes their sequence',
      () async {
        final client = FakeReadiumBridgeClient();
        final controller = ReadiumEpubController(
          configuration: const ReadiumEpubOpenConfiguration(
            instanceId: 'reader-1',
            bookId: 'book',
            localFilePath: '/book.epub',
          ),
          client: client,
        );
        await controller.start();

        ReadiumEventMetadata metadata(int sequence, String type) =>
            ReadiumEventMetadata(1, 'reader-1', sequence, type);

        client.emit(
          ReadiumManualScrollActivityEvent(
            metadata: metadata(
              1,
              ReadiumBridgeConstants.manualScrollActivityChanged,
            ),
            active: true,
          ),
        );
        client.emit(
          ReadiumPositionEvent(
            metadata: metadata(2, ReadiumBridgeConstants.positionChanged),
            position: const ReadiumPosition(
              href: 'chapter.xhtml',
              progression: .4,
            ),
            liveManual: true,
          ),
        );
        expect(controller.state.position?.progression, .4);

        client.emit(
          ReadiumManualScrollActivityEvent(
            metadata: metadata(
              3,
              ReadiumBridgeConstants.manualScrollActivityChanged,
            ),
            active: false,
          ),
        );
        client.emit(
          ReadiumPositionEvent(
            metadata: metadata(4, ReadiumBridgeConstants.positionChanged),
            position: const ReadiumPosition(
              href: 'chapter.xhtml',
              progression: .8,
            ),
            liveManual: true,
          ),
        );

        expect(controller.state.position?.progression, .4);
        expect(controller.state.positionLiveManual, isTrue);
        expect(controller.state.lastSequence, 4);

        client.emit(
          ReadiumPositionEvent(
            metadata: metadata(5, ReadiumBridgeConstants.positionChanged),
            position: const ReadiumPosition(
              href: 'chapter.xhtml',
              progression: .4,
            ),
          ),
        );
        expect(controller.state.position?.progression, .4);
        expect(controller.state.positionLiveManual, isFalse);
        expect(controller.state.lastSequence, 5);

        await controller.dispose();
      },
    );

    test(
      'uses one stable generated ID, subscribes before attach, and reduces sequence',
      () async {
        final client = FakeReadiumBridgeClient(
          onAttach: (client) {
            client.emit(
              ReadiumLifecycleEvent(
                metadata: const ReadiumEventMetadata(
                  1,
                  'stable-id',
                  1,
                  ReadiumBridgeConstants.readerLifecycleChanged,
                ),
                lifecycle: const ReadiumReaderLifecycle(
                  phase: 'navigatorReady',
                ),
              ),
            );
          },
        );
        var factoryCalls = 0;
        final controller = ReadiumEpubController(
          configuration: const ReadiumEpubOpenConfiguration(
            bookId: 'book',
            localFilePath: '/book.epub',
          ),
          client: client,
          instanceIdFactory: () {
            factoryCalls++;
            return 'stable-id';
          },
        );

        await controller.start();

        expect(factoryCalls, 1);
        expect(controller.instanceId, 'stable-id');
        expect(client.attachCalls, 1);
        expect(controller.state.lifecycle, ReadiumControllerLifecycle.ready);
        expect(controller.state.lastSequence, 1);

        client.emit(
          ReadiumLifecycleEvent(
            metadata: const ReadiumEventMetadata(
              1,
              'stable-id',
              1,
              ReadiumBridgeConstants.readerLifecycleChanged,
            ),
            lifecycle: const ReadiumReaderLifecycle(phase: 'initializing'),
          ),
        );
        expect(controller.state.lifecycle, ReadiumControllerLifecycle.ready);

        await controller.dispose();
        expect(client.disposeCalls, 1);
      },
    );

    test(
      'keeps the navigator ready through initial-locator restoration',
      () async {
        final client = FakeReadiumBridgeClient();
        final controller = ReadiumEpubController(
          configuration: const ReadiumEpubOpenConfiguration(
            instanceId: 'reader-1',
            bookId: 'book',
            localFilePath: '/book.epub',
          ),
          client: client,
        );
        await controller.start();

        client.emit(
          ReadiumLifecycleEvent(
            metadata: const ReadiumEventMetadata(
              1,
              'reader-1',
              1,
              ReadiumBridgeConstants.readerLifecycleChanged,
            ),
            lifecycle: const ReadiumReaderLifecycle(phase: 'navigatorReady'),
          ),
        );
        client.emit(
          ReadiumLifecycleEvent(
            metadata: const ReadiumEventMetadata(
              1,
              'reader-1',
              2,
              ReadiumBridgeConstants.readerLifecycleChanged,
            ),
            lifecycle: const ReadiumReaderLifecycle(
              phase: 'initialLocatorRestored',
            ),
          ),
        );

        expect(controller.isReady, isTrue);
        await controller.dispose();
      },
    );

    test(
      'disposal is terminal and later native events cannot mutate state',
      () async {
        final client = FakeReadiumBridgeClient();
        final controller = ReadiumEpubController(
          configuration: const ReadiumEpubOpenConfiguration(
            instanceId: 'reader-1',
            bookId: 'book',
            localFilePath: '/book.epub',
          ),
          client: client,
        );
        await controller.start();
        await controller.dispose();

        client.emit(
          ReadiumLifecycleEvent(
            metadata: const ReadiumEventMetadata(
              1,
              'reader-1',
              2,
              ReadiumBridgeConstants.readerLifecycleChanged,
            ),
            lifecycle: const ReadiumReaderLifecycle(phase: 'navigatorReady'),
          ),
        );

        expect(controller.state.lifecycle, ReadiumControllerLifecycle.disposed);
      },
    );

    test(
      'content taps use one broadcast stream and do not mutate reader state',
      () async {
        final client = FakeReadiumBridgeClient();
        final controller = ReadiumEpubController(
          configuration: const ReadiumEpubOpenConfiguration(
            instanceId: 'reader-1',
            bookId: 'book',
            localFilePath: '/book.epub',
          ),
          client: client,
        );
        await controller.start();
        final first = <ReadiumReaderInteractionEvent>[];
        final second = <ReadiumReaderInteractionEvent>[];
        final firstSub = controller.interactions.listen(first.add);
        final secondSub = controller.interactions.listen(second.add);
        final before = controller.state;
        client.emit(
          ReadiumContentTapEvent(
            metadata: const ReadiumEventMetadata(
              1,
              'reader-1',
              2,
              ReadiumBridgeConstants.contentTap,
            ),
            interactionId: 3,
            viewportGeneration: 0,
          ),
        );
        client.emit(
          ReadiumContentTapEvent(
            metadata: const ReadiumEventMetadata(
              1,
              'reader-1',
              2,
              ReadiumBridgeConstants.contentTap,
            ),
            interactionId: 4,
          ),
        );
        await Future<void>.value();
        expect(first, hasLength(1));
        expect(second, hasLength(1));
        expect((first.single as ReadiumContentTapEvent).interactionId, 3);
        expect(controller.state.position, before.position);
        expect(controller.state.selection, before.selection);
        expect(controller.state.lastSequence, 2);
        await firstSub.cancel();
        await secondSub.cancel();
        await controller.dispose();
      },
    );
  });
}

final class FakeReadiumBridgeClient implements ReadiumBridgeClient {
  FakeReadiumBridgeClient({this.onAttach});

  final void Function(FakeReadiumBridgeClient client)? onAttach;
  final StreamController<ReadiumReaderEvent> _events =
      StreamController<ReadiumReaderEvent>.broadcast(sync: true);
  int attachCalls = 0;
  int disposeCalls = 0;
  bool attached = false;

  @override
  Stream<ReadiumReaderEvent> get events => _events.stream;

  void emit(ReadiumReaderEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  Future<void> attachToPlatform() async {
    attachCalls++;
    attached = true;
    onAttach?.call(this);
  }

  @override
  Future<ReadiumBridgeInfo> getBridgeInfo() async =>
      const ReadiumBridgeInfo(protocolVersion: 1, instanceId: 'reader-1');

  @override
  Future<ReadiumReaderSnapshot> getSnapshot() async => _snapshot();

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
    attached = false;
    await _events.close();
  }
}

ReadiumReaderSnapshot _snapshot() => const ReadiumReaderSnapshot(
  lifecycle: ReadiumReaderLifecycle(phase: 'navigatorReady'),
  position: ReadiumPosition(href: 'chapter.xhtml', progression: 0.5),
  chapter: ReadiumChapter(title: 'Chapter'),
  preferences: ReadiumPreferencesState(
    applied: ReadiumEpubPreferences.defaults,
  ),
  toc: ReadiumTocState(status: ReadiumTocStatus.ready),
  search: ReadiumSearchState(status: ReadiumSearchStatus.idle),
  selection: ReadiumSelectionState(status: 'inactive'),
  decorations: <ReadiumDecorationGroup, ReadiumDecorationGroupState>{},
);

import 'package:bibliolife_readium/bibliolife_readium.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('watchdog and release diagnostics preserve recovery correlation', () {
    final event =
        ReadiumReaderEvent.parse({
              'protocolVersion': 1,
              'instanceId': 'reader',
              'sequence': 1,
              'type': ReadiumBridgeConstants.readerDiagnostic,
              'payload': {
                'category': 'Reader.Progress',
                'kind': 'progress_navigation_ownership',
                'gestureId': 1,
                'previewId': 3,
                'navigationGeneration': 3,
                'isFinal': false,
                'result': 'released',
                'terminalResult': 'recovered_timeout',
                'activeSlotCleared': true,
                'nextPendingPreviewId': 4,
                'nextPendingIsFinal': true,
                'activeOwnerMatches': true,
                'timeoutMs': 8000,
                'elapsedMs': 8001,
                'sideEffectsScope': 'scheduler_ownership',
                'previousGestureId': 1,
                'newGestureId': 2,
                'previousGestureEnded': true,
                'previousNavigationStillActive': true,
              },
            })
            as ReadiumDiagnosticEvent;
    expect(event.fields['terminalResult'], 'recovered_timeout');
    expect(event.fields['activeSlotCleared'], true);
    expect(event.fields['nextPendingPreviewId'], 4);
    expect(event.fields['nextPendingIsFinal'], true);
    expect(event.fields['newGestureId'], 2);
    expect(event.fields['previousNavigationStillActive'], true);
    expect(event.fields['timeoutMs'], 8000);
  });

  test(
    'terminal decision diagnostics retain progression domains and transition',
    () {
      final event =
          ReadiumReaderEvent.parse({
                'protocolVersion': 1,
                'instanceId': 'reader',
                'sequence': 1,
                'type': ReadiumBridgeConstants.readerDiagnostic,
                'payload': {
                  'category': 'Reader.Progress',
                  'kind': 'progress_invalid_progression_decision',
                  'stage': 'after_a10',
                  'requestedNormalizedProgress': .2765,
                  'requestedResourceProgression': .4736,
                  'requestedTotalProgression': .2755,
                  'observedResourceProgression': .47360001,
                  'viewportAlreadyVerified': true,
                  'authorityStillCurrent': true,
                  'valueBeingValidated': 'POSITION_APPLIED_BUT_NOT_ACCEPTED',
                  'validationDomain': 'OTHER',
                  'validationResult': 'a10_authoritative',
                  'terminalMutationAttempted': false,
                  'fromState': 'VERIFIED',
                  'toState': 'COMMITTED',
                },
              })
              as ReadiumDiagnosticEvent;
      expect(event.fields['requestedNormalizedProgress'], .2765);
      expect(event.fields['requestedResourceProgression'], .4736);
      expect(event.fields['requestedTotalProgression'], .2755);
      expect(event.fields['observedResourceProgression'], .47360001);
      expect(event.fields['viewportAlreadyVerified'], true);
      expect(event.fields['terminalMutationAttempted'], false);
      expect(event.fields['toState'], 'COMMITTED');
      expect(
        event.fields['valueBeingValidated'],
        'POSITION_APPLIED_BUT_NOT_ACCEPTED',
      );
    },
  );

  test(
    'native progress diagnostics retain correlation, target, viewport and privacy',
    () {
      final event =
          ReadiumReaderEvent.parse({
                'protocolVersion': ReadiumBridgeConstants.protocolVersion,
                'instanceId': 'reader',
                'sequence': 1,
                'type': ReadiumBridgeConstants.readerDiagnostic,
                'payload': {
                  'category': 'Reader.Progress',
                  'kind': 'progress_navigation_verified',
                  'gestureId': 8,
                  'previewId': 3,
                  'navigationGeneration': 19,
                  'isFinal': true,
                  'targetReadingOrderIndex': 2,
                  'requestedReadingOrderIndex': 2,
                  'observedReadingOrderIndex': 2,
                  'targetResourceHref': 'OPS/chapter-3.xhtml',
                  'resourceHref': 'OPS/chapter-3.xhtml',
                  'targetPosition': 196,
                  'requestedProgress': .61,
                  'observedProgress': .609375,
                  'progressError': -.000625,
                  'observedProgression': .42,
                  'firstVisibleTopPx': -120,
                  'viewportHeightPx': 900,
                  'a11State': 'verified',
                  'result': 'verified',
                  'sameRequestedResource': true,
                  'targetRangeAtReadingAnchor': true,
                  'authorityStillCurrent': true,
                  'source': 'final_navigation',
                  'stage': 'after_navigation',
                  'snapshotSource': 'settled_locator_publication',
                  'locatorJson': 'PRIVATE BOOK CONTENT',
                  'text': 'PRIVATE BOOK CONTENT',
                  'html': '<p>PRIVATE BOOK CONTENT</p>',
                  'notes': 'PRIVATE BOOK CONTENT',
                },
              })
              as ReadiumDiagnosticEvent;
      final fields = event.fields;
      expect(fields['category'], 'Reader.Progress');
      expect(fields['previewId'], 3);
      expect(fields['navigationGeneration'], 19);
      expect(fields['targetResourceHref'], 'OPS/chapter-3.xhtml');
      expect(fields['requestedProgress'], .61);
      expect(fields['observedProgress'], .609375);
      expect(fields['firstVisibleTopPx'], -120.0);
      expect(fields['targetRangeAtReadingAnchor'], true);
      expect(fields['a11State'], 'verified');
      expect(fields['source'], 'final_navigation');
      expect(fields['stage'], 'after_navigation');
      expect(fields['isFinal'], true);
      expect(fields.toString(), isNot(contains('PRIVATE')));
    },
  );
}

import 'package:bibliolife_readium/bibliolife_readium.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses typed selection action and decoration activation envelopes', () {
    final selectionEvent = ReadiumReaderEvent.parse({
      'protocolVersion': 1,
      'instanceId': 'reader-1',
      'sequence': 4,
      'type': 'selectionActionRequested',
      'payload': {
        'requestId': 9,
        'instanceId': 'reader-1',
        'selectionSessionId': 3,
        'action': 'highlightAndNote',
        'locatorJson': '{"href":"chapter.xhtml"}',
        'selectedText': 'selected',
      },
    });
    expect(selectionEvent, isA<ReadiumSelectionActionRequestedEvent>());
    final request =
        (selectionEvent as ReadiumSelectionActionRequestedEvent).request;
    expect(request.action, ReadiumSelectionAction.highlightAndNote);
    expect(request.requestId, 9);

    final activationEvent = ReadiumReaderEvent.parse({
      'protocolVersion': 1,
      'instanceId': 'reader-1',
      'sequence': 5,
      'type': 'decorationActivated',
      'payload': {
        'interactionId': 2,
        'instanceId': 'reader-1',
        'group': 'PERSISTENT_HIGHLIGHTS',
        'decorationId': 'annotation:a',
      },
    });
    expect(activationEvent, isA<ReadiumDecorationActivatedReaderEvent>());
    expect(
      (activationEvent as ReadiumDecorationActivatedReaderEvent)
          .activation
          .decorationId,
      'annotation:a',
    );

    final annotationActionEvent = ReadiumReaderEvent.parse({
      'protocolVersion': 1,
      'instanceId': 'reader-1',
      'sequence': 6,
      'type': 'annotationActionRequested',
      'payload': {
        'requestId': 10,
        'instanceId': 'reader-1',
        'annotationId': 'a',
        'action': 'recolor',
        'color': 'pink',
      },
    });
    expect(annotationActionEvent, isA<ReadiumAnnotationActionRequestedEvent>());
    final annotationRequest =
        (annotationActionEvent as ReadiumAnnotationActionRequestedEvent)
            .request;
    expect(annotationRequest.annotationId, 'a');
    expect(annotationRequest.action, ReadiumAnnotationAction.recolor);
    expect(annotationRequest.color, 'pink');
  });

  test('selection action resolution has stable wire values', () {
    const resolution = ReadiumSelectionActionResolution(
      requestId: 4,
      selectionSessionId: 8,
      outcome: ReadiumSelectionActionOutcome.committed,
      annotationId: 'annotation-1',
    );
    expect(resolution.toMap(), {
      'requestId': 4,
      'selectionSessionId': 8,
      'outcome': 'committed',
      'annotationId': 'annotation-1',
    });
  });

  test('annotation action resolution has stable typed wire values', () {
    const resolution = ReadiumAnnotationActionResolution(
      requestId: 10,
      outcome: ReadiumSelectionActionOutcome.committed,
    );
    expect(resolution.toMap(), {'requestId': 10, 'outcome': 'committed'});
  });
}

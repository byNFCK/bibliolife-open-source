import 'dart:async';

import 'package:bibliolife/features/reader/domain/models/reader_capabilities.dart';
import 'package:bibliolife/features/reader/domain/models/reader_kind.dart';
import 'package:bibliolife/features/reader/domain/models/reader_progress_state.dart';
import 'package:bibliolife/features/reader/presentation/models/reader_ui_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stale slider interaction tokens cannot clear the active slider', () {
    final controller = ReaderUiController(
      capabilities: ReaderCapabilities.forKind(ReaderKind.epub),
    );

    expect(controller.isSliderInteractionActive, isFalse);
    final firstToken = controller.beginSliderInteraction(
      ReaderSliderId.fontSize,
    );
    expect(controller.isSliderInteractionActive, isTrue);
    expect(controller.activeSliderId, ReaderSliderId.fontSize);

    final secondToken = controller.beginSliderInteraction(
      ReaderSliderId.lineHeight,
    );
    expect(controller.activeSliderId, ReaderSliderId.lineHeight);
    controller.endSliderInteraction(ReaderSliderId.fontSize, firstToken);
    expect(controller.isSliderInteractionActive, isTrue);
    expect(controller.activeSliderId, ReaderSliderId.lineHeight);
    controller.endSliderInteraction(ReaderSliderId.lineHeight, secondToken);
    expect(controller.isSliderInteractionActive, isFalse);
    expect(controller.activeSliderId, isNull);
    controller.endSliderInteraction(ReaderSliderId.lineHeight, secondToken);
    expect(controller.isSliderInteractionActive, isFalse);

    final firstSameIdToken = controller.beginSliderInteraction(
      ReaderSliderId.fontSize,
    );
    final secondSameIdToken = controller.beginSliderInteraction(
      ReaderSliderId.fontSize,
    );
    controller.endSliderInteraction(ReaderSliderId.fontSize, firstSameIdToken);
    expect(controller.activeSliderId, ReaderSliderId.fontSize);
    controller.endSliderInteraction(ReaderSliderId.fontSize, secondSameIdToken);
    expect(controller.isSliderInteractionActive, isFalse);

    final disposedToken = controller.beginSliderInteraction(
      ReaderSliderId.progress,
    );
    controller.dispose();
    expect(controller.isSliderInteractionActive, isFalse);
    controller.endSliderInteraction(ReaderSliderId.progress, disposedToken);
    expect(controller.isSliderInteractionActive, isFalse);
  });

  test(
    'queues a progress rollback while a native preview is in flight',
    () async {
      final controller = ReaderUiController(
        capabilities: ReaderCapabilities.forKind(ReaderKind.epub),
      );
      final releasePreview = Completer<void>();
      final calls = <double>[];
      controller.setProgress(
        ReaderProgressState.progression(progression: .05),
        seek: (value) async {
          calls.add(value);
          if (value == .88) await releasePreview.future;
        },
      );

      final preview = controller.seek(.88);
      final rollback = controller.seek(.05);
      await Future<void>.delayed(Duration.zero);
      expect(calls, <double>[.88]);

      releasePreview.complete();
      await Future.wait(<Future<void>>[preview, rollback]);
      expect(calls, <double>[.88, .05]);
      expect(controller.isSeeking, isFalse);
      controller.dispose();
    },
  );
}

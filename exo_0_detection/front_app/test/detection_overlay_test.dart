import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_app/detection/model/detection_result.dart';
import 'package:front_app/video/view/detection_overlay.dart';

DetectionResult result({bool empty = false, bool edges = false}) =>
    DetectionResult(
      frame: const FrameSize(width: 640, height: 480),
      inferenceMs: 1200,
      persons: empty
          ? []
          : [
              PersonDetection(
                label: 'person',
                confidence: 0.64,
                bbox: edges
                    ? const BoundingBox(x1: 0, y1: 0, x2: 640, y2: 480)
                    : const BoundingBox(x1: 160, y1: 120, x2: 480, y2: 360),
              ),
            ],
    );

void main() {
  test('Same aspect ratio scales source pixels', () {
    expect(detectionRects(result(), const Size(320, 240)), [
      const Rect.fromLTRB(80, 60, 240, 180),
    ]);
  });
  test('Contain centers horizontal and vertical letterboxing', () {
    expect(detectionRects(result(), const Size(1280, 720)), [
      const Rect.fromLTRB(400, 180, 880, 540),
    ]);
    expect(detectionRects(result(), const Size(640, 640)), [
      const Rect.fromLTRB(160, 200, 480, 440),
    ]);
  });
  test('Image boundary maps to the rendered image, excluding bars', () {
    expect(detectionRects(result(edges: true), const Size(1280, 720)), [
      const Rect.fromLTRB(160, 0, 1120, 720),
    ]);
  });
  test('Empty persons produces no rectangles', () {
    expect(detectionRects(result(empty: true), const Size(1280, 720)), isEmpty);
  });
  testWidgets('Overlay follows resize, ignores taps and clears detections', (
    tester,
  ) async {
    var taps = 0;
    Future<void> show(Size size, DetectionResult detection) =>
        tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox.fromSize(
                size: size,
                child: GestureDetector(
                  onTap: () => taps++,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: Colors.black),
                      DetectionOverlay(result: detection),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
    await show(const Size(320, 240), result());
    final painterFinder = find.descendant(
      of: find.byType(DetectionOverlay),
      matching: find.byType(CustomPaint),
    );
    expect(tester.getSize(painterFinder), const Size(320, 240));
    await tester.tapAt(tester.getCenter(find.byType(DetectionOverlay)));
    expect(taps, 1);
    await show(const Size(640, 360), result(empty: true));
    expect(tester.getSize(painterFinder), const Size(640, 360));
    final painter =
        tester.widget<CustomPaint>(painterFinder).painter!
            as DetectionOverlayPainter;
    expect(painter.result.persons, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

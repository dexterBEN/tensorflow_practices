import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../detection/model/detection_result.dart';

/// Maps source pixels to the centered RTCVideoView contain viewport.
List<Rect> detectionRects(DetectionResult result, Size displaySize) {
  final scale = math.min(
    displaySize.width / result.frame.width,
    displaySize.height / result.frame.height,
  );
  final dx = (displaySize.width - result.frame.width * scale) / 2;
  final dy = (displaySize.height - result.frame.height * scale) / 2;
  return result.persons.map((person) {
    final b = person.bbox;
    return Rect.fromLTRB(
      dx + b.x1 * scale,
      dy + b.y1 * scale,
      dx + b.x2 * scale,
      dy + b.y2 * scale,
    );
  }).toList();
}

class DetectionOverlay extends StatelessWidget {
  const DetectionOverlay({super.key, required this.result});
  final DetectionResult result;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(painter: DetectionOverlayPainter(result)),
  );
}

class DetectionOverlayPainter extends CustomPainter {
  DetectionOverlayPainter(this.result);
  final DetectionResult result;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rectangles = detectionRects(result, size);
    final pen = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var i = 0; i < rectangles.length; i++) {
      final rectangle = rectangles[i];
      final person = result.persons[i];
      canvas.drawRect(rectangle, pen);
      final text = TextPainter(
        text: TextSpan(
          text:
              '${person.label} ${(person.confidence * 100).toStringAsFixed(1)}%',
          style: const TextStyle(color: Colors.black, fontSize: 14),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      final origin = Offset(
        rectangle.left.clamp(0.0, math.max(0.0, size.width - text.width)),
        rectangle.top.clamp(0.0, math.max(0.0, size.height - text.height)),
      );
      canvas.drawRect(origin & text.size, Paint()..color = Colors.greenAccent);
      text.paint(canvas, origin);
      text.dispose();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DetectionOverlayPainter oldDelegate) =>
      oldDelegate.result != result;
}

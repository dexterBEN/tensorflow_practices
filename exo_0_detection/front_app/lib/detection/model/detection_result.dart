/// Pixel coordinates in the original PYNQ frame, not video transport data.
class BoundingBox {
  const BoundingBox({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });
  final int x1, y1, x2, y2;
}

class FrameSize {
  const FrameSize({required this.width, required this.height});
  final int width, height;
}

class PersonDetection {
  const PersonDetection({
    required this.label,
    required this.confidence,
    required this.bbox,
  });
  final String label;
  final double confidence;
  final BoundingBox bbox;
}

class DetectionResult {
  DetectionResult({
    required this.frame,
    required this.inferenceMs,
    required List<PersonDetection> persons,
  }) : persons = List.unmodifiable(persons);
  final FrameSize frame;
  final double inferenceMs;
  final List<PersonDetection> persons;

  factory DetectionResult.fromJson(Object? value) {
    Map<String, dynamic> object(Object? v) {
      if (v is! Map<String, dynamic>) {
        throw const FormatException('Expected object');
      }
      return v;
    }

    int integer(Object? v) {
      if (v is! num || !v.isFinite || v != v.roundToDouble()) {
        throw const FormatException('Expected integer');
      }
      return v.toInt();
    }

    double number(Object? v) {
      if (v is! num || !v.isFinite) {
        throw const FormatException('Expected finite number');
      }
      return v.toDouble();
    }

    final json = object(value);
    if (json['type'] != 'detection') {
      throw const FormatException('Unknown message type');
    }
    final f = object(json['frame']);
    final frame = FrameSize(
      width: integer(f['width']),
      height: integer(f['height']),
    );
    final ms = number(json['inference_ms']);
    if (frame.width <= 0 || frame.height <= 0 || ms < 0) {
      throw const FormatException('Invalid frame/time');
    }
    final entries = json['persons'];
    if (entries is! List) throw const FormatException('Missing persons list');
    final persons = <PersonDetection>[];
    for (final entry in entries) {
      final p = object(entry);
      final confidence = number(p['confidence']);
      final b = object(p['bbox']);
      final box = BoundingBox(
        x1: integer(b['x1']),
        y1: integer(b['y1']),
        x2: integer(b['x2']),
        y2: integer(b['y2']),
      );
      if (p['label'] != 'person' ||
          confidence < 0 ||
          confidence > 1 ||
          box.x1 < 0 ||
          box.y1 < 0 ||
          box.x2 <= box.x1 ||
          box.y2 <= box.y1 ||
          box.x2 > frame.width ||
          box.y2 > frame.height) {
        throw const FormatException('Invalid person');
      }
      persons.add(
        PersonDetection(label: 'person', confidence: confidence, bbox: box),
      );
    }
    return DetectionResult(frame: frame, inferenceMs: ms, persons: persons);
  }
}

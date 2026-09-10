/// Metadata only. Coordinates are normalized relative to the video frame.
class Detection {
  Detection({
    required this.label,
    required this.confidence,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  }) {
    for (final value in [confidence, x, y, width, height]) {
      if (!value.isFinite || value < 0 || value > 1) {
        throw ArgumentError('Confidence and coordinates must be in [0, 1].');
      }
    }
    if (x + width > 1 || y + height > 1) {
      throw ArgumentError('The bounding box must fit inside the frame.');
    }
  }

  final String label;
  final double confidence;
  final double x;
  final double y;
  final double width;
  final double height;
}

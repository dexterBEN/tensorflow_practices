import 'dart:async';
import '../model/detection_result.dart';
import 'detection_repository.dart';

class MockDetectionRepository implements DetectionRepository {
  MockDetectionRepository({this.interval = const Duration(seconds: 2)}) {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval', 'Must be positive');
    }
  }

  final Duration interval;
  StreamController<DetectionResult>? _controller;
  Timer? _timer;

  @override
  Stream<DetectionResult> get detections {
    final controller = _controller;
    if (controller == null) throw StateError('Connect before subscribing.');
    return controller.stream;
  }

  @override
  Future<void> connect() async {
    if (_controller != null) return;
    final controller = StreamController<DetectionResult>.broadcast();
    _controller = controller;
    _timer = Timer.periodic(interval, (_) {
      controller.add(
        DetectionResult(
          frame: const FrameSize(width: 640, height: 480),
          inferenceMs: 1200,
          persons: const [
            PersonDetection(
              label: 'person',
              confidence: 0.94,
              bbox: BoundingBox(x1: 192, y1: 72, x2: 352, y2: 384),
            ),
          ],
        ),
      );
    });
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _timer = null;
    final controller = _controller;
    _controller = null;
    await controller?.close();
  }
}

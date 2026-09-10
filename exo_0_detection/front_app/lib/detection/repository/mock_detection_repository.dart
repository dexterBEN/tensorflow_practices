import 'dart:async';
import '../model/detection.dart';
import 'detection_repository.dart';

class MockDetectionRepository implements DetectionRepository {
  MockDetectionRepository({this.interval = const Duration(seconds: 2)}) {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval', 'Must be positive');
    }
  }

  final Duration interval;
  StreamController<Detection>? _controller;
  Timer? _timer;

  @override
  Stream<Detection> get detections {
    final controller = _controller;
    if (controller == null) throw StateError('Connect before subscribing.');
    return controller.stream;
  }

  @override
  Future<void> connect() async {
    if (_controller != null) return;
    final controller = StreamController<Detection>.broadcast();
    _controller = controller;
    _timer = Timer.periodic(interval, (_) {
      controller.add(
        Detection(
          label: 'person',
          confidence: 0.94,
          x: 0.30,
          y: 0.15,
          width: 0.25,
          height: 0.65,
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

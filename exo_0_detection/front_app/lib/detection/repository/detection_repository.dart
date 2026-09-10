import '../model/detection.dart';

abstract class DetectionRepository {
  /// Subscribe after connect completes. Carries metadata, never video frames.
  Stream<Detection> get detections;

  Future<void> connect();

  /// Releases connection resources. Calling this repeatedly is safe.
  Future<void> disconnect();
}

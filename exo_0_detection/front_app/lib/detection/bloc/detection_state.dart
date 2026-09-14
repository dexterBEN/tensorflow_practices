import '../model/detection_result.dart';

enum DetectionStatus { initial, connecting, connected, disconnected, failure }

class DetectionState {
  const DetectionState({
    this.status = DetectionStatus.initial,
    this.detection,
    this.error,
  });

  final DetectionStatus status;
  final DetectionResult? detection;
  final String? error;
  bool get isConnected => status == DetectionStatus.connected;
}

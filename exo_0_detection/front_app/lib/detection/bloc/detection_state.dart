import '../model/detection.dart';

enum DetectionStatus { initial, connecting, connected, disconnected, failure }

class DetectionState {
  const DetectionState({
    this.status = DetectionStatus.initial,
    this.detection,
    this.error,
  });

  final DetectionStatus status;
  final Detection? detection;
  final String? error;
  bool get isConnected => status == DetectionStatus.connected;
}

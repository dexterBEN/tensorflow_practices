import '../model/detection_result.dart';

sealed class DetectionEvent {
  const DetectionEvent();
}

final class DetectionStarted extends DetectionEvent {
  const DetectionStarted();
}

final class DetectionStopped extends DetectionEvent {
  const DetectionStopped();
}

final class DetectionReceived extends DetectionEvent {
  const DetectionReceived(this.detection);
  final DetectionResult detection;
}

final class DetectionErrorOccurred extends DetectionEvent {
  const DetectionErrorOccurred(this.error);
  final Object error;
}

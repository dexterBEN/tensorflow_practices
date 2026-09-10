import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../model/detection.dart';
import '../repository/detection_repository.dart';
import 'detection_event.dart';
import 'detection_state.dart';

class DetectionBloc extends Bloc<DetectionEvent, DetectionState> {
  DetectionBloc(this._repository) : super(const DetectionState()) {
    // Serialize lifecycle events so start/stop cannot race each other.
    on<DetectionEvent>(
      _handle,
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
  }

  final DetectionRepository _repository;
  StreamSubscription<Detection>? _subscription;
  bool _closing = false;

  void _enqueue(DetectionEvent event) {
    if (!_closing && !isClosed) add(event);
  }

  Future<void> _disconnect() async {
    final cancellation = _subscription?.cancel();
    _subscription = null;
    final disconnection = _repository.disconnect();
    await cancellation;
    await disconnection;
  }

  Future<void> _handle(
    DetectionEvent event,
    Emitter<DetectionState> emit,
  ) async {
    if (_closing) return;
    try {
      switch (event) {
        case DetectionStarted():
          if (state.isConnected) return;
          emit(const DetectionState(status: DetectionStatus.connecting));
          await _repository.connect();
          if (_closing) {
            await _repository.disconnect();
            return;
          }
          _subscription = _repository.detections.listen(
            (detection) => _enqueue(DetectionReceived(detection)),
            onError: (Object error) => _enqueue(DetectionErrorOccurred(error)),
            onDone: () => _enqueue(const DetectionStopped()),
          );
          emit(const DetectionState(status: DetectionStatus.connected));
        case DetectionStopped():
          await _disconnect();
          if (!_closing) {
            emit(const DetectionState(status: DetectionStatus.disconnected));
          }
        case DetectionReceived(:final detection):
          if (state.isConnected) {
            emit(
              DetectionState(
                status: DetectionStatus.connected,
                detection: detection,
              ),
            );
          }
        case DetectionErrorOccurred(:final error):
          throw error;
      }
    } catch (error) {
      try {
        await _disconnect();
      } catch (_) {
        // Preserve the original connection/stream error for the UI.
      }
      if (!_closing) {
        emit(
          DetectionState(
            status: DetectionStatus.failure,
            error: error.toString(),
          ),
        );
      }
    }
  }

  @override
  Future<void> close() async {
    _closing = true;
    // Stop active resources immediately, then handle any in-flight connect.
    await _disconnect();
    await super.close();
    await _disconnect();
  }
}

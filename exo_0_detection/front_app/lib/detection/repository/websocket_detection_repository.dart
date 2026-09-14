import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../model/detection_result.dart';
import 'detection_repository.dart';

class WebSocketDetectionRepository implements DetectionRepository {
  WebSocketDetectionRepository({String url = 'ws://192.168.200.111:8766'})
    : _uri = Uri.parse(url);
  final Uri _uri;
  WebSocketChannel? _channel;
  StreamController<DetectionResult>? _controller;
  StreamSubscription<dynamic>? _subscription;

  @override
  Stream<DetectionResult> get detections {
    final controller = _controller;
    if (controller == null) throw StateError('Connect before subscribing');
    return controller.stream;
  }

  @override
  Future<void> connect() async {
    if (_channel != null) return;
    final controller = StreamController<DetectionResult>();
    _controller = controller;
    final channel = WebSocketChannel.connect(_uri);
    _channel = channel;
    _subscription = channel.stream.listen(
      (raw) {
        try {
          if (raw is! String) throw const FormatException('Expected JSON text');
          controller.add(DetectionResult.fromJson(jsonDecode(raw)));
        } catch (error) {
          debugPrint('Ignoring invalid detection message: $error');
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!controller.isClosed) controller.addError(error, stack);
      },
      onDone: () {
        debugPrint('Detection WebSocket disconnected');
        unawaited(controller.close());
      },
    );
    try {
      await channel.ready.timeout(const Duration(seconds: 10));
      debugPrint('Detection WebSocket connected: $_uri');
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    final subscription = _subscription;
    final channel = _channel;
    final controller = _controller;
    _subscription = null;
    _channel = null;
    _controller = null;
    await subscription?.cancel();
    // A single-subscription controller may not yet have a listener after a failed connect.
    if (controller != null && !controller.isClosed) {
      unawaited(controller.close());
    }
    await channel?.sink.close();
  }
}

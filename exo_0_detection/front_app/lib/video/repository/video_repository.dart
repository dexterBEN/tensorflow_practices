import 'package:flutter_webrtc/flutter_webrtc.dart';

enum VideoConnectionStatus { connecting, connected, disconnected, error }

abstract class VideoRepository {
  Stream<MediaStream> get remoteStreams;
  Stream<VideoConnectionStatus> get connectionStatus;
  Future<void> connect();
  Future<void> disconnect();
  Future<void> dispose();
}

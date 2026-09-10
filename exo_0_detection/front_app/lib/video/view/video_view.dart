import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../repository/video_repository.dart';

class VideoView extends StatefulWidget {
  const VideoView({super.key});

  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  final _renderer = RTCVideoRenderer();
  late final VideoRepository _repository;
  StreamSubscription<MediaStream>? _streams;
  StreamSubscription<VideoConnectionStatus>? _statuses;
  late final Future<void> _initialization;
  VideoConnectionStatus _status = VideoConnectionStatus.connecting;
  bool _hasStream = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _repository = context.read<VideoRepository>();
    _initialization = _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _renderer.initialize();
      _initialized = true;
      if (!mounted) return;
      _renderer.muted = true;
      _streams = _repository.remoteStreams.listen((stream) {
        if (!mounted) return;
        _renderer.srcObject = stream;
        setState(() => _hasStream = true);
      });
      _statuses = _repository.connectionStatus.listen((status) {
        if (!mounted) return;
        if (status == VideoConnectionStatus.disconnected ||
            status == VideoConnectionStatus.error) {
          _renderer.srcObject = null;
          _hasStream = false;
        }
        setState(() => _status = status);
      });
      await _repository.connect();
    } catch (error) {
      debugPrint('Video initialization error: $error');
      if (mounted) setState(() => _status = VideoConnectionStatus.error);
    }
  }

  @override
  void dispose() {
    unawaited(_streams?.cancel());
    unawaited(_statuses?.cancel());
    unawaited(_repository.disconnect());
    unawaited(_disposeRenderer());
    super.dispose();
  }

  Future<void> _disposeRenderer() async {
    await _initialization;
    try {
      if (_initialized) _renderer.srcObject = null;
      await _renderer.dispose();
    } catch (error) {
      debugPrint('Video renderer cleanup: $error');
    }
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 16 / 9,
    child: ColoredBox(
      color: const Color(0xFF202124),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_hasStream)
            RTCVideoView(
              _renderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
            )
          else
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.videocam_off_outlined,
                    color: Colors.white70,
                    size: 48,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Video stream not connected',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          Positioned(
            top: 8,
            left: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(switch (_status) {
                  VideoConnectionStatus.connecting => 'Connecting',
                  VideoConnectionStatus.connected => 'Connected',
                  VideoConnectionStatus.disconnected => 'Disconnected',
                  VideoConnectionStatus.error => 'Error',
                }, style: const TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

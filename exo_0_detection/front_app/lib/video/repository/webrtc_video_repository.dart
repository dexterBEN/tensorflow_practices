import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'video_repository.dart';

/// Receive-only video session. No camera capture or detection metadata.
class WebRtcVideoRepository implements VideoRepository {
  WebRtcVideoRepository({
    String signalingUrl = 'ws://192.168.200.111:8765',
    Future<RTCPeerConnection> Function(Map<String, dynamic>)? peerFactory,
    WebSocketChannel Function(Uri)? channelFactory,
  }) : _url = Uri.parse(signalingUrl),
       _peerFactory = peerFactory ?? ((config) => createPeerConnection(config)),
       _channelFactory = channelFactory ?? WebSocketChannel.connect;

  final Uri _url;
  final Future<RTCPeerConnection> Function(Map<String, dynamic>) _peerFactory;
  final WebSocketChannel Function(Uri) _channelFactory;
  final _streams = StreamController<MediaStream>.broadcast();
  final _statuses = StreamController<VideoConnectionStatus>.broadcast();
  _Session? _session;
  bool _disposed = false;

  @override
  Stream<MediaStream> get remoteStreams => _streams.stream;
  @override
  Stream<VideoConnectionStatus> get connectionStatus => _statuses.stream;

  bool _active(_Session session) => !_disposed && identical(_session, session);
  void _status(VideoConnectionStatus status) {
    if (!_disposed) _statuses.add(status);
  }

  @override
  Future<void> connect() async {
    if (_disposed) throw StateError('Video repository is disposed');
    if (_session != null) return;
    final session = _Session();
    _session = session;
    _status(VideoConnectionStatus.connecting);
    try {
      final peer = await _peerFactory({'iceServers': <dynamic>[]});
      if (!_active(session)) {
        await peer.close();
        await peer.dispose();
        return;
      }
      session.peer = peer;
      peer.onTrack = (event) {
        if (!_active(session) || event.track.kind != 'video') return;
        debugPrint('Remote video track received');
        if (event.streams.isNotEmpty) {
          final stream = event.streams.first;
          session.streams.add(stream);
          _streams.add(stream);
        }
      };
      peer.onIceCandidate = (candidate) {
        if (!_active(session)) return;
        final candidateValue = candidate.candidate;
        if (candidateValue == null || candidateValue.isEmpty) {
          debugPrint('ICE gathering candidate is empty/end-of-candidates');
          return;
        }
        final mLineIndex = candidate.sdpMLineIndex ?? 0;
        debugPrint(
          'Local ICE candidate generated: candidate=$candidateValue, '
          'mid=${candidate.sdpMid}, mLine=$mLineIndex',
        );
        final message = <String, dynamic>{
          'type': 'ice',
          'candidate': candidateValue,
          'sdpMLineIndex': mLineIndex,
          if (candidate.sdpMid != null) 'sdpMid': candidate.sdpMid,
        };
        // The answer must precede its trickled candidates on the wire.
        if (!session.answerSent) {
          session.localIce.add(message);
        } else {
          _send(session, message);
        }
      };
      peer.onIceGatheringState = (state) {
        if (_active(session) &&
            state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
          debugPrint('ICE gathering completed');
        }
      };
      peer.onConnectionState = (state) {
        if (!_active(session)) return;
        debugPrint('WebRTC connection state: $state');
        switch (state) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            _status(VideoConnectionStatus.connected);
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
            _fail(session, StateError('WebRTC connection failed'));
          case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
            _status(VideoConnectionStatus.disconnected);
          default:
            _status(VideoConnectionStatus.connecting);
        }
      };
      peer.onIceConnectionState = (state) {
        if (!_active(session)) return;
        debugPrint('ICE connection state: $state');
        if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          _fail(session, StateError('ICE connection failed'));
        } else if (state ==
                RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
          _status(VideoConnectionStatus.disconnected);
        }
      };
      final channel = _channelFactory(_url);
      session.channel = channel;
      // Listen immediately so connection errors are handled; messages wait for ready.
      session.subscription = channel.stream.listen(
        (message) {
          session.messages = session.messages
              .then<void>((_) async {
                await channel.ready;
                if (_active(session)) await _message(session, message);
              })
              .catchError(
                (Object error, StackTrace stackTrace) =>
                    _fail(session, error, stackTrace),
              );
        },
        onError: (Object error, StackTrace stackTrace) =>
            _fail(session, error, stackTrace),
        onDone: () {
          if (!_active(session)) return;
          debugPrint('WebSocket disconnected');
          unawaited(disconnect());
        },
      );
      await channel.ready.timeout(const Duration(seconds: 10));
      if (_active(session)) debugPrint('WebSocket connected');
    } catch (error, stackTrace) {
      _fail(session, error, stackTrace);
    }
  }

  void _send(_Session session, Map<String, dynamic> message) {
    if (!_active(session)) return;
    try {
      final channel = session.channel;
      if (channel == null) {
        debugPrint('Signaling channel unavailable; message not sent');
        return;
      }
      channel.sink.add(jsonEncode(message));
      if (message['type'] == 'ice') debugPrint('ICE candidate sent');
    } catch (error, stackTrace) {
      _fail(session, error, stackTrace);
    }
  }

  Future<void> _message(_Session session, dynamic raw) async {
    Map<String, dynamic> message;
    try {
      if (raw is! String) throw const FormatException('Expected JSON text');
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected object');
      }
      message = decoded;
      if (message['type'] == 'offer') {
        if (message['sdp'] is! String || (message['sdp'] as String).isEmpty) {
          throw const FormatException('Missing offer SDP');
        }
      } else if (message['type'] == 'ice') {
        if (message['candidate'] is! String ||
            message['sdpMLineIndex'] is! int ||
            (message['sdpMLineIndex'] as int) < 0 ||
            (message['sdpMid'] != null && message['sdpMid'] is! String)) {
          throw const FormatException('Invalid ICE candidate');
        }
      } else {
        throw const FormatException('Unknown signaling message type');
      }
    } catch (error) {
      debugPrint('Ignoring signaling message: $error');
      return;
    }
    final peer = session.peer;
    if (peer == null) {
      debugPrint('PeerConnection unavailable; signaling message ignored');
      return;
    }
    if (message['type'] == 'offer') {
      debugPrint('SDP offer received');
      session.answerSent = false;
      // This application has one video m-line. Use its actual SDP MID when
      // GStreamer omits sdpMid in trickled ICE (dart_webrtc requires it).
      session.remoteMid = RegExp(
        r'^a=mid:([^\r\n]+)',
        multiLine: true,
      ).firstMatch(message['sdp'] as String)?.group(1);
      await peer.setRemoteDescription(
        RTCSessionDescription(message['sdp'] as String, 'offer'),
      );
      if (!_active(session)) return;
      session.remoteDescriptionSet = true;
      debugPrint('Remote description set');
      for (final candidate in session.remoteIce) {
        await _addRemoteCandidate(session, peer, candidate);
        if (!_active(session)) return;
      }
      session.remoteIce.clear();
      final answer = await peer.createAnswer();
      if (!_active(session)) return;
      final answerSdp = answer.sdp;
      if (answerSdp == null || answerSdp.isEmpty) {
        throw StateError('WebRTC returned an empty SDP answer');
      }
      await peer.setLocalDescription(answer);
      if (!_active(session)) return;
      _send(session, {'type': 'answer', 'sdp': answerSdp});
      debugPrint('SDP answer sent');
      session.answerSent = true;
      for (final candidate in session.localIce) {
        _send(session, candidate);
      }
      session.localIce.clear();
    } else {
      debugPrint('Remote ICE candidate received: ${message['candidate']}');
      final candidate = RTCIceCandidate(
        message['candidate'] as String,
        message['sdpMid'] as String?,
        message['sdpMLineIndex'] as int,
      );
      if (!session.remoteDescriptionSet) {
        session.remoteIce.add(candidate);
      } else {
        await _addRemoteCandidate(session, peer, candidate);
      }
    }
  }

  Future<void> _addRemoteCandidate(
    _Session session,
    RTCPeerConnection peer,
    RTCIceCandidate candidate,
  ) async {
    final mid = candidate.sdpMid ?? session.remoteMid;
    if (mid == null) {
      debugPrint('Ignoring remote ICE: no sdpMid in candidate or SDP offer');
      return;
    }
    await peer.addCandidate(
      RTCIceCandidate(candidate.candidate, mid, candidate.sdpMLineIndex ?? 0),
    );
    debugPrint('Remote ICE candidate added');
  }

  void _fail(_Session session, Object error, [StackTrace? stackTrace]) {
    if (!_active(session)) return;
    debugPrint('Video connection error: $error');
    debugPrint('${stackTrace ?? StackTrace.current}');
    _status(VideoConnectionStatus.error);
    _session = null;
    unawaited(_release(session));
  }

  Future<void> _release(_Session session) async {
    // Attempt every cleanup even if a platform operation fails.
    Future<void> safely(Future<void> Function() operation) async {
      try {
        await operation();
      } catch (error) {
        debugPrint('Video cleanup: $error');
      }
    }

    final peer = session.peer;
    if (peer != null) {
      peer.onTrack = null;
      peer.onIceCandidate = null;
      peer.onIceGatheringState = null;
      peer.onConnectionState = null;
      peer.onIceConnectionState = null;
    }
    await safely(() async {
      await session.subscription?.cancel();
    });
    await safely(() async {
      await session.channel?.sink.close();
    });
    if (peer != null) {
      await safely(peer.close);
      await safely(peer.dispose);
    }
    for (final stream in session.streams) {
      await safely(stream.dispose);
    }
  }

  @override
  Future<void> disconnect() async {
    final session = _session;
    _session = null;
    _status(VideoConnectionStatus.disconnected);
    if (session != null) await _release(session);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disconnect();
    await _streams.close();
    await _statuses.close();
  }
}

class _Session {
  RTCPeerConnection? peer;
  WebSocketChannel? channel;
  StreamSubscription<dynamic>? subscription;
  Future<void> messages = Future<void>.value();
  String? remoteMid;
  bool remoteDescriptionSet = false;
  bool answerSent = false;
  final remoteIce = <RTCIceCandidate>[];
  final localIce = <Map<String, dynamic>>[];
  final streams = <MediaStream>{};
}

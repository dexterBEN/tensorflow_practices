import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:front_app/video/repository/video_repository.dart';
import 'package:front_app/video/repository/webrtc_video_repository.dart';

class FakePeer extends RTCPeerConnection {
  final calls = <String>[];
  bool closed = false;
  bool disposed = false;
  final released = Completer<void>();
  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    calls.add('remote:${description.type}');
  }

  @override
  Future<RTCSessionDescription> createAnswer([
    Map<String, dynamic>? constraints,
  ]) async {
    calls.add('answer');
    return RTCSessionDescription('answer-sdp', 'answer');
  }

  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    calls.add('local');
    onIceCandidate?.call(RTCIceCandidate(null, null, null));
    onIceCandidate?.call(RTCIceCandidate('', null, null));
    onIceCandidate?.call(RTCIceCandidate('local-candidate', null, null));
    onIceGatheringState?.call(
      RTCIceGatheringState.RTCIceGatheringStateComplete,
    );
  }

  @override
  Future<void> addCandidate(RTCIceCandidate candidate) async {
    expect(candidate.sdpMid, 'video0');
    calls.add('ice:${candidate.candidate}');
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    if (!released.isCompleted) released.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeStream implements MediaStream {
  bool disposed = false;
  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTrack implements MediaStreamTrack {
  @override
  String get kind => 'video';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'Answers the offer, buffers early ICE, ignores malformed messages and cleans up',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final peer = FakePeer();
      final socketReady = Completer<WebSocket>();
      server.listen((request) async {
        socketReady.complete(await WebSocketTransformer.upgrade(request));
      });
      final repository = WebRtcVideoRepository(
        signalingUrl: 'ws://127.0.0.1:${server.port}',
        peerFactory: (config) async {
          expect(config['iceServers'], isEmpty);
          return peer;
        },
      );
      addTearDown(() async {
        await repository.dispose();
        await server.close(force: true);
      });
      await repository.connect();
      final socket = await socketReady.future;
      final responses = socket
          .take(2)
          .map((raw) => jsonDecode(raw as String))
          .toList();
      socket.add('not json');
      socket.add(jsonEncode({'type': 'unknown'}));
      socket.add(jsonEncode({'type': 'offer'}));
      socket.add(
        jsonEncode({'type': 'ice', 'candidate': 'early', 'sdpMLineIndex': 0}),
      );
      socket.add(
        jsonEncode({
          'type': 'offer',
          'sdp': 'v=0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=mid:video0\r\n',
        }),
      );
      final messages = await responses.timeout(const Duration(seconds: 5));
      expect(messages[0], {'type': 'answer', 'sdp': 'answer-sdp'});
      expect(messages[1], {
        'type': 'ice',
        'candidate': 'local-candidate',
        'sdpMLineIndex': 0,
      });
      expect(peer.calls, ['remote:offer', 'ice:early', 'answer', 'local']);
      final connected = repository.connectionStatus.first;
      peer.onConnectionState!(
        RTCPeerConnectionState.RTCPeerConnectionStateConnected,
      );
      expect(await connected, VideoConnectionStatus.connected);
      final remote = FakeStream();
      final received = repository.remoteStreams.first;
      peer.onTrack!(RTCTrackEvent(streams: [remote], track: FakeTrack()));
      expect(await received, same(remote));
      await repository.disconnect();
      expect(remote.disposed, isTrue);
      expect(peer.closed, isTrue);
      expect(peer.disposed, isTrue);
      expect(peer.onTrack, isNull);
      await socket.close();
    },
  );

  test('Dispose during peer creation releases the late peer', () async {
    final gate = Completer<RTCPeerConnection>();
    final peer = FakePeer();
    final repository = WebRtcVideoRepository(peerFactory: (_) => gate.future);
    final connecting = repository.connect();
    await repository.dispose();
    gate.complete(peer);
    await connecting;
    expect(peer.closed, isTrue);
    expect(peer.disposed, isTrue);
  });

  test('Failed peer creation emits Error without throwing', () async {
    final repository = WebRtcVideoRepository(
      peerFactory: (_) async => throw StateError('unavailable'),
    );
    final statuses = <VideoConnectionStatus>[];
    final subscription = repository.connectionStatus.listen(statuses.add);
    await repository.connect();
    await repository.dispose();
    expect(statuses, [
      VideoConnectionStatus.connecting,
      VideoConnectionStatus.error,
    ]);
    await subscription.cancel();
  });
}

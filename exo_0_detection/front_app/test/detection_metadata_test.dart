import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_app/detection/model/detection_result.dart';
import 'package:front_app/detection/repository/detection_repository.dart';
import 'package:front_app/detection/repository/websocket_detection_repository.dart';
import 'package:front_app/detection/bloc/detection_bloc.dart';
import 'package:front_app/detection/bloc/detection_event.dart';
import 'package:front_app/detection/bloc/detection_state.dart';
import 'package:front_app/dashboard/widgets/detection_panel.dart';

Map<String, dynamic> message({bool empty = false}) => {
  'type': 'detection',
  'frame': {'width': 640, 'height': 480},
  'inference_ms': 1200.0,
  'persons': empty
      ? []
      : [
          {
            'label': 'person',
            'confidence': 0.64,
            'bbox': {'x1': 171, 'y1': 204, 'x2': 591, 'y2': 478},
          },
        ],
};

class Feed implements DetectionRepository {
  final controller = StreamController<DetectionResult>();
  @override
  Stream<DetectionResult> get detections => controller.stream;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {
    await controller.close();
  }
}

void main() {
  test('Validates metadata and rejects malformed fields', () {
    final result = DetectionResult.fromJson(message());
    expect(result.persons.single.bbox.x2, 591);
    expect(result.frame.width, 640);
    expect(DetectionResult.fromJson(message(empty: true)).persons, isEmpty);
    for (final invalid in [
      null,
      {},
      {'type': 'ice'},
      {...message(), 'inference_ms': -1},
      {...message(), 'persons': null},
      {
        ...message(),
        'frame': {'width': 0, 'height': 480},
      },
    ]) {
      expect(() => DetectionResult.fromJson(invalid), throwsFormatException);
    }
  });
  test(
    'WebSocket streams valid/empty results, ignores invalid JSON and reports close',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = Completer<WebSocket>();
      server.listen(
        (r) async => accepted.complete(await WebSocketTransformer.upgrade(r)),
      );
      final repository = WebSocketDetectionRepository(
        url: 'ws://127.0.0.1:${server.port}',
      );
      addTearDown(() async {
        await repository.disconnect();
        await server.close(force: true);
      });
      await repository.connect();
      final peer = await accepted.future;
      final results = <DetectionResult>[];
      final gotTwo = Completer<void>();
      final closed = Completer<void>();
      repository.detections.listen((r) {
        results.add(r);
        if (results.length == 2) gotTwo.complete();
      }, onDone: closed.complete);
      peer.add('bad JSON');
      peer.add(jsonEncode({'type': 'detection'}));
      peer.add(jsonEncode(message()));
      peer.add(jsonEncode(message(empty: true)));
      await gotTwo.future.timeout(const Duration(seconds: 5));
      expect(results.first.persons, hasLength(1));
      expect(results.last.persons, isEmpty);
      await peer.close();
      await closed.future.timeout(const Duration(seconds: 5));
    },
  );
  testWidgets('Panel clears previous person when empty result arrives', (
    tester,
  ) async {
    final feed = Feed();
    final bloc = DetectionBloc(feed);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(value: bloc, child: const DetectionPanel()),
      ),
    );
    bloc.add(const DetectionStarted());
    await tester.pumpAndSettle();
    feed.controller.add(DetectionResult.fromJson(message()));
    await tester.pumpAndSettle();
    expect(find.text('Source: PYNQ-Z2'), findsOneWidget);
    expect(find.text('Persons: 1'), findsOneWidget);
    feed.controller.add(DetectionResult.fromJson(message(empty: true)));
    await tester.pumpAndSettle();
    expect(find.text('Persons: 0'), findsOneWidget);
    expect(find.text('Status: NO DETECTION'), findsOneWidget);
    expect(find.text('Label: person'), findsNothing);
    bloc.add(const DetectionStopped());
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(bloc.state.status, DetectionStatus.disconnected);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(bloc.close);
  });
}

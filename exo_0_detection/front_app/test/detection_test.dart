import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_app/app.dart';
import 'package:front_app/detection/repository/mock_detection_repository.dart';
import 'package:front_app/detection/model/detection_result.dart';
import 'package:front_app/detection/bloc/detection_bloc.dart';
import 'package:front_app/detection/bloc/detection_event.dart';
import 'package:front_app/detection/bloc/detection_state.dart';
import 'package:front_app/detection/model/detection.dart';
import 'package:front_app/detection/repository/detection_repository.dart';

class TestRepository implements DetectionRepository {
  final controller = StreamController<DetectionResult>.broadcast();
  final gate = Completer<void>();
  bool disconnected = false;
  bool fail = false;

  @override
  Stream<DetectionResult> get detections => controller.stream;
  @override
  Future<void> connect() async {
    await gate.future;
    if (fail) throw StateError('Connection failed');
  }

  @override
  Future<void> disconnect() async {
    disconnected = true;
    await controller.close();
  }
}

void main() {
  testWidgets('Mock dashboard starts, stops, restarts and disposes', (
    tester,
  ) async {
    await tester.pumpWidget(
      DetectionApp(detectionRepositoryFactory: () => MockDetectionRepository()),
    );
    await tester.pump();
    expect(find.text('PYNQ detection: ONLINE'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('Confidence: 94.0 %'), findsOneWidget);
    expect(find.text('bbox: x1=192, y1=72, x2=352, y2=384'), findsOneWidget);
    expect(find.text('Video stream not connected'), findsOneWidget);
    await tester.tap(find.text('Stop'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('No detection received'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Confidence: 94.0 %'), findsNothing);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('Confidence: 94.0 %'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('Dashboard fits a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      DetectionApp(detectionRepositoryFactory: () => MockDetectionRepository()),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test('Close during connect releases the repository', () async {
    final repository = TestRepository();
    final bloc = DetectionBloc(repository);
    final connecting = bloc.stream.firstWhere(
      (s) => s.status == DetectionStatus.connecting,
    );
    bloc.add(const DetectionStarted());
    await connecting;
    final closed = bloc.close();
    repository.gate.complete();
    await closed;
    expect(repository.disconnected, isTrue);
    expect(repository.controller.hasListener, isFalse);
  });

  test('Connection errors become failure state', () async {
    final repository = TestRepository()..fail = true;
    repository.gate.complete();
    final bloc = DetectionBloc(repository);
    final failure = bloc.stream.firstWhere(
      (s) => s.status == DetectionStatus.failure,
    );
    bloc.add(const DetectionStarted());
    expect((await failure).error, contains('Connection failed'));
    expect(repository.disconnected, isTrue);
    await bloc.close();
  });

  test(
    'Stream errors release the subscription and become failure state',
    () async {
      final repository = TestRepository();
      repository.gate.complete();
      final bloc = DetectionBloc(repository);
      final connected = bloc.stream.firstWhere((s) => s.isConnected);
      bloc.add(const DetectionStarted());
      await connected;
      final failure = bloc.stream.firstWhere(
        (s) => s.status == DetectionStatus.failure,
      );
      repository.controller.addError(StateError('Stream failed'));
      expect((await failure).error, contains('Stream failed'));
      expect(repository.controller.hasListener, isFalse);
      await bloc.close();
    },
  );

  test('Bounding boxes reject invalid coordinates', () {
    for (final x in [-0.1, double.nan, 0.9]) {
      expect(
        () => Detection(
          label: 'person',
          confidence: 0.94,
          x: x,
          y: 0.15,
          width: 0.25,
          height: 0.65,
        ),
        throwsArgumentError,
      );
    }
  });
}

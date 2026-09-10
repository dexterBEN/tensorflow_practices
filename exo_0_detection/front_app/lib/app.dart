import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dashboard/dashboard_page.dart';
import 'video/repository/video_repository.dart';
import 'video/repository/webrtc_video_repository.dart';
import 'detection/bloc/detection_bloc.dart';
import 'detection/bloc/detection_event.dart';
import 'detection/repository/detection_repository.dart';
import 'detection/repository/mock_detection_repository.dart';

class DetectionApp extends StatelessWidget {
  const DetectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<DetectionRepository>(
          create: (_) => MockDetectionRepository(),
        ),
        RepositoryProvider<VideoRepository>(
          create: (_) => WebRtcVideoRepository(),
          dispose: (repository) => repository.dispose(),
        ),
      ],
      // DetectionBloc owns the connection and disconnects when disposed.
      child: BlocProvider(
        create: (context) =>
            DetectionBloc(context.read<DetectionRepository>())
              ..add(const DetectionStarted()),
        child: MaterialApp(
          title: 'Person Detection',
          theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
          home: const DashboardPage(),
        ),
      ),
    );
  }
}

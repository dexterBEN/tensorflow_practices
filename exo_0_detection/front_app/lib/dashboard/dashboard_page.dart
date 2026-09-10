import 'package:flutter/material.dart';
import 'widgets/detection_panel.dart';
import 'widgets/status_panel.dart';
import '../video/view/video_view.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Person Detection')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const StatusPanel(),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 800) {
                  return const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      VideoView(),
                      SizedBox(height: 16),
                      DetectionPanel(),
                    ],
                  );
                }
                return const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: VideoView()),
                    SizedBox(width: 16),
                    Expanded(child: DetectionPanel()),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

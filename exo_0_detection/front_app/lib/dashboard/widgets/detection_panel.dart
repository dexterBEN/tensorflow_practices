import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../detection/bloc/detection_bloc.dart';
import '../../detection/bloc/detection_state.dart';

class DetectionPanel extends StatelessWidget {
  const DetectionPanel({super.key});

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<DetectionBloc, DetectionState>(
    builder: (context, state) {
      final detection = state.detection;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Detection', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Text('Connection status: ${state.status.name.toUpperCase()}'),
              const Text('Source: simulated metadata (mock)'),
              const SizedBox(height: 16),
              if (state.error != null) Text('Error: ${state.error}'),
              if (detection == null)
                const Text('No detection received')
              else ...[
                Text('Label: ${detection.label}'),
                Text(
                  'Confidence: ${(detection.confidence * 100).toStringAsFixed(1)} %',
                ),
                const Text('Status: DETECTED'),
                const SizedBox(height: 16),
                const Text('Bounding box (normalized)'),
                Text('x: ${detection.x.toStringAsFixed(2)}'),
                Text('y: ${detection.y.toStringAsFixed(2)}'),
                Text('width: ${detection.width.toStringAsFixed(2)}'),
                Text('height: ${detection.height.toStringAsFixed(2)}'),
              ],
            ],
          ),
        ),
      );
    },
  );
}

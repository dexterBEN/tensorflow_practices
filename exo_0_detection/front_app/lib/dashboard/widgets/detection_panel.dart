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
              const Text('Source: PYNQ-Z2'),
              const SizedBox(height: 16),
              if (state.error != null) Text('Error: ${state.error}'),
              if (detection == null)
                const Text('No detection received')
              else ...[
                Text('Persons: ${detection.persons.length}'),
                Text(
                  'Status: ${detection.persons.isEmpty ? 'NO DETECTION' : 'DETECTED'}',
                ),
                Text(
                  'Inference time: ${detection.inferenceMs.toStringAsFixed(1)} ms',
                ),
                Text(
                  'Frame: ${detection.frame.width} × ${detection.frame.height}',
                ),
                for (final person in detection.persons) ...[
                  const SizedBox(height: 16),
                  Text('Label: ${person.label}'),
                  Text(
                    'Confidence: ${(person.confidence * 100).toStringAsFixed(1)} %',
                  ),
                  Text(
                    'bbox: x1=${person.bbox.x1}, y1=${person.bbox.y1}, x2=${person.bbox.x2}, y2=${person.bbox.y2}',
                  ),
                ],
              ],
            ],
          ),
        ),
      );
    },
  );
}

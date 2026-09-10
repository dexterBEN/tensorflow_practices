import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../detection/bloc/detection_bloc.dart';
import '../../detection/bloc/detection_event.dart';
import '../../detection/bloc/detection_state.dart';

class StatusPanel extends StatelessWidget {
  const StatusPanel({super.key});

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<DetectionBloc, DetectionState>(
    builder: (context, state) => Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Chip(
          avatar: Icon(state.isConnected ? Icons.cloud_done : Icons.cloud_off),
          label: Text(
            'Mock detection: ${state.isConnected ? 'ONLINE' : state.status.name.toUpperCase()}',
          ),
        ),
        FilledButton.icon(
          onPressed: state.status == DetectionStatus.connecting
              ? null
              : () {
                  context.read<DetectionBloc>().add(
                    state.isConnected
                        ? const DetectionStopped()
                        : const DetectionStarted(),
                  );
                },
          icon: Icon(state.isConnected ? Icons.stop : Icons.play_arrow),
          label: Text(state.isConnected ? 'Stop' : 'Start'),
        ),
      ],
    ),
  );
}

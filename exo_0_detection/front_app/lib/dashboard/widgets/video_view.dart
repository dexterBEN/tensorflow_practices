import 'package:flutter/material.dart';

/// Video rendering stays independent of detection metadata and its BLoC.
class VideoView extends StatelessWidget {
  const VideoView({super.key});

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 16 / 9,
    child: ColoredBox(
      color: const Color(0xFF202124),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined, color: Colors.white70, size: 48),
            SizedBox(height: 12),
            Text(
              'Video stream not connected',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    ),
  );
}

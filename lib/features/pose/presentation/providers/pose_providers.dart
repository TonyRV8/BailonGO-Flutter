import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/mediapipe_pose_landmarker.dart';
import '../../domain/pose_landmarker.dart';

/// Detector de pose (MediaPipe vía platform channel). Se cierra al desmontar
/// para liberar el detector nativo.
final poseLandmarkerProvider = Provider<PoseLandmarker>((ref) {
  final landmarker = MediaPipePoseLandmarker();
  ref.onDispose(landmarker.close);
  return landmarker;
});

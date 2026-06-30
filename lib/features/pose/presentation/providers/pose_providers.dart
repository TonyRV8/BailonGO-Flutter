import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/mlkit_pose_landmarker.dart';
import '../../domain/pose_landmarker.dart';

/// Detector de pose (ML Kit). Se cierra al desmontar para liberar el detector
/// nativo.
final poseLandmarkerProvider = Provider<PoseLandmarker>((ref) {
  final landmarker = MlkitPoseLandmarker();
  ref.onDispose(landmarker.close);
  return landmarker;
});

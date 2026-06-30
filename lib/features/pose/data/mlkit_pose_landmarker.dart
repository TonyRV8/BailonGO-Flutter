import 'dart:ui' show Size;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../domain/entities/pose_frame.dart' as domain;
import '../domain/entities/pose_landmark.dart' as domain;
import '../domain/pose_landmarker.dart';

/// Implementación de [PoseLandmarker] con Google ML Kit Pose Detection
/// (BlazePose, 33 landmarks, doc 6.1). On-device, sin red.
class MlkitPoseLandmarker implements PoseLandmarker {
  MlkitPoseLandmarker()
      : _detector = PoseDetector(
          options: PoseDetectorOptions(
            mode: PoseDetectionMode.stream,
            model: PoseDetectionModel.base, // "lite"; accurate = más pesado
          ),
        );

  final PoseDetector _detector;

  @override
  Future<domain.PoseFrame> detect(InputImage inputImage) async {
    final size = inputImage.metadata?.size ?? Size.zero;
    final rotation = inputImage.metadata?.rotation.rawValue ?? 0;

    final poses = await _detector.processImage(inputImage);
    if (poses.isEmpty) {
      return domain.PoseFrame.empty(size, rotation);
    }

    // Un solo cuerpo (el bailarín). Tomamos la primera pose.
    final pose = poses.first;
    final landmarks = pose.landmarks.values
        .map((lm) => domain.PoseLandmark(
              type: lm.type.index,
              x: lm.x,
              y: lm.y,
              z: lm.z,
              confidence: lm.likelihood,
            ))
        .toList();

    return domain.PoseFrame(
      landmarks: landmarks,
      imageSize: size,
      rotationDegrees: rotation,
    );
  }

  @override
  Future<void> close() => _detector.close();
}

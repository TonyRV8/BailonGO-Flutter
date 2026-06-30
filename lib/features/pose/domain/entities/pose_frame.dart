import 'pose_landmark.dart';

/// Resultado de pose para un fotograma: los 33 landmarks (o vacío si no se
/// detectó cuerpo). Las coordenadas vienen normalizadas 0..1 respecto a la
/// imagen vertical (MediaPipe ya aplicó la rotación), por lo que la UI las
/// mapea directo al canvas.
class PoseFrame {
  const PoseFrame({required this.landmarks});

  final List<PoseLandmark> landmarks;

  bool get hasBody => landmarks.isNotEmpty;

  PoseLandmark? byType(int type) {
    for (final lm in landmarks) {
      if (lm.type == type) return lm;
    }
    return null;
  }

  static const PoseFrame empty = PoseFrame(landmarks: []);
}

import 'dart:ui' show Size;

import 'pose_landmark.dart';

/// Resultado de pose para un fotograma: los 33 landmarks (o vacío si no se
/// detectó cuerpo) más los metadatos de la imagen de origen, necesarios para
/// dibujar el overlay (RF-09) sin acoplar la UI al detector.
class PoseFrame {
  const PoseFrame({
    required this.landmarks,
    required this.imageSize,
    required this.rotationDegrees,
  });

  final List<PoseLandmark> landmarks;

  /// Tamaño de la imagen de la cámara (px, antes de rotar).
  final Size imageSize;

  /// Rotación a aplicar (0/90/180/270) para mapear a coords de pantalla.
  final int rotationDegrees;

  bool get hasBody => landmarks.isNotEmpty;

  PoseLandmark? byType(int type) {
    for (final lm in landmarks) {
      if (lm.type == type) return lm;
    }
    return null;
  }

  static PoseFrame empty(Size size, int rotation) =>
      PoseFrame(landmarks: const [], imageSize: size, rotationDegrees: rotation);
}

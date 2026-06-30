/// Un landmark de pose (1 de 33, orden BlazePose/MediaPipe, doc 6.1).
/// Coordenadas en el espacio de la imagen de origen (px).
class PoseLandmark {
  const PoseLandmark({
    required this.type,
    required this.x,
    required this.y,
    required this.z,
    required this.confidence,
  });

  /// Índice 0..32 (BlazePose). Ver [PoseLandmarks].
  final int type;
  final double x;
  final double y;

  /// Profundidad relativa (no en px). Se usa en el motor de evaluación.
  final double z;

  /// Confianza 0..1 (likelihood). RNF-05 invalida con < 0.90 sostenido.
  final double confidence;
}

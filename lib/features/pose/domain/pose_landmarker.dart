import 'dart:typed_data';

import 'entities/pose_frame.dart';

/// Interfaz del Módulo de Adquisición de Landmarks (doc 5.3.2). Desacopla el
/// motor de evaluación del origen de los datos. La implementación actual usa
/// MediaPipe Tasks Vision vía platform channel; la firma es neutral (no
/// depende de ningún plugin) para poder sustituirla.
abstract class PoseLandmarker {
  /// Inicializa el detector nativo (carga el modelo .task).
  Future<void> initialize();

  /// Procesa un fotograma NV21 y devuelve sus landmarks (vacío si no hay
  /// cuerpo). [rotationDegrees] es la rotación necesaria para enderezar la
  /// imagen (0/90/180/270).
  Future<PoseFrame> detect({
    required Uint8List nv21,
    required int width,
    required int height,
    required int rotationDegrees,
  });

  /// Libera el detector nativo.
  Future<void> close();
}

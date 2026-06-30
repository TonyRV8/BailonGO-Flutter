import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    show InputImage;

import 'entities/pose_frame.dart';

/// Interfaz del Módulo de Adquisición de Landmarks (doc 5.3.2). Desacopla el
/// motor de evaluación del origen de los datos (ML Kit hoy, MediaPipe propio
/// si en el futuro hace falta más FPS).
///
/// El parámetro [InputImage] es el único punto de contacto con ML Kit; el
/// motor de evaluación solo consume [PoseFrame].
abstract class PoseLandmarker {
  /// Procesa un fotograma y devuelve sus landmarks (vacío si no hay cuerpo).
  Future<PoseFrame> detect(InputImage inputImage);

  /// Libera el detector nativo.
  Future<void> close();
}

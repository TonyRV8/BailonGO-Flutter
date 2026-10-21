import 'entities/pose_frame.dart';
import 'pose_landmarks.dart';

/// Lado del cuerpo con el brazo levantado, según los landmarks.
enum RaisedSide { none, left, right, both }

/// Comprobación de lateralidad (la usa `LateralityCheckPage`).
///
/// Se mantiene fuera de la pantalla para poder probarla sin cámara: es la
/// parte que decide si el teléfono entrega los lados cambiados.
class Laterality {
  Laterality._();

  /// Cuánto tiene que subir la muñeca por encima del hombro para contar como
  /// brazo levantado, en alto de imagen normalizado.
  static const double raiseMargin = 0.05;

  static const double minConfidence = 0.5;

  /// Lado levantado tal como lo reporta el detector. [RaisedSide.none] si no
  /// hay cuerpo, si los puntos no son fiables o si los dos brazos están abajo.
  static RaisedSide raisedArm(PoseFrame f) {
    if (!f.hasBody) return RaisedSide.none;
    bool up(int wrist, int shoulder) {
      final w = f.byType(wrist);
      final s = f.byType(shoulder);
      if (w == null || s == null) return false;
      if (w.confidence < minConfidence || s.confidence < minConfidence) {
        return false;
      }
      // La y crece hacia abajo: la muñeca está arriba si su y es MENOR.
      return w.y < s.y - raiseMargin;
    }

    final left = up(PoseLandmarks.leftWrist, PoseLandmarks.leftShoulder);
    final right = up(PoseLandmarks.rightWrist, PoseLandmarks.rightShoulder);
    if (left && right) return RaisedSide.both;
    if (left) return RaisedSide.left;
    if (right) return RaisedSide.right;
    return RaisedSide.none;
  }

  /// Lo que la EVALUACIÓN entendería: con "Corregir lateralidad" activo
  /// (`users.settings.mirrorCapture`) los lados se intercambian, así que la
  /// prueba tiene que mirar lo mismo que mira el motor.
  static RaisedSide asEvaluated(RaisedSide raw, {required bool mirrored}) {
    if (!mirrored) return raw;
    return switch (raw) {
      RaisedSide.left => RaisedSide.right,
      RaisedSide.right => RaisedSide.left,
      _ => raw,
    };
  }
}

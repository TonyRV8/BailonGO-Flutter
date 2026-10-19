import 'dart:ui' show lerpDouble;

import '../../pose/domain/entities/pose_frame.dart';
import '../../pose/domain/entities/pose_landmark.dart';
import '../../pose/domain/pose_landmarks.dart';

/// Postura de los brazos de la figura del tutorial.
enum TutorialArms { down, up, hips }

/// Figura de pie, de frente a la cámara, descrita en coordenadas normalizadas
/// de la pantalla (0..1, y hacia abajo), igual que los [PoseFrame] que entrega
/// MediaPipe. Así el tutorial la dibuja con el mismo `PosePainter` que la
/// evaluación real.
class TutorialFigure {
  const TutorialFigure({
    required this.centerX,
    required this.top,
    required this.height,
    required this.arms,
  });

  /// Centro horizontal del cuerpo.
  final double centerX;

  /// Coronilla.
  final double top;

  /// Altura total (coronilla → planta), en fracción del alto de pantalla.
  final double height;

  /// Mezcla de posturas de brazos: peso por postura (suman 1).
  final Map<TutorialArms, double> arms;

  /// Puntos de cada postura de brazos, relativos a la figura: (x en
  /// alturas desde el centro, y en alturas desde la coronilla). La izquierda
  /// de la persona queda a la derecha de la pantalla (está de frente).
  static const _armPoints = {
    TutorialArms.down: (elbow: (0.14, 0.34), wrist: (0.15, 0.48)),
    TutorialArms.up: (elbow: (0.17, 0.07), wrist: (0.18, -0.07)),
    TutorialArms.hips: (elbow: (0.23, 0.37), wrist: (0.10, 0.49)),
  };

  /// Torso y piernas (no cambian con los brazos).
  static const _body = {
    0: (0.0, 0.06), // nariz
    7: (0.035, 0.05), // oreja izquierda
    8: (-0.035, 0.05), // oreja derecha
    PoseLandmarks.leftShoulder: (0.11, 0.18),
    PoseLandmarks.rightShoulder: (-0.11, 0.18),
    PoseLandmarks.leftHip: (0.07, 0.50),
    PoseLandmarks.rightHip: (-0.07, 0.50),
    PoseLandmarks.leftKnee: (0.075, 0.72),
    PoseLandmarks.rightKnee: (-0.075, 0.72),
    PoseLandmarks.leftAnkle: (0.08, 0.94),
    PoseLandmarks.rightAnkle: (-0.08, 0.94),
    PoseLandmarks.leftHeel: (0.08, 0.97),
    PoseLandmarks.rightHeel: (-0.08, 0.97),
    PoseLandmarks.leftFootIndex: (0.10, 1.0),
    PoseLandmarks.rightFootIndex: (-0.10, 1.0),
  };

  (double, double) _arm(bool elbow) {
    var x = 0.0, y = 0.0;
    arms.forEach((pose, w) {
      final p = _armPoints[pose]!;
      final pt = elbow ? p.elbow : p.wrist;
      x += pt.$1 * w;
      y += pt.$2 * w;
    });
    return (x, y);
  }

  /// Posición en pantalla (normalizada) de un landmark.
  (double, double) point(int type) {
    final rel = switch (type) {
      PoseLandmarks.leftElbow => _arm(true),
      PoseLandmarks.leftWrist => _arm(false),
      PoseLandmarks.rightElbow => (-_arm(true).$1, _arm(true).$2),
      PoseLandmarks.rightWrist => (-_arm(false).$1, _arm(false).$2),
      _ => _body[type]!,
    };
    return (centerX + rel.$1 * height, top + rel.$2 * height);
  }

  /// Todos los landmarks que dibuja el esqueleto. Los que quedan fuera de
  /// pantalla llevan confianza baja, como haría MediaPipe con un cuerpo
  /// recortado (el `PosePainter` los marca en rojo).
  PoseFrame toFrame() {
    final types = [
      ..._body.keys,
      PoseLandmarks.leftElbow,
      PoseLandmarks.rightElbow,
      PoseLandmarks.leftWrist,
      PoseLandmarks.rightWrist,
    ];
    return PoseFrame(landmarks: [
      for (final type in types)
        () {
          final (x, y) = point(type);
          final inside = y >= 0 && y <= 1;
          return PoseLandmark(
            type: type,
            x: x,
            y: y,
            z: 0,
            confidence: inside ? 0.99 : 0.2,
          );
        }(),
    ]);
  }

  /// Interpolación entre dos figuras.
  static TutorialFigure lerp(TutorialFigure a, TutorialFigure b, double t) {
    final arms = <TutorialArms, double>{};
    for (final pose in TutorialArms.values) {
      arms[pose] = lerpDouble(a.arms[pose] ?? 0, b.arms[pose] ?? 0, t)!;
    }
    return TutorialFigure(
      centerX: lerpDouble(a.centerX, b.centerX, t)!,
      top: lerpDouble(a.top, b.top, t)!,
      height: lerpDouble(a.height, b.height, t)!,
      arms: arms,
    );
  }
}

import 'package:bailongo/features/pose/domain/entities/pose_frame.dart';
import 'package:bailongo/features/pose/domain/entities/pose_landmark.dart';
import 'package:bailongo/features/pose/domain/laterality.dart';
import 'package:bailongo/features/pose/domain/pose_landmarks.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cuerpo de pie con los hombros a y=0.3 y las muñecas donde se pidan.
/// La y crece hacia abajo, así que una muñeca "arriba" tiene y menor.
PoseFrame body({
  required double leftWristY,
  required double rightWristY,
  double confidence = 0.9,
}) {
  PoseLandmark lm(int type, double y) =>
      PoseLandmark(type: type, x: 0.5, y: y, z: 0, confidence: confidence);
  return PoseFrame(landmarks: [
    lm(PoseLandmarks.leftShoulder, 0.3),
    lm(PoseLandmarks.rightShoulder, 0.3),
    lm(PoseLandmarks.leftWrist, leftWristY),
    lm(PoseLandmarks.rightWrist, rightWristY),
  ]);
}

void main() {
  group('brazo levantado', () {
    test('sin cuerpo no hay lado', () {
      expect(Laterality.raisedArm(PoseFrame.empty), RaisedSide.none);
    });

    test('brazos abajo', () {
      expect(Laterality.raisedArm(body(leftWristY: 0.6, rightWristY: 0.6)),
          RaisedSide.none);
    });

    test('derecho arriba', () {
      expect(Laterality.raisedArm(body(leftWristY: 0.6, rightWristY: 0.1)),
          RaisedSide.right);
    });

    test('izquierdo arriba', () {
      expect(Laterality.raisedArm(body(leftWristY: 0.1, rightWristY: 0.6)),
          RaisedSide.left);
    });

    test('los dos arriba no decide', () {
      expect(Laterality.raisedArm(body(leftWristY: 0.1, rightWristY: 0.1)),
          RaisedSide.both);
    });

    test('la muñeca apenas por encima del hombro no cuenta', () {
      // 0.02 < raiseMargin: rascarse la cabeza no es levantar el brazo.
      expect(Laterality.raisedArm(body(leftWristY: 0.6, rightWristY: 0.28)),
          RaisedSide.none);
    });

    test('puntos poco fiables no deciden', () {
      expect(
        Laterality.raisedArm(
            body(leftWristY: 0.6, rightWristY: 0.1, confidence: 0.2)),
        RaisedSide.none,
      );
    });
  });

  group('lo que entiende la evaluación', () {
    test('sin corrección, el lado es el del detector', () {
      expect(Laterality.asEvaluated(RaisedSide.right, mirrored: false),
          RaisedSide.right);
    });

    test('con corrección, los lados se intercambian', () {
      expect(Laterality.asEvaluated(RaisedSide.right, mirrored: true),
          RaisedSide.left);
      expect(Laterality.asEvaluated(RaisedSide.left, mirrored: true),
          RaisedSide.right);
    });

    test('los casos sin lado no cambian', () {
      for (final s in [RaisedSide.none, RaisedSide.both]) {
        expect(Laterality.asEvaluated(s, mirrored: true), s);
      }
    });
  });
}

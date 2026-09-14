import 'package:bailongo/features/evaluation/engine/retry_gesture_detector.dart';
import 'package:bailongo/features/pose/domain/entities/pose_frame.dart';
import 'package:bailongo/features/pose/domain/entities/pose_landmark.dart';
import 'package:bailongo/features/pose/domain/pose_landmarks.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cuerpo sintético de pie. Hombros en y=0.30 y caderas en y=0.55: torso = 0.25.
///
/// [pose] elige la postura de los brazos:
///  - `hips`  : manos en la cintura (muñeca a la altura de la cadera, codo fuera)
///  - `down`  : brazos colgando (muñeca a la altura del muslo)
///  - `up`    : brazos levantados
///  - `folded`: muñecas en la cintura pero con los codos pegados al cuerpo
PoseFrame frameOf({
  String pose = 'hips',
  double confidence = 0.9,
  double scale = 1,
}) {
  const shoulderY = 0.30;
  final hipY = shoulderY + 0.25 * scale;

  late double wristY, wristXOffset, elbowXOffset;
  switch (pose) {
    case 'hips':
      wristY = hipY; // a la altura de la cadera
      wristXOffset = 0.02;
      elbowXOffset = 0.09; // codo más abierto que la muñeca
    case 'down':
      wristY = hipY + 0.35; // muslo
      wristXOffset = 0.02;
      elbowXOffset = 0.01;
    case 'up':
      wristY = 0.10;
      wristXOffset = 0.02;
      elbowXOffset = 0.05;
    case 'folded':
      wristY = hipY;
      wristXOffset = 0.02;
      elbowXOffset = 0.0; // codo pegado: no es jarras
    default:
      throw ArgumentError(pose);
  }

  PoseLandmark lm(int type, double x, double y) =>
      PoseLandmark(type: type, x: x, y: y, z: 0, confidence: confidence);

  return PoseFrame(landmarks: [
    lm(PoseLandmarks.leftShoulder, 0.40, shoulderY),
    lm(PoseLandmarks.rightShoulder, 0.60, shoulderY),
    lm(PoseLandmarks.leftElbow, 0.42 - elbowXOffset, (shoulderY + hipY) / 2),
    lm(PoseLandmarks.rightElbow, 0.58 + elbowXOffset, (shoulderY + hipY) / 2),
    lm(PoseLandmarks.leftWrist, 0.42 - wristXOffset, wristY),
    lm(PoseLandmarks.rightWrist, 0.58 + wristXOffset, wristY),
    lm(PoseLandmarks.leftHip, 0.42, hipY),
    lm(PoseLandmarks.rightHip, 0.58, hipY),
  ]);
}

void main() {
  final t0 = DateTime(2026, 1, 1, 12, 0, 0);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  test('no escucha durante el margen inicial', () {
    final d = RetryGestureDetector()..start(t0);
    expect(d.update(frameOf(), now: at(0)), isFalse);
    expect(d.update(frameOf(), now: at(1100)), isFalse);
    expect(d.progress, 0);
  });

  test('manos en la cintura sostenidas disparan el reintento', () {
    final d = RetryGestureDetector()..start(t0);
    expect(d.update(frameOf(), now: at(1300)), isFalse);
    expect(d.update(frameOf(), now: at(1700)), isFalse);
    expect(d.update(frameOf(), now: at(2100)), isTrue);
  });

  test('brazos colgando no disparan', () {
    final d = RetryGestureDetector()..start(t0);
    for (var ms = 1300; ms <= 6000; ms += 300) {
      expect(d.update(frameOf(pose: 'down'), now: at(ms)), isFalse);
    }
  });

  test('brazos levantados no disparan', () {
    final d = RetryGestureDetector()..start(t0);
    for (var ms = 1300; ms <= 6000; ms += 300) {
      expect(d.update(frameOf(pose: 'up'), now: at(ms)), isFalse);
    }
  });

  test('muñecas en la cintura con los codos pegados no cuentan como jarras', () {
    final d = RetryGestureDetector()..start(t0);
    for (var ms = 1300; ms <= 6000; ms += 300) {
      expect(d.update(frameOf(pose: 'folded'), now: at(ms)), isFalse);
    }
  });

  test('soltar la postura reinicia la ventana', () {
    final d = RetryGestureDetector()..start(t0);
    d.update(frameOf(), now: at(1300));
    d.update(frameOf(), now: at(1800)); // 500 ms sostenidos
    d.update(frameOf(pose: 'down'), now: at(1850)); // se rompe
    expect(d.progress, 0);
    d.update(frameOf(), now: at(1900));
    expect(d.update(frameOf(), now: at(2400)), isFalse);
    expect(d.update(frameOf(), now: at(2650)), isTrue);
  });

  test('sin cuerpo no dispara', () {
    final d = RetryGestureDetector()..start(t0);
    for (var ms = 1300; ms <= 6000; ms += 300) {
      expect(d.update(PoseFrame.empty, now: at(ms)), isFalse);
    }
  });

  test('landmarks sin confianza suficiente no disparan', () {
    final d = RetryGestureDetector()..start(t0);
    for (var ms = 1300; ms <= 6000; ms += 300) {
      expect(d.update(frameOf(confidence: 0.3), now: at(ms)), isFalse);
    }
  });

  test('el progreso avanza mientras se sostiene', () {
    final d = RetryGestureDetector()..start(t0);
    d.update(frameOf(), now: at(1300));
    d.update(frameOf(), now: at(1650));
    expect(d.progress, closeTo(0.5, 0.01));
  });

  test('tras disparar queda listo para el siguiente intento', () {
    final d = RetryGestureDetector()..start(t0);
    d.update(frameOf(), now: at(1300));
    expect(d.update(frameOf(), now: at(2100)), isTrue);
    expect(d.progress, 0);
    // Sin volver a llamar a start(), el margen inicial vuelve a aplicarse.
    expect(d.update(frameOf(), now: at(2200)), isFalse);
  });
}

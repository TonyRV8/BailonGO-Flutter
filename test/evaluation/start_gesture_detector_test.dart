import 'package:bailongo/features/evaluation/engine/start_gesture_detector.dart';
import 'package:bailongo/features/pose/domain/entities/pose_frame.dart';
import 'package:bailongo/features/pose/domain/entities/pose_landmark.dart';
import 'package:bailongo/features/pose/domain/pose_landmarks.dart';
import 'package:flutter_test/flutter_test.dart';

/// Construye un fotograma sintético. [armsUp] sube las muñecas por encima de
/// los hombros; [dx]/[dy] desplazan todo el cuerpo (para probar la quietud);
/// [lowerConfidence] permite romper el gate de RNF-05.
PoseFrame frameOf({
  bool armsUp = false,
  bool leftArmUp = false,
  double dx = 0,
  double dy = 0,
  double lowerConfidence = 0.9,
  double wristY = -1,
}) {
  PoseLandmark lm(int type, double x, double y, [double c = 0.9]) =>
      PoseLandmark(type: type, x: x + dx, y: y + dy, z: 0, confidence: c);

  const shoulderY = 0.30;
  final double upY = wristY >= 0 ? wristY : 0.15; // por encima de los hombros
  const downY = 0.55; // colgando

  return PoseFrame(landmarks: [
    lm(PoseLandmarks.leftShoulder, 0.40, shoulderY),
    lm(PoseLandmarks.rightShoulder, 0.60, shoulderY),
    lm(PoseLandmarks.leftWrist, 0.35, armsUp || leftArmUp ? upY : downY),
    lm(PoseLandmarks.rightWrist, 0.65, armsUp ? upY : downY),
    lm(PoseLandmarks.leftHip, 0.42, 0.55, lowerConfidence),
    lm(PoseLandmarks.rightHip, 0.58, 0.55, lowerConfidence),
    lm(PoseLandmarks.leftKnee, 0.42, 0.72, lowerConfidence),
    lm(PoseLandmarks.rightKnee, 0.58, 0.72, lowerConfidence),
    lm(PoseLandmarks.leftAnkle, 0.42, 0.90, lowerConfidence),
    lm(PoseLandmarks.rightAnkle, 0.58, 0.90, lowerConfidence),
  ]);
}

void main() {
  final t0 = DateTime(2026, 1, 1, 10, 0, 0);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  group('gate de encuadre', () {
    test('sin cuerpo no arma', () {
      final d = StartGestureDetector()..start(t0);
      final s = d.update(PoseFrame.empty, now: at(100));
      expect(s.state, ArmingState.noBody);
      expect(s.isTriggered, isFalse);
    });

    test('tren inferior sin confianza suficiente: outOfFrame aunque el gesto sea válido', () {
      final d = StartGestureDetector()..start(t0);
      final s = d.update(frameOf(armsUp: true, lowerConfidence: 0.4),
          now: at(1000));
      expect(s.state, ArmingState.outOfFrame);
      expect(s.isTriggered, isFalse);
    });
  });

  group('gesto de brazos arriba', () {
    test('brazos abajo: en espera', () {
      final d = StartGestureDetector(stillnessEnabled: false)..start(t0);
      expect(d.update(frameOf(), now: at(100)).state, ArmingState.waiting);
    });

    test('una sola muñeca arriba no cuenta', () {
      final d = StartGestureDetector(stillnessEnabled: false)..start(t0);
      d.update(frameOf(leftArmUp: true), now: at(0));
      final s = d.update(frameOf(leftArmUp: true), now: at(2000));
      expect(s.state, ArmingState.waiting);
      expect(s.isTriggered, isFalse);
    });

    test('mantener menos de la ventana no dispara, pero muestra progreso', () {
      final d = StartGestureDetector(stillnessEnabled: false)..start(t0);
      d.update(frameOf(armsUp: true), now: at(0));
      final s = d.update(frameOf(armsUp: true), now: at(200));
      expect(s.state, ArmingState.raisingArms);
      expect(s.progress, closeTo(0.5, 0.01));
      expect(s.isTriggered, isFalse);
    });

    test('mantener la ventana completa dispara por brazos', () {
      final d = StartGestureDetector(stillnessEnabled: false)..start(t0);
      d.update(frameOf(armsUp: true), now: at(0));
      final s = d.update(frameOf(armsUp: true), now: at(400));
      expect(s.trigger, StartTrigger.arms);
      expect(s.progress, 1);
    });

    test('interrumpir el gesto reinicia la ventana', () {
      final d = StartGestureDetector(stillnessEnabled: false)..start(t0);
      d.update(frameOf(armsUp: true), now: at(0));
      d.update(frameOf(armsUp: true), now: at(300));
      d.update(frameOf(), now: at(350)); // baja los brazos
      d.update(frameOf(armsUp: true), now: at(400));
      final s = d.update(frameOf(armsUp: true), now: at(700));
      expect(s.isTriggered, isFalse, reason: 'solo lleva 300 ms desde el reinicio');
      expect(d.update(frameOf(armsUp: true), now: at(800)).trigger,
          StartTrigger.arms);
    });

    test('muñecas fuera del borde superior (y negativa) cuentan como gesto', () {
      final d = StartGestureDetector(stillnessEnabled: false)..start(t0);
      d.update(frameOf(armsUp: true, wristY: -0.08), now: at(0));
      final s = d.update(frameOf(armsUp: true, wristY: -0.08), now: at(500));
      expect(s.trigger, StartTrigger.arms);
    });
  });

  group('arranque por quietud', () {
    test('no dispara durante el margen de cortesía', () {
      final d = StartGestureDetector()..start(t0);
      d.update(frameOf(), now: at(0));
      final s = d.update(frameOf(), now: at(1400));
      expect(s.isTriggered, isFalse);
      expect(s.state, ArmingState.waiting);
    });

    test('quieto y encuadrado dispara a los 2 s', () {
      final d = StartGestureDetector()..start(t0);
      d.update(frameOf(), now: at(1500)); // fija el ancla
      expect(d.update(frameOf(), now: at(2500)).state, ArmingState.holdingStill);
      final s = d.update(frameOf(), now: at(3500));
      expect(s.trigger, StartTrigger.stillness);
    });

    test('moverse reinicia la cuenta de quietud', () {
      final d = StartGestureDetector()..start(t0);
      d.update(frameOf(), now: at(1500));
      d.update(frameOf(), now: at(3000)); // 1.5 s quieto
      d.update(frameOf(dx: 0.10), now: at(3100)); // da un paso
      final s = d.update(frameOf(dx: 0.10), now: at(4500));
      expect(s.isTriggered, isFalse, reason: 'solo lleva 1.4 s desde el paso');
      expect(d.update(frameOf(dx: 0.10), now: at(5200)).trigger,
          StartTrigger.stillness);
    });

    test('micro-movimiento dentro de la tolerancia no reinicia', () {
      final d = StartGestureDetector()..start(t0);
      d.update(frameOf(), now: at(1500));
      d.update(frameOf(dx: 0.01), now: at(2500));
      final s = d.update(frameOf(dy: 0.01), now: at(3500));
      expect(s.trigger, StartTrigger.stillness);
    });

    test('desactivado: no arranca nunca solo', () {
      final d = StartGestureDetector(stillnessEnabled: false)..start(t0);
      d.update(frameOf(), now: at(1500));
      for (var ms = 2000; ms <= 10000; ms += 500) {
        expect(d.update(frameOf(), now: at(ms)).isTriggered, isFalse);
      }
    });

    test('se puede activar y desactivar en caliente', () {
      final d = StartGestureDetector(stillnessEnabled: false)..start(t0);
      d.update(frameOf(), now: at(1500));
      expect(d.update(frameOf(), now: at(4000)).isTriggered, isFalse);
      d.stillnessEnabled = true;
      d.update(frameOf(), now: at(4100));
      expect(d.update(frameOf(), now: at(6200)).trigger, StartTrigger.stillness);
    });

    test('perder el encuadre reinicia la quietud', () {
      final d = StartGestureDetector()..start(t0);
      d.update(frameOf(), now: at(1500));
      d.update(frameOf(lowerConfidence: 0.2), now: at(2000));
      final s = d.update(frameOf(), now: at(3600));
      expect(s.isTriggered, isFalse);
    });
  });

  test('reset deja el detector como recién armado', () {
    final d = StartGestureDetector(stillnessEnabled: false)..start(t0);
    d.update(frameOf(armsUp: true), now: at(0));
    d.reset();
    d.start(at(1000));
    final s = d.update(frameOf(armsUp: true), now: at(1200));
    expect(s.isTriggered, isFalse);
    expect(s.state, ArmingState.raisingArms);
  });
}

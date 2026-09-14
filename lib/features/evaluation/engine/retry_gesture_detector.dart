import '../../pose/domain/entities/pose_frame.dart';
import '../../pose/domain/entities/pose_landmark.dart';
import '../../pose/domain/pose_landmarks.dart';

/// Detecta la postura "manos en la cintura" (brazos en jarras) para reintentar
/// el paso sin volver al teléfono (RF-11).
///
/// La postura se reconoce por tres rasgos simultáneos en cada lado, todos
/// medidos EN PROPORCIÓN AL TORSO para que la distancia a la cámara no influya:
///
///  1. La muñeca queda a la altura de la cadera (no colgando junto al muslo).
///  2. La muñeca queda cerca de la cadera en horizontal.
///  3. El codo apunta hacia fuera, más lejos del eje del cuerpo que la muñeca:
///     es lo que distingue los brazos en jarras de los brazos caídos.
///
/// Se exige la postura sostenida durante [hold] para que un gesto de paso no la
/// dispare, y un [warmup] desde que se muestra el resultado para que la pose
/// final del baile no cuente como intención de reintentar.
class RetryGestureDetector {
  RetryGestureDetector({
    this.hold = const Duration(milliseconds: 700),
    this.warmup = const Duration(milliseconds: 1200),
    this.verticalBand = 0.38,
    this.horizontalBand = 0.5,
  });

  /// Cuánto hay que mantener las manos en la cintura.
  final Duration hold;

  /// Margen desde que se abre el resultado antes de empezar a escuchar.
  final Duration warmup;

  /// Distancia vertical máxima muñeca-cadera, en fracción del alto del torso.
  final double verticalBand;

  /// Distancia horizontal máxima muñeca-cadera, en fracción del alto del torso.
  final double horizontalBand;

  DateTime? _startedAt;
  DateTime? _since;

  /// Avance 0..1 de la ventana de confirmación en curso.
  double _progress = 0;
  double get progress => _progress;

  void start([DateTime? now]) {
    reset();
    _startedAt = now ?? DateTime.now();
  }

  void reset() {
    _startedAt = null;
    _since = null;
    _progress = 0;
  }

  /// Devuelve `true` cuando la postura se ha mantenido lo suficiente.
  bool update(PoseFrame frame, {DateTime? now}) {
    final t = now ?? DateTime.now();
    _startedAt ??= t;
    if (t.difference(_startedAt!) < warmup) return false;

    if (!frame.hasBody || !_handsOnHips(frame)) {
      _since = null;
      _progress = 0;
      return false;
    }

    _since ??= t;
    final held = t.difference(_since!);
    _progress =
        (held.inMilliseconds / hold.inMilliseconds).clamp(0.0, 1.0).toDouble();
    if (held >= hold) {
      reset();
      return true;
    }
    return false;
  }

  bool _handsOnHips(PoseFrame frame) {
    final ls = frame.byType(PoseLandmarks.leftShoulder);
    final rs = frame.byType(PoseLandmarks.rightShoulder);
    final lh = frame.byType(PoseLandmarks.leftHip);
    final rh = frame.byType(PoseLandmarks.rightHip);
    final le = frame.byType(PoseLandmarks.leftElbow);
    final re = frame.byType(PoseLandmarks.rightElbow);
    final lw = frame.byType(PoseLandmarks.leftWrist);
    final rw = frame.byType(PoseLandmarks.rightWrist);
    final points = [ls, rs, lh, rh, le, re, lw, rw];
    for (final p in points) {
      if (p == null || p.confidence < PoseLandmarks.minConfidence) return false;
    }

    final shoulderY = (ls!.y + rs!.y) / 2;
    final hipY = (lh!.y + rh!.y) / 2;
    // Alto del torso: escala de referencia, inmune a la distancia a la cámara.
    final torso = (hipY - shoulderY).abs();
    if (torso < 0.04) return false; // cuerpo demasiado pequeño o mal detectado

    final centerX = (lh.x + rh.x) / 2;
    return _sideOnHip(hip: lh, elbow: le!, wrist: lw!, torso: torso, centerX: centerX) &&
        _sideOnHip(hip: rh, elbow: re!, wrist: rw!, torso: torso, centerX: centerX);
  }

  bool _sideOnHip({
    required PoseLandmark hip,
    required PoseLandmark elbow,
    required PoseLandmark wrist,
    required double torso,
    required double centerX,
  }) {
    // (1) muñeca a la altura de la cadera.
    if ((wrist.y - hip.y).abs() > verticalBand * torso) return false;
    // (2) muñeca pegada a la cadera en horizontal.
    if ((wrist.x - hip.x).abs() > horizontalBand * torso) return false;
    // (3) codo más abierto que la muñeca: el brazo forma el triángulo en jarras.
    final elbowOut = (elbow.x - centerX).abs();
    final wristOut = (wrist.x - centerX).abs();
    return elbowOut > wristOut;
  }
}

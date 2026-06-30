import 'dart:math' as math;

import '../../pose/domain/entities/pose_landmark.dart';

/// Port 1:1 de `FeatureExtractor.kt` (prototipo Kotlin). Extrae un vector de 15
/// características por fotograma a partir de los 33 landmarks BlazePose.
///
/// Todas las features se normalizan por `hipDist` (distancia entre caderas), por
/// lo que son invariantes a escala: dan el mismo resultado con coordenadas en
/// píxeles (ML Kit) o normalizadas 0..1 (MediaPipe). La confianza usada es
/// `PoseLandmark.confidence` (equivalente a `visibility()` en Kotlin).
class FeatureExtractor {
  FeatureExtractor._();

  static const int _leftHip = 23;
  static const int _rightHip = 24;
  static const int _leftKnee = 25;
  static const int _rightKnee = 26;
  static const int _leftAnkle = 27;
  static const int _rightAnkle = 28;
  static const int _leftHeel = 29;
  static const int _rightHeel = 30;
  static const int _leftFootIndex = 31;
  static const int _rightFootIndex = 32;

  static const double _minVisibility = 0.5;
  static const double _minVisibilityFeet = 0.3;
  static const List<int> _criticalIndices = [
    _leftHip,
    _rightHip,
    _leftKnee,
    _rightKnee,
    _leftAnkle,
    _rightAnkle,
  ];

  /// Vector de 15 features (ver mapa de índices en el .kt original). Devuelve
  /// `null` si faltan landmarks o la visibilidad crítica es insuficiente.
  static List<double>? extractFeatures(
    List<PoseLandmark> landmarks, {
    bool isMirrored = false,
  }) {
    if (landmarks.length < 33) return null;

    // Indexar por tipo (ML Kit no garantiza orden posicional).
    final lm = List<PoseLandmark?>.filled(33, null);
    for (final p in landmarks) {
      if (p.type >= 0 && p.type < 33) lm[p.type] = p;
    }

    for (final idx in _criticalIndices) {
      if ((lm[idx]?.confidence ?? 0) < _minVisibility) return null;
    }

    final lHip = lm[_leftHip]!;
    final rHip = lm[_rightHip]!;
    final lKnee = lm[_leftKnee]!;
    final rKnee = lm[_rightKnee]!;
    final lAnkle = lm[_leftAnkle]!;
    final rAnkle = lm[_rightAnkle]!;

    final hipDist = _euclidean(lHip.x, lHip.y, rHip.x, rHip.y);
    if (hipDist < 0.001) return null;

    final hipCenterX = (lHip.x + rHip.x) / 2;

    final lFoot = _footFeatures(lm[_leftHeel], lm[_leftFootIndex], hipDist);
    final rFoot = _footFeatures(lm[_rightHeel], lm[_rightFootIndex], hipDist);

    final raw = <double>[
      _angleDeg(lHip, lKnee, lAnkle), // 0
      _angleDeg(rHip, rKnee, rAnkle), // 1
      _cosineWithVertical(lAnkle.x, lAnkle.y, lKnee.x, lKnee.y), // 2
      _cosineWithVertical(rAnkle.x, rAnkle.y, rKnee.x, rKnee.y), // 3
      _euclidean(lAnkle.x, lAnkle.y, rAnkle.x, rAnkle.y) / hipDist, // 4
      (lAnkle.y - lHip.y) / hipDist, // 5
      (rAnkle.y - rHip.y) / hipDist, // 6
      (lAnkle.x - hipCenterX) / hipDist, // 7
      (rAnkle.x - hipCenterX) / hipDist, // 8
      (lKnee.x - hipCenterX) / hipDist, // 9
      (rKnee.x - hipCenterX) / hipDist, // 10
      lFoot.$1, // 11
      rFoot.$1, // 12
      lFoot.$2, // 13
      rFoot.$2, // 14
    ];

    return isMirrored ? mirrorFeatures(raw) : raw;
  }

  /// Invierte el vector como si la imagen no estuviera espejada: intercambia
  /// pares L/R y niega las features de posición X (lateralidad). Público para
  /// que [DtwComparator] genere la variante espejada de la referencia.
  static List<double> mirrorFeatures(List<double> f) {
    final m = List<double>.filled(f.length, 0);
    m[0] = f[1]; // knee angle L↔R
    m[1] = f[0];
    m[2] = f[3]; // leg inclination cos-vertical (Y-only, solo swap)
    m[3] = f[2];
    m[4] = f[4]; // feet distance (simétrico)
    m[5] = f[6]; // ankle Y height L↔R
    m[6] = f[5];
    m[7] = -f[8]; // ankle X rel hipCenter: swap + negar
    m[8] = -f[7];
    m[9] = -f[10]; // knee X rel hipCenter
    m[10] = -f[9];
    if (f.length >= 15) {
      m[11] = -f[12]; // foot dir X
      m[12] = -f[11];
      m[13] = f[14]; // foot pitch Y (solo swap)
      m[14] = f[13];
    }
    return m;
  }

  /// Si talón o punta no son visibles, devuelve (0, 0) — pie "neutro".
  static (double, double) _footFeatures(
    PoseLandmark? heel,
    PoseLandmark? toe,
    double hipDist,
  ) {
    final heelVis = heel?.confidence ?? 0;
    final toeVis = toe?.confidence ?? 0;
    if (heelVis < _minVisibilityFeet || toeVis < _minVisibilityFeet) {
      return (0, 0);
    }
    final dirX = (toe!.x - heel!.x) / hipDist;
    final pitch = (heel.y - toe.y) / hipDist;
    return (dirX, pitch);
  }

  static double _angleDeg(PoseLandmark a, PoseLandmark b, PoseLandmark c) {
    final v1x = a.x - b.x;
    final v1y = a.y - b.y;
    final v2x = c.x - b.x;
    final v2y = c.y - b.y;
    final dot = v1x * v2x + v1y * v2y;
    final mag1 = math.sqrt(v1x * v1x + v1y * v1y);
    final mag2 = math.sqrt(v2x * v2x + v2y * v2y);
    if (mag1 == 0.0 || mag2 == 0.0) return 0;
    final cos = (dot / (mag1 * mag2)).clamp(-1.0, 1.0);
    return math.acos(cos) * 180.0 / math.pi;
  }

  static double _cosineWithVertical(
      double fromX, double fromY, double toX, double toY) {
    final vx = toX - fromX;
    final vy = toY - fromY;
    final mag = math.sqrt(vx * vx + vy * vy);
    if (mag == 0.0) return 0;
    return (-vy) / mag;
  }

  static double _euclidean(double x1, double y1, double x2, double y2) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    return math.sqrt(dx * dx + dy * dy);
  }
}

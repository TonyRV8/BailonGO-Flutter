import 'dart:math' as math;

import '../../pose/domain/entities/pose_landmark.dart';

/// Extrae el vector de características por fotograma a partir de los 33 landmarks
/// BlazePose. Base portada 1:1 de `FeatureExtractor.kt` (features 0–14, tren
/// inferior) + extensión de tren superior (15–21) para pasos donde importan
/// brazos/hombros. La relevancia por paso se aplica luego con un vector de pesos
/// en [DtwComparator].
///
/// Todas las features son invariantes a escala (normalizadas por `hipDist` o
/// `shoulderDist`).
class FeatureExtractor {
  FeatureExtractor._();

  /// Número total de features del vector.
  /// 15 tren inferior + 7 tren superior + 4 de cadera.
  static const int featureCount = 26;

  // Tren inferior.
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

  // Tren superior.
  static const int _leftShoulder = 11;
  static const int _rightShoulder = 12;
  static const int _leftElbow = 13;
  static const int _rightElbow = 14;
  static const int _leftWrist = 15;
  static const int _rightWrist = 16;

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

  /// Vector de [featureCount] features. `null` si faltan landmarks o la
  /// visibilidad crítica (tren inferior) es insuficiente. El tren superior no
  /// invalida: si no es visible, sus features quedan en 0 (neutras).
  static List<double>? extractFeatures(
    List<PoseLandmark> landmarks, {
    bool isMirrored = false,
  }) {
    if (landmarks.length < 33) return null;

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
    final upper = _upperFeatures(lm);
    final hips = _hipFeatures(lm, lHip, rHip, hipDist);

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
      ...upper, // 15–21
      ...hips, // 22–25
    ];

    return isMirrored ? mirrorFeatures(raw) : raw;
  }

  /// Invierte el vector como si la imagen no estuviera espejada. Intercambia
  /// pares L/R y niega las features de posición/lateralidad en X.
  static List<double> mirrorFeatures(List<double> f) {
    final m = List<double>.filled(f.length, 0);
    // Tren inferior (0–14).
    m[0] = f[1];
    m[1] = f[0];
    m[2] = f[3];
    m[3] = f[2];
    m[4] = f[4];
    m[5] = f[6];
    m[6] = f[5];
    m[7] = -f[8];
    m[8] = -f[7];
    m[9] = -f[10];
    m[10] = -f[9];
    m[11] = -f[12];
    m[12] = -f[11];
    m[13] = f[14];
    m[14] = f[13];
    // Tren superior (15–21).
    if (f.length >= 22) {
      m[15] = f[16]; // arm angle L↔R
      m[16] = f[15];
      m[17] = -f[17]; // shoulder tilt (signo se invierte)
      m[18] = -f[19]; // wrist X rel: swap + negar
      m[19] = -f[18];
      m[20] = f[21]; // wrist Y rel: solo swap
      m[21] = f[20];
    }
    // Cadera (22–25). Al reflejar, la cadera que estaba alta pasa a estar baja
    // y el desplazamiento lateral cambia de signo; la altura y la rotación no
    // dependen de la lateralidad.
    if (f.length >= 26) {
      m[22] = -f[22]; // inclinación
      m[23] = -f[23]; // desplazamiento lateral
      m[24] = f[24]; // altura
      m[25] = f[25]; // rotación
    }
    return m;
  }

  /// Tren superior: ángulos de brazo, inclinación de hombros y posición de
  /// muñecas (rel. al centro de hombros, normalizado por ancho de hombros).
  /// Devuelve 7 valores; 0 donde no haya visibilidad suficiente.
  static List<double> _upperFeatures(List<PoseLandmark?> lm) {
    final lS = lm[_leftShoulder];
    final rS = lm[_rightShoulder];
    final lE = lm[_leftElbow];
    final rE = lm[_rightElbow];
    final lW = lm[_leftWrist];
    final rW = lm[_rightWrist];

    var armAngleL = 0.0, armAngleR = 0.0, shoulderTilt = 0.0;
    var wristLX = 0.0, wristRX = 0.0, wristLY = 0.0, wristRY = 0.0;

    final shouldersOk = (lS?.confidence ?? 0) >= _minVisibility &&
        (rS?.confidence ?? 0) >= _minVisibility;
    if (shouldersOk) {
      final shoulderDist = _euclidean(lS!.x, lS.y, rS!.x, rS.y);
      if (shoulderDist > 0.001) {
        final scX = (lS.x + rS.x) / 2;
        final scY = (lS.y + rS.y) / 2;
        shoulderTilt = (lS.y - rS.y) / shoulderDist;

        if ((lW?.confidence ?? 0) >= _minVisibility) {
          wristLX = (lW!.x - scX) / shoulderDist;
          wristLY = (lW.y - scY) / shoulderDist;
        }
        if ((rW?.confidence ?? 0) >= _minVisibility) {
          wristRX = (rW!.x - scX) / shoulderDist;
          wristRY = (rW.y - scY) / shoulderDist;
        }
        if ((lE?.confidence ?? 0) >= _minVisibility &&
            (lW?.confidence ?? 0) >= _minVisibility) {
          armAngleL = _angleDeg(lS, lE!, lW!);
        }
        if ((rE?.confidence ?? 0) >= _minVisibility &&
            (rW?.confidence ?? 0) >= _minVisibility) {
          armAngleR = _angleDeg(rS, rE!, rW!);
        }
      }
    }

    return [armAngleL, armAngleR, shoulderTilt, wristLX, wristRX, wristLY, wristRY];
  }

  /// Cadera (landmarks 23 y 24). Hasta ahora la cadera solo servía de ancla de
  /// normalización (`hipDist` fija la escala, `hipCenterX` el origen), así que
  /// su movimiento propio era invisible para el motor — una carencia seria en
  /// salsa, donde el acento de cadera es parte del paso.
  ///
  /// Las tres últimas se miden CONTRA LOS HOMBROS a propósito: referirlas a la
  /// propia cadera las haría constantes por construcción. Si los hombros no
  /// son visibles quedan a 0 (neutras), igual que el resto del tren superior.
  /// La inclinación (22) solo necesita las caderas, que son landmarks críticos
  /// y por tanto siempre están.
  ///
  ///   22 inclinación de cadera  (una cadera más alta que la otra)
  ///   23 desplazamiento lateral de cadera respecto al torso  <- el acento
  ///   24 altura de cadera respecto al torso (flexión / rebote)
  ///   25 rotación de cadera: al girar, el ancho proyectado se estrecha
  static List<double> _hipFeatures(
    List<PoseLandmark?> lm,
    PoseLandmark lHip,
    PoseLandmark rHip,
    double hipDist,
  ) {
    final hipTilt = (lHip.y - rHip.y) / hipDist;

    var swayX = 0.0, swayY = 0.0, rotation = 0.0;
    final lS = lm[_leftShoulder];
    final rS = lm[_rightShoulder];
    final shouldersOk = (lS?.confidence ?? 0) >= _minVisibility &&
        (rS?.confidence ?? 0) >= _minVisibility;
    if (shouldersOk) {
      final shoulderDist = _euclidean(lS!.x, lS.y, rS!.x, rS.y);
      if (shoulderDist > 0.001) {
        final scX = (lS.x + rS.x) / 2;
        final scY = (lS.y + rS.y) / 2;
        final hcX = (lHip.x + rHip.x) / 2;
        final hcY = (lHip.y + rHip.y) / 2;
        swayX = (hcX - scX) / shoulderDist;
        swayY = (hcY - scY) / shoulderDist;
        rotation = hipDist / shoulderDist;
      }
    }
    return [hipTilt, swayX, swayY, rotation];
  }

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
